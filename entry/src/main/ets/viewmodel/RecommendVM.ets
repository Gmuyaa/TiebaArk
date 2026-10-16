/** 推荐流加载、刷新与分页状态。刷新取消旧请求的发布资格，续页去重并检测无进展。 */

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

/** 单次列表请求条数（服务端有自己的 page_size，这里只是请求意图） */
const REQUEST_PAGE_SIZE: number = 30;

@ObservedV2
export class RecommendVM {
  /** '' = 推荐模式；非空 = 指定吧名 */
  @Trace mode: string = '';
  @Trace loading: boolean = false;
  @Trace errorText: string = '';
  /** 是否成功加载过至少一次（区分首次加载与刷新） */
  @Trace loadedOnce: boolean = false;
  /** 正在翻下一页（列表尾部的"正在加载更多"+ 触底重复触发守卫） */
  @Trace loadingMore: boolean = false;
  /**
   * 还能继续往下刷吗。两种模式共用一个对外字段，界面只读它一个。
   * 推荐模式 = 官方流本页有新增帖子；指定吧模式 = 服务端 `page.hasMore`。
   */
  @Trace hasMore: boolean = false;
  /** 翻页失败的原因（与首刷的 `errorText` 分开：失败只影响尾部一条提示，不该清空列表） */
  @Trace loadMoreError: string = '';

  /** 吧统计。推荐模式下没有单一"当前吧"，仅指定吧模式有值 */
  @Trace forum: ForumBrief = new ForumBrief();
  @Trace page: PageInfo = new PageInfo();
  @Trace threads: ThreadBrief[] = [];

  private api: TiebaApi = new TiebaApi();
  /** 每轮加载的令牌：过期响应（期间又刷新/进吧/切频道）一律丢弃 */
  private loadToken: number = 0;
  private account: string = authSession.sessionKey();
  private current(token: number): boolean { return token === this.loadToken && this.account === authSession.sessionKey(); }
  resetAccount(): void {
    this.loadToken++; this.account = authSession.sessionKey();
    this.loading = false; this.loadingMore = false; this.loadedOnce = false;
    this.threads = []; this.hasMore = false; this.errorText = ''; this.loadMoreError = '';
    this.recommendPage = 1; this.page = new PageInfo(); this.forum = new ForumBrief();
    this.recommendSeen.clear();
  }
  private syncAccount(): void { if (this.account !== authSession.sessionKey()) { this.resetAccount(); } }
  /** 官方流的分页游标：pn 从 1 起，每触底一次 +1（pb 响应不带页码，本地计数） */
  private recommendPage: number = 1;
  private recommendSeen: Set<number> = new Set<number>();
  private acceptRecommended(items: ThreadBrief[], replace: boolean): boolean {
    if (replace) { this.recommendSeen.clear(); }
    let fresh: boolean = false;
    for (const item of items) { if (!this.recommendSeen.has(item.tid)) { fresh = true; this.recommendSeen.add(item.tid); } }
    const visible: ThreadBrief[] = items.filter((item: ThreadBrief): boolean => !item.isVideo);
    this.threads = mergeThreadPages(replace ? [] : this.threads, visible);
    return items.length > 0 && fresh;
  }

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
    /** 耗时打点（真机优化用） */
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
      const canContinue: boolean = this.acceptRecommended(briefs, true);
      this.loadedOnce = true;
      this.hasMore = canContinue;
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
    if (this.current(token) && this.threads.length === 0 && this.hasMore) { await this.loadMore(context); }
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
    for (let attempt: number = 0; attempt < 3; attempt++) {
      const before: number = this.threads.length;
      const expectedToken: number = this.loadToken + 1;
      await this.loadMoreRecommend(context);
      if (!this.current(expectedToken)) { break; }
      if (this.threads.length > before || !this.hasMore || this.loadMoreError.length > 0) { break; }
    }
  }

  /**
   * 推荐模式（官方流）续页：`load_type=2, pn+1`，官方序**追加**（不洗牌 ——
   * 官方流有它自己的推荐序，洗牌会毁掉"相关推荐"的局部性），`mergeThreadPages`
   * 按 tid 去重。
   *
   * 终止判据（防死循环）：某页 0 条 → 到底；整页全是已见过的 tid（`added=0`）
   * 也停 —— 那说明服务端没理会 pn 的推进，继续翻只会无限重刷同一批。
   */
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
        // 保留原列表，只在尾部提示重试
        this.loadMoreError = response.describeFailure();
        return;
      }

      const canContinue: boolean = this.acceptRecommended(personalizedToBriefs(response.data), false);
      const added: number = this.threads.length - before;
      this.recommendPage = this.recommendPage + 1;
      this.hasMore = canContinue;
      /*
       * 打点给真机取证用：`added` 是去重后实际进流的条数，`total` 是追加后的总条数。
       */
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

  /** 指定吧模式续页：单吧翻页，与 `ThreadListVM.loadMore` 同一链路与判据。 */
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

  /** 进入指定吧。与旧 ThreadListVM.refresh 相同的链路，但给帖子打上来源吧名 */
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
    // 作废在途的推荐加载：它的响应不能盖到"某个吧"的列表上
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

  /** 从指定吧模式回到推荐。失败时保留 errorText，不把 mode 悄悄切回去 */
  async backToRecommend(context: common.UIAbilityContext): Promise<void> {
    await this.refreshRecommend(context);
  }

  /** 下拉刷新入口：按当前模式刷新 */
  async refresh(context: common.UIAbilityContext): Promise<void> {
    if (this.mode.length === 0) {
      await this.refreshRecommend(context);
    } else {
      await this.openForum(context, this.mode);
    }
  }

}
