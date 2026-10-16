import { common } from '@kit.AbilityKit';
import { TiebaApi, DirectoryResponse } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { DirectoryData, DirectoryKind, mergeDirectoryUsers } from '../model/PageDirectory';
import { DeviceIdentity } from '../utils/DeviceIdentity';

@ObservedV2
export class DirectoryVM {
  @Trace data: DirectoryData = new DirectoryData();
  @Trace loading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace error: string = '';
  @Trace pagingError: string = '';
  @Trace loadingMore: boolean = false;
  private page: number = 0;
  private api: TiebaApi = new TiebaApi();

  async load(context: common.UIAbilityContext, kind: DirectoryKind, id: number,
    more: boolean = false): Promise<void> {
    if (this.loading || this.loadingMore || (more && !this.data.hasMore)) { return; }
    if (more) { this.loadingMore = true; this.pagingError = ''; }
    else { this.loading = true; this.error = ''; }
    try {
      const device = await DeviceIdentity.ensure(context);
      const response: DirectoryResponse = await this.api.fetchDirectory(
        device, authSession.session(), kind, id, more ? this.page + 1 : 1);
      if (!response.ok) {
        if (more) { this.pagingError = response.describeFailure(); }
        else { this.error = response.describeFailure(); }
        return;
      }
      if (more) {
        const oldCount: number = this.data.users.length;
        response.data.users = mergeDirectoryUsers(this.data.users, response.data.users);

        response.data.hasMore = response.data.hasMore && response.data.users.length > oldCount;
      }
      this.data = response.data;
      this.page = more ? this.page + 1 : 1;
    } catch (err) {
      if (more) { this.pagingError = '加载失败，请重试'; }
      else { this.error = '加载失败，请重试'; }
    } finally {
      this.loading = false;
      this.loadingMore = false;
      this.loaded = true;
    }
  }
}
