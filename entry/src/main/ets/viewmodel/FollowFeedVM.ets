

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ThreadBrief, anySourceHasMore, appendTimeSortedBatch, mergeThreadPages, pickRandomForums,
  sortThreadsByTimeDesc, takeNonPinnedThreads
} from '../model/ThreadList';
import { putForumAvatar } from '../model/ForumAvatarStore';
import { ThreadListResponse, TiebaApi } from '../api/TiebaApi';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { TiebaDevice, TiebaSession } from '../net/TiebaParams';
import { authSession } from '../auth/AuthSession';

const FOLLOW_PAGE_SIZE: number = 50;

const SOURCE_PICK: number = 6;

const TAKE_PER_FORUM: number = 8;

const REQUEST_PAGE_SIZE: number = 30;

class FollowSource {
  name: string;
  nextPage: number;
  hasMore: boolean;

  constructor(name: string, nextPage: number, hasMore: boolean) {
    this.name = name;
    this.nextPage = nextPage;
    this.hasMore = hasMore;
  }
}

@ObservedV2
export class FollowFeedVM {
  @Trace loading: boolean = false;

  @Trace loadedOnce: boolean = false;

  @Trace errorText: string = '';

  @Trace needLogin: boolean = false;

  @Trace followedCount: number = 0;

  @Trace sourceCount: number = 0;
  @Trace threads: ThreadBrief[] = [];

  @Trace loadingMore: boolean = false;

  @Trace hasMore: boolean = false;

  @Trace loadMoreError: string = '';

  private api: TiebaApi = new TiebaApi();

  private sources: FollowSource[] = [];

  private loadToken: number = 0;
  private account: string = authSession.sessionKey();
  private current(token: number): boolean { return token === this.loadToken && this.account === authSession.sessionKey(); }
  resetAccount(): void {
    this.loadToken++; this.account = authSession.sessionKey();
    this.loading = false; this.loadingMore = false; this.loadedOnce = false;
    this.threads = []; this.hasMore = false; this.errorText = ''; this.loadMoreError = '';
    this.sources = []; this.buffer = []; this.followedCount = 0; this.sourceCount = 0; this.needLogin = !authSession.isLoggedIn();
  }
  private syncAccount(): void { if (this.account !== authSession.sessionKey()) { this.resetAccount(); } }

  private buffer: ThreadBrief[] = [];

  private okCount: number = 0;
  private lastError: string = '';

  private progressiveLoad: boolean = false;

  async load(context: common.UIAbilityContext): Promise<void> {
    this.syncAccount();
    if (this.loading || this.loadingMore) {
      return;
    }
    this.errorText = '';
    this.loadMoreError = '';

    this.sources = [];
    this.hasMore = false;
    this.buffer = [];

    if (!authSession.isLoggedIn()) {
      this.needLogin = true;

      this.loadedOnce = false;
      this.threads = [];
      this.sourceCount = 0;
      return;
    }
    this.needLogin = false;
    this.loading = true;

    this.progressiveLoad = !this.loadedOnce;

    const t0: number = Date.now();
    const token: number = ++this.loadToken;

    try {
      let session = authSession.session();
      if (session.tbs.length === 0) {

        hilog.info(0x0000, 'FollowFeedVM', 'tbs missing, refreshing once');
        await authSession.refreshTbs(context);
        session = authSession.session();
      }

      if (!this.current(token)) { return; }

      const guide = await this.api.fetchFollowForums(session, 1, FOLLOW_PAGE_SIZE);
      if (!this.current(token)) { return; }
      if (!guide.ok) {
        this.errorText = guide.describeFailure();
        this.threads = [];
        return;
      }

      const names: string[] = [];
      const items = guide.data.items;
      for (let i = 0; i < items.length; i++) {
        const name: string = items[i].fname.trim();

        if (name.length === 0 || names.indexOf(name) >= 0) {
          continue;
        }
        names.push(name);
      }
      this.followedCount = names.length;

      if (names.length === 0) {

        this.threads = [];
        this.sourceCount = 0;
        this.loadedOnce = true;
        return;
      }

      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!this.current(token)) { return; }
      const picked: string[] = pickRandomForums(names, SOURCE_PICK);

      for (let i = 0; i < picked.length; i++) {
        this.sources.push(new FollowSource(picked[i], 2, false));
      }
      this.sourceCount = picked.length;
      this.okCount = 0;
      this.lastError = '';

      const tasks: Promise<void>[] = [];
      for (let i = 0; i < picked.length; i++) {
        tasks.push(this.fetchFirstPage(device, session, i, token));
      }
      await Promise.all(tasks);

      if (!this.current(token)) {
        return;
      }

      if (this.okCount === 0) {
        this.errorText = this.lastError;
        this.threads = [];
        this.sources = [];
        return;
      }

      this.loadedOnce = true;

      this.threads = sortThreadsByTimeDesc(this.buffer);
      this.updateHasMore();

      hilog.info(0x0000, 'FollowFeedVM',
        'followed=%{public}d picked=%{public}d threads=%{public}d hasMore=%{public}s ms=%{public}d sources=%{public}s',
        names.length, picked.length, this.threads.length, String(this.hasMore),
        Date.now() - t0, picked.join(','));
    } catch (err) {
      if (this.current(token)) {
        const e: Error = err as Error;
        this.errorText = `加载失败：${e.message}`;
        this.threads = [];
      }
    } finally {
      if (token === this.loadToken) {
        this.loading = false;
        this.syncAccount();
      }
    }
  }

  private async fetchFirstPage(device: TiebaDevice, session: TiebaSession,
    index: number, token: number): Promise<void> {
    const source: FollowSource = this.sources[index];
    const started: number = Date.now();
    try {
      const response: ThreadListResponse = await this.api.fetchThreadList(
        device, session, source.name, 1, REQUEST_PAGE_SIZE);
      if (!this.current(token)) {
        return;
      }
      if (!response.ok) {
        this.lastError = response.describeFailure();

        source.hasMore = false;
        hilog.info(0x0000, 'FollowFeedVM', 'source=%{public}s failed ms=%{public}d',
          source.name, Date.now() - started);
        return;
      }
      this.okCount++;
      source.nextPage = response.data.page.currentPage + 1;
      source.hasMore = response.data.page.hasMore;

      const taken: ThreadBrief[] = takeNonPinnedThreads(response.data.threads, TAKE_PER_FORUM);
      for (let j = 0; j < taken.length; j++) {
        taken[j].sourceForum = source.name;
        taken[j].sourceForumAvatar = response.data.forum.avatar;
      }
      this.buffer = mergeThreadPages(this.buffer, taken);

      putForumAvatar(source.name, response.data.forum.avatar);

      if (this.progressiveLoad && this.buffer.length > 0) {
        this.threads = sortThreadsByTimeDesc(this.buffer);
        this.loadedOnce = true;
      }
      hilog.info(0x0000, 'FollowFeedVM',
        'source=%{public}s got=%{public}d total=%{public}d ms=%{public}d',
        source.name, taken.length, this.threads.length, Date.now() - started);
    } catch (err) {
      if (!this.current(token)) {
        return;
      }
      const e: Error = err as Error;
      this.lastError = `加载失败：${e.message}`;
      source.hasMore = false;
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
    if (!authSession.isLoggedIn()) {
      return;
    }

    const pending: number[] = [];
    for (let i = 0; i < this.sources.length; i++) {
      if (this.sources[i].hasMore) {
        pending.push(i);
      }
    }
    if (pending.length === 0) {
      this.hasMore = false;
      return;
    }

    this.loadingMore = true;
    this.loadMoreError = '';
    const before: number = this.threads.length;
    const t0: number = Date.now();
    const token: number = ++this.loadToken;
    this.okCount = 0;
    this.lastError = '';

    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!this.current(token)) { return; }
      const session = authSession.session();
      const tasks: Promise<void>[] = [];
      for (let i = 0; i < pending.length; i++) {
        tasks.push(this.fetchNextPage(device, session, pending[i], token));
      }
      await Promise.all(tasks);
      if (!this.current(token)) {
        return;
      }

      if (this.okCount === 0) {

        this.loadMoreError = this.lastError;
        return;
      }

      this.updateHasMore();
      if (this.lastError.length > 0) { this.loadMoreError = this.lastError; }
      hilog.info(0x0000, 'FollowFeedVM',
        'loadMore sources=%{public}d added=%{public}d total=%{public}d hasMore=%{public}s ms=%{public}d',
        pending.length, this.threads.length - before, this.threads.length, String(this.hasMore),
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

  private async fetchNextPage(device: TiebaDevice, session: TiebaSession,
    index: number, token: number): Promise<void> {
    const source: FollowSource = this.sources[index];
    const started: number = Date.now();
    try {
      const response: ThreadListResponse = await this.api.fetchThreadList(
        device, session, source.name, source.nextPage, REQUEST_PAGE_SIZE);
      if (!this.current(token)) {
        return;
      }
      if (!response.ok) {

        this.lastError = response.describeFailure();
        return;
      }
      this.okCount++;
      const progressed: boolean = response.data.page.currentPage === source.nextPage;
      const unseen: boolean = takeNonPinnedThreads(response.data.threads, TAKE_PER_FORUM).some((item: ThreadBrief): boolean => !this.threads.some((old: ThreadBrief): boolean => old.tid === item.tid));
      source.nextPage = response.data.page.currentPage + 1;
      source.hasMore = response.data.page.hasMore && progressed && unseen;
      if (response.data.page.hasMore && !source.hasMore) { this.lastError = '分页没有进展，请刷新后重试'; }
      const taken: ThreadBrief[] = takeNonPinnedThreads(response.data.threads, TAKE_PER_FORUM);
      for (let j = 0; j < taken.length; j++) {
        taken[j].sourceForum = source.name;
        taken[j].sourceForumAvatar = response.data.forum.avatar;
      }
      this.threads = appendTimeSortedBatch(this.threads, taken);

      putForumAvatar(source.name, response.data.forum.avatar);
      hilog.info(0x0000, 'FollowFeedVM',
        'next source=%{public}s got=%{public}d total=%{public}d ms=%{public}d',
        source.name, taken.length, this.threads.length, Date.now() - started);
    } catch (err) {
      if (!this.current(token)) {
        return;
      }
      const e: Error = err as Error;
      this.lastError = `加载失败：${e.message}`;
    }
  }

  private updateHasMore(): void {
    const flags: boolean[] = [];
    for (let i = 0; i < this.sources.length; i++) {
      flags.push(this.sources[i].hasMore);
    }
    this.hasMore = anySourceHasMore(flags);
  }
}
