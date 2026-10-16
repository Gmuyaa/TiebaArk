import { ForumCacheGuard, publishForumRead } from './ForumReadCache';
/**
 * 帖子列表的状态与行为。
 *
 * V2 状态管理：`@ObservedV2` + `@Trace` 让页面能观察到字段变化。
 * 注意 `@Trace` 对数组只跟踪**整体替换**，不跟踪元素增删——
 * 所以本类每次都赋新数组，不做 `push`。
 */

import { common } from '@kit.AbilityKit';
import { ForumBrief, ForumTab, mergeThreadPages, PageInfo, ThreadBrief } from '../model/ThreadList';
import { ThreadListResponse, TiebaApi } from '../api/TiebaApi';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { TiebaDevice } from '../net/TiebaParams';
import { authSession } from '../auth/AuthSession';
import { getForumHeadline, putForumHeadline } from '../model/ForumHeadline';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FollowReadGuard, seedFollowState } from './FollowActionVM';
import { forumDefaultTabStore } from '../common/appearance/ForumDefaultTabStore';
import { preferredForumTabId } from '../model/ForumDefaultTab';

/**
 * 请求条数。注意服务端有自己的 page_size（实测返回 13 条），
 * 这个值只是"请求意图"，真实条数以响应里的 page.pageSize 为准。
 */
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
  /** 当前吧名 */
  @Trace forumName: string = '';
  @Trace loading: boolean = false;
  @Trace isLoadingMore: boolean = false;
  @Trace errorText: string = '';
  @Trace loadMoreError: string = '';
  /** 是否成功加载过至少一次（用于区分"首次加载"与"刷新"） */
  @Trace loadedOnce: boolean = false;
  @Trace switchingTab: boolean = false;

  @Trace forum: ForumBrief = new ForumBrief();
  @Trace page: PageInfo = new PageInfo();
  @Trace threads: ThreadBrief[] = [];
  @Trace tabs: ForumTab[] = [];
  @Trace selectedTabId: number = 0;
  @Trace videoSort: number = 0;
  isVideoTab(): boolean { return this.tabs.some((tab: ForumTab): boolean => tab.id === this.selectedTabId && tab.isVideo); }
  private fetchCategory(device: TiebaDevice, name: string, page: number, tabId: number): Promise<ThreadListResponse> {
    const tab: ForumTab | undefined = this.tabs.find((value: ForumTab): boolean => value.id === tabId);
    if (tab?.isVideo && this.forum.id > 0 && this.forum.name.toLowerCase() === name.toLowerCase()) {
      return this.api.fetchForumVideos(device, authSession.session(), this.forum, tab, page, this.videoSort);
    }
    return this.api.fetchThreadList(device, authSession.session(), name, page, REQUEST_PAGE_SIZE, tabId);
  }
  async changeVideoSort(context: common.UIAbilityContext, sort: number): Promise<void> {
    if (!this.isVideoTab() || this.loading || this.isLoadingMore || this.switchingTab || sort === this.videoSort) { return; }
    const previous: number = this.videoSort; this.videoSort = sort;
    await this.refresh(context, this.forumName, true);
    if (this.errorText.length > 0) { this.videoSort = previous; }
  }

  @Trace heroHeadline: string = '';

  /** 本 VM 已发起过头图请求的吧名（会话内每吧最多发一次；缓存命中不发） */
  private headlineRequested: Set<string> = new Set<string>();

  private api: TiebaApi = new TiebaApi();
  private tabSnapshots: Map<number, ThreadListTabSnapshot> = new Map<number, ThreadListTabSnapshot>();
  private tabReads: Map<number, Promise<ThreadListResponse>> = new Map<number, Promise<ThreadListResponse>>();
  private tabOwner: string = '';
  private warmingOwner: string = '';
  private tabVersion: number = 0;

  private ownerKey(): string { return `${authSession.sessionKey()}:${this.forumName}`; }

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
    request.then((response: ThreadListResponse) => {
      if (owner !== this.ownerKey() || owner !== this.tabOwner || version !== this.tabVersion) { return; }
      if (response.ok && response.data.forum.id === this.forum.id &&
        (response.data.selectedTabId === tabId || response.data.selectedTabId === 0)) {
        const threads: ThreadBrief[] = mergeThreadPages([], response.data.threads);
        this.tagSourceForum(threads, name, this.forum.id);
        this.tabSnapshots.set(tabId, new ThreadListTabSnapshot(response.data.forum, response.data.page,
          threads, response.data.tabs.length > 0 ? response.data.tabs : this.tabs, tabId));
      }
    }).catch(() => {}).finally(() => { if (this.tabReads.get(tabId) === request) { this.tabReads.delete(tabId); } });
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

  /** 拉取第一页。失败时保留 errorText 供界面展示，不抛异常。 */
  async refresh(context: common.UIAbilityContext, forumName: string, currentCategoryOnly: boolean = false): Promise<void> {
    if (this.loading || this.isLoadingMore || this.switchingTab) {
      return;
    }
    const name: string = forumName.trim();
    this.forumName = name;
    const owner: string = this.ownerKey();
    const selected: number = this.selectedTabId;
    const sameOwner: boolean = this.tabOwner === this.ownerKey();
    ++this.tabVersion;
    if (!currentCategoryOnly || !sameOwner) { this.tabSnapshots.clear(); }
    else { this.tabSnapshots.delete(selected); }
    this.tabOwner = this.ownerKey(); this.tabReads.clear(); this.warmingOwner = '';
    this.loading = true;
    this.errorText = '';
    this.loadMoreError = '';

    const followGuard: FollowReadGuard = new FollowReadGuard();
    const cacheGuard: ForumCacheGuard = new ForumCacheGuard(name);

    try {
      // 首次打开吧页先读本机偏好，避免启动时默认值抢在持久化值前发请求。
      if (!currentCategoryOnly) { await forumDefaultTabStore.load(context); }
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (owner !== this.ownerKey()) { return; }
      const initialResponse: ThreadListResponse = await this.fetchCategory(device, name, 1, this.selectedTabId);
      if (owner !== this.ownerKey()) { return; }
      let response: ThreadListResponse = initialResponse;
      let availableTabs: ForumTab[] = initialResponse.data.tabs;
      let selectedOverride: number = 0;

      if (initialResponse.ok && !currentCategoryOnly) {
        const preferredId: number = preferredForumTabId(availableTabs, forumDefaultTabStore.value);
        if (preferredId > 0 && preferredId !== initialResponse.data.selectedTabId) {
          // 分区 ID 来自本吧首包；目标失败或服务端未确认选择时仍显示首包的真实内容。
          try {
            const preferredResponse: ThreadListResponse = await this.api.fetchThreadList(
              device, authSession.session(), name, 1, REQUEST_PAGE_SIZE, preferredId);
            if (owner !== this.ownerKey()) { return; }
            if (preferredResponse.ok && preferredResponse.data.forum.id === initialResponse.data.forum.id &&
              (preferredResponse.data.selectedTabId === preferredId || preferredResponse.data.selectedTabId === 0)) {
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
      // 整体替换，触发 @Trace
      if (!currentCategoryOnly) {
        seedFollowState(followGuard, 'forum', response.data.forum.id, '', name, response.data.forum.followed);
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
      if (this.selectedTabId > 0) {
        this.saveTabSnapshot();
      }
      this.loadedOnce = true;
      // 吧头图是异步锦上添花：不阻塞列表渲染，失败静默（界面回退底纹层）
      if (!currentCategoryOnly) {
        void this.loadHeroHeadline(context, name);
        this.prefetchAdjacent(context);
      }
    } catch (err) {
      const e: Error = err as Error;
      this.errorText = `加载失败：${e.message}`;
    } finally {
      this.loading = false;
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

    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (owner !== this.ownerKey()) { return; }
      const nextPage: number = this.page.currentPage + 1;
      const response: ThreadListResponse = await this.fetchCategory(device, this.forumName, nextPage, this.selectedTabId);

      if (owner !== this.ownerKey()) { return; }
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
      const e: Error = err as Error;
      this.loadMoreError = `加载失败：${e.message}`;
    } finally {
      this.isLoadingMore = false;
    }
  }

  /** 切换真实分类；失败时恢复原列表与选择，避免出现假切换。 */
  async switchTab(context: common.UIAbilityContext, tabId: number): Promise<boolean> {
    if (tabId <= 0 || tabId === this.selectedTabId || this.loading || this.switchingTab || this.isLoadingMore
      || this.forumName.length === 0) {
      return false;
    }
    const oldForum: ForumBrief = this.forum;
    const oldPage: PageInfo = this.page;
    const oldThreads: ThreadBrief[] = this.threads;
    const oldTabs: ForumTab[] = this.tabs;
    const oldSelected: number = this.selectedTabId;
    const owner: string = this.ownerKey();
    if (owner !== this.tabOwner) {
      this.tabSnapshots.clear(); this.tabReads.clear();
      this.errorText = '账号已变化，请刷新吧页面'; return false;
    }
    this.saveTabSnapshot();
    const cached: ThreadListTabSnapshot | undefined = this.tabSnapshots.get(tabId);
    this.selectedTabId = tabId;
    if (cached !== undefined) {
      this.forum = cached.forum;
      this.page = cached.page;
      this.threads = cached.threads.slice();
      this.tabs = cached.tabs;
      this.selectedTabId = cached.selectedTabId;
      this.errorText = '';
      this.loadMoreError = '';
      this.prefetchAdjacent(context);
      return true;
    }
    this.switchingTab = true;
    this.loading = true;
    this.errorText = '';
    try {
      const response: ThreadListResponse = await this.readTab(context, tabId);
      if (owner !== this.ownerKey()) { this.selectedTabId = oldSelected; return false; }
      if (!response.ok) {
        this.forum = oldForum;
        this.page = oldPage;
        this.threads = oldThreads;
        this.tabs = oldTabs;
        this.selectedTabId = oldSelected;
        this.errorText = response.describeFailure();
        return false;
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
      this.forum = oldForum;
      this.page = oldPage;
      this.threads = oldThreads;
      this.tabs = oldTabs;
      this.selectedTabId = oldSelected;
      const e: Error = err as Error;
      this.errorText = `加载失败：${e.message}`;
      return false;
    } finally {
      this.loading = false;
      this.switchingTab = false;
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
  }

  private async loadHeroHeadline(context: common.UIAbilityContext, forumName: string): Promise<void> {
    const name: string = forumName.trim();
    if (name.length === 0 || this.headlineRequested.has(name)) {
      return;
    }
    const cached: string = getForumHeadline(name);
    if (cached.length > 0) {
      this.heroHeadline = cached;
      return;
    }
    this.headlineRequested.add(name);
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      const result = await this.api.fetchForumHeadline(device, authSession.session(), name);
      const url: string = result.resolved();
      if (url.length > 0) {
        putForumHeadline(name, url);
        this.heroHeadline = url;
      }
    } catch (err) {
      hilog.warn(0x0000, 'ForumHero', 'headline load failed forum=%{public}s err=%{public}s',
        name, (err as Error).message);
    }
  }
}
