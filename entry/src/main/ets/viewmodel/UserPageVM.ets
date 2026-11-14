import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DirectoryResponse, PublicProfileResponse, TiebaApi, UserPostsResponse } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { UserPostItem, mergeUserReplies } from '../model/MyContent';
import { ProfileForum, UserProfileInfo, avatarIdentity } from '../model/UserProfile';
import { backfillForumAvatars, ForumAvatarBackfillPlan, ForumAvatarNeed } from '../utils/ForumAvatarBackfill';
import { TiebaDevice, TiebaSession } from '../net/TiebaParams';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { FollowReadGuard, seedFollowState } from './FollowActionVM';

@ObservedV2
export class UserPageVM {
  @Trace profile: UserProfileInfo = new UserProfileInfo();
  @Trace profileLoaded: boolean = false;
  @Trace avatarRevision: number = 0;
  @Trace profileError: string = '';
  @Trace tab: number = 0;
  @Trace items: UserPostItem[] = [];
  @Trace forums: ProfileForum[] = [];
  @Trace loading: boolean = false;
  @Trace loadingMore: boolean = false;
  @Trace error: string = '';
  @Trace pagingError: string = '';
  @Trace postForumAvatars: Map<number, string> = new Map<number, string>();
  @Trace hasMore: boolean = false;
  private uid: number = 0;
  private portrait: string = '';
  /** 已发布展示版本对应的远端头像身份；只有它变化才推进缓存键。 */
  private portraitIdentity: string = '';
  private page: number = 0;
  private request: number = 0;
  private api: TiebaApi = new TiebaApi();
  private forumAvatars: Map<number, string> = new Map<number, string>();

  async initialize(context: common.UIAbilityContext, uid: number, portrait: string, tab: number = 0): Promise<void> {
    this.uid = uid;
    this.portrait = portrait;
    this.tab = tab === 1 || tab === 2 ? tab : 0;
    await this.refresh(context);
  }

  async refresh(context: common.UIAbilityContext, forceAvatarReload: boolean = false): Promise<void> {
    if (this.loading || this.loadingMore) { return; }
    const request: number = ++this.request;
    this.loading = true;
    this.profileError = '';
    const followGuard: FollowReadGuard = new FollowReadGuard();
    try {
      const device = await DeviceIdentity.ensure(context);
      const response: PublicProfileResponse = await this.api.fetchPublicProfile(
        device, authSession.session(), this.uid, this.portrait);
      if (request !== this.request) { return; }
      if (response.ok) {
        seedFollowState(followGuard, 'user', response.data.uid, response.data.portrait, '', response.data.followed);
        this.profile = response.data;
        this.publishAvatarIdentity(response.data.portrait, forceAvatarReload);
        this.profileLoaded = true;
        if (response.data.uid > 0) { this.uid = response.data.uid; }
        if (response.data.portrait.length > 0) { this.portrait = response.data.portrait; }
      } else { this.profileError = response.describeFailure(); }
    } catch (err) {
      if (request === this.request) { this.profileError = '用户资料加载失败'; }
    } finally {
      if (request === this.request) { this.loading = false; }
    }
    if (request === this.request) { await this.load(context); }
  }

  /**
   * 首次取得身份沿用服务端地址；之后仅在身份变化或用户明确重试时推进展示版本。
   *
   * 普通刷新（进入/返回本页、切换页签、关注关系刷新）不再无条件改图片缓存键：
   * 那会让每次进入个人主页都重新下载同一张头像。身份未识别时按"未知"处理，不推进。
   */
  private publishAvatarIdentity(portrait: string, force: boolean): void {
    const identity: string = avatarIdentity(portrait);
    if (!force && (identity.length === 0 || identity === this.portraitIdentity)) { return; }
    if (!force && this.portraitIdentity.length === 0) {
      this.portraitIdentity = identity;
      return;
    }
    if (identity.length > 0) { this.portraitIdentity = identity; }
    this.avatarRevision = Math.max(Date.now(), this.avatarRevision + 1);
  }

  async selectTab(context: common.UIAbilityContext, tab: number): Promise<void> {
    if (this.tab === tab || !this.profileLoaded) { return; }
    ++this.request;
    this.tab = tab;
    this.items = [];
    this.forums = [];
    this.loading = false;
    this.loadingMore = false;
    this.hasMore = false;
    this.page = 0;
    await this.load(context);
  }

  /**
   * 「关注吧」头像补齐：缓存 / TTL / 并发 / 回写全部交给 `utils/ForumAvatarBackfill`，
   * 这里只提供「按吧 ID 走目录接口取图」与「取到后替换行对象」。
   * 失败保留文字回退、刷新可重试；换请求代次后不再上屏。
   */
  private async loadForumAvatars(device: TiebaDevice, request: number): Promise<void> {
    const pending: ProfileForum[] = this.forums.filter((forum: ProfileForum): boolean =>
      forum.id > 0 && forum.avatar.length === 0);
    if (pending.length === 0) { return; }
    const session: TiebaSession = authSession.session();
    const needs: ForumAvatarNeed[] = pending.map((forum: ProfileForum): ForumAvatarNeed =>
      new ForumAvatarNeed(forum.name, forum.id));
    const plan: ForumAvatarBackfillPlan = new ForumAvatarBackfillPlan();
    plan.label = 'UserPageVM';
    plan.stopped = (): boolean => request !== this.request;
    plan.fetch = async (_name: string, forumId: number): Promise<string> => {
      const response: DirectoryResponse = await this.api.fetchDirectory(device, session, 'forum', forumId);
      return response.ok ? response.data.forum.avatar : '';
    };
    plan.apply = (_name: string, forumId: number, url: string): void => {
      this.forumAvatars.set(forumId, url);
      this.applyForumAvatar(forumId, url);
    };
    await backfillForumAvatars(needs, plan);
  }
  /** 替换该吧的行对象与数组，让纯模型字段的异步更新被页面观察到。 */
  private applyForumAvatar(forumId: number, avatarUrl: string): void {
    this.forums = this.forums.map((row: ProfileForum): ProfileForum => {
      if (row.id !== forumId) { return row; }
      const updated: ProfileForum = new ProfileForum();
      updated.id = row.id;
      updated.name = row.name;
      updated.avatar = avatarUrl;
      return updated;
    });
  }

  async load(context: common.UIAbilityContext, more: boolean = false): Promise<void> {
    if (this.loading || this.loadingMore || (more && !this.hasMore)) { return; }
    const request: number = ++this.request;
    const tab: number = this.tab;
    const page: number = more ? this.page + 1 : 1;
    if (more) { this.loadingMore = true; this.pagingError = ''; }
    else { this.loading = true; this.error = ''; this.pagingError = ''; }
    try {
      const device = await DeviceIdentity.ensure(context);
      if (tab === 2) {
        const response: PublicProfileResponse = await this.api.fetchPublicProfile(
          device, authSession.session(), this.uid, this.portrait, page);
        if (request !== this.request) { return; }
        if (!response.ok) { throw new Error(response.describeFailure()); }
        const old: ProfileForum[] = more ? this.forums : [];
        const merged: ProfileForum[] = old.slice();
        const names: Set<string> = new Set<string>(old.map((forum: ProfileForum) => forum.name));
        for (const forum of response.data.forums) {
          if (!names.has(forum.name)) { merged.push(forum); names.add(forum.name); }
        }
        for (const forum of merged) {
          forum.avatar = this.forumAvatars.get(forum.id) || forum.avatar;
        }
        this.forums = merged;
        this.hasMore = merged.length > old.length && merged.length < response.data.likeForumNum;
        await this.loadForumAvatars(device, request);
        if (request !== this.request) { return; }
      } else {
        const response: UserPostsResponse = await this.api.fetchPublicUserPosts(
          device, authSession.session(), this.uid, tab === 0 ? 1 : 0, page, 20);
        if (request !== this.request) { return; }
        if (!response.ok) { throw new Error(response.describeFailure()); }
        const old: UserPostItem[] = more ? this.items : [];
        const merged: UserPostItem[] = tab === 1 ? mergeUserReplies(old, response.data) : old.slice();
        if (tab === 0) {
          const tids: Set<number> = new Set<number>(old.map((item: UserPostItem) => item.tid));
          for (const item of response.data) {
            if (item.tid > 0 && !tids.has(item.tid)) { merged.push(item); tids.add(item.tid); }
          }
        }
        this.items = merged;
        this.hasMore = response.hasMore && merged.length > old.length;
        if (tab === 0) { await this.loadPostForumAvatars(device, request); }
        if (request !== this.request) { return; }
      }
      this.page = page;
    } catch (err) {
      if (request === this.request) {
        const message: string = (err as Error).message || '加载失败，请重试';
        if (more) { this.pagingError = message; } else { this.error = message; }
      }
    } finally {
      if (request === this.request) { this.loading = false; this.loadingMore = false; }
    }
  }

  /**
   * 「帖子栏」吧头像补齐：同一套共享编排；取到一张就发布一次
   * （尾部慢请求不能拖住已经拿到的首屏头像）。
   */
  private async loadPostForumAvatars(device: TiebaDevice, request: number): Promise<void> {
    // 切回帖子栏时先展示当前 VM 已知的头像，不等其他吧的补图请求。
    this.postForumAvatars = new Map<number, string>(this.forumAvatars);
    const session: TiebaSession = authSession.session();
    const needs: ForumAvatarNeed[] = [];
    for (const item of this.items) {
      if (item.forumId <= 0 || this.forumAvatars.has(item.forumId)) { continue; }
      needs.push(new ForumAvatarNeed(item.forumName, item.forumId));
    }
    if (needs.length === 0) { return; }
    const plan: ForumAvatarBackfillPlan = new ForumAvatarBackfillPlan();
    plan.label = 'UserPageVM/post';
    plan.stopped = (): boolean => request !== this.request;
    plan.fetch = async (_name: string, forumId: number): Promise<string> => {
      const response: DirectoryResponse = await this.api.fetchDirectory(device, session, 'forum', forumId);
      return response.ok ? response.data.forum.avatar : '';
    };
    // 每张成功就发布；尾部慢请求不能拖住已经拿到的首屏头像。
    plan.apply = (_name: string, forumId: number, url: string): void => {
      this.forumAvatars.set(forumId, url);
      this.postForumAvatars = new Map<number, string>(this.forumAvatars);
    };
    await backfillForumAvatars(needs, plan);
  }}

