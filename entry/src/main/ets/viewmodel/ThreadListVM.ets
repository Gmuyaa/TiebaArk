import { ForumCacheGuard, publishForumRead } from './ForumReadCache';

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

  @Trace forum: ForumBrief = new ForumBrief();
  @Trace page: PageInfo = new PageInfo();
  @Trace threads: ThreadBrief[] = [];
  @Trace tabs: ForumTab[] = [];
  @Trace selectedTabId: number = 0;

  @Trace heroHeadline: string = '';

  private headlineRequested: Set<string> = new Set<string>();

  private api: TiebaApi = new TiebaApi();
  private tabSnapshots: Map<number, ThreadListTabSnapshot> = new Map<number, ThreadListTabSnapshot>();
  private tabReads: Map<number, Promise<ThreadListResponse>> = new Map<number, Promise<ThreadListResponse>>();
  private tabOwner: string = '';
  private warmingOwner: string = '';
  private tabVersion: number = 0;

  private ownerKey(): string { return `${authSession.sessionKey()}:${this.forumName}`; }

  private readTab(context: common.UIAbilityContext, tabId: number): Promise<ThreadListResponse> {
    const existing: Promise<ThreadListResponse> | undefined = this.tabReads.get(tabId);
    if (existing !== undefined) { return existing; }
    const name: string = this.forumName;
    const owner: string = this.ownerKey();
    const version: number = this.tabVersion;
    const request: Promise<ThreadListResponse> = DeviceIdentity.ensure(context).then((device: TiebaDevice) => {
      if (owner !== this.ownerKey() || owner !== this.tabOwner || version !== this.tabVersion) { throw new Error('分类请求已失效'); }
      return this.api.fetchThreadList(device, authSession.session(), name, 1, REQUEST_PAGE_SIZE, tabId);
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
        try { await this.readTab(context, tab.id); } catch (err) {  }
      }
    };

    void Promise.all([warm(), warm()]).finally(() => { if (this.warmingOwner === warmKey) { this.warmingOwner = ''; } });
  }

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

      if (!currentCategoryOnly) { await forumDefaultTabStore.load(context); }
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (owner !== this.ownerKey()) { return; }
      const initialResponse: ThreadListResponse = await this.api.fetchThreadList(
        device, authSession.session(), name, 1, REQUEST_PAGE_SIZE, this.selectedTabId);
      if (owner !== this.ownerKey()) { return; }
      let response: ThreadListResponse = initialResponse;
      let availableTabs: ForumTab[] = initialResponse.data.tabs;
      let selectedOverride: number = 0;

      if (initialResponse.ok && !currentCategoryOnly) {
        const preferredId: number = preferredForumTabId(availableTabs, forumDefaultTabStore.value);
        if (preferredId > 0 && preferredId !== initialResponse.data.selectedTabId) {

          try {
            const preferredResponse: ThreadListResponse = await this.api.fetchThreadList(
              device, authSession.session(), name, 1, REQUEST_PAGE_SIZE, preferredId);
            if (owner !== this.ownerKey()) { return; }
            if (preferredResponse.ok && preferredResponse.data.forum.id === initialResponse.data.forum.id &&
              (preferredResponse.data.selectedTabId === preferredId || preferredResponse.data.selectedTabId === 0)) {
              response = preferredResponse;
              selectedOverride = preferredId;
            }
          } catch (err) {  }
        }
      }

      if (!response.ok) {
        this.errorText = response.describeFailure();
        if (!currentCategoryOnly) { this.threads = []; }
        return;
      }

      publishForumRead(cacheGuard, name, response);

      if (!currentCategoryOnly) {
        seedFollowState(followGuard, 'forum', response.data.forum.id, '', name, response.data.forum.followed);
        this.forum = response.data.forum;
      }
      this.page = response.data.page;
      if (!currentCategoryOnly) { this.tabs = response.data.tabs.length > 0 ? response.data.tabs : availableTabs; }
      this.selectedTabId = currentCategoryOnly ? selected
        : (selectedOverride > 0 ? selectedOverride : response.data.selectedTabId);

      this.threads = mergeThreadPages([], response.data.threads);

      this.tagSourceForum(this.threads, name, this.forum.id);
      if (this.selectedTabId > 0) {
        this.saveTabSnapshot();
      }
      this.loadedOnce = true;

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
      const response: ThreadListResponse = await this.api.fetchThreadList(
        device, authSession.session(), this.forumName, nextPage, REQUEST_PAGE_SIZE, this.selectedTabId);

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
