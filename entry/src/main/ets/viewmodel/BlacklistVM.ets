/**
 * 官方黑名单列表状态与写回：复用 `net/ImSocket`（104103 读列表、104102 增删，maskType=10），
 * 同步更新 `ThreadBlockStore` 本机过滤镜像与 `AuthorBlockVM` 内存缓存；支持单条与多选批量解除。
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import {
  ImBlacklistResult, ImBlacklistUser, ImMaskUpdateResult, parseImBlacklist, parseImMaskUpdate
} from '../model/AuthorBlock';
import { BlockedUser } from '../model/ThreadBlock';
import {
  IM_MASK_TYPE_BLACKLIST, ImGetMaskInfoParams, ImRequest, ImUpdateMaskInfoParams
} from '../net/ImParams';
import { TiebaDevice } from '../net/TiebaParams';
import { imSocket } from '../net/ImSocket';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { threadBlockStore } from '../utils/ThreadBlockStore';
import { authorBlockAction, markAuthorBlocked, syncAuthorBlockCache } from './AuthorBlockVM';
import { loggedInSessionKey } from './SessionOwner';

const DOMAIN: number = 0x0000;
const TAG: string = 'BlacklistVM';
/** 进程内主站最新昵称缓存（按 uid），避免重复请求同一用户的公开资料。 */
const resolvedNames: Map<number, string> = new Map<number, string>();

/** 通过 IM 通道（cmd 104102, maskType=10）写入单个用户的黑名单状态；返回空串表示服务端已确认。 */
export async function syncImBlacklistMask(context: common.UIAbilityContext, uidText: string,
  masked: boolean): Promise<string> {
  if (!authSession.isLoggedIn()) { return '需要登录后才能操作黑名单'; }
  if (!/^\d+$/.test(uidText)) { return '用户身份无效'; }
  const uidBig: bigint = BigInt(uidText);
  if (uidBig <= BigInt(0)) { return '用户身份无效'; }
  const owner: string = loggedInSessionKey();
  const session = authSession.session();
  try {
    const device = await DeviceIdentity.ensure(context);
    if (!authSession.matchesSession(session, owner)) { return '账号已变化，未继续操作'; }
    await imSocket.login(session, owner, device);
    if (!authSession.matchesSession(session, owner)) { return '账号已变化，未继续操作'; }
    const req: ImRequest = ImUpdateMaskInfoParams.build(uidBig, masked, IM_MASK_TYPE_BLACKLIST);
    const raw: Uint8Array = await imSocket.request(req, true);
    if (!authSession.matchesSession(session, owner)) { return '账号已变化，请在原账号确认结果'; }
    const result: ImMaskUpdateResult = parseImMaskUpdate(raw);
    if (result.code !== 0) {
      hilog.warn(DOMAIN, TAG, 'im mask update rejected masked=%{public}s code=%{public}d', String(masked), result.code);
      return result.message.length > 0 ? result.message : `黑名单同步失败（${result.code}）`;
    }
    return '';
  } catch (err) {
    const msg: string = err instanceof Error ? (err as Error).message : String(err);
    hilog.warn(DOMAIN, TAG, 'im mask update failed: %{public}s', msg);
    return msg.length > 0 ? msg : '黑名单同步失败，请重试';
  }
}

@ObservedV2
export class BlacklistVM {
  @Trace items: ImBlacklistUser[] = [];
  @Trace loading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace error: string = '';
  @Trace selecting: boolean = false;
  @Trace selectedIds: string[] = [];
  @Trace actionBusy: boolean = false;
  @Trace actionMessage: string = '';
  @Trace preparedCount: number = 0;
  @Trace executing: boolean = false;
  @Trace processed: number = 0;

  private prepared: ImBlacklistUser[] = [];
  private preparedOwner: string = '';
  private stopRequested: boolean = false;
  private selectedSnapshot: string[] = [];
  private selectedIndex: Set<string> = new Set<string>();
  private account: string = '';
  private epoch: number = 0;
  private disposed: boolean = false;
  private api: TiebaApi = new TiebaApi();

  ownsCurrentAccount(): boolean {
    return !this.disposed && this.account.length > 0 && this.account === loggedInSessionKey();
  }

  dispose(): void {
    this.disposed = true;
    this.epoch++;
    this.loading = false;
    this.cancelPrepared();
  }

  private current(mine: number): boolean {
    return !this.disposed && mine === this.epoch && this.account === loggedInSessionKey();
  }

  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.disposed || this.actionBusy) { return; }
    const currentAccount: string = loggedInSessionKey();
    if (this.loading && this.account === currentAccount) { return; }
    const mine: number = ++this.epoch;
    const switching: boolean = this.account.length > 0 && this.account !== currentAccount;
    this.account = currentAccount;
    this.error = '';

    if (currentAccount.length === 0) {
      this.selecting = false;
      this.selectedIds = [];
      this.items = [];
      this.loaded = false;
      this.loading = false;
      this.error = '登录后才能同步贴吧黑名单';
      return;
    }
    if (switching) {
      this.selecting = false;
      this.selectedIds = [];
      this.items = [];
      this.loaded = false;
    }

    this.loading = true;
    const session = authSession.session();
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!this.current(mine)) { return; }
      await imSocket.login(session, currentAccount, device);
      if (!this.current(mine)) { return; }
      const req: ImRequest = ImGetMaskInfoParams.build(IM_MASK_TYPE_BLACKLIST);
      const raw: Uint8Array = await imSocket.request(req, true);
      if (!this.current(mine)) { return; }
      const parsed: ImBlacklistResult = parseImBlacklist(raw);
      if (parsed.code !== 0) {
        this.error = parsed.message.length > 0 ? parsed.message : '读取黑名单失败，请重试';
        return;
      }
      // 服务端 104103 不返回拉黑时间戳且顺序不保证按时间排列，且其 name/nameShow 常为旧账号名：
      // 保留本机记录的真实拉黑时间与主站昵称，使新拉黑的用户按新→旧排在最前，其余保持服务端原序。
      await threadBlockStore.load(context);
      if (!this.current(mine)) { return; }
      const knownTimes: Map<number, number> = new Map<number, number>();
      const localNames: Map<number, string> = new Map<number, string>();
      for (const local of threadBlockStore.blockedUsers) {
        if (local.uid <= 0) { continue; }
        if (local.timeMs > 0) { knownTimes.set(local.uid, local.timeMs); }
        if (local.name.length > 0) { localNames.set(local.uid, local.name); }
      }
      const order: Map<string, number> = new Map<string, number>();
      for (let i = 0; i < parsed.users.length; i++) {
        const u: ImBlacklistUser = parsed.users[i];
        order.set(u.uidText, i);
        // 优先用已补全的主站昵称或本机拉黑时记录的主站昵称，避免被 IM 104103 旧名覆盖。
        if (u.uid > 0) {
          const best: string = resolvedNames.get(u.uid) ?? localNames.get(u.uid) ?? '';
          if (best.length > 0) { u.nameShow = best; }
        }
      }
      const sorted: ImBlacklistUser[] = parsed.users.slice().sort((a: ImBlacklistUser, b: ImBlacklistUser): number => {
        const ta: number = a.uid > 0 ? (knownTimes.get(a.uid) ?? 0) : 0;
        const tb: number = b.uid > 0 ? (knownTimes.get(b.uid) ?? 0) : 0;
        if (ta !== tb) { return tb - ta; }
        return (order.get(a.uidText) ?? 0) - (order.get(b.uidText) ?? 0);
      });

      this.items = sorted;
      this.loaded = true;
      this.error = '';

      const mirror: BlockedUser[] = [];
      const uids: number[] = [];
      for (const user of sorted) {
        if (user.uid <= 0) { continue; }
        uids.push(user.uid);
        const row: BlockedUser = new BlockedUser();
        row.uid = user.uid;
        row.name = user.nameShow.length > 0 ? user.nameShow : user.name;
        row.portrait = user.portrait;
        row.timeMs = knownTimes.get(user.uid) ?? 0;
        mirror.push(row);
      }
      syncAuthorBlockCache(uids);
      await threadBlockStore.replaceBlockedUsers(context, mirror);
      void this.backfillProfileNames(context, device, mine, knownTimes);
    } catch (err) {
      if (this.current(mine)) {
        const msg: string = err instanceof Error ? (err as Error).message : String(err);
        this.error = msg.length > 0 ? msg : '读取黑名单失败，请重试';
      }
    } finally {
      if (mine === this.epoch) {
        this.loading = false;
        if (this.account !== loggedInSessionKey()) {
          this.selecting = false;
          this.selectedIds = [];
          this.items = [];
          this.loaded = false;
          this.error = '账号已变化，请重新读取';
        }
      }
    }
  }

  /**
   * 后台低并发（3 路）用公开资料页补齐主站最新昵称：IM 104103 的 name/nameShow 为旧缓存。
   * 仅对本进程尚未核实过的 uid 发起只读请求，离页或换号即停。
   */
  private async backfillProfileNames(context: common.UIAbilityContext, device: TiebaDevice,
    mine: number, knownTimes: Map<number, number>): Promise<void> {
    const queue: ImBlacklistUser[] = this.items.filter(
      (u: ImBlacklistUser): boolean => u.uid > 0 && !resolvedNames.has(u.uid));
    if (queue.length === 0) { return; }
    const session = authSession.session();
    let cursor: number = 0;
    let changed: boolean = false;
    let lastPublish: number = 0;
    const worker = async (): Promise<void> => {
      while (cursor < queue.length) {
        if (!this.current(mine)) { return; }
        const target: ImBlacklistUser = queue[cursor++];
        try {
          const prof = await this.api.fetchPublicProfile(device, session, target.uid, target.portrait);
          if (!this.current(mine)) { return; }
          if (!prof.ok) { continue; }
          let rowChanged: boolean = false;
          const freshName: string = prof.data.nickName || prof.data.userName;
          if (freshName.length > 0) {
            resolvedNames.set(target.uid, freshName);
            if (target.nameShow !== freshName) {
              target.nameShow = freshName;
              rowChanged = true;
            }
          }
          if (prof.data.portrait.length > 0 && target.portrait !== prof.data.portrait) {
            target.portrait = prof.data.portrait;
            rowChanged = true;
          }
          if (rowChanged) {
            changed = true;
            const now: number = Date.now();
            if (now - lastPublish >= 300) {
              lastPublish = now;
              this.items = this.items.slice();
            }
          }
        } catch (err) { /* 单个补齐失败保留原名，不影响列表 */ }
      }
    };
    const concurrency: number = Math.min(3, queue.length);
    const workers: Promise<void>[] = [];
    for (let i = 0; i < concurrency; i++) { workers.push(worker()); }
    await Promise.all(workers);
    if (!changed || !this.current(mine)) { return; }
    this.items = this.items.slice();
    const mirror: BlockedUser[] = [];
    for (const user of this.items) {
      if (user.uid <= 0) { continue; }
      const row: BlockedUser = new BlockedUser();
      row.uid = user.uid;
      row.name = user.nameShow.length > 0 ? user.nameShow : user.name;
      row.portrait = user.portrait;
      row.timeMs = knownTimes.get(user.uid) ?? 0;
      mirror.push(row);
    }
    await threadBlockStore.replaceBlockedUsers(context, mirror);
  }

  toggleSelection(): void {
    if (this.actionBusy || !this.ownsCurrentAccount()) { return; }
    this.selecting = !this.selecting;
    this.selectedIds = [];
  }

  toggleItem(uidText: string): void {
    if (!this.selecting || this.actionBusy || !this.ownsCurrentAccount()) { return; }
    if (!this.items.some((item: ImBlacklistUser): boolean => item.uidText === uidText)) { return; }
    this.selectedIds = this.selectedIds.includes(uidText)
      ? this.selectedIds.filter((value: string): boolean => value !== uidText)
      : this.selectedIds.concat(uidText);
  }

  isSelected(uidText: string): boolean {
    if (this.selectedSnapshot !== this.selectedIds) {
      this.selectedSnapshot = this.selectedIds;
      this.selectedIndex = new Set<string>(this.selectedIds);
    }
    return this.selectedIndex.has(uidText);
  }

  allSelected(): boolean {
    return this.loaded && this.items.length > 0
      && this.items.every((item: ImBlacklistUser): boolean => this.isSelected(item.uidText));
  }

  toggleAll(): void {
    if (!this.selecting || this.actionBusy || !this.ownsCurrentAccount()) { return; }
    if (this.allSelected()) {
      this.selectedIds = [];
    } else {
      this.selectedIds = this.items.map((item: ImBlacklistUser): string => item.uidText);
    }
  }

  prepareItems(ids: string[]): boolean {
    if (this.actionBusy || this.loading || !this.ownsCurrentAccount()) { return false; }
    this.actionMessage = '';
    const selected: Set<string> = new Set<string>(ids);
    this.prepared = this.items.filter((item: ImBlacklistUser): boolean => selected.has(item.uidText));
    if (this.prepared.length === 0) {
      this.actionMessage = '请先选择要解除拉黑的用户';
      return false;
    }
    this.preparedOwner = loggedInSessionKey();
    this.preparedCount = this.prepared.length;
    this.actionBusy = true;
    return true;
  }

  private preparedCurrent(): boolean {
    return !this.disposed && this.preparedOwner.length > 0 && this.preparedOwner === loggedInSessionKey();
  }

  cancelPrepared(): void {
    if (this.executing) { return; }
    this.prepared = [];
    this.preparedCount = 0;
    this.preparedOwner = '';
    this.actionBusy = false;
  }

  requestStop(): void {
    if (this.executing) {
      this.stopRequested = true;
      this.actionMessage = '正在停止…';
    }
  }

  /** 执行单个用户的服务端双写解除（HTTP 309697 + IM 104102）；返回空串表示已确认。 */
  private async unblockServerOne(context: common.UIAbilityContext, user: ImBlacklistUser,
    owner: string): Promise<string> {
    if (user.uid > 0) {
      const vm = authorBlockAction(user.uid);
      const httpErr: string = await vm.set(context, false);
      if (owner !== loggedInSessionKey()) { return '账号已变化，请在原账号确认结果'; }
      if (httpErr.length > 0) { return httpErr; }
      if (!vm.known || vm.blocked) { return '拉黑状态未确认，请稍后重试'; }
    }
    const imErr: string = await syncImBlacklistMask(context, user.uidText, false);
    if (owner !== loggedInSessionKey()) { return '账号已变化，请在原账号确认结果'; }
    return imErr;
  }

  /** 批量或单条解除（经 prepareItems 锁定目标后执行），完成后一次提交列表与本机镜像。 */
  async executePrepared(context: common.UIAbilityContext): Promise<void> {
    if (this.executing || !this.actionBusy || this.prepared.length === 0) { return; }
    if (!this.preparedCurrent()) {
      this.cancelPrepared();
      this.actionMessage = '账号已变化，请重新确认';
      return;
    }
    this.executing = true;
    this.stopRequested = false;
    this.processed = 0;
    const targets: ImBlacklistUser[] = this.prepared.slice();
    const operationOwner: string = this.preparedOwner;
    const succeeded: Set<string> = new Set<string>();
    let failed: number = 0;
    let firstFailure: string = '';
    let stopReason: string = '';
    const total: number = targets.length;
    try {
      for (let i = 0; i < total; i++) {
        if (this.stopRequested || stopReason.length > 0) { break; }
        if (!this.preparedCurrent()) {
          stopReason = '账号已变化或页面已关闭';
          break;
        }
        const user: ImBlacklistUser = targets[i];
        try {
          const err: string = await this.unblockServerOne(context, user, operationOwner);
          if (operationOwner !== loggedInSessionKey()) {
            stopReason = '账号已变化';
            break;
          }
          if (err.length === 0) {
            succeeded.add(user.uidText);
          } else {
            failed++;
            if (firstFailure.length === 0) { firstFailure = err; }
          }
        } catch (err) {
          failed++;
          if (firstFailure.length === 0) { firstFailure = (err as Error).message; }
          stopReason = '请求异常，已停止后续操作';
        }
        const completed: number = succeeded.size + failed;
        if (!this.disposed && !this.stopRequested) {
          this.processed = completed;
          if (total > 1) { this.actionMessage = `正在解除 ${completed}/${total}…`; }
        }
      }
    } finally {
      if (operationOwner === loggedInSessionKey()) {
        const removed: ImBlacklistUser[] = targets.filter((item: ImBlacklistUser): boolean => succeeded.has(item.uidText));
        if (!this.disposed) {
          this.items = this.items.filter((item: ImBlacklistUser): boolean => !succeeded.has(item.uidText));
          this.selectedIds = this.selectedIds.filter((id: string): boolean => !succeeded.has(id));
          this.processed = succeeded.size + failed;
        }
        if (removed.length > 0) {
          for (const item of removed) {
            if (item.uid > 0) { markAuthorBlocked(item.uid, false); }
          }
          const knownTimes: Map<number, number> = new Map<number, number>();
          for (const local of threadBlockStore.blockedUsers) {
            if (local.uid > 0 && local.timeMs > 0) { knownTimes.set(local.uid, local.timeMs); }
          }
          const remainingMirror: BlockedUser[] = [];
          for (const item of this.items) {
            if (item.uid <= 0) { continue; }
            const row: BlockedUser = new BlockedUser();
            row.uid = item.uid;
            row.name = item.nameShow.length > 0 ? item.nameShow : item.name;
            row.portrait = item.portrait;
            row.timeMs = knownTimes.get(item.uid) ?? 0;
            remainingMirror.push(row);
          }
          try {
            await threadBlockStore.replaceBlockedUsers(context, remainingMirror);
          } catch (err) {
            stopReason = '本机记录同步失败，请重新读取';
          }
        }
        if (!this.disposed && operationOwner === loggedInSessionKey()) {
          const remaining: number = total - succeeded.size - failed;
          if (total === 1 && failed === 0 && succeeded.size === 1) {
            this.actionMessage = `已解除对 ${targets[0].displayName()} 的拉黑`;
          } else if (failed > 0) {
            this.actionMessage = `已解除 ${succeeded.size} 人，${failed} 人失败：${firstFailure}`;
          } else {
            this.actionMessage = `已解除 ${succeeded.size} 人的拉黑`;
          }
          if (this.stopRequested || stopReason.length > 0) {
            this.actionMessage += `；${stopReason || '已停止'}，剩余 ${remaining} 人未完成确认`;
          } else if (failed === 0) {
            this.selecting = false;
            this.selectedIds = [];
          }
        } else if (!this.disposed) {
          this.actionMessage = '账号已变化，请在原账号重新读取结果';
        }
      } else if (!this.disposed) {
        this.actionMessage = '账号已变化，请在原账号重新读取结果';
      }
      this.executing = false;
      this.cancelPrepared();
    }
  }
}
