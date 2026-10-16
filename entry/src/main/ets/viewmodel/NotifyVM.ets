
import { common } from '@kit.AbilityKit';
import { NotifyResponse, TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { NotifyCursor, NotifyItem, NotifyKind } from '../model/Notify';
import { DeviceIdentity } from '../utils/DeviceIdentity';

function owner(): string {
  return authSession.isLoggedIn() ? `${authSession.snapshot.uid}:${authSession.snapshot.portrait}` : '';
}

@ObservedV2
export class NotifyVM {
  /** 通知种类（构造后由页面设置一次；运行中不切换 —— 切种类就换一个新的 VM 实例） */
  readonly kind: NotifyKind;
  @Trace items: NotifyItem[] = [];
  @Trace loading: boolean = false;
  @Trace loadingMore: boolean = false;
  @Trace loadedOnce: boolean = false;
  @Trace error: string = '';
  /** 翻页失败的一次性提示（不打断已有列表） */
  @Trace loadMoreError: string = '';
  @Trace hasMore: boolean = false;
  /** reply：当前页码；agree：游标。两者合并在一个游标对象里 */
  private cursor: NotifyCursor = new NotifyCursor();
  /** 异步代次：刷新/翻页期间又触发新的加载时，旧结果一律丢弃 */
  private epoch: number = 0;
  private api: TiebaApi = new TiebaApi();
  private account: string = '';
  private disposed: boolean = false;

  constructor(kind: NotifyKind) {
    this.kind = kind;
  }

  hasItems(): boolean {
    return this.items.length > 0;
  }

  /** 首次加载 / 下拉刷新：清空重来，页码/游标复位 */
  async refresh(context: common.UIAbilityContext): Promise<void> {
    if (this.disposed || (this.loading && this.account === owner())) { return; }
    const changed: boolean = this.account !== owner();
    this.account = owner();
    const mine: number = ++this.epoch;
    this.loading = true;
    this.loadingMore = false;
    this.error = '';
    this.loadMoreError = '';
    if (changed) { this.items = []; this.hasMore = false; this.loadedOnce = false; this.cursor = new NotifyCursor(); }
    if (this.account.length === 0) { this.loading = false; this.error = '登录后才能读取通知'; return; }
    try {
      await this.fetch(context, mine, true, new NotifyCursor());
    } finally {
      this.finish(mine);
    }
  }

  /** 触底加载下一页（reply 推进页码 / agree 推进游标） */
  async loadMore(context: common.UIAbilityContext): Promise<void> {
    if (this.disposed) { return; }
    if (this.account !== owner()) { await this.refresh(context); return; }
    if (this.loading || this.loadingMore || !this.hasMore) { return; }
    const mine: number = ++this.epoch;
    this.loadingMore = true;
    this.loadMoreError = '';
    try {
      // 候选游标与已确认游标分离，只有当前代次成功时才提交。
      const request: NotifyCursor = new NotifyCursor();
      request.page = this.cursor.page + (this.kind !== 'agree' ? 1 : 0);
      request.agreeId = this.cursor.agreeId;
      await this.fetch(context, mine, false, request);
    } finally {
      this.finish(mine);
    }
  }

  /** 发一次请求并合并结果；返回"是否真的拿到了新条目" */
  private async fetch(context: common.UIAbilityContext, mine: number, replace: boolean,
    request: NotifyCursor): Promise<boolean> {
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!this.current(mine)) { return false; }
      const response: NotifyResponse = await this.api.fetchNotifyFeed(
        device, authSession.session(), this.kind, request.page, request.agreeId, authSession.snapshot.uid);
      if (!this.current(mine)) { return false; }
      if (!response.ok) {
        if (replace) {
          this.error = response.describeFailure();
        } else {
          this.loadMoreError = response.describeFailure();
        }
        return false;
      }
      if (this.kind === 'at' && response.page > 0 && response.page !== request.page) {
        if (replace) { this.error = '返回页码不一致，请重试'; } else { this.loadMoreError = '返回页码不一致，请重试'; }
        return false;
      }
      if (replace) {
        this.items = response.items;
      } else {
        // 去重：reply 按 thread_id+post_id，agree 按对方+时间（agree 的稳定键是 thread+agreeer）
        const seen: Set<string> = new Set<string>();
        for (const item of this.items) { seen.add(this.keyOf(item)); }
        let added: number = 0;
        for (const item of response.items) {
          const key: string = this.keyOf(item);
          if (!seen.has(key)) { seen.add(key); this.items.push(item); added++; }
        }
        if (added === 0) {
          // 服务端给了重复内容：按"没有更多"处理，避免死循环续页
          this.hasMore = false;
          return false;
        }
      }
      this.cursor = request;
      if (this.kind !== 'agree') {
        this.hasMore = response.hasMore && response.items.length > 0;
      } else {
        this.hasMore = response.agreeHasMore && response.items.length > 0 &&
          response.nextAgreeId > 0 && response.nextAgreeId !== request.agreeId;
        this.cursor.agreeId = response.nextAgreeId;
      }
      this.loadedOnce = true;
      return response.items.length > 0;
    } catch (err) {
      if (this.current(mine)) {
        if (replace) { this.error = '加载失败，请重试'; } else { this.loadMoreError = '加载更多失败'; }
      }
      return false;
    }
  }

  private keyOf(item: NotifyItem): string {
    if (this.kind === 'at') { return `at-${item.threadIdText}-${item.postIdText}-${item.userIdText}-${item.timeMs}`; }
    if (this.kind === 'reply') {
      return `r-${item.threadId}-${item.postId}-${item.userId}`;
    }
    return `a-${item.threadId}-${item.postId}-${item.userId}-${item.timeMs}`;
  }
  private current(mine: number): boolean { return !this.disposed && mine === this.epoch && this.account === owner(); }
  private finish(mine: number): void {
    if (mine !== this.epoch) { return; }
    this.loading = false; this.loadingMore = false;
    if (this.account !== owner()) {
      this.items = []; this.hasMore = false; this.loadedOnce = false; this.cursor = new NotifyCursor();
      this.error = '账号已变化，请重新读取'; this.loadMoreError = '';
    }
  }
  dispose(): void {
    this.disposed = true; this.epoch++; this.items = []; this.hasMore = false; this.loadedOnce = false;
    this.loading = false; this.loadingMore = false;
  }
}
