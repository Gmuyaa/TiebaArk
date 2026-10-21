import { common } from '@kit.AbilityKit';
import { TiebaApi, DirectoryResponse } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { DirectoryData, DirectoryKind, mergeDirectoryUsers } from '../model/PageDirectory';
import { DeviceIdentity } from '../utils/DeviceIdentity';

function owner(): string { return authSession.sessionKey(); }

@ObservedV2
export class DirectoryVM {
  @Trace data: DirectoryData = new DirectoryData();
  @Trace loading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace error: string = '';
  @Trace pagingError: string = '';
  @Trace loadingMore: boolean = false;
  private page: number = 0;
  private target: string = '';
  private account: string = '';
  private epoch: number = 0;
  private disposed: boolean = false;
  private api: TiebaApi = new TiebaApi();

  async load(context: common.UIAbilityContext, kind: DirectoryKind, id: number,
    more: boolean = false): Promise<void> {
    if (this.disposed) { return; }
    const target: string = `${kind}:${id}`;
    const changed: boolean = this.target !== target || this.account !== owner();
    if (!changed && ((this.loading && !more) || (more && (this.loading || this.loadingMore || !this.data.hasMore)))) { return; }
    if (changed) {
      this.target = target; this.account = owner(); more = false;
      this.data = new DirectoryData(); this.page = 0; this.loaded = false;
    }
    const mine: number = ++this.epoch;
    const nextPage: number = more ? this.page + 1 : 1;
    this.loadingMore = false;
    this.pagingError = '';
    if (more) { this.loadingMore = true; this.pagingError = ''; }
    else { this.loading = true; this.error = ''; }
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!this.current(mine)) { return; }
      const response: DirectoryResponse = await this.api.fetchDirectory(
        device, authSession.session(), kind, id, nextPage);
      if (!this.current(mine)) { return; }
      if (!response.ok) {
        if (more) { this.pagingError = response.describeFailure(); }
        else { this.error = response.describeFailure(); }
        return;
      }
      if (more) {
        const oldCount: number = this.data.users.length;
        response.data.users = mergeDirectoryUsers(this.data.users, response.data.users);
        // 服务端重复同页时停止续页，避免触底产生无进展的循环请求。
        response.data.hasMore = response.data.hasMore && response.data.users.length > oldCount;
      }
      this.data = response.data;
      this.page = nextPage;
      this.loaded = true;
    } catch (err) {
      if (!this.current(mine)) { return; }
      if (more) { this.pagingError = '加载失败，请重试'; }
      else { this.error = '加载失败，请重试'; }
    } finally {
      if (mine === this.epoch) {
        this.loading = false; this.loadingMore = false;
        if (this.account !== owner()) {
          this.data = new DirectoryData(); this.page = 0; this.loaded = false;
          this.error = '账号已变化，请重新读取'; this.pagingError = '';
        }
      }
    }
  }
  private current(mine: number): boolean {
    return !this.disposed && mine === this.epoch && this.account === owner();
  }
  dispose(): void {
    this.disposed = true; this.epoch++; this.data = new DirectoryData();
    this.loaded = false; this.loading = false; this.loadingMore = false;
  }
}
