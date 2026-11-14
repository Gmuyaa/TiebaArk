import { common } from '@kit.AbilityKit';
import { TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { ForumSearchItem } from '../model/ForumSearch';
import {
  getCachedForumAvatarUrl, getForumAvatar, getForumAvatarId, isForumAvatarFetched, markForumAvatarFetched, putForumAvatar
} from '../model/ForumAvatarStore';
import { FORUM_AVATAR_URL_TTL_MS } from '../model/CachePolicy';
import { SearchPostItem } from '../model/SearchPost';
import { TiebaDevice } from '../net/TiebaParams';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { addSearchHistory } from '../utils/SearchHistory';
import { SearchForumAvatarDone, SearchPostAvatarsVM } from './SearchPostAvatarsVM';
import { SearchUsersVM } from './SearchUsersVM';

/** 搜帖结果每页条数；搜吧与搜人沿用各自接口的分页规格。 */
const SEARCH_PAGE_SIZE: number = 30;

/** 搜索请求与分页状态；页面只负责输入、结果分类及展示。 */
@ObservedV2
export class SearchResultVM {
  @Trace word: string = '';
  @Trace items: SearchPostItem[] = [];
  @Trace loading: boolean = false;
  @Trace loadingMore: boolean = false;
  @Trace hasMore: boolean = false;
  @Trace errorText: string = '';
  @Trace pagingError: string = '';
  @Trace forumItems: ForumSearchItem[] = [];
  @Trace forumLoading: boolean = false;
  @Trace forumErrorText: string = '';
  @Trace users: SearchUsersVM = new SearchUsersVM();
  @Trace postAvatars: SearchPostAvatarsVM = new SearchPostAvatarsVM();

  private page: number = 0;
  private scopeForum: string = '';
  private requestEpoch: number = 0;
  private disposed: boolean = false;
  private api: TiebaApi = new TiebaApi();

  private current(epoch: number): boolean {
    return !this.disposed && epoch === this.requestEpoch;
  }

  private currentOwner(epoch: number, owner: string): boolean {
    return this.current(epoch) && owner === authSession.sessionKey();
  }

  /** 每次改词独立补图；旧查询与旧账号的结果不能回填当前卡片。 */
  private prepareAvatars(context: common.UIAbilityContext, epoch: number): void {
    const owner: string = authSession.sessionKey();
    this.postAvatars.reset(async (name: string, forum: boolean, tid: number, pid: number,
      onForumAvatar: SearchForumAvatarDone): Promise<string> => {
      if (!this.currentOwner(epoch, owner)) { return ''; }
      const avatarApi: TiebaApi = new TiebaApi();
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!this.currentOwner(epoch, owner)) { return ''; }
      if (!forum) {
        const url: string = await avatarApi.fetchSearchPostAuthorAvatar(device, authSession.session(), tid, pid,
          (forumName: string, avatar: string): void => {
            if (!this.currentOwner(epoch, owner) || forumName.trim() !== name || name.length === 0) { return; }
            putForumAvatar(name, avatar);
            markForumAvatarFetched(name);
            onForumAvatar(name, avatar);
          });
        return this.currentOwner(epoch, owner) ? url : '';
      }
      if (isForumAvatarFetched(name)) {
        const cached: string = getForumAvatar(name);
        if (cached.length > 0) { return cached; }
      }
      // 落盘地址在 TTL 内直接复用，不发请求（2026-11-13 方案 2）。
      const fromDisk: string = getCachedForumAvatarUrl(name, Date.now(), FORUM_AVATAR_URL_TTL_MS);
      if (fromDisk.length > 0) {
        markForumAvatarFetched(name);
        return fromDisk;
      }
      // 会话里已知这个吧的 fid 就走轻量端点；不知道才按吧名拉整页 frs/page。
      const known: number = getForumAvatarId(name);
      const url: string = await avatarApi.fetchForumAvatar(device, authSession.session(), name, known, 'search');
      if (!this.currentOwner(epoch, owner)) { return ''; }
      if (url.length > 0) { putForumAvatar(name, url, known); markForumAvatarFetched(name); }
      return url;
    });
  }

  /** 改词重搜与进入页面共用；空词不写历史，也不发起请求。 */
  async reload(context: common.UIAbilityContext, input: string, scopeForum: string = '',
    searchUsers: boolean = false): Promise<void> {
    const word: string = input.trim();
    if (this.disposed || word.length === 0) { return; }
    const epoch: number = ++this.requestEpoch;
    this.prepareAvatars(context, epoch);
    this.scopeForum = scopeForum;
    this.loadingMore = false;
    this.forumItems = [];
    this.forumLoading = false;
    this.forumErrorText = '';
    this.word = word;
    this.loading = true;
    this.errorText = ''; this.pagingError = '';
    this.page = 0;
    this.items = [];
    this.hasMore = false;
    this.users.reset(word);
    // 历史保持去重置顶；落库失败不影响搜索。
    await addSearchHistory(context, word).catch(() => {});
    if (!this.current(epoch)) { return; }
    // 公开搜吧与搜帖并行，失败状态互不影响；吧内只搜索帖子。
    if (this.scopeForum.length === 0) {
      void this.fetchForums(word, epoch);
      if (searchUsers) { void this.users.load(); }
    }
    await this.fetchPage(context, word, epoch);
    if (this.current(epoch)) { this.loading = false; }
  }

  async retryForums(): Promise<void> {
    if (this.disposed || this.word.length === 0 || this.scopeForum.length > 0 || this.forumLoading) { return; }
    await this.fetchForums(this.word, this.requestEpoch);
  }

  private async fetchForums(word: string, epoch: number): Promise<void> {
    this.forumLoading = true;
    this.forumErrorText = '';
    try {
      const response = await this.api.searchForums(word, 1, 20);
      if (!this.current(epoch)) { return; }
      if (!response.ok) {
        this.forumErrorText = response.describeFailure();
        return;
      }
      this.forumItems = response.data.items;
    } catch (err) {
      const e: Error = err as Error;
      if (this.current(epoch)) { this.forumErrorText = `加载失败：${e.message}`; }
    } finally {
      if (this.current(epoch)) { this.forumLoading = false; }
    }
  }

  async loadMore(context: common.UIAbilityContext, retry: boolean = false): Promise<void> {
    if (this.disposed || this.loading || this.loadingMore || !this.hasMore || (this.pagingError.length > 0 && !retry)) {
      return;
    }
    this.loadingMore = true; this.pagingError = '';
    const epoch: number = this.requestEpoch;
    await this.fetchPage(context, this.word, epoch);
    if (this.current(epoch)) { this.loadingMore = false; }
  }

  private async fetchPage(context: common.UIAbilityContext, word: string, epoch: number): Promise<void> {
    const requested: number = this.page + 1;
    const owner: string = authSession.sessionKey();
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!this.currentOwner(epoch, owner)) { return; }
      const response = await this.api.searchPosts(
        device, authSession.session(), word, requested, SEARCH_PAGE_SIZE, this.scopeForum);
      if (!this.currentOwner(epoch, owner)) { return; }
      if (!response.ok) { this.setPageError(requested, response.describeFailure()); return; }
      if (response.data.page !== requested) { this.setPageError(requested, '返回页码不一致，请重试'); return; }
      const seen: Set<string> = new Set<string>();
      const next: SearchPostItem[] = requested === 1 ? [] : this.items.slice();
      for (const item of next) { seen.add(`${item.tid}:${item.pid}`); }
      const before: number = next.length;
      for (const item of response.data.items) {
        const key: string = `${item.tid}:${item.pid}`;
        if (!seen.has(key)) { seen.add(key); next.push(item); }
      }
      this.items = next;
      this.page = requested;
      this.hasMore = response.data.hasMore && next.length > before;
    } catch (err) {
      const e: Error = err as Error;
      if (this.currentOwner(epoch, owner)) { this.setPageError(requested, `加载失败：${e.message}`); }
    }
  }

  private setPageError(requested: number, message: string): void {
    if (requested === 1) { this.errorText = message; } else { this.pagingError = message; }
  }

  requestAvatar(item: SearchPostItem): void {
    if (this.disposed) { return; }
    const cached: string = isForumAvatarFetched(item.forumName) ? getForumAvatar(item.forumName) : '';
    this.postAvatars.request(item.tid, item.pid, item.forumName, cached);
  }

  dispose(): void {
    this.disposed = true;
    this.requestEpoch++;
    this.loading = false;
    this.loadingMore = false;
    this.forumLoading = false;
    this.users.dispose();
    this.postAvatars.reset();
  }
}
