import { cachedForumTabs, cachedFreshThreadList, ForumCacheGuard, publishForumRead } from './ForumReadCache';
/**
 * 帖子列表的状态与行为。`@Trace` 对数组只跟踪**整体替换**，不跟踪元素增删——本类每次都赋新数组，
 * 不做 `push`。
 */

import { common } from '@kit.AbilityKit';
import { ForumBrief, ForumTab, mergeThreadPages, PageInfo, ThreadBrief } from '../model/ThreadList';
import { ThreadListResponse, TiebaApi } from '../api/TiebaApi';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { TiebaDevice } from '../net/TiebaParams';
import { authSession } from '../auth/AuthSession';
import { getForumHeadline, putForumHeadline } from '../model/ForumHeadline';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { applyForumRead, clearFirstPageRead, markFirstPageRead } from './ForumStateStore';
import { forumDefaultTabStore } from '../common/appearance/ForumDefaultTabStore';
import { knownDefaultTabHint, preferredForumTabId } from '../model/ForumDefaultTab';

/** 只是请求意图：服务端有自己的 page_size，真实条数以响应的 `page.pageSize` 为准。 */
const REQUEST_PAGE_SIZE: number = 30;

class ThreadListTabSnapshot {
  forum: ForumBrief;
  page: PageInfo;
  threads: ThreadBrief[];
  tabs: ForumTab[];
  selectedTabId: number;

  constructor(forum: ForumBrief, page: PageInfo, threads: ThreadBrief[], tabs: ForumTab[], selectedTabId: number) {
    this.forum = forum;
    this.page = page;
    this.threads = threads;
    this.tabs = tabs;
    this.selectedTabId = selectedTabId;
  }
}

@ObservedV2
export class ThreadListVM {
  @Trace forumName: string = '';
  @Trace loading: boolean = false;
  @Trace isLoadingMore: boolean = false;
  @Trace errorText: string = '';
  @Trace loadMoreError: string = '';
  @Trace loadedOnce: boolean = false;
  @Trace switchingTab: boolean = false;
  /** 选择可先响应；正文只在目标分类读取成功后替换。 */
  @Trace pendingTabId: number = 0;
  targetTabId(): number { return this.pendingTabId > 0 ? this.pendingTabId : this.selectedTabId; }

  @Trace forum: ForumBrief = new ForumBrief();
  @Trace page: PageInfo = new PageInfo();
  @Trace threads: ThreadBrief[] = [];
  @Trace tabs: ForumTab[] = [];
  @Trace selectedTabId: number = 0;
  @Trace tabSnapshotRevision: number = 0;
  @Trace helpPartition: number = 0;
  @Trace private categorySorts: Map<number, number> = new Map<number, number>();
  hasPostOrder(): boolean { return this.tabs.some((tab: ForumTab): boolean => tab.id === this.selectedTabId && tab.supportsPostOrder); }
  currentSort(): number { return this.sortForTab(this.selectedTabId); }
  private sortForTab(tabId: number): number { return this.categorySorts.get(tabId) ?? 0; }
  private setTabSort(tabId: number, sort: number): void {
    const next: Map<number, number> = new Map<number, number>(this.categorySorts);
    next.set(tabId, sort); this.categorySorts = next;
  }
  isLatestTab(): boolean { return this.tabs.some((tab: ForumTab): boolean => tab.id === this.selectedTabId && tab.isLatest); }
  isVideoTab(): boolean { return this.tabs.some((tab: ForumTab): boolean => tab.id === this.selectedTabId && tab.isVideo); }
  isHelpTab(): boolean { return this.tabs.some((tab: ForumTab): boolean => tab.id === this.selectedTabId && tab.isHelp); }
  private fetchCategory(device: TiebaDevice, name: string, page: number, tabId: number,
    allowTabFallback: boolean = false): Promise<ThreadListResponse> {
    const tab: ForumTab | undefined = this.tabs.find((value: ForumTab): boolean => value.id === tabId);
    if (tab?.isVideo && this.forum.id > 0 && this.forum.name.toLowerCase() === name.toLowerCase()) {
      return this.api.fetchForumVideos(device, authSession.session(), this.forum, tab, page, this.sortForTab(tabId));
    }
    if (tab?.isGeneral && this.forum.id > 0 && this.forum.name.toLowerCase() === name.toLowerCase()) {
      return this.api.fetchForumGeneralTab(device, authSession.session(), this.forum, tab, page,
        this.sortForTab(tabId), tab.isHelp ? this.helpPartition : 0);
    }
    return this.api.fetchThreadList(device, authSession.session(), name, page, REQUEST_PAGE_SIZE, tabId,
      tab?.supportsPostOrder ? this.sortForTab(tabId) : -1, allowTabFallback);
  }
  async changeSort(context: common.UIAbilityContext, sort: number): Promise<boolean> {
    if (!this.hasPostOrder() || this.loading || this.isLoadingMore || this.switchingTab ||
      (sort !== 0 && sort !== 1) || sort === this.currentSort()) { return false; }
    const tabId: number = this.selectedTabId;
    const owner: string = this.ownerKey();
    const previous: number = this.currentSort();
    this.setTabSort(tabId, sort);
    await this.refresh(context, this.forumName, true);
    if (owner !== this.ownerKey()) { return false; }
    if (this.errorText.length > 0) { this.setTabSort(tabId, previous); return false; }
    return true;
  }

  async changeHelpFilter(context: common.UIAbilityContext, partition: number, sort: number): Promise<boolean> {
    if (!this.isHelpTab() || this.loading || this.isLoadingMore || this.switchingTab ||
      (partition !== 0 && partition !== 1) || (sort !== 0 && sort !== 1) ||
      (partition === this.helpPartition && sort === this.currentSort()) ||
      (sort !== this.currentSort() && !this.hasPostOrder())) { return false; }
    const tabId: number = this.selectedTabId;
    const oldPartition: number = this.helpPartition;
    const owner: string = this.ownerKey();
    const oldSort: number = this.currentSort();
    this.helpPartition = partition; this.setTabSort(tabId, sort);
    await this.refresh(context, this.forumName, true);
    if (owner !== this.ownerKey()) { return false; }
    if (this.errorText.length > 0) {
      this.helpPartition = oldPartition; this.setTabSort(tabId, oldSort); return false;
    }
    return true;
  }

  @Trace heroHeadline: string = '';
  @Trace heroHeadlineSettled: boolean = false;

  /** 本 VM 已发起过头图请求的吧名（会话内每吧最多发一次；缓存命中不发） */
  private headlineRequested: Set<string> = new Set<string>();

  private api: TiebaApi = new TiebaApi();
  private tabSnapshots: Map<number, ThreadListTabSnapshot> = new Map<number, ThreadListTabSnapshot>();
  private tabReads: Map<number, Promise<ThreadListResponse>> = new Map<number, Promise<ThreadListResponse>>();
  private tabOwner: string = '';
  private warmingOwner: string = '';
  private tabVersion: number = 0;
  /** 切换分类使旧分页、旧切换回包及其 finally 一起失效。 */
  private contentVersion: number = 0;
  /** 首包到达后延迟启动相邻分类预读，避免与首屏卡片布局和图片解码争抢资源。 */
  prefetchDelayMs: number = 400;
  private prefetchTimer: number = -1;

  private ownerKey(): string { return `${authSession.sessionKey()}:${this.forumName}`; }

  /** 首包到达前用本地已知资料预填吧头展示字段，不置 loadedOnce。 */
  seedHeader(name: string, forumId: number, avatar: string, heroColor: string, headline: string,
    tabs?: ForumTab[]): void {
    if (this.loadedOnce) { return; }
    const trimmed: string = name.trim();
    if (trimmed.length === 0) { return; }
    if (this.forumName.length === 0) { this.forumName = trimmed; }
    const nextForum: ForumBrief = new ForumBrief();
    nextForum.id = this.forum.id > 0 ? this.forum.id : forumId;
    nextForum.name = this.forum.name.length > 0 ? this.forum.name : trimmed;
    nextForum.avatar = this.forum.avatar.length > 0 ? this.forum.avatar : avatar;
    nextForum.heroColor = this.forum.heroColor.length > 0 ? this.forum.heroColor : heroColor;
    nextForum.heroImage = this.forum.heroImage;
    nextForum.memberCount = this.forum.memberCount;
    nextForum.threadCount = this.forum.threadCount;
    nextForum.postCount = this.forum.postCount;
    nextForum.followed = this.forum.followed;
    nextForum.category = this.forum.category;
    nextForum.slogan = this.forum.slogan;
    this.forum = nextForum;
    if (this.heroHeadline.length === 0 && headline.length > 0) {
      this.heroHeadline = headline;
      this.heroHeadlineSettled = true;
    }
    if (this.tabs.length === 0 && tabs !== undefined && tabs.length > 0) {
      this.tabs = tabs.slice();
    }
  }

  cancelPrefetch(): void {
    if (this.prefetchTimer >= 0) {
      clearTimeout(this.prefetchTimer);
      this.prefetchTimer = -1;
    }
  }

  hasTabSnapshot(tabId: number): boolean {
    void this.tabSnapshotRevision;
    return this.ownerKey() === this.tabOwner && this.tabSnapshots.has(tabId);
  }

  threadsForTab(tabId: number): ThreadBrief[] {
    void this.tabSnapshotRevision;
    if (tabId <= 0 || tabId === this.selectedTabId) { return this.threads; }
    const snapshot: ThreadListTabSnapshot | undefined = this.tabSnapshots.get(tabId);
    return snapshot !== undefined ? snapshot.threads : [];
  }

  pageForTab(tabId: number): PageInfo {
    void this.tabSnapshotRevision;
    if (tabId <= 0 || tabId === this.selectedTabId) { return this.page; }
    const snapshot: ThreadListTabSnapshot | undefined = this.tabSnapshots.get(tabId);
    return snapshot !== undefined ? snapshot.page : new PageInfo();
  }

  isTabCached(tabId: number): boolean {
    void this.tabSnapshotRevision;
    if (tabId <= 0 || tabId === this.selectedTabId) { return this.loadedOnce; }
    return this.hasTabSnapshot(tabId);
  }

  isTabReading(tabId: number): boolean {
    void this.tabSnapshotRevision;
    if (tabId <= 0 || tabId === this.selectedTabId) { return this.loading && !this.loadedOnce; }
    return this.tabReads.has(tabId) || (this.switchingTab && this.pendingTabId === tabId);
  }

  /** 相邻分类预读与点击共用同一请求，避免用户切过去后重复等待。 */
  private readTab(context: common.UIAbilityContext, tabId: number): Promise<ThreadListResponse> {
    const existing: Promise<ThreadListResponse> | undefined = this.tabReads.get(tabId);
    if (existing !== undefined) { return existing; }
    const name: string = this.forumName;
    const owner: string = this.ownerKey();
    const version: number = this.tabVersion;
    const request: Promise<ThreadListResponse> = DeviceIdentity.ensure(context).then((device: TiebaDevice) => {
      if (owner !== this.ownerKey() || owner !== this.tabOwner || version !== this.tabVersion) { throw new Error('分类请求已失效'); }
      return this.fetchCategory(device, name, 1, tabId);
    });
    this.tabReads.set(tabId, request);
    ++this.tabSnapshotRevision;
    request.then((response: ThreadListResponse) => {
      if (owner !== this.ownerKey() || owner !== this.tabOwner || version !== this.tabVersion) { return; }
      if (response.ok && response.data.forum.id === this.forum.id &&
        (response.data.selectedTabId === tabId || response.data.selectedTabId === 0)) {
        const threads: ThreadBrief[] = mergeThreadPages([], response.data.threads);
        this.tagSourceForum(threads, name, this.forum.id);
        this.tabSnapshots.set(tabId, new ThreadListTabSnapshot(response.data.forum, response.data.page,
          threads, response.data.tabs.length > 0 ? response.data.tabs : this.tabs, tabId));
        ++this.tabSnapshotRevision;
      }
    }).catch(() => {}).finally(() => {
      if (this.tabReads.get(tabId) === request) {
        this.tabReads.delete(tabId);
        ++this.tabSnapshotRevision;
      }
    });
    return request;
  }

  private prefetchAdjacent(context: common.UIAbilityContext): void {
    const owner: string = this.ownerKey();
    const version: number = this.tabVersion;
    const warmKey: string = `${owner}:${version}`;
    if (this.warmingOwner === warmKey) { return; }
    const index: number = this.tabs.findIndex((tab: ForumTab) => tab.id === this.selectedTabId);
    if (index < 0) { return; }
    const queue: ForumTab[] = this.tabs.filter((tab: ForumTab) => tab.id !== this.selectedTabId);
    this.warmingOwner = warmKey;
    const warm = async (): Promise<void> => {
      while (queue.length > 0 && owner === this.ownerKey() && owner === this.tabOwner && version === this.tabVersion) {
        const tab: ForumTab | undefined = queue.shift();
        if (tab === undefined || this.tabSnapshots.has(tab.id)) { continue; }
        try { await this.readTab(context, tab.id); } catch (err) { /* 预读失败仍允许前台重试。 */ }
      }
    };
    // 最多两路后台请求；点击仍复用同一 Promise，首屏不会等待预读。
    void Promise.all([warm(), warm()]).finally(() => { if (this.warmingOwner === warmKey) { this.warmingOwner = ''; } });
  }

  private schedulePrefetchAdjacent(context: common.UIAbilityContext): void {
    this.cancelPrefetch();
    if (this.prefetchDelayMs <= 0) {
      this.prefetchAdjacent(context);
      return;
    }
    const owner: string = this.ownerKey();
    const version: number = this.tabVersion;
    this.prefetchTimer = setTimeout((): void => {
      this.prefetchTimer = -1;
      if (owner === this.ownerKey() && owner === this.tabOwner && version === this.tabVersion) {
        this.prefetchAdjacent(context);
      }
    }, this.prefetchDelayMs) as number;
  }

  /** 拉取第一页。失败时保留 errorText 供界面展示，不抛异常。 */
  async refresh(context: common.UIAbilityContext, forumName: string, currentCategoryOnly: boolean = false): Promise<void> {
    if (this.loading || this.isLoadingMore || this.switchingTab) {
      return;
    }
    const startedAt: number = Date.now();
    this.cancelPrefetch();
    const name: string = forumName.trim();
    const wasLoaded: boolean = this.loadedOnce;
    this.forumName = name;
    const owner: string = this.ownerKey();
    const selected: number = this.selectedTabId;
    const sameOwner: boolean = this.tabOwner === this.ownerKey();
    if (!sameOwner) { this.categorySorts = new Map<number, number>(); this.helpPartition = 0; }
    ++this.tabVersion;
    ++this.contentVersion;
    if (!currentCategoryOnly || !sameOwner) { this.tabSnapshots.clear(); }
    else { this.tabSnapshots.delete(selected); }
    ++this.tabSnapshotRevision;
    this.tabOwner = this.ownerKey(); this.tabReads.clear(); this.warmingOwner = '';
    this.loading = true;
    this.errorText = '';
    this.loadMoreError = '';

    const cacheGuard: ForumCacheGuard = new ForumCacheGuard(name);
    // 首包同时带 `is_like` 与签到段：登记后其它页面（吧头）等这份回包，不再另发 rn=1 请求。
    markFirstPageRead(name);

    try {
      // 首次打开吧页先读本机偏好，避免启动时默认值抢在持久化值前发请求。
      if (!currentCategoryOnly) { await forumDefaultTabStore.load(context); }
      if (owner !== this.ownerKey()) { return; }
      const prefMs: number = Date.now() - startedAt;

      if (!currentCategoryOnly && !wasLoaded) {
        const freshCached: ThreadListResponse | undefined = cachedFreshThreadList(name);
        if (freshCached !== undefined) {
          const preferredCached: number = preferredForumTabId(freshCached.data.tabs, forumDefaultTabStore.value);
          if (preferredCached === 0 || preferredCached === freshCached.data.selectedTabId) {
            void this.loadHeroHeadline(context, name);
            applyForumRead(freshCached);
            this.forum = freshCached.data.forum;
            this.page = freshCached.data.page;
            this.tabs = freshCached.data.tabs;
            this.selectedTabId = freshCached.data.selectedTabId;
            this.threads = mergeThreadPages([], freshCached.data.threads);
            this.tagSourceForum(this.threads, name, this.forum.id);
            if (this.selectedTabId > 0) { this.saveTabSnapshot(); }
            this.loadedOnce = true;
            this.schedulePrefetchAdjacent(context);
            hilog.info(0x0000, 'ForumPerf',
              'forum=%{public}s cacheHit=true rttCount=0 prefMs=%{public}d totalMs=%{public}d threads=%{public}d',
              name, prefMs, Date.now() - startedAt, this.threads.length);
            return;
          }
        }
      }

      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (owner !== this.ownerKey()) { return; }
      const deviceMs: number = Date.now() - startedAt;
      // 与首包并行，允许页面在加载遮罩内提前解码和判断；头图失败不阻塞帖子。
      if (!currentCategoryOnly) { void this.loadHeroHeadline(context, name); }

      let requestTabId: number = this.selectedTabId;
      let allowTabFallback: boolean = false;
      if (!currentCategoryOnly && requestTabId === 0) {
        const cachedTabs: ForumTab[] | undefined = cachedForumTabs(name);
        const cachedPreferred: number = cachedTabs !== undefined
          ? preferredForumTabId(cachedTabs, forumDefaultTabStore.value) : 0;
        requestTabId = cachedPreferred > 0 ? cachedPreferred : knownDefaultTabHint(forumDefaultTabStore.value);
        allowTabFallback = true;
      }

      const fetchStart: number = Date.now();
      let rttCount: number = 1;
      const initialResponse: ThreadListResponse =
        await this.fetchCategory(device, name, 1, requestTabId, allowTabFallback);
      if (owner !== this.ownerKey()) { return; }
      let response: ThreadListResponse = initialResponse;
      let availableTabs: ForumTab[] = initialResponse.data.tabs;
      let selectedOverride: number = 0;
      let fallbackSnapshot: ThreadListResponse | undefined = undefined;

      if (initialResponse.ok && !currentCategoryOnly) {
        const preferredId: number = preferredForumTabId(availableTabs, forumDefaultTabStore.value);
        if (preferredId > 0 && preferredId !== initialResponse.data.selectedTabId) {
          // 分区 ID 来自本吧首包；目标失败或服务端未确认选择时仍显示首包的真实内容。
          rttCount = 2;
          try {
            const preferredResponse: ThreadListResponse = await this.api.fetchThreadList(
              device, authSession.session(), name, 1, REQUEST_PAGE_SIZE, preferredId,
              availableTabs.some((tab: ForumTab): boolean => tab.id === preferredId && tab.supportsPostOrder) ? this.sortForTab(preferredId) : -1);
            if (owner !== this.ownerKey()) { return; }
            if (preferredResponse.ok && preferredResponse.data.forum.id === initialResponse.data.forum.id &&
              (preferredResponse.data.selectedTabId === preferredId || preferredResponse.data.selectedTabId === 0)) {
              fallbackSnapshot = initialResponse;
              response = preferredResponse;
              selectedOverride = preferredId;
            }
          } catch (err) { /* 首包仍可显示，不把偏好请求失败伪装为成功。 */ }
        }
      }

      if (!response.ok) {
        this.errorText = response.describeFailure();
        if (!currentCategoryOnly) { this.threads = []; }
        return;
      }

      publishForumRead(cacheGuard, name, response);
      applyForumRead(response);
      // 整体替换，触发 @Trace
      if (!currentCategoryOnly) {
        this.forum = response.data.forum;
      }
      this.page = response.data.page;
      if (!currentCategoryOnly) { this.tabs = response.data.tabs.length > 0 ? response.data.tabs : availableTabs; }
      this.selectedTabId = currentCategoryOnly ? selected
        : (selectedOverride > 0 ? selectedOverride : response.data.selectedTabId);
      // 服务端偶尔会在同一页重复下发同一个置顶 tid；去重但不改变其它帖子顺序。
      this.threads = mergeThreadPages([], response.data.threads);
      // 吧内列表的帖子不带来源吧字段，用当前吧兜底（帖子卡「屏蔽：XX吧」要用 fid）
      this.tagSourceForum(this.threads, name, this.forum.id);
      if (fallbackSnapshot !== undefined && fallbackSnapshot.data.selectedTabId > 0 &&
        fallbackSnapshot.data.selectedTabId !== this.selectedTabId) {
        const prevThreads: ThreadBrief[] = mergeThreadPages([], fallbackSnapshot.data.threads);
        this.tagSourceForum(prevThreads, name, this.forum.id);
        this.tabSnapshots.set(fallbackSnapshot.data.selectedTabId, new ThreadListTabSnapshot(
          fallbackSnapshot.data.forum, fallbackSnapshot.data.page, prevThreads,
          this.tabs, fallbackSnapshot.data.selectedTabId));
      }
      if (this.selectedTabId > 0) {
        this.saveTabSnapshot();
      }
      this.loadedOnce = true;
      hilog.info(0x0000, 'ForumPerf',
        'forum=%{public}s cacheHit=false rttCount=%{public}d prefMs=%{public}d deviceMs=%{public}d fetchMs=%{public}d totalMs=%{public}d threads=%{public}d',
        name, rttCount, prefMs, deviceMs, Date.now() - fetchStart, Date.now() - startedAt, this.threads.length);
      if (!currentCategoryOnly) {
        this.schedulePrefetchAdjacent(context);
      }
    } catch (err) {
      const e: Error = err as Error;
      this.errorText = `加载失败：${e.message}`;
    } finally {
      this.loading = false;
      clearFirstPageRead(name);
    }
  }

  /** 拉取下一页。吧信息只在首刷时更新，分页请求只追加主题列表。 */
  async loadMore(context: common.UIAbilityContext, retry: boolean = false): Promise<void> {
    if (this.loading || this.switchingTab || this.isLoadingMore || !this.page.hasMore || this.forumName.length === 0
      || (this.loadMoreError.length > 0 && !retry)) {
      return;
    }
    this.isLoadingMore = true;
    this.loadMoreError = '';
    const owner: string = this.ownerKey();
    const version: number = this.contentVersion;
    const tabId: number = this.selectedTabId;
    const name: string = this.forumName;
    const nextPage: number = this.page.currentPage + 1;
    const current = (): boolean => version === this.contentVersion && owner === this.ownerKey();

    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!current()) { return; }
      const response: ThreadListResponse = await this.fetchCategory(device, name, nextPage, tabId);

      if (!current()) { return; }
      if (!response.ok) {
        this.loadMoreError = response.describeFailure();
        return;
      }

      const before: number = this.threads.length;
      this.threads = mergeThreadPages(this.threads, response.data.threads);
      const progressed: boolean = response.data.page.currentPage === nextPage && this.threads.length > before;
      if (response.data.page.hasMore && !progressed) {
        response.data.page.hasMore = false; this.loadMoreError = '分页没有进展，请刷新后重试';
      }
      this.tagSourceForum(this.threads, this.forumName, this.forum.id);
      this.page = response.data.page;
      this.saveTabSnapshot();
    } catch (err) {
      if (!current()) { return; }
      const e: Error = err as Error;
      this.loadMoreError = `加载失败：${e.message}`;
    } finally {
      if (version === this.contentVersion) { this.isLoadingMore = false; }
    }
  }

  /** 后一次选择优先；读取期间保留原正文，失败时继续显示原分类。 */
  async switchTab(context: common.UIAbilityContext, tabId: number): Promise<boolean> {
    if (tabId <= 0 || tabId === this.targetTabId() || (this.loading && !this.switchingTab)
      || this.forumName.length === 0 || !this.tabs.some((tab: ForumTab): boolean => tab.id === tabId)) {
      return false;
    }
    const oldTabs: ForumTab[] = this.tabs;
    const owner: string = this.ownerKey();
    if (owner !== this.tabOwner) {
      this.tabSnapshots.clear(); this.tabReads.clear();
      this.errorText = '账号已变化，请刷新吧页面'; return false;
    }
    if (!this.switchingTab) { this.saveTabSnapshot(); }
    this.cancelPrefetch();
    const version: number = ++this.contentVersion;
    this.isLoadingMore = false;
    this.pendingTabId = tabId;
    this.errorText = '';
    this.loadMoreError = '';
    const cached: ThreadListTabSnapshot | undefined = this.tabSnapshots.get(tabId);
    if (cached !== undefined) {
      this.forum = cached.forum;
      this.page = cached.page;
      this.threads = cached.threads.slice();
      this.tabs = cached.tabs;
      this.selectedTabId = cached.selectedTabId;
      this.pendingTabId = 0;
      this.loading = false;
      this.switchingTab = false;
      this.prefetchAdjacent(context);
      return true;
    }
    this.switchingTab = true;
    this.loading = true;
    try {
      const response: ThreadListResponse = await this.readTab(context, tabId);
      if (version !== this.contentVersion) { return false; }
      if (owner !== this.ownerKey()) { this.errorText = '账号已变化，请刷新吧页面'; return false; }
      if (!response.ok) {
        this.errorText = response.describeFailure();
        return false;
      }
      if (response.data.forum.id !== this.forum.id ||
        (response.data.selectedTabId > 0 && response.data.selectedTabId !== tabId)) {
        this.errorText = '分类返回不匹配，请重试'; return false;
      }
      this.forum = response.data.forum;
      this.page = response.data.page;
      this.tabs = response.data.tabs.length > 0 ? response.data.tabs : oldTabs;
      this.selectedTabId = response.data.selectedTabId > 0 ? response.data.selectedTabId : tabId;
      this.threads = mergeThreadPages([], response.data.threads);
      this.tagSourceForum(this.threads, this.forumName, this.forum.id);
      this.loadMoreError = '';
      this.loadedOnce = true;
      this.saveTabSnapshot();
      this.prefetchAdjacent(context);
      return true;
    } catch (err) {
      if (version !== this.contentVersion) { return false; }
      const e: Error = err as Error;
      this.errorText = `加载失败：${e.message}`;
      return false;
    } finally {
      if (version === this.contentVersion) {
        this.pendingTabId = 0;
        this.loading = false;
        this.switchingTab = false;
      }
    }
  }

  private tagSourceForum(threads: ThreadBrief[], forumName: string, forumId: number): void {
    for (let i = 0; i < threads.length; i++) {
      threads[i].sourceForum = forumName;
      if (forumId > 0) { threads[i].sourceForumId = forumId; }
    }
  }

  private saveTabSnapshot(): void {
    if (this.selectedTabId <= 0) {
      return;
    }
    this.tabSnapshots.set(this.selectedTabId, new ThreadListTabSnapshot(
      this.forum, this.page, this.threads.slice(), this.tabs, this.selectedTabId));
    ++this.tabSnapshotRevision;
  }

  private async loadHeroHeadline(context: common.UIAbilityContext, forumName: string): Promise<void> {
    const name: string = forumName.trim();
    if (name.length === 0 || this.headlineRequested.has(name)) {
      return;
    }
    const cached: string = getForumHeadline(name);
    if (cached.length > 0) {
      if (this.forumName === name) { this.heroHeadline = cached; this.heroHeadlineSettled = true; }
      return;
    }
    this.headlineRequested.add(name);
    this.heroHeadlineSettled = false;
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      const result = await this.api.fetchForumHeadline(device, authSession.session(), name);
      const url: string = result.resolved();
      if (url.length > 0) {
        putForumHeadline(name, url);
        if (this.forumName === name) { this.heroHeadline = url; }
      }
    } catch (err) {
      hilog.warn(0x0000, 'ForumHero', 'headline load failed forum=%{public}s err=%{public}s',
        name, (err as Error).message);
    } finally {
      if (this.forumName === name) { this.heroHeadlineSettled = true; }
    }
  }
}
