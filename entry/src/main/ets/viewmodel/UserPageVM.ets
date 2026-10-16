import { common } from '@kit.AbilityKit';
import { DirectoryResponse, PublicProfileResponse, TiebaApi, UserPostsResponse } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { UserPostItem, mergeUserReplies } from '../model/MyContent';
import { ProfileForum, UserProfileInfo, avatarIdentity } from '../model/UserProfile';
import { TiebaDevice } from '../net/TiebaParams';
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
  @Trace hasMore: boolean = false;
  private uid: number = 0;
  private portrait: string = '';

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

  private async loadForumAvatars(device: TiebaDevice, request: number): Promise<void> {
    const pending: ProfileForum[] = this.forums.filter((forum: ProfileForum) =>
      forum.id > 0 && forum.avatar.length === 0);
    const session = authSession.session();
    let next: number = 0;
    const worker = async (): Promise<void> => {
      while (request === this.request && next < pending.length) {
        const forum: ProfileForum = pending[next++];
        try {
          const response: DirectoryResponse = await this.api.fetchDirectory(device, session, 'forum', forum.id);
          if (!response.ok || response.data.forum.avatar.length === 0) { continue; }
          this.forumAvatars.set(forum.id, response.data.forum.avatar);
          if (request !== this.request) { return; }

          this.forums = this.forums.map((row: ProfileForum): ProfileForum => {
            if (row.id !== forum.id) { return row; }
            const updated: ProfileForum = new ProfileForum();
            updated.id = row.id;
            updated.name = row.name;
            updated.avatar = response.data.forum.avatar;
            return updated;
          });
        } catch (err) {

        }
      }
    };
    const workers: Promise<void>[] = [];
    for (let i: number = 0; i < Math.min(4, pending.length); i++) { workers.push(worker()); }
    await Promise.all(workers);
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
}
