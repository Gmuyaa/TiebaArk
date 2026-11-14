import { common } from '@kit.AbilityKit';
import { NotifyUnreadResponse, TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { NotifyPreviews, NotifyUnreadCounts, NotifyUnreadKind, fanActionPreview, notifyActionPreview } from '../model/NotifyUnread';
import { NotifyKind } from '../model/Notify';
import { TiebaSession } from '../net/TiebaParams';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { loggedInSessionKey } from './SessionOwner';


/** 首页与底栏只读取计数；摘要仅复用用户主动查看的结果，不自动消费列表。 */
@ObservedV2
export class NotifyUnreadVM {
  @Trace counts: NotifyUnreadCounts = new NotifyUnreadCounts();
  @Trace loaded: boolean = false;
  @Trace loading: boolean = false;
  @Trace error: string = '';
  @Trace marking: boolean = false;
  @Trace previews: NotifyPreviews = new NotifyPreviews();
  @Trace previewRevision: number = 0;
  private refreshRequest: Promise<void> | undefined = undefined;
  private account: string = '';
  private epoch: number = 0;
  private disposed: boolean = false;
  private api: TiebaApi = new TiebaApi();

  /** 并发调用等待同一个真实请求；下拉不会因后台请求已在途而提前结束。 */
  refresh(context: common.UIAbilityContext): Promise<void> {
    if (this.disposed) { return Promise.resolve(); }
    this.syncAccount();
    if (this.marking || this.account.length === 0) { return Promise.resolve(); }
    if (this.refreshRequest !== undefined) { return this.refreshRequest; }
    const mine: number = ++this.epoch;
    this.error = '';
    this.loading = true;
    const session: TiebaSession = authSession.session();
    // 先保存共享 Promise 再进入读取，确保依赖同步抛错时也能正确释放在途状态。
    this.refreshRequest = Promise.resolve().then((): Promise<void> => this.readCounts(context, session, mine));
    return this.refreshRequest;
  }

  private async readCounts(context: common.UIAbilityContext, session: TiebaSession, mine: number): Promise<void> {
    try {
      if (!this.current(mine)) { return; }
      const device = await DeviceIdentity.ensure(context);
      if (!this.current(mine)) { return; }
      const response: NotifyUnreadResponse = await this.api.fetchNotifyUnread(device, session);
      if (!this.current(mine)) { return; }
      if (!response.ok) { this.error = response.describeFailure(); return; }
      this.counts = response.data; this.loaded = true;
    } catch (err) {
      if (this.current(mine)) { this.error = '新消息提醒读取失败，请下拉重试'; }
    } finally {
      if (mine === this.epoch) {
        this.loading = false; this.refreshRequest = undefined;
        this.syncAccount();
      }
    }
  }

  /** 调用方已确认首屏成功及自身代次；这里只接收当前会话的真实摘要。 */
  acceptPreview(kind: NotifyUnreadKind, text: string, expectedAccount: string): void {
    if (this.disposed || expectedAccount.length === 0 || expectedAccount !== loggedInSessionKey() || text.length === 0) { return; }
    this.syncAccount();
    if (this.account !== expectedAccount) { return; }
    if (!this.marking && this.refreshRequest !== undefined) {
      // 主动查看可能消费未读；丢弃此前在途的计数，让 revision 触发的补读取得新结果。
      this.epoch++; this.loading = false; this.refreshRequest = undefined;
    }
    const previews: NotifyPreviews = new NotifyPreviews();
    previews.agree = this.previews.agree; previews.reply = this.previews.reply;
    previews.at = this.previews.at; previews.fans = this.previews.fans;
    if (kind === 'agree') { previews.agree = text; }
    else if (kind === 'reply') { previews.reply = text; }
    else if (kind === 'at') { previews.at = text; }
    else { previews.fans = text; }
    this.previews = previews;
    // 同一摘要也可能来自一次新的主动读取，通知外壳补读服务端计数。
    this.previewRevision++;
  }

  syncAccount(): void {
    if (this.disposed) { return; }
    const currentAccount: string = loggedInSessionKey();
    if (this.account === currentAccount) { return; }
    this.clear();
    this.account = currentAccount;
  }

  private current(mine: number): boolean {
    return !this.disposed && mine === this.epoch && this.account === loggedInSessionKey();
  }

  /** 用户确认后才消费各类通知；最终以服务端计数读回为准，绝不本地模拟清零。 */
  async markAllRead(context: common.UIAbilityContext, expectedAccount: string): Promise<string> {
    if (this.disposed || expectedAccount.length === 0 || expectedAccount !== loggedInSessionKey()) { return ''; }
    this.syncAccount();
    if (this.marking) { return ''; }
    const mine: number = ++this.epoch;
    this.loading = false; this.refreshRequest = undefined; this.marking = true; this.error = '';
    const session = authSession.session();
    const uid: number = authSession.snapshot.uid;
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!this.current(mine)) { return ''; }
      const before = await this.api.fetchNotifyUnread(device, session);
      if (!this.current(mine)) { return ''; }
      if (!before.ok) { this.error = before.describeFailure(); return '提醒读取失败，请重试'; }
      this.counts = before.data; this.loaded = true;
      if (this.allRead()) { return '暂无未读消息'; }
      let failed: boolean = false;
      const kinds: NotifyKind[] = ['agree', 'reply', 'at'];
      for (const kind of kinds) {
        if (!this.current(mine)) { return ''; }
        if (before.data.count(kind) === 0) { continue; }
        try {
          const result = await this.api.fetchNotifyFeed(device, session, kind, 1, 0, uid);
          if (!this.current(mine)) { return ''; }
          if (!result.ok) { failed = true; }
          else { this.acceptPreview(kind, notifyActionPreview(result.items.length > 0 ? result.items[0] : undefined), expectedAccount); }
        } catch (err) { failed = true; }
      }
      if (!this.current(mine)) { return ''; }
      if (before.data.fans > 0) {
        if (!Number.isSafeInteger(uid) || uid <= 0) { failed = true; }
        else {
          try {
            const fans = await this.api.fetchDirectory(device, session, 'fans', uid, 1);
            if (!this.current(mine)) { return ''; }
            if (!fans.ok) { failed = true; }
            else {
              this.acceptPreview('fans', fanActionPreview(fans.data.users.length > 0 ? fans.data.users[0].name : undefined,
                fans.data.preface), expectedAccount);
            }
          } catch (err) { failed = true; }
        }
      }
      if (!this.current(mine)) { return ''; }
      const after = await this.api.fetchNotifyUnread(device, session);
      if (!this.current(mine)) { return ''; }
      if (!after.ok) {
        this.error = after.describeFailure(); return '已读状态未确认，请下拉刷新核对';
      }
      this.counts = after.data;
      if (this.allRead()) { return '已将消息全部标记为已读'; }
      return failed ? '部分消息标记失败，请重试' : '仍有未读消息，请稍后重试';
    } catch (err) {
      if (!this.current(mine)) { return ''; }
      this.error = '已读状态未确认，请下拉刷新核对';
      return this.error;
    } finally {
      if (mine === this.epoch) {
        this.marking = false;
        this.syncAccount();
      }
    }
  }

  private allRead(): boolean {
    return this.counts.agree === 0 && this.counts.reply === 0 && this.counts.at === 0 && this.counts.fans === 0;
  }

  private clear(): void {
    this.epoch++; this.loading = false; this.marking = false; this.refreshRequest = undefined;
    this.counts = new NotifyUnreadCounts(); this.loaded = false; this.error = '';
    this.previews = new NotifyPreviews(); this.account = '';
  }

  /** 外壳销毁时清理会话内存；单例在新外壳中仍可使用。 */
  reset(): void {
    this.clear(); this.disposed = false;
  }

  dispose(): void {
    this.clear(); this.disposed = true;
  }
}

export const notifyUnreadVM: NotifyUnreadVM = new NotifyUnreadVM();
