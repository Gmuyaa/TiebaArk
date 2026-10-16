/** 关注频道从已关注贴吧中选取来源并聚合帖子。刷新重新选择来源，续页沿用当前批次的来源与分页状态；首屏可渐进展示，刷新完成后统一替换。 */

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

/** 取关注吧列表的条数（forumGuide 单页；够抽样本即可，不做分页） */
const FOLLOW_PAGE_SIZE: number = 50;
/** 每轮抽几个关注吧当来源。⚠️ 改大它 = 改大首屏的并发请求数，别随手调 */
const SOURCE_PICK: number = 6;
/** 每个吧最多取几条进流（跳过置顶后计） */
const TAKE_PER_FORUM: number = 8;
/** 单次列表请求条数（服务端有自己的 page_size，这里只是请求意图） */
const REQUEST_PAGE_SIZE: number = 30;

/**
 * 一个关注来源的分页状态。`nextPage` 取服务端回报的 `currentPage + 1`
 * （不用本地计数器自增：服务端可能夹取页码，以响应为准才真的是"下一页"）。
 */
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
  /** 成功加载过至少一次（区分首屏加载与下拉刷新） */
  @Trace loadedOnce: boolean = false;
  /** 失败原因；为空串表示无错误 */
  @Trace errorText: string = '';
  /** 未登录 —— 界面据此走"去登录"引导，且此时**没有任何请求发出过** */
  @Trace needLogin: boolean = false;
  /**
   * 已登录但**关注的吧为空**（`forumGuide` 返回空列表）。
   * 与"关注了吧但暂时没有新帖"是两种空态，文案不同，所以分开记。
   */
  @Trace followedCount: number = 0;

  @Trace sourceCount: number = 0;
  @Trace threads: ThreadBrief[] = [];

  /** 正在翻下一页（尾部提示 + 触底重复触发守卫） */
  @Trace loadingMore: boolean = false;

  @Trace hasMore: boolean = false;
  /** 翻页失败原因（与首屏 `errorText` 分开：它只让尾部出一条提示，不清空列表） */
  @Trace loadMoreError: string = '';

  private api: TiebaApi = new TiebaApi();

  private sources: FollowSource[] = [];
  /** 每轮加载的令牌：过期响应（期间又刷新/切频道）一律丢弃 */
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
  /** 首屏的累积缓冲（渐进渲染的中间态，每个来源到货就并进来） */
  private buffer: ThreadBrief[] = [];

  private okCount: number = 0;
  private lastError: string = '';

  private progressiveLoad: boolean = false;

  /**
   * 加载关注流（首屏 + 下拉刷新共用）。
   *
   * context 由调用方（组件）传入 —— VM 不是组件，拿不到 UIContext。
   * 未登录直接返回，**不发任何请求**（`needLogin = true` 让界面走引导）。
   */
  async load(context: common.UIAbilityContext): Promise<void> {
    this.syncAccount();
    if (this.loading || this.loadingMore) {
      return;
    }
    this.errorText = '';
    this.loadMoreError = '';
    // 刷新即重抽来源：上一轮的分页状态作废
    this.sources = [];
    this.hasMore = false;
    this.buffer = [];

    if (!authSession.isLoggedIn()) {
      this.needLogin = true;
      // 登录后再进来必须重新加载，所以这次不算"加载过"
      this.loadedOnce = false;
      this.threads = [];
      this.sourceCount = 0;
      return;
    }
    this.needLogin = false;
    this.loading = true;

    this.progressiveLoad = !this.loadedOnce;
    /** 耗时打点（真机优化用）：从发起加载到**全部来源到齐**的毫秒数 */
    const t0: number = Date.now();
    const token: number = ++this.loadToken;

    try {
      let session = authSession.session();
      if (session.tbs.length === 0) {
        // 启动恢复路径可能没带 tbs（forumGuide 缺 tbs 必然被服务端拒）
        hilog.info(0x0000, 'FollowFeedVM', 'tbs missing, refreshing once');
        await authSession.refreshTbs(context);
        session = authSession.session();
      }

      if (!this.current(token)) { return; }
      // ── 一、我关注的吧 ──
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
        // 吧名是后续请求的 kw，空名请求必失败；重名（理论上不会）也只留一个
        if (name.length === 0 || names.indexOf(name) >= 0) {
          continue;
        }
        names.push(name);
      }
      this.followedCount = names.length;

      if (names.length === 0) {
        // 已登录但没关注任何吧：空态，不算错误
        this.threads = [];
        this.sourceCount = 0;
        this.loadedOnce = true;
        return;
      }

      // ── 二、抽几个吧，各取一页（并发发完，谁先回来谁先上屏）──
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!this.current(token)) { return; }
      const picked: string[] = pickRandomForums(names, SOURCE_PICK);
      // 先把来源槽位建好：并发任务按下标回填，界面不等全部到齐
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
      // 期间用户又刷新了一轮 → 本次结果作废（新那轮已经在跑）
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
      // 全部来源到齐：照实呈现（到这里才允许出现真正的空态）
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

  /**
   * 取某个来源的第一页并**立即上屏**（渐进渲染的最小单元）。
   *
   * 每个来源一个任务，互不等待；失败只标记该来源到底，不影响其它来源。
   */
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
      // 挑进流里的帖子：跳过置顶 + 条数上限（纯函数，Node 侧有用例钉住）
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
        // 全批都失败：保留原列表，只在尾部提示重试
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

  /**
   * 取某个来源的下一页并**立即追加**（续页也渐进：先回来的先落列表，
   * 用户看到的是"内容一段段长出来"，而不是等齐六个才一起出现）。
   *
   * 每一段内部按时间倒序（`appendTimeSortedBatch`），段与段之间按到达顺序 ——
   * 这正是"分段倒序"的形态，理由见文件头注释。
   */
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
        // 失败保留来源与页码；只有用户显式重试才继续。
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

  /** 由各来源的 `hasMore` 汇总出对外字段（判据见 `anySourceHasMore`） */
  private updateHasMore(): void {
    const flags: boolean[] = [];
    for (let i = 0; i < this.sources.length; i++) {
      flags.push(this.sources[i].hasMore);
    }
    this.hasMore = anySourceHasMore(flags);
  }
}
