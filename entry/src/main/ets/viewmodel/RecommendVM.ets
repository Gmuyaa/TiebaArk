

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ForumBrief, PageInfo, ThreadBrief, mergeThreadPages
} from '../model/ThreadList';
import {
  personalizedToBriefs
} from '../model/PersonalizedFeed';
import { forumAvatarCount, putForumAvatar } from '../model/ForumAvatarStore';
import { PersonalizedFeedResponse, ThreadListResponse, TiebaApi } from '../api/TiebaApi';
import { PersonalizedParams, TiebaDevice, TiebaSession } from '../net/TiebaParams';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { authSession } from '../auth/AuthSession';

const REQUEST_PAGE_SIZE: number = 30;

@ObservedV2
export class RecommendVM {

  @Trace mode: string = '';
  @Trace loading: boolean = false;
  @Trace errorText: string = '';

  @Trace loadedOnce: boolean = false;

  @Trace loadingMore: boolean = false;

  @Trace hasMore: boolean = false;

  @Trace loadMoreError: string = '';

  @Trace forum: ForumBrief = new ForumBrief();
  @Trace page: PageInfo = new PageInfo();
  @Trace threads: ThreadBrief[] = [];

  private api: TiebaApi = new TiebaApi();

  private loadToken: number = 0;
  private account: string = authSession.sessionKey();
  private current(token: number): boolean { return token === this.loadToken && this.account === authSession.sessionKey(); }
  resetAccount(): void {
    this.loadToken++; this.account = authSession.sessionKey();
    this.loading = false; this.loadingMore = false; this.loadedOnce = false;
    this.threads = []; this.hasMore = false; this.errorText = ''; this.loadMoreError = '';
    this.recommendPage = 1; this.page = new PageInfo(); this.forum = new ForumBrief();
  }
  private syncAccount(): void { if (this.account !== authSession.sessionKey()) { this.resetAccount(); } }

  private recommendPage: number = 1;

  async refreshRecommend(context: common.UIAbilityContext): Promise<void> {
    this.syncAccount();
    hilog.info(0x0000, 'RecommendVM', 'refresh called loading=%{public}s loadingMore=%{public}s',
      String(this.loading), String(this.loadingMore));
    if (this.loading) {
      return;
    }

    const token: number = ++this.loadToken;
    this.loadingMore = false;
    this.mode = '';
    this.loading = true;
    this.errorText = '';
    this.loadMoreError = '';
    this.hasMore = false;

    const t0: number = Date.now();

    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!this.current(token)) { return; }
      const session: TiebaSession = authSession.session();
      if (!session.hasBduss()) {

        return;
      }
      if (!this.current(token)) { return; }
      const response: PersonalizedFeedResponse = await this.api.fetchPersonalizedFeed(
        device, session, PersonalizedParams.LOAD_REFRESH, 1, PersonalizedParams.PAGE_THREAD_COUNT);
      if (!this.current(token)) {
        return;
      }
      if (!response.ok) {
        this.errorText = response.describeFailure();
        this.threads = [];
        return;
      }

      const briefs: ThreadBrief[] = personalizedToBriefs(response.data);
      this.recommendPage = 1;
      this.threads = briefs;
      this.loadedOnce = true;
      this.hasMore = briefs.length > 0;
      hilog.info(0x0000, 'RecommendVM',
        'first official threads=%{public}d hasMore=%{public}s ms=%{public}d',
        this.threads.length, String(this.hasMore), Date.now() - t0);

      let avatarHits: number = 0;
      for (let i = 0; i < briefs.length; i++) {
        if (briefs[i].sourceForumAvatar.length > 0) {
          avatarHits++;
        }
      }
      hilog.info(0x0000, 'RecommendVM', 'avatar cache hits=%{public}d/%{public}d size=%{public}d',
        avatarHits, briefs.length, forumAvatarCount());
    } catch (err) {
      if (this.current(token)) {
        const e: Error = err as Error;
        this.errorText = `加载失败：${e.message}`;
      }
    } finally {
      if (token === this.loadToken) {
        this.loading = false;
        this.syncAccount();
      }
    }
  }

  async loadMore(context: common.UIAbilityContext, retry: boolean = false): Promise<void> {
    this.syncAccount();
    if (this.loading || this.loadingMore || !this.hasMore) {
      return;
    }
    if (this.loadMoreError.length > 0 && !retry) {
      return;
    }
    if (this.mode.length > 0) {
      await this.loadMoreSpecifiedForum(context);
      return;
    }
    await this.loadMoreRecommend(context);
  }

  private async loadMoreRecommend(context: common.UIAbilityContext): Promise<void> {
    this.loadingMore = true;
    this.loadMoreError = '';
    const before: number = this.threads.length;
    const t0: number = Date.now();
    const token: number = ++this.loadToken;

    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!this.current(token)) { return; }
      const response: PersonalizedFeedResponse = await this.api.fetchPersonalizedFeed(
        device, authSession.session(), PersonalizedParams.LOAD_MORE,
        this.recommendPage + 1, PersonalizedParams.PAGE_THREAD_COUNT);
      if (!this.current(token)) {
        return;
      }
      if (!response.ok) {

        this.loadMoreError = response.describeFailure();
        return;
      }

      this.threads = mergeThreadPages(this.threads, personalizedToBriefs(response.data));
      const added: number = this.threads.length - before;
      this.recommendPage = this.recommendPage + 1;
      this.hasMore = response.data.length > 0 && added > 0;

      hilog.info(0x0000, 'RecommendVM',
        'loadMore official page=%{public}d added=%{public}d total=%{public}d hasMore=%{public}s ms=%{public}d',
        this.recommendPage, added, this.threads.length, String(this.hasMore), Date.now() - t0);
    } catch (err) {
      if (this.current(token)) {
        const e: Error = err as Error;
        this.loadMoreError = `加载失败：${e.message}`;
      }
    } finally {
      if (token === this.loadToken) {
        this.loadingMore = false;
        this.syncAccount();
      }
    }
  }

  private async loadMoreSpecifiedForum(context: common.UIAbilityContext): Promise<void> {
    this.loadingMore = true;
    this.loadMoreError = '';
    const before: number = this.threads.length;
    const t0: number = Date.now();
    const token: number = ++this.loadToken;

    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      const nextPage: number = this.page.currentPage + 1;
      if (!this.current(token)) { return; }
      const response: ThreadListResponse = await this.api.fetchThreadList(
        device, authSession.session(), this.mode, nextPage, REQUEST_PAGE_SIZE);
      if (!this.current(token)) {
        return;
      }

      if (!response.ok) {
        this.loadMoreError = response.describeFailure();
        return;
      }

      const threads: ThreadBrief[] = response.data.threads;
      for (let i = 0; i < threads.length; i++) {
        threads[i].sourceForum = this.mode;
        threads[i].sourceForumId = response.data.forum.id;
        threads[i].sourceForumAvatar = response.data.forum.avatar;

        putForumAvatar(this.mode, response.data.forum.avatar);
      }
      this.threads = mergeThreadPages(this.threads, threads);
      this.page = response.data.page;
      this.hasMore = response.data.page.hasMore && this.threads.length > before && response.data.page.currentPage === nextPage;
      if (!this.hasMore && response.data.page.hasMore) { this.loadMoreError = '分页没有进展，请刷新后重试'; }
      hilog.info(0x0000, 'RecommendVM',
        'loadMore forum=%{public}s added=%{public}d total=%{public}d hasMore=%{public}s ms=%{public}d',
        this.mode, this.threads.length - before, this.threads.length, String(this.hasMore),
        Date.now() - t0);
    } catch (err) {
      if (this.current(token)) {
        const e: Error = err as Error;
        this.loadMoreError = `加载失败：${e.message}`;
      }
    } finally {
      if (token === this.loadToken) {
        this.loadingMore = false;
        this.syncAccount();
      }
    }
  }

  async openForum(context: common.UIAbilityContext, forumName: string): Promise<void> {
    this.syncAccount();
    if (this.loading || this.loadingMore) {
      return;
    }
    const name: string = forumName.trim();
    if (name.length === 0) {
      return;
    }
    this.mode = name;
    this.loading = true;
    this.errorText = '';
    this.loadMoreError = '';
    this.hasMore = false;

    const token: number = ++this.loadToken;

    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!this.current(token)) { return; }
      const response: ThreadListResponse = await this.api.fetchThreadList(
        device, authSession.session(), name, 1, REQUEST_PAGE_SIZE);
      if (!this.current(token)) {
        return;
      }

      if (!response.ok) {
        this.errorText = response.describeFailure();
        this.threads = [];
        return;
      }

      this.forum = response.data.forum;
      this.page = response.data.page;
      const threads: ThreadBrief[] = response.data.threads;
      for (let i = 0; i < threads.length; i++) {
        threads[i].sourceForum = name;
        threads[i].sourceForumId = this.forum.id;
        threads[i].sourceForumAvatar = this.forum.avatar;

        putForumAvatar(name, this.forum.avatar);
      }
      this.threads = threads;
      this.loadedOnce = true;
      this.hasMore = response.data.page.hasMore;
    } catch (err) {
      if (this.current(token)) {
        const e: Error = err as Error;
        this.errorText = `加载失败：${e.message}`;
      }
    } finally {
      if (token === this.loadToken) {
        this.loading = false;
        this.syncAccount();
      }
    }
  }

  async backToRecommend(context: common.UIAbilityContext): Promise<void> {
    await this.refreshRecommend(context);
  }

  async refresh(context: common.UIAbilityContext): Promise<void> {
    if (this.mode.length === 0) {
      await this.refreshRecommend(context);
    } else {
      await this.openForum(context, this.mode);
    }
  }

}
