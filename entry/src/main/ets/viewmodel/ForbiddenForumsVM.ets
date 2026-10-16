import { common } from '@kit.AbilityKit';
import { TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { ForbiddenForum, mergeForbiddenForums } from '../model/ForbiddenForums';
import { DeviceIdentity } from '../utils/DeviceIdentity';

function owner(): string {
  return authSession.isLoggedIn() ? authSession.sessionKey() : '';
}

/** 屏蔽吧列表的刷新与分页状态。分页失败不推进页码，重试沿用失败页；停滞与全部加载完成分别处理。 */
@ObservedV2
export class ForbiddenForumsVM {
  @Trace items: ForbiddenForum[] = [];
  @Trace loading: boolean = false;
  @Trace loadingMore: boolean = false;
  @Trace loaded: boolean = false;
  @Trace hasMore: boolean = false;
  /** 服务端说还有更多、但连续翻页没有带来新内容（拉不动了，不等于已加载完） */
  @Trace stalled: boolean = false;
  @Trace error: string = '';
  @Trace pagingError: string = '';
  private account: string = '';
  private epoch: number = 0;
  private page: number = 0;
  private disposed: boolean = false;
  private api: TiebaApi = new TiebaApi();

  async load(context: common.UIAbilityContext, more: boolean = false, onStarted: () => void = (): void => {},
    onSettled: () => void = (): void => {}): Promise<void> {
    if (this.disposed) { return; }
    // 账号切换后的续页变成首屏，禁止沿用前一账号列表和页码。
    if (this.account !== owner()) { more = false; }

    if (more && (!this.loaded || !this.hasMore || this.loading || this.loadingMore || this.pagingError.length > 0)) { return; }
    if (!more && this.loading && this.account === owner()) { return; }
    const mine: number = ++this.epoch;
    const switching: boolean = this.account.length > 0 && this.account !== owner();
    this.account = owner();
    this.error = ''; this.pagingError = '';
    if (this.account.length === 0) {
      // 未登录/退出：立即清空列表、分页与错误状态，旧账号数据不能顶替
      this.loading = false; this.error = '登录后才能读取屏蔽吧';
      this.items = []; this.loaded = false; this.hasMore = false; this.page = 0; this.stalled = false;
      return;
    }
    if (switching) {
      // 换号：立即清空旧账号的列表、分页与状态，读取期间不展示旧账号数据
      this.items = []; this.loaded = false; this.hasMore = false; this.page = 0; this.stalled = false; this.pagingError = '';
    }
    /*
     * ⚠️ 刷新分支**不动** `items`/`page`/`hasMore`：
     * 失败时要把已有内容原样留在屏幕上，并保住游标（重试仍请求同一页）。
     * 成功后再整体替换（下面的 `mergeForbiddenForums([], …)`）。
     */
    const requested: number = more ? this.page + 1 : 1;
    this.loading = !more; this.loadingMore = more;
    if (more) { onStarted(); }
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!this.current(mine)) { return; }
      const response = await this.api.fetchForbiddenForums(device, authSession.session(), authSession.snapshot.uid, requested);
      if (!this.current(mine)) { return; }
      if (!response.ok) {
        if (more) { this.pagingError = response.describeFailure(); } else { this.error = response.describeFailure(); }
        return;
      }
      if (response.data.page > 0 && response.data.page !== requested) {
        if (more) { this.pagingError = '返回页码不一致，请重试'; } else { this.error = '返回页码不一致，请重试'; }
        return;
      }
      const before: number = more ? this.items.length : 0;
      const merged: ForbiddenForum[] = mergeForbiddenForums(more ? this.items : [], response.data.items);
      const grew: boolean = merged.length > before;
      this.items = merged; this.page = requested; this.loaded = true;
      this.hasMore = response.data.hasMore && grew;
      this.stalled = response.data.hasMore && !grew;
    } catch (err) {
      if (this.current(mine)) {
        if (more) { this.pagingError = '屏蔽吧续页读取失败，请重试'; } else { this.error = '屏蔽吧读取失败，请重试'; }
      }
    } finally {
      if (mine === this.epoch) {
        this.loading = false; this.loadingMore = false;
        if (this.account !== owner()) {
          this.items = []; this.loaded = false; this.hasMore = false; this.page = 0; this.stalled = false;
          this.error = '账号已变化，请重新读取'; this.pagingError = '';
        } else if (!this.disposed) { onSettled(); }
      }
    }
  }

  private current(mine: number): boolean { return !this.disposed && mine === this.epoch && this.account === owner(); }
  dispose(): void { this.disposed = true; this.epoch++; this.loading = false; this.loadingMore = false; }

  /**
   * 手动重试分页：清掉 `pagingError` 后请求**失败的那一页**（页码未推进）。
   *
   * 与自动续页分道的原因：失败后再次触底不该静默重发（可能连环打失败接口），
   * 只有用户点了「加载失败，点击重试」才允许再请求。没有待重试的错误时是空操作。
   */
  async retryPaging(context: common.UIAbilityContext): Promise<void> {
    if (this.disposed || this.pagingError.length === 0) { return; }
    this.pagingError = '';
    await this.load(context, true);
  }
}
