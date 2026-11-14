import { common } from '@kit.AbilityKit';
import { TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { ForbiddenForum, mergeForbiddenForums } from '../model/ForbiddenForums';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { loggedInSessionKey } from './SessionOwner';


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
  @Trace selecting: boolean = false;
  @Trace selectedIds: string[] = [];
  @Trace actionBusy: boolean = false;
  @Trace actionMessage: string = '';
  @Trace preparedCount: number = 0;
  private prepared: ForbiddenForum[] = [];
  private preparedOwner: string = '';
  @Trace executing: boolean = false;
  @Trace processed: number = 0;
  private stopRequested: boolean = false;
  private selectedSnapshot: string[] = [];
  private selectedIndex: Set<string> = new Set<string>();
  private account: string = '';
  private epoch: number = 0;
  private page: number = 0;
  private disposed: boolean = false;
  private api: TiebaApi = new TiebaApi();

  async load(context: common.UIAbilityContext, more: boolean = false, onStarted: () => void = (): void => {},
    onSettled: () => void = (): void => {}): Promise<void> {
    if (this.disposed || this.actionBusy) { return; }
    // 账号切换后的续页变成首屏，禁止沿用前一账号列表和页码。
    if (this.account !== loggedInSessionKey()) { more = false; }

    if (more && (!this.loaded || !this.hasMore || this.loading || this.loadingMore || this.pagingError.length > 0)) { return; }
    if (!more && this.loading && this.account === loggedInSessionKey()) { return; }
    const mine: number = ++this.epoch;
    const switching: boolean = this.account.length > 0 && this.account !== loggedInSessionKey();
    this.account = loggedInSessionKey();
    this.error = ''; this.pagingError = '';
    if (this.account.length === 0) {
      this.selecting = false; this.selectedIds = [];
      // 未登录/退出：立即清空列表、分页与错误状态，旧账号数据不能顶替
      this.loading = false; this.error = '登录后才能读取屏蔽吧';
      this.items = []; this.loaded = false; this.hasMore = false; this.page = 0; this.stalled = false;
      return;
    }
    if (switching) {
      this.selecting = false; this.selectedIds = [];
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
        if (this.account !== loggedInSessionKey()) {
          this.items = []; this.loaded = false; this.hasMore = false; this.page = 0; this.stalled = false;
          this.error = '账号已变化，请重新读取'; this.pagingError = '';
        } else if (!this.disposed) { onSettled(); }
      }
    }
  }

  private current(mine: number): boolean { return !this.disposed && mine === this.epoch && this.account === loggedInSessionKey(); }
  dispose(): void { this.disposed = true; this.epoch++; this.loading = false; this.loadingMore = false; this.cancelPrepared(); }

  ownsCurrentAccount(): boolean { return !this.disposed && this.account.length > 0 && this.account === loggedInSessionKey(); }

  toggleSelection(): void {
    if (this.actionBusy || !this.ownsCurrentAccount()) { return; }
    this.selecting = !this.selecting; this.selectedIds = [];
  }

  toggleItem(id: string): void {
    if (!this.selecting || this.actionBusy || !this.ownsCurrentAccount()) { return; }
    if (!this.items.some((item: ForbiddenForum): boolean => item.id === id)) { return; }
    this.selectedIds = this.selectedIds.includes(id) ? this.selectedIds.filter((value: string): boolean => value !== id) : this.selectedIds.concat(id);
  }

  isSelected(id: string): boolean {
    if (this.selectedSnapshot !== this.selectedIds) {
      this.selectedSnapshot = this.selectedIds;
      this.selectedIndex = new Set<string>(this.selectedIds);
    }
    return this.selectedIndex.has(id);
  }

  allSelected(): boolean {
    return this.loaded && !this.hasMore && !this.stalled && this.pagingError.length === 0 && this.items.length > 0 &&
      this.items.every((item: ForbiddenForum): boolean => this.isSelected(item.id));
  }

  /** 全选覆盖全部分页；完整读取失败时保持原选择，绝不把已加载部分当成全量。 */
  async toggleAll(context: common.UIAbilityContext): Promise<void> {
    if (!this.selecting || this.actionBusy || !this.ownsCurrentAccount()) { return; }
    if (this.allSelected()) { this.selectedIds = []; return; }
    if (!await this.prepareAll(context)) { return; }
    this.selectedIds = this.items.map((item: ForbiddenForum): string => item.id);
    this.cancelPrepared();
  }

  prepareItems(ids: string[]): boolean {
    if (this.actionBusy || this.loading || this.loadingMore || !this.ownsCurrentAccount()) { return false; }
    this.actionMessage = '';
    const selected: Set<string> = new Set<string>(ids);
    this.prepared = this.items.filter((item: ForbiddenForum): boolean => selected.has(item.id));
    if (this.prepared.length === 0) { this.actionMessage = '请先选择要解除屏蔽的吧'; return false; }
    this.preparedOwner = loggedInSessionKey(); this.preparedCount = this.prepared.length; this.actionBusy = true;
    return true;
  }

  /** 全选前从第一页重读完整名单；未知、失败、停滞或超出读取上限都不能进入写入。 */
  async prepareAll(context: common.UIAbilityContext): Promise<boolean> {
    if (this.disposed || this.actionBusy || this.loading || this.loadingMore || !this.ownsCurrentAccount()) { return false; }
    this.actionBusy = true; this.actionMessage = '正在读取完整名单…';
    this.preparedOwner = loggedInSessionKey();
    try {
      const device = await DeviceIdentity.ensure(context);
      let all: ForbiddenForum[] = [];
      for (let page: number = 1; page <= 100; page++) {
        if (!this.preparedCurrent()) { throw new Error('账号已变化，未继续操作'); }
        const response = await this.api.fetchForbiddenForums(device, authSession.session(), authSession.snapshot.uid, page);
        if (!this.preparedCurrent()) { throw new Error('账号已变化，未继续操作'); }
        if (!response.ok) { throw new Error(response.describeFailure()); }
        if (response.data.page > 0 && response.data.page !== page) { throw new Error('返回页码不一致，未继续操作'); }
        const merged: ForbiddenForum[] = mergeForbiddenForums(all, response.data.items);
        if (response.data.hasMore && merged.length === all.length) { throw new Error('名单未读取完整，请重试'); }
        all = merged;
        if (!response.data.hasMore) {
          this.items = all; this.page = page; this.loaded = true; this.hasMore = false;
          this.stalled = false; this.error = ''; this.pagingError = '';
          this.prepared = all.slice(); this.preparedCount = all.length;
          this.actionMessage = '';
          if (all.length > 0) { return true; }
          this.cancelPrepared(); this.actionMessage = '账号暂无屏蔽吧'; return false;
        }
      }
      throw new Error('名单过多，未读取完整，请分批解除');
    } catch (err) {
      if (!this.disposed) { this.actionMessage = (err as Error).message; }
      this.cancelPrepared(); return false;
    }
  }

  private preparedCurrent(): boolean {
    return !this.disposed && this.preparedOwner.length > 0 && this.preparedOwner === loggedInSessionKey();
  }

  cancelPrepared(): void {
    if (this.executing) { return; }
    this.prepared = []; this.preparedCount = 0; this.preparedOwner = ''; this.actionBusy = false;
  }

  requestStop(): void {
    if (this.executing) { this.stopRequested = true; this.actionMessage = '正在停止…'; }
  }

  /** 两路有界请求，完成后一次提交列表和本机镜像；不自动重放失败或未确认的写入。 */
  async executePrepared(context: common.UIAbilityContext,
    onRemoved: (items: ForbiddenForum[]) => Promise<void>): Promise<void> {
    if (this.executing || !this.actionBusy || this.prepared.length === 0) { return; }
    if (!this.preparedCurrent()) { this.cancelPrepared(); this.actionMessage = '账号已变化，请重新确认'; return; }
    this.executing = true; this.stopRequested = false; this.processed = 0;
    const targets: ForbiddenForum[] = this.prepared.slice();
    const operationOwner: string = this.preparedOwner;
    const succeeded: Set<string> = new Set<string>();
    let failed: number = 0;
    let firstFailure: string = '';
    let stopReason: string = '';
    let next: number = 0;
    let lastProgress: number = 0;
    const total: number = targets.length;
    try {
      if (authSession.session().tbs.length === 0) {
        const refreshed = await authSession.refreshTbs(context);
        if (!this.preparedCurrent()) { throw new Error('账号已变化，已停止'); }
        if (!refreshed.ok) { throw new Error(refreshed.message); }
      }
      const session = authSession.session();
      const device = await DeviceIdentity.ensure(context);
      const worker = async (): Promise<void> => {
        while (next < total && !this.stopRequested && stopReason.length === 0) {
          if (!this.preparedCurrent() || !authSession.matchesSession(session, operationOwner)) {
            stopReason = '账号已变化或页面已关闭'; return;
          }
          const item: ForbiddenForum = targets[next++];
          try {
            const result = await this.api.unblockForum(device, session, item.id);
            if (!authSession.matchesSession(session, operationOwner)) { stopReason = '账号已变化'; return; }
            if (result.ok) { succeeded.add(item.id); }
            else {
              failed++; if (firstFailure.length === 0) { firstFailure = result.describeFailure(); }
              if (result.transportError && result.transportError.length > 0) { stopReason = '网络异常，已停止后续操作'; }
            }
          } catch (err) {
            failed++; if (firstFailure.length === 0) { firstFailure = (err as Error).message; }
            stopReason = '请求异常，已停止后续操作';
          }
          const completed: number = succeeded.size + failed;
          if (!this.disposed && !this.stopRequested && (completed === total || Date.now() - lastProgress >= 150)) {
            lastProgress = Date.now(); this.processed = completed;
            this.actionMessage = `正在取消 ${completed}/${total}…`;
          }
        }
      };
      await Promise.all([worker(), worker()]);
    } catch (err) {
      stopReason = (err as Error).message;
    } finally {
      // 保留稳定的行集合直到所有在途请求结束，避免每项成功触发整页重建。
      if (operationOwner === loggedInSessionKey()) {
        const removed: ForbiddenForum[] = targets.filter((item: ForbiddenForum): boolean => succeeded.has(item.id));
        if (!this.disposed) {
          this.items = this.items.filter((item: ForbiddenForum): boolean => !succeeded.has(item.id));
          this.selectedIds = this.selectedIds.filter((id: string): boolean => !succeeded.has(id));
          this.processed = succeeded.size + failed;
        }
        if (removed.length > 0) {
          try { await onRemoved(removed); } catch (err) { stopReason = '本机记录同步失败，请重新读取'; }
        }
        if (!this.disposed && operationOwner === loggedInSessionKey()) {
          const remaining: number = total - succeeded.size - failed;
          this.actionMessage = failed > 0 ? `已解除 ${succeeded.size} 个，${failed} 个失败：${firstFailure}` : `已解除 ${succeeded.size} 个吧的屏蔽`;
          if (this.stopRequested || stopReason.length > 0) {
            this.actionMessage += `；${stopReason || '已停止'}，剩余 ${remaining} 个未完成确认`;
          } else if (failed === 0) { this.selecting = false; this.selectedIds = []; }
        } else if (!this.disposed) { this.actionMessage = '账号已变化，请在原账号重新读取结果'; }
      } else if (!this.disposed) { this.actionMessage = '账号已变化，请在原账号重新读取结果'; }
      this.executing = false; this.cancelPrepared();
    }
  }

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
