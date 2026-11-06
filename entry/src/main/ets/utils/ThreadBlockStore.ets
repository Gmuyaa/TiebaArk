/** 帖子屏蔽与隐藏规则的本地持久化。 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { authSession } from '../auth/AuthSession';
import {
  BlockRules, BlockedUser, HiddenThread, blockedUserUids, emptyRules, mergeBlockedUser,
  mergeHiddenThread, normalizeForumName, normalizeForumNames, normalizeTids, normalizeUids, parseBlockedUsers,
  parseHiddenThreads, removeBlockedUser, removeHiddenThread, serializeBlockedUsers,
  serializeHiddenThreads
} from '../model/ThreadBlock';

const STORE: string = 'tieba_thread_block';
const KEY_HIDDEN: string = 'hidden_threads';
const KEY_FORUMS: string = 'blocked_forums';
/** 拉黑用户名单（uid + 昵称）的账号级键：本机记录，服务端无全量列表可读 */
const KEY_USERS: string = 'blocked_users';

interface RawStringList {
  values?: string[];
}

function ownerKey(): string {
  return authSession.isLoggedIn() ? String(authSession.snapshot.uid) : 'anonymous';
}

/** 账号级键名：换号即换键，绝不跨账号复用一份服务端镜像 */
function scoped(base: string, owner: string): string {
  return `${base}_${owner}`;
}

@ObservedV2
export class ThreadBlockStore {
  /** 本机隐藏的帖子（最近隐藏的在前） */
  @Trace hidden: HiddenThread[] = [];
  /** 已屏蔽的吧名（归一化后的纯吧名，不含「吧」后缀） */
  @Trace blockedForums: string[] = [];
  /**
   * 本机记录"拉黑过的用户"（uid + 昵称）。
   * ⚠️ 服务端没有全量黑名单 HTTP 接口，这份名单只是**本应用内的部分视图**，
   * 界面必须如实说明（见 `model/ThreadBlock.ets` 的 `BlockedUser`）。
   */
  @Trace blockedUsers: BlockedUser[] = [];
  @Trace reading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace readError: string = '';
  @Trace saving: boolean = false;
  @Trace saveError: string = '';
  @Trace hiddenSaveError: string = '';
  @Trace usersSaveError: string = '';
  @Trace forumsSaveError: string = '';

  @Trace private owner: string = '';
  private loadingOwner: string = '';
  private loading: Promise<void> | undefined = undefined;
  private operations: Promise<void> = Promise.resolve();
  /** flush 失败后 Preferences 仍可能返回待写缓存，不能替代最后确认的隐藏列表。 */
  private hiddenWriteUnconfirmed: boolean = false;

  /** 同账号已读取时复用；读取失败保留旧内容，通过状态区分失败和空列表。 */
  async load(context: common.UIAbilityContext): Promise<void> {
    await this.queueLoad(context, false);
  }

  /** 管理页手动重读；只读本机记录，不重放任何服务端操作。 */
  async reload(context: common.UIAbilityContext): Promise<void> {
    await this.queueLoad(context, true);
  }

  private enqueue(operation: () => Promise<void>): Promise<void> {
    const pending: Promise<void> = this.operations.then(operation, operation);
    this.operations = pending.catch((): void => {});
    return pending;
  }

  private current(current: string, session: string): boolean {
    return current === ownerKey() && session === authSession.sessionKey();
  }

  private syncOwner(current: string): void {
    if (this.owner === current) { return; }
    this.blockedForums = [];
    this.blockedUsers = [];
    this.owner = current;
    this.loaded = false;
    this.readError = '';
    this.usersSaveError = '';
    this.forumsSaveError = '';
    this.updateSaveError();
  }

  private async queueLoad(context: common.UIAbilityContext, refresh: boolean): Promise<void> {
    const current: string = ownerKey();
    const session: string = authSession.sessionKey();
    this.syncOwner(current);
    if (this.loading !== undefined && this.loadingOwner === session) { return this.loading; }
    if (!refresh && this.loaded) { return; }
    this.loadingOwner = session;
    const pending: Promise<void> = this.enqueue(async (): Promise<void> => {
      if (this.current(current, session)) { await this.read(context, current, session); }
    });
    this.loading = pending;
    try { await pending; } finally { if (this.loading === pending) { this.loading = undefined; } }
  }

  private async read(context: common.UIAbilityContext, current: string, session: string): Promise<void> {
    this.reading = true;
    this.loaded = false;
    this.readError = '';
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      const hiddenRaw: string = (await store.get(KEY_HIDDEN, '')) as string;

      const forumsRaw: string = (await store.get(scoped(KEY_FORUMS, current), '')) as string;

      const usersRaw: string = (await store.get(scoped(KEY_USERS, current), '')) as string;
      if (!this.current(current, session)) { return; }
      if (!this.hiddenWriteUnconfirmed) { this.hidden = parseHiddenThreads(hiddenRaw); }
      this.blockedForums = parseForumList(forumsRaw);
      this.blockedUsers = parseBlockedUsers(usersRaw);
      this.owner = current;
      this.loaded = true;
    } catch (e) {
      if (!this.current(current, session)) { return; }
      hilog.warn(0x0, 'TiebaThreadBlock', 'block load failed: %{public}s', String(e));
      this.readError = '本机记录读取失败，请重试';
    } finally { this.reading = false; }
  }

  /** 汇总尚未确认的保存；具体动作只读取对应存储键的错误。 */
  private updateSaveError(): void {
    this.saveError = [this.hiddenSaveError, this.usersSaveError, this.forumsSaveError]
      .filter((message: string): boolean => message.length > 0).join('\n');
  }

  /** 错误跟随持久化键；另一类记录写成功不能替当前键证明已保存。 */
  private setSaveError(key: string, message: string): void {
    if (key === KEY_HIDDEN) { this.hiddenSaveError = message; }
    else if (key === KEY_USERS) { this.usersSaveError = message; }
    else { this.forumsSaveError = message; }
    this.updateSaveError();
  }

  /** 读改写串行；未读到历史记录时不把当前内存当成完整列表写回。 */
  private async change(context: common.UIAbilityContext, key: string,
    operation: (current: string, session: string) => Promise<boolean>): Promise<void> {
    const current: string = ownerKey();
    const session: string = authSession.sessionKey();
    this.syncOwner(current);
    await this.enqueue(async (): Promise<void> => {
      if (!this.current(current, session)) { return; }
      if (!this.loaded) { await this.read(context, current, session); }
      if (!this.current(current, session)) { return; }
      if (!this.loaded) {
        this.setSaveError(key, '本机记录未读取，未保存更改。请先重新读取。');
        return;
      }
      this.saving = true;
      try {
        const saved: boolean = await operation(current, session);
        // 隐藏记录属于设备；即使写入期间换号，未确认的缓存也不能覆盖已知快照。
        if (key === KEY_HIDDEN) { this.hiddenWriteUnconfirmed = !saved; }
        if (key === KEY_HIDDEN || this.current(current, session)) {
          this.setSaveError(key, saved ? '' : '本机记录保存未确认，重启后可能恢复旧记录。');
        }
      } finally { this.saving = false; }
    });
  }

  /**
   * 过滤口径（列表渲染时读它；内部读 @Trace 字段，建立 V2 渲染依赖）。
   *
   * 账号对不上时**返回空口径**：换号/退出后旧账号的屏蔽与拉黑绝不能继续套在
   * 新账号的列表上（下一次进页面 `load` 会把新账号那份读回来）。
   */
  rules(): BlockRules {
    if (this.owner !== ownerKey()) { return emptyRules(); }
    const rules: BlockRules = new BlockRules();
    // 存储中的吧名已经归一化；再次削尾会让以「吧」结尾的实际吧名失配。
    rules.forums = this.blockedForums.slice();
    rules.uids = normalizeUids(blockedUserUids(this.blockedUsers));
    rules.tids = normalizeTids(this.hidden.map((item: HiddenThread): number => item.tid));
    return rules;
  }

  isHidden(tid: number): boolean {
    for (const item of this.hidden) {
      if (item.tid === tid) { return true; }
    }
    return false;
  }

  /** 隐藏一条帖子（本机） */
  async hide(context: common.UIAbilityContext, item: HiddenThread): Promise<void> {
    if (item.tid <= 0) { return; }
    await this.change(context, KEY_HIDDEN, async (current: string, session: string): Promise<boolean> => {
      const next: HiddenThread[] = mergeHiddenThread(this.hidden, item);
      const saved: boolean = await this.persist(context, KEY_HIDDEN, serializeHiddenThreads(next));
      if (saved && this.current(current, session)) { this.hidden = next; }
      return saved;
    });
  }

  /** 恢复（取消隐藏）一条帖子 */
  async unhide(context: common.UIAbilityContext, tid: number): Promise<void> {
    await this.change(context, KEY_HIDDEN, async (current: string, session: string): Promise<boolean> => {
      const next: HiddenThread[] = removeHiddenThread(this.hidden, tid);
      const saved: boolean = await this.persist(context, KEY_HIDDEN, serializeHiddenThreads(next));
      if (saved && this.current(current, session)) { this.hidden = next; }
      return saved;
    });
  }

  /** 服务端屏蔽成功后记一笔，用于即时过滤（不改变服务端状态） */
  async rememberBlockedForum(context: common.UIAbilityContext, forumName: string): Promise<void> {
    const name: string = normalizeForumName(forumName);
    if (name.length === 0) { return; }
    await this.change(context, KEY_FORUMS, async (current: string, _session: string): Promise<boolean> => {
      this.blockedForums = uniqueForumNames(this.blockedForums.concat([name]));
      return this.persist(context, scoped(KEY_FORUMS, current), JSON.stringify({ values: this.blockedForums }));
    });
  }

  /** 服务端解除屏蔽后从本机镜像里删掉 */
  async forgetBlockedForum(context: common.UIAbilityContext, forumName: string): Promise<void> {
    await this.forgetBlockedForums(context, [forumName]);
  }

  /** 批量取消只更新一次内存镜像并落盘一次，避免逐项序列化和flush。 */
  async forgetBlockedForums(context: common.UIAbilityContext, forumNames: string[]): Promise<void> {
    await this.change(context, KEY_FORUMS, async (current: string, _session: string): Promise<boolean> => {
      const names: Set<string> = new Set<string>(normalizeForumNames(forumNames));
      this.blockedForums = this.blockedForums.filter((item: string): boolean => !names.has(item));
      return this.persist(context, scoped(KEY_FORUMS, current), JSON.stringify({ values: this.blockedForums }));
    });
  }

  /** 服务端拉黑成功后记一笔（uid + 昵称，供设置页展示），用于即时过滤 */
  async rememberBlockedUser(context: common.UIAbilityContext, uid: number, name: string): Promise<void> {
    if (!Number.isSafeInteger(uid) || uid <= 0) { return; }
    const user: BlockedUser = new BlockedUser();
    user.uid = uid;
    user.name = name;
    user.timeMs = Date.now();
    await this.change(context, KEY_USERS, async (current: string, _session: string): Promise<boolean> => {
      this.blockedUsers = mergeBlockedUser(this.blockedUsers, user);
      return this.persist(context, scoped(KEY_USERS, current), serializeBlockedUsers(this.blockedUsers));
    });
  }

  /** 解除拉黑后从本机名单里删掉 */
  async forgetBlockedUser(context: common.UIAbilityContext, uid: number): Promise<void> {
    await this.change(context, KEY_USERS, async (current: string, _session: string): Promise<boolean> => {
      this.blockedUsers = removeBlockedUser(this.blockedUsers, uid);
      return this.persist(context, scoped(KEY_USERS, current), serializeBlockedUsers(this.blockedUsers));
    });
  }

  /**
   * 服务端完整屏蔽吧列表覆盖镜像；部分分页只合并，保留尚未读到的吧。
   *
   * ⚠️ 只有吧这一份能这么做：拉黑用户**没有**服务端全量列表可读（见 `BlockedUser`），
   * 所以本机的拉黑名单永远只是部分视图，不会被这里覆盖。
   */
  async replaceBlockedForums(context: common.UIAbilityContext, forums: string[], complete: boolean = true): Promise<void> {
    await this.change(context, KEY_FORUMS, async (current: string, _session: string): Promise<boolean> => {
      const incoming: string[] = normalizeForumNames(forums);
      this.blockedForums = complete ? incoming : uniqueForumNames(this.blockedForums.concat(incoming));
      return this.persist(context, scoped(KEY_FORUMS, current), JSON.stringify({ values: this.blockedForums }));
    });
  }

  /** 退出登录/换号时清空账号级镜像（隐藏列表是设备级的，保留） */
  resetAccount(): void {
    this.blockedForums = [];
    this.blockedUsers = [];
    this.owner = '';
    this.loaded = false;
    this.readError = '';
    this.usersSaveError = '';
    this.forumsSaveError = '';
    this.updateSaveError();
  }

  private async persist(context: common.UIAbilityContext, key: string, value: string): Promise<boolean> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      await store.put(key, value);
      await store.flush();
      return true;
    } catch (e) {
      hilog.warn(0x0, 'TiebaThreadBlock', 'block persist failed: %{public}s', String(e));
      return false;
    }
  }
}

/** 吧名清单的存储格式：`{"values":["吧名",…]}`；旧值/坏值一律当空 */
function parseForumList(raw: string): string[] {
  if (raw.length === 0) { return []; }
  try {
    const parsed: RawStringList = JSON.parse(raw) as RawStringList;
    if (parsed === null || parsed === undefined || !Array.isArray(parsed.values)) { return []; }
    const values: string[] = [];
    for (const item of parsed.values) {
      if (typeof item === 'string') { values.push(item); }
    }
    return uniqueForumNames(values);
  } catch (err) {
    return [];
  }
}

/** 已归一化的存储值只去空和去重，不再次移除吧名尾字。 */
function uniqueForumNames(names: string[]): string[] {
  const values: string[] = [];
  for (const name of names) {
    const value: string = name.trim();
    if (value.length > 0 && values.indexOf(value) < 0) { values.push(value); }
  }
  return values;
}

export const threadBlockStore: ThreadBlockStore = new ThreadBlockStore();
