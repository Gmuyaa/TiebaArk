/** 帖子屏蔽与隐藏规则的本地持久化。 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { authSession } from '../auth/AuthSession';
import {
  BlockRules, BlockedUser, HiddenThread, blockedUserUids, emptyRules, mergeBlockedUser,
  mergeHiddenThread, mergeRules, normalizeForumName, normalizeForumNames, parseBlockedUsers,
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

  private owner: string = '';
  private loadingOwner: string = '';
  private loaded: boolean = false;
  private loading: Promise<void> | undefined = undefined;

  /**
   * 读取本机记录。
   *
   * 账号变了就重读账号级那两份（隐藏列表是设备级的，不需要重读）；
   * 同一账号重复调用是空操作。**读取失败不抛给界面**：镜像读不出来只是少了
   * 即时过滤，服务端列表照旧由设置页展示。
   */
  async load(context: common.UIAbilityContext): Promise<void> {
    const current: string = ownerKey();
    if (this.loading !== undefined && this.loadingOwner === current) { return this.loading; }
    if (this.loaded && this.owner === current) { return; }
    this.loadingOwner = current;
    const pending: Promise<void> = this.read(context, current, authSession.sessionKey());
    this.loading = pending;
    try { await pending; } finally { if (this.loading === pending) { this.loading = undefined; } }
  }

  private async read(context: common.UIAbilityContext, current: string, session: string): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      const hiddenRaw: string = (await store.get(KEY_HIDDEN, '')) as string;

      const forumsRaw: string = (await store.get(scoped(KEY_FORUMS, current), '')) as string;

      const usersRaw: string = (await store.get(scoped(KEY_USERS, current), '')) as string;
      if (current !== ownerKey() || session !== authSession.sessionKey()) { return; }
      this.hidden = parseHiddenThreads(hiddenRaw);
      this.blockedForums = parseForumList(forumsRaw);
      this.blockedUsers = parseBlockedUsers(usersRaw);
      this.owner = current;
      this.loaded = true;
    } catch (e) {
      if (current !== ownerKey() || session !== authSession.sessionKey()) { return; }
      hilog.warn(0x0, 'TiebaThreadBlock', 'block load failed: %{public}s', String(e));
      // 读不到就按"没有本机记录"处理，但**不标记 loaded**：下次进页面再试一次
      this.owner = current;
      this.hidden = [];
      this.blockedForums = [];
      this.blockedUsers = [];
    }
  }

  /**
   * 过滤口径（列表渲染时读它；内部读 @Trace 字段，建立 V2 渲染依赖）。
   *
   * 账号对不上时**返回空口径**：换号/退出后旧账号的屏蔽与拉黑绝不能继续套在
   * 新账号的列表上（下一次进页面 `load` 会把新账号那份读回来）。
   */
  rules(): BlockRules {
    if (this.owner !== ownerKey()) { return emptyRules(); }
    return mergeRules(this.blockedForums, [], blockedUserUids(this.blockedUsers), this.hidden);
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
    this.hidden = mergeHiddenThread(this.hidden, item);
    await this.persist(context, KEY_HIDDEN, serializeHiddenThreads(this.hidden));
  }

  /** 恢复（取消隐藏）一条帖子 */
  async unhide(context: common.UIAbilityContext, tid: number): Promise<void> {
    this.hidden = removeHiddenThread(this.hidden, tid);
    await this.persist(context, KEY_HIDDEN, serializeHiddenThreads(this.hidden));
  }

  /** 服务端屏蔽成功后记一笔，用于即时过滤（不改变服务端状态） */
  async rememberBlockedForum(context: common.UIAbilityContext, forumName: string): Promise<void> {
    const session: string = authSession.sessionKey();
    await this.load(context);
    if (session !== authSession.sessionKey()) { return; }
    const name: string = normalizeForumName(forumName);
    if (name.length === 0) { return; }
    this.blockedForums = normalizeForumNames(this.blockedForums.concat([name]));
    await this.persist(context, scoped(KEY_FORUMS, ownerKey()),
      JSON.stringify({ values: this.blockedForums }));
  }

  /** 服务端解除屏蔽后从本机镜像里删掉 */
  async forgetBlockedForum(context: common.UIAbilityContext, forumName: string): Promise<void> {
    const session: string = authSession.sessionKey();
    await this.load(context);
    if (session !== authSession.sessionKey()) { return; }
    const name: string = normalizeForumName(forumName);
    const kept: string[] = [];
    for (const item of this.blockedForums) {
      if (item !== name) { kept.push(item); }
    }
    this.blockedForums = kept;
    await this.persist(context, scoped(KEY_FORUMS, ownerKey()),
      JSON.stringify({ values: this.blockedForums }));
  }

  /** 服务端拉黑成功后记一笔（uid + 昵称，供设置页展示），用于即时过滤 */
  async rememberBlockedUser(context: common.UIAbilityContext, uid: number, name: string): Promise<void> {
    const session: string = authSession.sessionKey();
    await this.load(context);
    if (session !== authSession.sessionKey()) { return; }
    if (!Number.isSafeInteger(uid) || uid <= 0) { return; }
    const user: BlockedUser = new BlockedUser();
    user.uid = uid;
    user.name = name;
    user.timeMs = Date.now();
    this.blockedUsers = mergeBlockedUser(this.blockedUsers, user);
    await this.persist(context, scoped(KEY_USERS, ownerKey()),
      serializeBlockedUsers(this.blockedUsers));
  }

  /** 解除拉黑后从本机名单里删掉 */
  async forgetBlockedUser(context: common.UIAbilityContext, uid: number): Promise<void> {
    const session: string = authSession.sessionKey();
    await this.load(context);
    if (session !== authSession.sessionKey()) { return; }
    this.blockedUsers = removeBlockedUser(this.blockedUsers, uid);
    await this.persist(context, scoped(KEY_USERS, ownerKey()),
      serializeBlockedUsers(this.blockedUsers));
  }

  /**
   * 服务端完整屏蔽吧列表覆盖镜像；部分分页只合并，保留尚未读到的吧。
   *
   * ⚠️ 只有吧这一份能这么做：拉黑用户**没有**服务端全量列表可读（见 `BlockedUser`），
   * 所以本机的拉黑名单永远只是部分视图，不会被这里覆盖。
   */
  async replaceBlockedForums(context: common.UIAbilityContext, forums: string[], complete: boolean = true): Promise<void> {
    const session: string = authSession.sessionKey();
    await this.load(context);
    if (session !== authSession.sessionKey()) { return; }
    this.blockedForums = normalizeForumNames(complete ? forums : this.blockedForums.concat(forums));
    await this.persist(context, scoped(KEY_FORUMS, ownerKey()),
      JSON.stringify({ values: this.blockedForums }));
  }

  /** 退出登录/换号时清空账号级镜像（隐藏列表是设备级的，保留） */
  resetAccount(): void {
    this.blockedForums = [];
    this.blockedUsers = [];
    this.owner = '';
    this.loaded = false;
  }

  private async persist(context: common.UIAbilityContext, key: string, value: string): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      await store.put(key, value);
      await store.flush();
    } catch (e) {
      // 写失败不影响本次会话的界面：内存里已经是新值，下次启动可能少一条
      hilog.warn(0x0, 'TiebaThreadBlock', 'block persist failed: %{public}s', String(e));
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
    return normalizeForumNames(values);
  } catch (err) {
    return [];
  }
}

export const threadBlockStore: ThreadBlockStore = new ThreadBlockStore();
