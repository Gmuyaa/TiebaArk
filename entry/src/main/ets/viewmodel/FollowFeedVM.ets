/** 关注流轮换来源，首个有帖响应即可展示，慢来源随后追加；显式刷新接管旧请求。 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ThreadBrief, appendTimeSortedBatch, pickRandomForums,
  sortThreadsByTimeDesc } from '../model/ThreadList';
import { markForumAvatarFetched, putForumAvatar } from '../model/ForumAvatarStore';
import { ThreadListResponse, TiebaApi } from '../api/TiebaApi';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { TiebaDevice, TiebaSession } from '../net/TiebaParams';
import { authSession } from '../auth/AuthSession';
import { readFollowForumsShared } from './ForumReadCache';

const SOURCE_PICK: number = 6;
const TAKE_PER_FORUM: number = 8;
const REQUEST_PAGE_SIZE: number = 30;

class FollowSource {
  name: string;
  nextPage: number = 1;
  hasMore: boolean = true;
  error: string = '';

  constructor(name: string) { this.name = name; }
}

/** 在途结果只属于本次请求，不能提前覆盖已展示内容的分页状态。 */
class FollowBatch {
  sources: FollowSource[];
  pages: ThreadBrief[][] = [];
  seen: Set<number> = new Set<number>();
  okCount: number = 0;
  committed: boolean = false;

  constructor(sources: FollowSource[], current: ThreadBrief[]) {
    this.sources = sources;
    for (const item of current) { this.seen.add(item.tid); }
    for (let i: number = 0; i < sources.length; i++) { this.pages.push([]); }
  }

  errorText(): string {
    for (const source of this.sources) {
      if (source.error.length > 0) { return source.error; }
    }
    return '';
  }
}

/** 前台等待与网络收尾分离；首批可见、被接管或失败时均能结束等待。 */
class FollowRefresh {
  ready: Promise<void>;
  private resolveReady: () => void = (): void => {};
  private released: boolean = false;

  constructor() {
    this.ready = new Promise<void>((resolve: () => void): void => { this.resolveReady = resolve; });
  }

  release(): void {
    if (this.released) { return; }
    this.released = true;
    this.resolveReady();
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
  /** 仅保存当前关注池的轮换次序；成功一轮才移尾，换号即清空，不落盘。 */
  private sourceOrder: string[] = [];
  private loadToken: number = 0;
  private activeRefresh: FollowRefresh | undefined = undefined;
  private account: string = authSession.sessionKey();

  private current(token: number): boolean {
    return token === this.loadToken && this.account === authSession.sessionKey();
  }

  resetAccount(): void {
    this.loadToken++; this.account = authSession.sessionKey();
    this.activeRefresh?.release(); this.activeRefresh = undefined;
    this.loading = false; this.loadingMore = false; this.loadedOnce = false;
    this.threads = []; this.hasMore = false; this.errorText = ''; this.loadMoreError = '';
    this.sources = []; this.sourceOrder = []; this.followedCount = 0; this.sourceCount = 0;
    this.needLogin = !authSession.isLoggedIn();
  }

  private syncAccount(): void {
    if (this.account !== authSession.sessionKey()) { this.resetAccount(); }
  }

  private nextSourceOrder(names: string[]): string[] {
    const available: Set<string> = new Set<string>(names);
    const previous: Set<string> = new Set<string>(this.sourceOrder);
    const added: string[] = names.filter((name: string): boolean => !previous.has(name));
    return pickRandomForums(added, added.length).concat(
      this.sourceOrder.filter((name: string): boolean => available.has(name)));
  }

  load(context: common.UIAbilityContext, refresh: boolean = false): Promise<void> {
    this.syncAccount();
    if (!refresh && (this.loading || this.loadingMore)) { return Promise.resolve(); }
    if (!authSession.isLoggedIn()) { this.resetAccount(); return Promise.resolve(); }
    const token: number = ++this.loadToken;
    this.activeRefresh?.release();
    const work: FollowRefresh = new FollowRefresh();
    this.activeRefresh = work;
    this.needLogin = false;
    this.loading = true;
    this.loadingMore = false;
    this.errorText = '';
    void this.runLoad(context, token, work);
    return work.ready;
  }

  private async runLoad(context: common.UIAbilityContext, token: number, work: FollowRefresh): Promise<void> {
    const started: number = Date.now();
    try {
      // 复用完整关注列表、并发合并与既有30秒新鲜期，避免每次刷新重复拉目录。
      const guide = await readFollowForumsShared(context);
      if (!this.current(token)) { return; }
      const directoryMs: number = Date.now() - started;
      const unique: Set<string> = new Set<string>();
      const names: string[] = [];
      for (const item of guide.items) {
        const name: string = item.fname.trim();
        if (name.length > 0 && !unique.has(name)) { unique.add(name); names.push(name); }
      }
      if (names.length === 0) {
        this.threads = []; this.sources = []; this.sourceOrder = [];
        this.followedCount = 0; this.sourceCount = 0; this.hasMore = false;
        this.loadMoreError = ''; this.loadedOnce = true;
        return;
      }
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!this.current(token)) { return; }
      const order: string[] = this.nextSourceOrder(names);
      const picked: string[] = order.slice(0, SOURCE_PICK);
      const sources: FollowSource[] = picked.map((name: string): FollowSource => new FollowSource(name));
      const batch: FollowBatch = new FollowBatch(sources, []);
      await this.fetchBatch(device, authSession.session(), batch, token, (index: number): void => {
        const page: ThreadBrief[] = batch.pages[index];
        if (page.length > 0) {
          if (!batch.committed) {
            this.commitRefresh(batch, order, names.length);
            this.threads = sortThreadsByTimeDesc(page);
            // 先设置后台忙状态，避免首批结束时触底重复读取尚未返回的来源。
            this.loadingMore = true;
            this.loading = false;
            hilog.info(0x0000, 'FollowFeedVM',
              'refresh first rows=%{public}d directoryMs=%{public}d ms=%{public}d',
              page.length, directoryMs, Date.now() - started);
            work.release();
          } else {
            this.threads = appendTimeSortedBatch(this.threads, page);
          }
        }
        if (batch.committed) {
          this.loadMoreError = batch.errorText();
          this.updateHasMore();
        }
      });
      if (!this.current(token)) { return; }
      if (!batch.committed && batch.okCount !== sources.length) {
        // 没有可展示帖子且读取不完整，不能把部分空结果当作已确认空列表。
        this.errorText = batch.errorText() || '关注内容读取失败，请重试';
        return;
      }
      if (!batch.committed) {
        this.commitRefresh(batch, order, names.length);
        this.threads = [];
      }
      this.loadMoreError = batch.errorText();
      this.updateHasMore();
      hilog.info(0x0000, 'FollowFeedVM',
        'refresh followed=%{public}d sources=%{public}d threads=%{public}d ms=%{public}d',
        names.length, picked.length, this.threads.length, Date.now() - started);
    } catch (err) {
      if (this.current(token)) {
        const message: string = `加载失败：${(err as Error).message}`;
        if (this.loading) { this.errorText = message; } else { this.loadMoreError = message; }
      }
    } finally {
      if (token === this.loadToken) {
        this.loading = false; this.loadingMore = false; this.syncAccount();
      }
      if (this.activeRefresh === work) { this.activeRefresh = undefined; }
      work.release();
    }
  }

  private commitRefresh(batch: FollowBatch, order: string[], followedCount: number): void {
    batch.committed = true;
    this.sources = batch.sources;
    this.sourceOrder = order.slice(batch.sources.length).concat(order.slice(0, batch.sources.length));
    this.followedCount = followedCount; this.sourceCount = batch.sources.length;
    this.loadedOnce = true; this.errorText = ''; this.loadMoreError = '';
  }

  async loadMore(context: common.UIAbilityContext, retry: boolean = false): Promise<void> {
    this.syncAccount();
    if (this.loading || this.loadingMore || !this.hasMore || !authSession.isLoggedIn()) { return; }
    if (this.loadMoreError.length > 0 && !retry) { return; }
    const failed: FollowSource[] = this.sources.filter((source: FollowSource): boolean =>
      source.hasMore && (source.error ?? '').length > 0);
    const pending: FollowSource[] = retry && failed.length > 0 ? failed :
      this.sources.filter((source: FollowSource): boolean => source.hasMore);
    if (pending.length === 0) { this.updateHasMore(); return; }
    this.loadingMore = true;
    this.loadMoreError = '';
    const token: number = ++this.loadToken;
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!this.current(token)) { return; }
      const batch: FollowBatch = new FollowBatch(pending, this.threads);
      await this.fetchBatch(device, authSession.session(), batch, token, (index: number): void => {
        // 在同一响应回调中发布帖子和来源页码，被新刷新接管时不会跳过未展示的页。
        if (batch.pages[index].length > 0) {
          this.threads = appendTimeSortedBatch(this.threads, batch.pages[index]);
        }
        this.loadMoreError = batch.errorText();
        this.updateHasMore();
      });
      if (!this.current(token)) { return; }
      this.loadMoreError = batch.errorText();
      this.updateHasMore();
    } catch (err) {
      if (this.current(token)) { this.loadMoreError = `加载失败：${(err as Error).message}`; }
    } finally {
      if (token === this.loadToken) { this.loadingMore = false; this.syncAccount(); }
    }
  }

  private async fetchBatch(device: TiebaDevice, session: TiebaSession, batch: FollowBatch,
    token: number, onSettled: (index: number) => void): Promise<void> {
    const tasks: Promise<void>[] = [];
    for (let i: number = 0; i < batch.sources.length; i++) {
      tasks.push(this.fetchSourcePage(device, session, batch, i, token, onSettled));
    }
    await Promise.all(tasks);
  }

  /** 先对整页过滤和去重，再限额；页首重复不能遮掉其后的新帖子。 */
  private takeThreads(threads: ThreadBrief[], displayed: Set<number>): ThreadBrief[] {
    const seen: Set<number> = new Set<number>();
    const result: ThreadBrief[] = [];
    for (const item of threads) {
      if (item.isTop || item.tid <= 0 || displayed.has(item.tid) || seen.has(item.tid)) { continue; }
      seen.add(item.tid); result.push(item);
      if (result.length === TAKE_PER_FORUM) { break; }
    }
    return result;
  }

  private async fetchSourcePage(device: TiebaDevice, session: TiebaSession, batch: FollowBatch,
    index: number, token: number, onSettled: (index: number) => void): Promise<void> {
    const source: FollowSource = batch.sources[index];
    const requested: number = source.nextPage;
    const started: number = Date.now();
    try {
      const response: ThreadListResponse = await this.api.fetchThreadList(
        device, session, source.name, requested, REQUEST_PAGE_SIZE);
      if (!this.current(token)) { return; }
      if (!response.ok) { source.error = response.describeFailure(); return; }
      if (response.data.page.currentPage !== requested) {
        source.hasMore = false; source.error = '分页没有进展，请刷新后重试'; return;
      }
      const taken: ThreadBrief[] = this.takeThreads(response.data.threads, batch.seen);
      if (response.data.page.hasMore && taken.length === 0) {
        source.hasMore = false; source.error = '分页没有进展，请刷新后重试'; return;
      }
      batch.okCount++;
      source.error = '';
      source.hasMore = response.data.page.hasMore;
      source.nextPage = requested + 1;
      for (const item of taken) {
        item.sourceForum = source.name; item.sourceForumAvatar = response.data.forum.avatar;
        batch.seen.add(item.tid);
      }
      batch.pages[index] = taken;
      if (response.data.forum.avatar.trim().length > 0) {
        putForumAvatar(source.name, response.data.forum.avatar);
        markForumAvatarFetched(source.name);
      }
    } catch (err) {
      if (this.current(token)) { source.error = `加载失败：${(err as Error).message}`; }
    } finally {
      if (this.current(token)) {
        onSettled(index);
        hilog.info(0x0000, 'FollowFeedVM',
          'source slot=%{public}d page=%{public}d rows=%{public}d failed=%{public}s ms=%{public}d',
          index, requested, batch.pages[index].length, String(source.error.length > 0), Date.now() - started);
      }
    }
  }

  private updateHasMore(): void {
    this.hasMore = this.sources.some((source: FollowSource): boolean => source.hasMore);
  }
}
