import { common } from '@kit.AbilityKit';
import { TiebaApi, DirectoryResponse } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { DirectoryData, DirectoryKind, DirectoryUser, mergeDirectoryUsers } from '../model/PageDirectory';
import { fanActionPreview } from '../model/NotifyUnread';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { FollowReadGuard, seedFollowState } from './FollowActionVM';
import { registerForumAlias } from './ForumStateStore';
import { notifyUnreadVM } from './NotifyUnreadVM';
import { rawSessionKey } from './SessionOwner';


@ObservedV2
export class DirectoryVM {
  @Trace data: DirectoryData = new DirectoryData();
  @Trace loading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace error: string = '';
  @Trace pagingError: string = '';
  @Trace loadingMore: boolean = false;
  @Trace removingUid: number = 0;
  @Trace pagingNeedsRefresh: boolean = false;
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
    const changed: boolean = this.target !== target || this.account !== rawSessionKey();
    if (this.removingUid > 0 && !changed) { return; }
    if (!changed && ((this.loading && !more) || (more && (this.loading || this.loadingMore || !this.data.hasMore)))) { return; }
    if (changed) {
      this.removingUid = 0;
      this.pagingNeedsRefresh = false;
      this.target = target; this.account = rawSessionKey(); more = false;
      this.data = new DirectoryData(); this.page = 0; this.loaded = false;
    }
    const mine: number = ++this.epoch;
    const previewAccount: string = authSession.isLoggedIn() ? authSession.sessionKey() : '';
    const session = authSession.session();
    const ownUid: number = authSession.snapshot.uid;
    const followGuard: FollowReadGuard = new FollowReadGuard();
    const nextPage: number = more ? this.page + 1 : 1;
    this.loadingMore = false;
    this.pagingError = '';
    if (more) { this.loadingMore = true; this.pagingError = ''; }
    else { this.loading = true; this.error = ''; }
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!this.current(mine)) { return; }
      const response: DirectoryResponse = await this.api.fetchDirectory(
        device, session, kind, id, nextPage);
      if (!this.current(mine)) { return; }
      if (!response.ok) {
        if (more) { this.pagingError = response.describeFailure(); }
        else { this.error = response.describeFailure(); }
        return;
      }
      if (!more && kind === 'fans' && previewAccount.length > 0 && id === ownUid &&
        authSession.snapshot.uid === ownUid) {
        notifyUnreadVM.acceptPreview('fans',
          fanActionPreview(response.data.users.length > 0 ? response.data.users[0].name : undefined, response.data.preface),
          previewAccount);
      }
      // 只发布本次网络返回的关系；合并后的旧页行不能覆盖刚确认的回关。
      if (kind === 'fans' || kind === 'following') {
        for (const user of response.data.users) {
          seedFollowState(followGuard, 'user', user.uid, user.portrait, user.name, user.followed);
        }
      } else if (kind === 'forum' && response.data.forum.id > 0) {
        // 吧资料回包不含关注字段，但能把名字与 fid 对上：关注按钮据此复用同一份身份状态。
        registerForumAlias(response.data.forum.id, response.data.forum.name);
      }
      if (more) {
        const oldCount: number = this.data.users.length;
        response.data.users = mergeDirectoryUsers(this.data.users, response.data.users);
        // 服务端重复同页时停止续页，避免触底产生无进展的循环请求。
        response.data.hasMore = response.data.hasMore && response.data.users.length > oldCount;
      }
      this.data = response.data;
      this.pagingNeedsRefresh = false;
      this.page = nextPage;
      this.loaded = true;
    } catch (err) {
      if (!this.current(mine)) { return; }
      if (more) { this.pagingError = '加载失败，请重试'; }
      else { this.error = '加载失败，请重试'; }
    } finally {
      if (mine === this.epoch) {
        this.loading = false; this.loadingMore = false;
        if (this.account !== rawSessionKey()) {
          this.data = new DirectoryData(); this.page = 0; this.loaded = false;
          this.error = '账号已变化，请重新读取'; this.pagingError = '';
        }
      }
    }
  }

  /** 仅本人列表、确认后的当前会话可移除；业务成功才撤下行，写后停止旧偏移续页。 */
  async removeFan(context: common.UIAbilityContext, user: DirectoryUser, expectedOwner: string): Promise<string> {
    const uid: number = authSession.snapshot.uid;
    if (this.disposed || this.removingUid > 0 || !authSession.isLoggedIn() || expectedOwner !== rawSessionKey() ||
      this.account !== expectedOwner || this.target !== `fans:${uid}` || !Number.isSafeInteger(user.uid) ||
      user.uid <= 0 || user.uid === uid || !this.data.users.some((row: DirectoryUser): boolean => row.uid === user.uid)) { return ''; }
    const mine: number = ++this.epoch;
    const hadMore: boolean = this.data.hasMore || this.loadingMore || this.pagingNeedsRefresh;
    this.loading = false; this.loadingMore = false; this.removingUid = user.uid;
    let sent: boolean = false;
    try {
      if (authSession.session().tbs.length === 0) {
        const refreshed = await authSession.refreshTbs(context);
        if (!this.current(mine)) { return ''; }
        if (!refreshed.ok) { return refreshed.message; }
      }
      const device = await DeviceIdentity.ensure(context);
      if (!this.current(mine)) { return ''; }
      sent = true;
      const result = await this.api.removeFan(device, authSession.session(), user.uid);
      if (!this.current(mine)) { return ''; }
      if (!result.ok) {
        return result.transportError.length > 0 || result.errorCode < 0 ? '移除结果未确认，请下拉刷新核对' : result.describeFailure();
      }
      this.data = this.withoutPagination(this.data.users.filter((row: DirectoryUser): boolean => row.uid !== user.uid));
      void authSession.refreshProfile(context);
      return '已移除粉丝';
    } catch (err) {
      return this.current(mine) ? (sent ? '移除结果未确认，请下拉刷新核对' : '移除失败，请重试') : '';
    } finally {
      if (mine === this.epoch) {
        this.removingUid = 0;
        if (sent) { this.data = this.withoutPagination(this.data.users); this.pagingError = ''; this.pagingNeedsRefresh = hadMore; }
        if (this.account !== rawSessionKey()) { this.data = new DirectoryData(); this.loaded = false; this.error = ''; }
      }
    }
  }
  private withoutPagination(users: DirectoryUser[]): DirectoryData {
    const data: DirectoryData = new DirectoryData();
    data.forum = this.data.forum; data.rules = this.data.rules; data.title = this.data.title; data.preface = this.data.preface;
    data.users = users; data.total = Math.max(0, this.data.total - (this.data.users.length - users.length));
    return data;
  }
  private current(mine: number): boolean {
    return !this.disposed && mine === this.epoch && this.account === rawSessionKey();
  }
  dispose(): void {
    this.disposed = true; this.epoch++; this.data = new DirectoryData();
    this.loaded = false; this.loading = false; this.loadingMore = false; this.removingUid = 0; this.pagingNeedsRefresh = false;
  }
}
