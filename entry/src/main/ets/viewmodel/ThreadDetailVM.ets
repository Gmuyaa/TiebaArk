

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AgreeResponse, MemeEmojiResponse, ReplyResponse, StoreOpResponse, SubPostResponse,
  ThreadDetailResponse, TiebaApi
} from '../api/TiebaApi';
import {
  copyPostItem, isAgreeSupported, PostItem, ReplySortType, resolveAgreeCount, resolveAgreeLiked,
  resolveForumName, SubPostItem, SubPostThreadState, ThreadDetail, syncSubPostThreadStates, unsupportedAgreeTip
} from '../model/ThreadDetail';
import { MEME_TOKEN_SALT, memeEmojiHashInput, memeEmojiToken, MemePicItem } from '../model/MemeEmoji';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { CryptoUtil } from '../utils/CryptoUtil';
import { AddPostTarget, AgreeObjType, TiebaDevice, TiebaSession } from '../net/TiebaParams';
import { authSession } from '../auth/AuthSession';

/** 每页楼层数。服务端实测会按自己的 page_size 返回，这里只是请求意图 */
const REQUEST_PAGE_SIZE: number = 30;
/** 每页楼中楼条数。与详情页一样，服务端可能按自己的 page_size 返回 */
const SUB_POST_PAGE_SIZE: number = 30;

const AGREE_CONFIRM_DELAY_MS: number = 3000;

const FLOW_TAG: string = 'AgreeFlow';
const FLOW_DOMAIN: number = 0x0000;
const FLOW_FLAG: (v: boolean) => number = (v: boolean): number => v ? 1 : 0;

/** 单层回复的可观察点赞状态，供相关组件共享。 */
@ObservedV2
export class AgreeState {
  /** confirmed：服务端权威状态（来自重新读取的 `agree.has_agree` 与 `agree.agree_num`） */
  @Trace isAgreed: boolean = false;
  @Trace count: number = 0;
  /**
   * optimistic：本地"还没被服务端确认"的那次翻转。
   * 与服务端值做 XOR 得到显示值：确认读回后会清零，显示回到服务端真值。
   */
  @Trace toggled: boolean = false;
  /** opAgree 写请求在途；仅供状态展示，点击仍可即时反转。 */
  @Trace pending: boolean = false;

  constructor(agreed: boolean, count: number) {
    this.isAgreed = agreed;
    this.count = count;
  }

  /** 界面显示的点赞态：confirmed 值 + optimistic 翻转 */
  liked(): boolean {
    return resolveAgreeLiked(this.isAgreed, this.toggled);
  }

  /** 界面显示的点赞数：confirmed 数值 + optimistic 翻转的 ±1，不为负 */
  displayCount(): number {
    return resolveAgreeCount(this.count, this.isAgreed, this.toggled);
  }
}

/** 同一点赞目标的串行写入：只保留用户最后一次点击意图。 */
class AgreeWriteState {
  owner: string = authSession.sessionKey();
  desired: boolean;
  expected: boolean;
  state: AgreeState;
  seq: number;

  constructor(desired: boolean, expected: boolean, state: AgreeState, seq: number) {
    this.desired = desired;
    this.expected = expected;
    this.state = state;
    this.seq = seq;
  }
}

@ObservedV2
export class ThreadDetailVM {
  /** 当前帖子 id */
  @Trace tid: number = 0;
  /** 是否正在进行首次加载 */
  @Trace loading: boolean = false;
  /** 是否正在下拉刷新 */
  @Trace isRefreshing: boolean = false;
  /** 是否正在加载下一页 */
  @Trace isLoadingMore: boolean = false;
  @Trace errorText: string = '';

  @Trace lastErrorCode: number = 0;
  /** 是否还没有成功加载过任何一页 */
  @Trace loadedOnce: boolean = false;

  /** 主题级信息（标题、楼主、楼层总数） */
  @Trace detail: ThreadDetail = new ThreadDetail();
  /** 已加载的楼层。每次变更都整体替换 */
  @Trace posts: PostItem[] = [];
  @Trace hasMore: boolean = false;
  /** 定位模式只展示主帖和目标回复；通过明确入口回到完整回复列表。 */
  @Trace focusedReplyPid: number = 0;
  /** 每层楼的楼中楼状态，按 pid 区分。数组整体替换触发 @Trace */
  @Trace subStates: SubPostThreadState[] = [];
  /** 当前回复排序；贴吧默认行为是按楼层正序。 */
  @Trace sortType: ReplySortType = ReplySortType.ASC;
  /**
   * 主帖收藏态（可观察）。
   *
   * **权威来源是详情响应的 `thread.is_stored`**：每次 load/refresh 成功都用
   * 服务端值重置（与点赞的 confirmed 同思路）；点击走
   * "乐观翻转 → 写接口 → 失败回滚"（`toggleStore`）。
   * 放在 VM 而不是改 `ThreadDetail` 字段的原因同点赞：`ThreadDetail` 不是
   * `@ObservedV2`，就地改它的字段不会触发界面重绘。
   */
  @Trace collected: boolean = false;
  /**
   * 收藏写操作在途（addstore / rmstore）。期间同一请求禁止第二笔——
   * 收藏仍阻止在途重复点击；点赞现会即时翻转并串行处理最新点击意图。
   */
  @Trace storePending: boolean = false;

  @Trace replyPending: boolean = false;
  /**
   * 最近一次**发表成功**的楼层 pid（0 = 还没有）。
   *
   * 用途只有一条：发表成功后让页面跳到这一层。
   * 刷新是整页替换，页面很难从"哪些是新数据"反推位置，所以由 VM 直接把
   * 服务端给的 pid 递出来；页面找不到（正序排在后面几页）就留在原地，不猜。
   */
  @Trace lastReplyPid: number = 0;
  /**
   * 切换排序时只清空和刷新回复，主帖保持原对象不动。
   *
   * （历史说明）本类曾有 `@Trace agreeToggledPids: number[]` 记录"本地未同步的翻转"，
   * 现已由 `AgreeState.toggled` 取代——那份账本与可观察态会形成两份真相，故移除。
   * 点赞显示的基准仍是服务端 `post.agree.has_agree`，见 `resolveAgreeLiked`。
   */
  @Trace isSwitchingSort: boolean = false;

  /** 收藏表情列表（云端为空 = 空数组，不是错误） */
  @Trace memePics: MemePicItem[] = [];
  /** '' = 已就绪/未开始；'loading' = 在途；其它 = 面板展示的失败文案 */
  @Trace memeStateText: string = '';
  private memeLoadedOnce: boolean = false;
  /** 发帖 token 映射：显示 URL（thumbnail 优先）→ `#(meme,collect_...)` 完整 token。
   * Map 不是 @Trace：界面渲染读 memePics，token 只在镜像提取时查表。 */
  private memeTokens: Map<string, string> = new Map<string, string>();

  /** 面板格子的显示 URL：缩略图优先，缺则原图 */
  memeDisplayUrl(item: MemePicItem): string {
    return item.thumbnail.length > 0 ? item.thumbnail : item.picUrl;
  }

  /** 镜像提取（richEditorReplyText）用的 token 查表 */
  memeTokenFor(url: string): string {
    const hit: string | undefined = this.memeTokens.get(url);
    return hit === undefined ? '' : hit;
  }

  /** token 查表入口（页面镜像函数只传 Map，不感知 VM） */
  memeTokenTable(): Map<string, string> {
    return this.memeTokens;
  }

  memeUrlFor(token: string): string {
    let found: string = '';
    this.memeTokens.forEach((value: string, key: string) => {
      if (found.length === 0 && value === token) {
        found = key;
      }
    });
    return found;
  }

  /** 失败重试：清掉"只拉一次"的闸再走同一条加载路径 */
  async retryMemePics(context: common.UIAbilityContext): Promise<void> {
    this.memeLoadedOnce = false;
    this.memeStateText = '';
    await this.loadMemePics(context);
  }

  /** 首次拉取收藏表情 + 预计算每个条目的发帖 token 映射 */
  async loadMemePics(context: common.UIAbilityContext): Promise<void> {
    if (this.memeLoadedOnce || this.memeStateText === 'loading') {
      return;
    }
    this.memeStateText = 'loading';
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      const response: MemeEmojiResponse =
        await this.api.fetchAllMeme(device, this.currentSession());
      if (!response.ok) {
        this.memeStateText = response.describeFailure();
        return;
      }
      // token 全部算完才放列表：先放列表后补映射会有"点到了但 token 没算完"的窗口
      const tokens: Map<string, string> = new Map<string, string>();
      const pics: MemePicItem[] = response.data.pics;
      for (let i = 0; i < pics.length; i++) {
        const p: MemePicItem = pics[i];
        if (p.picId.length === 0) {
          continue; // 缺 pic_id 的条目发不出合法 token，面板里也不该给它位置
        }
        const hash: string = await CryptoUtil.md5(
          memeEmojiHashInput(p.pkgId, p.picId, p.width, p.height) + MEME_TOKEN_SALT);
        const token: string = memeEmojiToken(p.pkgId, p.picId, p.width, p.height, hash);
        tokens.set(this.memeDisplayUrl(p), token);
      }
      this.memeTokens = tokens;
      this.memePics = pics;
      this.memeLoadedOnce = true;
      this.memeStateText = '';
    } catch (err) {
      this.memeStateText = `收藏表情加载失败：${(err as Error).message}`;
    }
  }

  private api: TiebaApi = new TiebaApi();
  /**
   * 当前登录凭据。**每次现取**而不是构造时缓存：
   * 用户可能在本页停留期间登录/退出，缓存一份会把旧凭据一直带下去。
   */
  private currentSession(): TiebaSession {
    return authSession.session();
  }
  /** 已成功加载到第几页（服务端的楼层页页码） */
  private loadedPage: number = 0;
  /** 楼层 pid 对应的服务端页码；确认点赞时必须读回该页。 */
  private postPages: Map<number, number> = new Map<number, number>();
  /** 楼中楼 pid 所在页与所属楼层，供点赞后读回对应的 floor 页面。 */
  private subPostPages: Map<number, number> = new Map<number, number>();
  private subPostParents: Map<number, number> = new Map<number, number>();
  /** 正序第一页响应给出的服务端总页数，倒序首屏必须从最后一页开始。 */
  private knownTotalPage: number = 1;
  /**
   * 每层楼的可观察点赞态，按 pid 索引。
   *
   * **Map 本身不需要是 @Trace**：界面读的是 `AgreeState` 自己那些 `@Trace` 字段，
   * 只要对象引用稳定（同一 pid 始终同一个实例），局部刷新就能生效。
   * 因此这里只做 `set`，从不在同 pid 上换新实例。
   */
  private agreeStates: Map<number, AgreeState> = new Map<number, AgreeState>();
  /** 同一协议目标一次只发一笔写入，连点只更新 desired，响应后按需发下一笔。 */
  private agreeWrites: Map<string, AgreeWriteState> = new Map<string, AgreeWriteState>();
  /**
   * 每层楼的**确认读回代次**：受理后安排 3s 读回；刷新或重载时旧读回作废。
   */
  private agreeConfirmSeq: Map<number, number> = new Map<number, number>();
  /** 请求版本号。每次"重来一次"的操作（首次加载 / 刷新 / 切排序）都 +1，
   * 请求返回时比对：版本号对不上说明期间又发起了新请求，旧结果直接丢弃，
   * 避免慢响应覆盖新状态造成数据串页。
   */
  private requestSeq: number = 0;

  forumNameHint: string = '';

  /** 设定来源吧名兜底。空串等同没设；调用方必须"确实知道"，不许猜 */
  setForumNameHint(name: string | undefined): void {
    this.forumNameHint = name === undefined ? '' : name.trim();
  }

  /**
   * 详情响应落地前的最后一道归一：把来源吧名补进空着的 `forumName`。
   *
   * 放在这里而不是 `ThreadDetail.fromRaw`：那是"照响应建模型"的纯函数，
   * 不该知道路由层的事；兜底是**页面语境**，属于 VM。
   */
  private absorbDetail(source: ThreadDetail): ThreadDetail {
    source.forumName = resolveForumName(source.forumName, this.forumNameHint);
    return source;
  }

  /**
   * 加载第一页。重复调用会重置到第一页。
   * 失败时保留 errorText 供界面展示，不抛异常。
   */
  async load(context: common.UIAbilityContext, tid: number, targetPid: number = 0): Promise<void> {
    if (tid <= 0) {
      this.errorText = '帖子 id 无效';
      return;
    }
    this.tid = tid;
    this.loading = true;
    this.errorText = '';
    this.lastErrorCode = 0;
    this.focusedReplyPid = 0;
    this.sortType = ReplySortType.ASC;
    this.requestSeq++;
    const seq: number = this.requestSeq;

    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      let targetPage: number = 0;
      let response: ThreadDetailResponse = await this.api.fetchThreadDetail(
        device, this.currentSession(), tid, 1, REQUEST_PAGE_SIZE, this.sortType, targetPid);
      if (targetPid > 0 && seq === this.requestSeq) {
        const targetPosts: PostItem[] = response.data.posts;
        const found: boolean = response.ok && targetPosts.some((post: PostItem) => post.pid === targetPid);
        const original: ThreadDetailResponse = await this.api.fetchThreadDetail(
          device, this.currentSession(), tid, 1, REQUEST_PAGE_SIZE, this.sortType);
        if (seq !== this.requestSeq) {
          return;
        }
        if (found && original.ok) {
          const main: PostItem | undefined = ThreadDetail.locateMainPost(original.data);
          if (main !== undefined) {
            original.data.posts = [main].concat(targetPosts.filter((post: PostItem) => post.pid !== main.pid));
            this.focusedReplyPid = targetPid;
            targetPage = response.data.page.currentPage;
          } else {
            original.failLocal('暂时无法读取原帖内容，请稍后重试');
          }
        }
        // 未命中、已删除或暂不可见时，保留原帖阅读入口，不伪造目标楼层。
        response = original;
      }
      if (seq !== this.requestSeq) {
        return;
      }

      if (!response.ok) {
        this.errorText = response.describeFailure();
        this.lastErrorCode = response.errorCode;
        this.posts = [];
        this.postPages.clear();
        this.subPostPages.clear();
        this.subPostParents.clear();
        this.subStates = [];
        this.visiblePosts = [];
        this.loadedPage = 0;
        hilog.warn(FLOW_DOMAIN, FLOW_TAG, 'source=reload-failed reason=%{public}s', this.errorText);
        return;
      }

      // 整体替换，触发 @Trace（兜底吧名在这一步合并进去）
      this.detail = this.absorbDetail(response.data);
      // 收藏态跟详情一起从服务端重置（本地乐观值随权威值落地）
      this.collected = response.data.isStored;
      this.posts = response.data.posts;
      if (this.focusedReplyPid > 0) {
        this.rememberPostPages([this.posts[0]], 1, true);
        // 回复所属页来自 pid 定位响应，不能记成补取主帖的第一页。
        this.rememberPostPages(this.posts.slice(1), targetPage, false);
      } else {
        this.rememberPostPages(response.data.posts, response.data.page.currentPage, true);
      }
      this.hasMore = this.focusedReplyPid === 0 && response.data.page.hasMore;
      this.loadedPage = response.data.page.currentPage;
      this.knownTotalPage = Math.max(1, response.data.page.totalPage);
      this.loadedOnce = true;
      this.syncVisiblePosts();
      // 新数据到位后重建可观察点赞态（整批换新实例）
      this.rebuildAgreeStates('reload');
      // 新建/重置楼中楼状态；已有楼层数据不再保留，状态也应从零开始
      this.syncSubStates(this.posts, true);
      this.agreeFlowSnapshot('load-done');
    } catch (err) {
      const e: Error = err as Error;
      this.errorText = `加载失败：${e.message}`;
    } finally {
      this.loading = false;
    }
  }

  /**
   * 刷新当前帖子第一页。
   *
   * 与首次 load 不同，刷新保留当前 tid 和排序；非正序模式保留主帖对象，
   * 只替换回复列表并重置分页、楼中楼状态。
   */
  async refresh(context: common.UIAbilityContext): Promise<void> {
    if (this.tid <= 0 || this.loading || this.isRefreshing || this.isLoadingMore ||
      this.isSwitchingSort) {
      return;
    }
    if (this.focusedReplyPid > 0) {
      await this.load(context, this.tid);
      return;
    }
    this.isRefreshing = true;
    this.errorText = '';
    this.requestSeq++;
    const seq: number = this.requestSeq;

    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      const requestPage: number = this.firstPageForSort(this.sortType);
      const requestSort: ReplySortType = this.sortType;
      const response: ThreadDetailResponse = await this.api.fetchThreadDetail(
        device, this.currentSession(), this.tid, requestPage, REQUEST_PAGE_SIZE, requestSort);
      // 期间又切了排序/重新加载过 → 结果已过期，丢弃
      if (requestSort !== this.sortType || seq !== this.requestSeq) {
        return;
      }

      if (!response.ok) {
        this.errorText = response.describeFailure();
        return;
      }

      if (this.sortType === ReplySortType.ASC) {
        this.detail = this.absorbDetail(response.data);
        this.posts = response.data.posts;
      } else {
        this.replaceRepliesKeepingMain(response.data.posts);
      }
      this.rememberPostPages(response.data.posts, response.data.page.currentPage, true);
      // 刷新同样用服务端收藏态重置（两个分支都要走）
      this.collected = response.data.isStored;
      this.updatePaging(response.data.page.currentPage, response.data.page.totalPage,
        response.data.page.hasMore);
      this.loadedOnce = true;
      this.syncVisiblePosts();
      this.rebuildAgreeStates('refresh');
      this.syncSubStates(this.posts, true);
      this.agreeFlowSnapshot('refresh-done');
    } catch (err) {
      const e: Error = err as Error;
      this.errorText = `刷新失败：${e.message}`;
    } finally {
      this.isRefreshing = false;
    }
  }

  /**
   * 加载下一页楼层并追加。
   *
   * 有并发保护：滚动到底会连续触发，不挡住会重复请求同一页。
   * 注意翻页依据是**页码**而不是已加载条数——服务端会跳号（实测缺 4/10/13 楼），
   * 用条数推算页码迟早对不上。
   */
  async loadMore(context: common.UIAbilityContext): Promise<void> {
    if (this.loading || this.isRefreshing || this.isLoadingMore || this.isSwitchingSort ||
      !this.hasMore || this.loadedPage <= 0) {
      return;
    }
    this.isLoadingMore = true;
    this.errorText = '';
    const seq: number = this.requestSeq;
    // 发出请求时的排序；回来时若已被切走，这一页属于旧排序，不能接上去
    const requestSort: ReplySortType = this.sortType;

    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      const nextPage: number = this.sortType === ReplySortType.DESC
        ? this.loadedPage - 1 : this.loadedPage + 1;
      const response: ThreadDetailResponse = await this.api.fetchThreadDetail(
        device, this.currentSession(), this.tid, nextPage, REQUEST_PAGE_SIZE, requestSort);
      if (requestSort !== this.sortType || seq !== this.requestSeq) {
        return;
      }

      if (!response.ok) {
        // 加载更多失败不该清空已有内容，只提示
        this.errorText = response.describeFailure();
        return;
      }

      // 只追加尚未出现的 pid，避免服务端重复页造成重复楼层。
      this.posts = this.mergePostsByPid(this.posts, response.data.posts);
      this.rememberPostPages(response.data.posts, response.data.page.currentPage, false);
      this.updatePaging(response.data.page.currentPage, response.data.page.totalPage,
        response.data.page.hasMore);
      this.syncVisiblePosts();
      // 保留已有楼中楼的展开/加载状态，只为新楼层补状态
      this.syncSubStates(this.posts, false);
    } catch (err) {
      const e: Error = err as Error;
      this.errorText = `加载失败：${e.message}`;
    } finally {
      this.isLoadingMore = false;
    }
  }

  /** 合并楼层并按 pid 去重；保留已有顺序，新增楼层按服务端顺序追加 */
  private mergePostsByPid(existing: PostItem[], incoming: PostItem[]): PostItem[] {
    const merged: PostItem[] = existing.concat([]);
    const knownPids: Set<number> = new Set<number>();
    for (let i = 0; i < existing.length; i++) {
      knownPids.add(existing[i].pid);
    }
    for (let i = 0; i < incoming.length; i++) {
      if (!knownPids.has(incoming[i].pid)) {
        knownPids.add(incoming[i].pid);
        merged.push(incoming[i]);
      }
    }
    return merged;
  }

  private rememberPostPages(posts: PostItem[], page: number, replace: boolean): void {
    if (replace) {
      this.postPages.clear();
    }
    for (let i = 0; i < posts.length; i++) {
      if (!this.postPages.has(posts[i].pid)) {
        this.postPages.set(posts[i].pid, page);
      }
    }
  }

  /** 界面实际渲染的楼层；整体替换保证 @Trace 列表稳定刷新。 */
  @Trace visiblePosts: PostItem[] = [];

  private syncVisiblePosts(): void {
    this.visiblePosts = this.posts;
  }

  /**
   * 切换回复排序。服务端真实能力：r=0 正序、r=1 倒序、r=2 热门、lz=1 楼主。
   * 倒序从最后一页开始并逐页递减；不会对当前已加载页做 reverse。
   */
  async switchReplySort(context: common.UIAbilityContext, newType: ReplySortType): Promise<void> {
    if (newType === this.sortType || this.tid <= 0 || this.loading || this.isRefreshing ||
      this.isLoadingMore || this.isSwitchingSort || this.posts.length === 0) {
      return;
    }

    const previousType: ReplySortType = this.sortType;
    const previousPosts: PostItem[] = this.posts;
    const previousVisible: PostItem[] = this.visiblePosts;
    const previousSubStates: SubPostThreadState[] = this.subStates;
    const previousPage: number = this.loadedPage;
    const previousHasMore: boolean = this.hasMore;
    this.sortType = newType;
    this.isSwitchingSort = true;
    this.errorText = '';
    this.requestSeq++;
    const seq: number = this.requestSeq;
    // 换了一批楼层，本地未同步的点赞翻转不再对应任何可见楼层
    // 保留同一个主帖对象，只清空回复。
    this.posts = [previousPosts[0]];
    this.syncVisiblePosts();
    this.rebuildAgreeStates('switchSort');
    this.subStates = [];

    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      const requestPage: number = this.firstPageForSort(newType);
      const response: ThreadDetailResponse = await this.api.fetchThreadDetail(
        device, this.currentSession(), this.tid, requestPage, REQUEST_PAGE_SIZE, newType);
      // 期间又切了一次排序（或整体重新加载）→ 这次结果已过期，丢弃且不改状态
      if (seq !== this.requestSeq || newType !== this.sortType) {
        return;
      }
      if (!response.ok) {
        this.errorText = response.describeFailure();
        this.sortType = previousType;
        this.posts = previousPosts;
        this.visiblePosts = previousVisible;
        this.loadedPage = previousPage;
        this.hasMore = previousHasMore;
        this.subStates = previousSubStates;
        return;
      }

      this.replaceRepliesKeepingMain(response.data.posts);
      this.focusedReplyPid = 0;
      this.rememberPostPages(response.data.posts, response.data.page.currentPage, true);
      this.updatePaging(response.data.page.currentPage, response.data.page.totalPage,
        response.data.page.hasMore);
      this.syncVisiblePosts();
      this.syncSubStates(this.posts, true);
    } catch (err) {
      const e: Error = err as Error;
      this.errorText = `切换失败：${e.message}`;
      this.sortType = previousType;
      this.posts = previousPosts;
      this.visiblePosts = previousVisible;
      this.loadedPage = previousPage;
      this.hasMore = previousHasMore;
      this.subStates = previousSubStates;
    } finally {
      this.isSwitchingSort = false;
    }
  }

  /** 倒序首屏从服务端最后一页开始，其他模式从第一页开始。 */
  private firstPageForSort(type: ReplySortType): number {
    return type === ReplySortType.DESC ? Math.max(1, this.knownTotalPage) : 1;
  }

  /** 过滤响应里可能重复携带的主帖，并把新回复接到现有主帖后。 */
  private replaceRepliesKeepingMain(incoming: PostItem[]): void {
    if (this.posts.length === 0) {
      this.posts = incoming;
      return;
    }
    const main: PostItem = this.posts[0];
    const replies: PostItem[] = [];
    for (let i = 0; i < incoming.length; i++) {
      if (incoming[i].pid !== main.pid) {
        replies.push(incoming[i]);
      }
    }
    this.posts = [main].concat(replies);
  }

  /** 服务端倒序的 has_more 含义不稳定，以当前页是否大于 1 判断是否还能向前翻。 */
  private updatePaging(currentPage: number, totalPage: number, serverHasMore: boolean): void {
    this.loadedPage = currentPage;
    if (totalPage > 0 && (this.sortType === ReplySortType.ASC ||
      this.sortType === ReplySortType.DESC)) {
      this.knownTotalPage = totalPage;
    }
    this.hasMore = this.sortType === ReplySortType.DESC ? currentPage > 1 : serverHasMore;
  }

  /** 读取某楼状态。状态尚未建立时返回临时空状态，保证渲染层不必先判空 */
  subState(pid: number): SubPostThreadState {
    const found: SubPostThreadState | undefined = this.findSubState(pid);
    if (found !== undefined) {
      return found;
    }
    const fallback: SubPostThreadState = new SubPostThreadState();
    fallback.pid = pid;
    return fallback;
  }

  /**
   * 展开/收起某层楼中楼。
   *
   * 首次展开时自动加载第一页。首次加载失败后再次点击是收起而不是重试；
   * 重试由独立的 retrySubPosts 负责，避免"重试"按钮把区域收起来。
   */
  async toggleSubPosts(context: common.UIAbilityContext, pid: number,
    threadAuthorId: number): Promise<void> {
    let state: SubPostThreadState | undefined = this.findSubState(pid);
    if (state === undefined) {
      state = new SubPostThreadState();
      state.pid = pid;
      this.subStates = this.subStates.concat([state]);
    }

    if (state.expanded) {
      state.expanded = false;
      this.touchSubStates();
      return;
    }

    state.expanded = true;
    state.errorText = '';
    this.touchSubStates();
    if (!state.loadedOnce && !state.loading) {
      await this.loadSubPosts(context, pid, threadAuthorId, 1);
    }
  }

  /**
   * 静默拉取某层楼中楼第一页，供一级回复下方的预览灰块使用。
   *
   * 与 toggleSubPosts 的区别：不改 expanded，也不要求用户点开——
   * 楼层进入视口就会调用，靠 loadedOnce/loading 去重，一层只请求一次。
   */
  async ensureSubPostPreview(context: common.UIAbilityContext, pid: number,
    threadAuthorId: number): Promise<void> {
    const state: SubPostThreadState | undefined = this.findSubState(pid);
    if (state === undefined || state.loadedOnce || state.loading) {
      return;
    }
    await this.loadSubPosts(context, pid, threadAuthorId, 1);
  }

  /**
   * 取某层楼的可观察点赞态（**引用稳定**：同一 pid 永远返回同一个实例）。
   *
   * 这是给 UI 读的唯一入口。界面不再从 `PostItem` 派生点赞显示值——
   * 那样在 `ForEach` 复用下不会更新（见 `AgreeState` 注释）。
   * 首次取到时按当前服务端值建一次；之后只更新字段，不换对象。
   */
  agreeState(pid: number): AgreeState {
    const found: AgreeState | undefined = this.agreeStates.get(pid);
    if (found !== undefined) {
      return found;
    }
    const post: PostItem | undefined = this.postByPid(pid);
    const created: AgreeState = new AgreeState(
      post === undefined ? false : post.isAgreed,
      post === undefined ? 0 : post.agreeCount);
    this.agreeStates.set(pid, created);
    /*
     * AgreeFlow 追踪：惰性建项是"UI 显示未点赞"的头号嫌疑——
     * 若主帖 pid 不在 agreeStates（例如重建时主帖不在 posts 里），
     * 这里会静默造出 isAgreed=false 的默认态。
     */
    hilog.info(FLOW_DOMAIN, FLOW_TAG,
      'source=lazyCreate pid=%{public}d isMain=%{public}s postFound=%{public}s'
        + ' created[isAgreed=%{public}s count=%{public}d]',
      pid, String(FLOW_FLAG(pid === this.detail.mainPostId)),
      String(post === undefined ? 'NO' : 'yes'),
      String(FLOW_FLAG(created.isAgreed)), created.count);
    return created;
  }

  /** 楼中楼列表项的可观察点赞态。首次读取时从 floor 响应播种。 */
  subAgreeState(sub: SubPostItem): AgreeState {
    const found: AgreeState | undefined = this.agreeStates.get(sub.pid);
    if (found !== undefined) {
      return found;
    }
    const created: AgreeState = new AgreeState(sub.isAgreed, sub.agreeCount);
    this.agreeStates.set(sub.pid, created);
    return created;
  }

  /**
   * 用服务端数据重建全部可观察态（首次加载 / 下拉刷新 / 切排序后调用）。
   *
   * 这里**换新实例**是有意的：整批数据都换了，旧引用不该再被复用。
   * `source` 仅用于 AgreeFlow 追踪（reload / refresh / switchSort）。
   */
  private rebuildAgreeStates(source: string): void {
    const mainId: number = this.detail.mainPostId;
    const oldState: AgreeState | undefined = mainId > 0 ? this.agreeStates.get(mainId) : undefined;
    const next: Map<number, AgreeState> = new Map<number, AgreeState>();
    for (let i = 0; i < this.posts.length; i++) {
      const p: PostItem = this.posts[i];
      next.set(p.pid, new AgreeState(p.isAgreed, p.agreeCount));
    }
    this.agreeStates = next;
    const newState: AgreeState | undefined = mainId > 0 ? next.get(mainId) : undefined;
    hilog.info(FLOW_DOMAIN, FLOW_TAG,
      'source=%{public}s rebuildAgreeStates mainPostId=%{public}d'
        + ' old[isAgreed=%{public}s toggled=%{public}s count=%{public}d]'
        + ' new[isAgreed=%{public}s toggled=%{public}s count=%{public}d] mainInPosts=%{public}s',
      source, mainId,
      oldState === undefined ? 'absent' : String(FLOW_FLAG(oldState.isAgreed)),
      oldState === undefined ? '-' : String(FLOW_FLAG(oldState.toggled)),
      oldState === undefined ? -1 : oldState.count,
      newState === undefined ? 'absent' : String(FLOW_FLAG(newState.isAgreed)),
      newState === undefined ? '-' : String(FLOW_FLAG(newState.toggled)),
      newState === undefined ? -1 : newState.count,
      newState === undefined ? 'NO(主帖不在楼层列表!)' : 'yes');
    if (mainId > 0) {
      this.agreeFlowSnapshot(`after-rebuild(${source})`);
    }
  }

  /**
   * AgreeFlow 追踪：输出 C 层（UI/VM）四项读数。
   * `agreeState(mainPostId)` 与界面读的是同一个入口（含惰性建项的副作用，这正是要观测的）。
   */
  private agreeFlowSnapshot(source: string): void {
    const mainId: number = this.detail.mainPostId;
    const main: PostItem | undefined = this.mainPost();
    const state: AgreeState = this.agreeState(mainId);
    hilog.info(FLOW_DOMAIN, FLOW_TAG,
      'vm[%{public}s] tid=%{public}d mainPostId=%{public}d'
        + ' detail.isAgreed=%{public}s detail.agreeCount=%{public}d'
        + ' mainPost.isAgreed=%{public}s mainPost.agreeCount=%{public}d'
        + ' agreeState(mainPostId)[liked=%{public}s toggled=%{public}s count=%{public}d]',
      source, this.tid, mainId,
      String(FLOW_FLAG(this.detail.isAgreed)), this.detail.agreeCount,
      String(main === undefined ? -1 : FLOW_FLAG(main.isAgreed)),
      main === undefined ? -1 : main.agreeCount,
      String(FLOW_FLAG(state.liked())), String(FLOW_FLAG(state.toggled)), state.count);
  }

  /** 界面显示的点赞态。读 `AgreeState`（可观察），不再从 PostItem 派生 */
  isLiked(item: PostItem): boolean {
    return this.agreeState(item.pid).liked();
  }

  /** 界面显示的点赞数。读 `AgreeState`（可观察） */
  agreeCountOf(item: PostItem): number {
    return this.agreeState(item.pid).displayCount();
  }

  private applyServerAgree(pid: number, agreed: boolean, count: number): void {
    const oldState: AgreeState = this.agreeState(pid);
    const oldAgreed: boolean = oldState.isAgreed;
    const oldCount: number = oldState.count;
    const next: PostItem[] = [];
    for (let i = 0; i < this.posts.length; i++) {
      const src: PostItem = this.posts[i];
      if (src.pid === pid) {
        const copy: PostItem = copyPostItem(src);
        copy.isAgreed = agreed;
        copy.agreeCount = count;
        next.push(copy);
      } else {
        next.push(src);
      }
    }
    this.posts = next;
    this.syncVisiblePosts();

    const state: AgreeState = this.agreeState(pid);
    state.isAgreed = agreed;
    state.count = count;
    state.toggled = false;

    /*
     * 改的若是主帖，必须同时同步 `detail`：
     * 底栏读 `detail.agreeCount` / `detail.isAgreed`，而楼层列表读 `posts`——
     * 只改一边会让底栏与楼内显示分叉（点完赞，楼里变了、底栏没变）。
     * 按 pid 与 `mainPostId` 比对，不用数组位置。
     */
    if (this.detail.mainPostId > 0 && pid === this.detail.mainPostId) {
      this.detail.agreeCount = count;
      this.detail.isAgreed = agreed;
    }
    hilog.info(FLOW_DOMAIN, FLOW_TAG,
      'source=applyServerAgree pid=%{public}d isMain=%{public}s'
        + ' old[isAgreed=%{public}s count=%{public}d] new[isAgreed=%{public}s count=%{public}d]'
        + ' detail.synced=%{public}s detail.isAgreed=%{public}s',
      pid, String(FLOW_FLAG(pid === this.detail.mainPostId)),
      String(FLOW_FLAG(oldAgreed)), oldCount,
      String(FLOW_FLAG(agreed)), count,
      String(FLOW_FLAG(this.detail.mainPostId > 0 && pid === this.detail.mainPostId)),
      String(FLOW_FLAG(this.detail.isAgreed)));
  }

  /**
   * 当前主帖（首楼）。定位规则见 `ThreadDetail.locateMainPost`：
   * 先按 `mainPostId`（权威），缺失时才退到 `floor === 1`，**绝不用数组位置**。
   * 定位不到返回 undefined —— 调用方据此不提供该操作，而不是拿 `posts[0]` 顶上。
   */
  mainPost(): PostItem | undefined {
    return ThreadDetail.locateMainPost(this.detail);
  }

  /** 回复点赞与取消点赞的异步状态管理。 */
  async toggleAgree(context: common.UIAbilityContext, item: PostItem | SubPostItem,
    objType: AgreeObjType = AgreeObjType.POST, parentPid: number = 0): Promise<string> {
    const pid: number = item.pid;
    const state: AgreeState = objType === AgreeObjType.SUB_POST
      ? this.subAgreeState(item as SubPostItem) : this.agreeState(pid);

    if (!this.currentSession().hasBduss()) {
      return '需要登录后才能点赞';
    }

    if (!isAgreeSupported(objType)) {
      return unsupportedAgreeTip(objType);
    }
    if (objType === AgreeObjType.SUB_POST && parentPid <= 0) {
      return '暂时无法定位这条回复';
    }

    const key: string = `${objType}:${this.tid}:${pid}`;
    const before: boolean = state.liked();
    const target: boolean = !before;

    state.toggled = !state.toggled;
    hilog.info(FLOW_DOMAIN, FLOW_TAG,
      'source=localState(optimistic) pid=%{public}d isMain=%{public}s target.agreed=%{public}s'
        + ' old[isAgreed=%{public}s liked=%{public}s count=%{public}d]',
      pid, String(FLOW_FLAG(pid === this.detail.mainPostId)), String(FLOW_FLAG(target)),
      String(FLOW_FLAG(state.isAgreed)), String(FLOW_FLAG(before)), state.count);

    const existing: AgreeWriteState | undefined = this.agreeWrites.get(key);
    if (existing !== undefined && existing.state === state && existing.seq === this.requestSeq && existing.owner === authSession.sessionKey()) {
      existing.desired = target;
      hilog.info(FLOW_DOMAIN, FLOW_TAG,
        'source=queued-latest pid=%{public}d desired=%{public}s', pid, String(FLOW_FLAG(target)));
      return '';
    }

    // 新点击立即废掉上一轮尚未完成的确认读回。
    const previous: number | undefined = this.agreeConfirmSeq.get(pid);
    this.agreeConfirmSeq.set(pid, (previous === undefined ? 0 : previous) + 1);
    const flight: AgreeWriteState = new AgreeWriteState(target, before, state, this.requestSeq);
    this.agreeWrites.set(key, flight);
    state.pending = true;
    return await this.runAgreeWrites(context, pid, objType, parentPid, key, flight,
      this.tid, this.detail.forumId);
  }

  /** 请求串行化，但用户每次点击都直接改变可见状态。 */
  private async runAgreeWrites(context: common.UIAbilityContext, pid: number,
    objType: AgreeObjType, parentPid: number, key: string, flight: AgreeWriteState,
    tid: number, forumId: number): Promise<string> {
    let reason: string = '';
    let wrote: boolean = false;
    const session: TiebaSession = this.currentSession();
    const owner: string = authSession.sessionKey();
    const current: () => boolean = (): boolean => authSession.matchesSession(session, owner) &&
      flight.seq === this.requestSeq && this.tid === tid;
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!current()) { return '账号或帖子已变化，未继续点赞'; }
      while (current() && flight.desired !== flight.expected) {
        const target: boolean = flight.desired;
        // 请求已发出后即使响应异常，也要读回核对可能已经落账的服务端状态。
        wrote = true;
        const response: AgreeResponse = await this.api.agreePost(
          device, session, tid, pid, target, objType,
          objType === AgreeObjType.POST ? forumId : 0);
        if (!current()) { return '账号或帖子已变化，请重新读取点赞结果'; }
        if (response.ok) {
          flight.expected = target;
          hilog.info(FLOW_DOMAIN, FLOW_TAG,
            'source=accepted pid=%{public}d target=%{public}s score=%{public}s',
            pid, String(FLOW_FLAG(target)), response.agreeScore);
        } else if (flight.desired === target) {
          reason = response.describeFailure();
          flight.state.toggled = flight.state.isAgreed !== flight.expected;
          hilog.info(FLOW_DOMAIN, FLOW_TAG,
            'source=write-rollback pid=%{public}d expected=%{public}s reason=%{public}s',
            pid, String(FLOW_FLAG(flight.expected)), reason);
          break;
        }
      }
    } catch (err) {
      const e: Error = err as Error;
      reason = `点赞失败：${e.message}`;
      flight.state.toggled = flight.state.isAgreed !== flight.expected;
    } finally {
      flight.state.pending = false;
      if (this.agreeWrites.get(key) === flight) {
        this.agreeWrites.delete(key);
      }
      if (wrote && current()) {
        this.scheduleAgreeConfirm(context, pid, objType, parentPid);
      }
    }
    return reason;
  }

  private scheduleAgreeConfirm(context: common.UIAbilityContext, pid: number,
    objType: AgreeObjType, parentPid: number): void {
    const prev: number | undefined = this.agreeConfirmSeq.get(pid);
    const token: number = (prev === undefined ? 0 : prev) + 1;
    this.agreeConfirmSeq.set(pid, token);
    const seq: number = this.requestSeq;
    setTimeout((): void => {
      this.finishAgreeConfirm(context, pid, objType, parentPid, token, seq);
    }, AGREE_CONFIRM_DELAY_MS);
  }

  private async finishAgreeConfirm(context: common.UIAbilityContext, pid: number,
    objType: AgreeObjType, parentPid: number, token: number, seq: number): Promise<void> {
    try {
      if (objType === AgreeObjType.SUB_POST) {
        await this.confirmSubAgreeFromServer(context, pid, parentPid, token, seq);
      } else {
        await this.confirmAgreeFromServer(context, pid, token, seq);
      }
    } catch (err) {
      const e: Error = err as Error;
      hilog.warn(FLOW_DOMAIN, FLOW_TAG,
        'source=confirm-unexpected-error pid=%{public}d reason=%{public}s', pid, e.message);
    }
  }

  private async confirmAgreeFromServer(context: common.UIAbilityContext, pid: number,
    token: number, seq: number): Promise<void> {
    const current: number | undefined = this.agreeConfirmSeq.get(pid);
    if (current === undefined || current !== token || seq !== this.requestSeq) {
      return; // 已有点更新的读回，或期间刷新/重载/切排序过 → 过期，跳过
    }
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      const isMain: boolean = pid === this.detail.mainPostId;
      const floorPage: number | undefined = this.postPages.get(pid);
      if (!isMain && floorPage === undefined) {
        hilog.warn(FLOW_DOMAIN, FLOW_TAG,
          'source=confirm-skip(page-unknown) pid=%{public}d', pid);
        return;
      }
      const response: ThreadDetailResponse = await this.api.fetchThreadDetail(
        device, this.currentSession(), this.tid, isMain ? 1 : floorPage!, REQUEST_PAGE_SIZE,
        isMain ? ReplySortType.ASC : this.sortType);
      const latest: number | undefined = this.agreeConfirmSeq.get(pid);
      if (latest === undefined || latest !== token || seq !== this.requestSeq) {
        return; // 读取期间状态又被推进了，这次读数过期
      }
      if (!response.ok) {
        hilog.warn(FLOW_DOMAIN, FLOW_TAG,
          'source=confirm-read-failed pid=%{public}d reason=%{public}s',
          pid, response.describeFailure());
        return;
      }

      let agreed: boolean;
      let count: number;
      if (pid === response.data.mainPostId) {
        // 主帖：权威来源是主题级 thread.agree（fromRaw 已归一），见 model/ThreadDetail.ets
        agreed = response.data.isAgreed;
        count = response.data.agreeCount;
      } else {
        const posts: PostItem[] = response.data.posts;
        let fresh: PostItem | undefined = undefined;
        for (let i = 0; i < posts.length; i++) {
          if (posts[i].pid === pid) {
            fresh = posts[i];
            break;
          }
        }
        if (fresh === undefined) {
          hilog.info(FLOW_DOMAIN, FLOW_TAG,
            'source=confirm-skip(floor-not-on-page) pid=%{public}d page=%{public}d',
            pid, floorPage!);
          return;
        }
        agreed = fresh.isAgreed;
        count = fresh.agreeCount;
      }
      hilog.info(FLOW_DOMAIN, FLOW_TAG,
        'source=confirm-read pid=%{public}d isMain=%{public}s server[agreed=%{public}s count=%{public}d]',
        pid, String(FLOW_FLAG(pid === response.data.mainPostId)),
        String(FLOW_FLAG(agreed)), count);
      // confirmed 写回：isAgreed=服务端真值、toggled 清零。服务端已撤销时显示自动回滚
      this.applyServerAgree(pid, agreed, count);
    } catch (err) {
      const e: Error = err as Error;
      hilog.warn(FLOW_DOMAIN, FLOW_TAG,
        'source=confirm-read-exception pid=%{public}d reason=%{public}s', pid, e.message);
    }
  }

  /** 楼中楼用 floor 端点读回，不能用帖子详情的一级楼层列表确认。 */
  private async confirmSubAgreeFromServer(context: common.UIAbilityContext, pid: number,
    parentPid: number, token: number, seq: number): Promise<void> {
    const page: number | undefined = this.subPostPages.get(pid);
    if (page === undefined || this.subPostParents.get(pid) !== parentPid) {
      hilog.warn(FLOW_DOMAIN, FLOW_TAG, 'source=sub-confirm-skip(page-unknown) pid=%{public}d', pid);
      return;
    }
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      const response: SubPostResponse = await this.api.fetchSubPosts(
        device, this.currentSession(), this.tid, parentPid, this.detail.author.id, page,
        SUB_POST_PAGE_SIZE);
      const latest: number | undefined = this.agreeConfirmSeq.get(pid);
      if (latest !== token || seq !== this.requestSeq || !response.ok) {
        return;
      }
      for (let i = 0; i < response.data.subPosts.length; i++) {
        const fresh: SubPostItem = response.data.subPosts[i];
        if (fresh.pid === pid) {
          const parent: SubPostThreadState | undefined = this.findSubState(parentPid);
          if (parent !== undefined) {
            for (let j = 0; j < parent.subPosts.length; j++) {
              if (parent.subPosts[j].pid === pid) {
                parent.subPosts[j].isAgreed = fresh.isAgreed;
                parent.subPosts[j].agreeCount = fresh.agreeCount;
                break;
              }
            }
          }
          const state: AgreeState = this.subAgreeState(fresh);
          state.isAgreed = fresh.isAgreed;
          state.count = fresh.agreeCount;
          state.toggled = false;
          hilog.info(FLOW_DOMAIN, FLOW_TAG,
            'source=sub-confirm-read pid=%{public}d agreed=%{public}s count=%{public}d',
            pid, String(FLOW_FLAG(fresh.isAgreed)), fresh.agreeCount);
          return;
        }
      }
      hilog.info(FLOW_DOMAIN, FLOW_TAG,
        'source=sub-confirm-skip(not-on-page) pid=%{public}d page=%{public}d', pid, page);
    } catch (err) {
      const e: Error = err as Error;
      hilog.warn(FLOW_DOMAIN, FLOW_TAG,
        'source=sub-confirm-exception pid=%{public}d reason=%{public}s', pid, e.message);
    }
  }

  /** 某层的 opAgree 是否仍在途（供界面按需显示"处理中"，读 `AgreeState.pending`） */
  isAgreePending(item: PostItem): boolean {
    return this.agreeState(item.pid).pending;
  }

  /** 收藏或取消收藏主帖。以服务端结果确认操作，失败时保留可重试状态。 */
  async toggleStore(context: common.UIAbilityContext): Promise<string> {
    if (!this.currentSession().hasBduss()) {
      return '需要登录后才能收藏';
    }
    if (this.tid <= 0) {
      return '帖子 id 无效';
    }
    if (this.storePending) {
      hilog.info(FLOW_DOMAIN, FLOW_TAG, 'source=storeBlocked(pending) tid=%{public}d', this.tid);
      return '上一次收藏还在处理中';
    }
    const main: PostItem | undefined = this.mainPost();
    const pid: number = main === undefined ? 0 : main.pid;
    if (pid <= 0) {
      return '主帖还没加载出来';
    }

    const target: boolean = !this.collected;
    const session: TiebaSession = this.currentSession();
    const owner: string = authSession.sessionKey();
    const tid: number = this.tid;
    const seq: number = this.requestSeq;
    const current: () => boolean = (): boolean => authSession.matchesSession(session, owner) &&
      this.tid === tid && seq === this.requestSeq;
    this.collected = target;
    this.storePending = true;
    hilog.info(FLOW_DOMAIN, FLOW_TAG,
      'source=storeToggled(optimistic) tid=%{public}d pid=%{public}d target=%{public}s',
      this.tid, pid, String(FLOW_FLAG(target)));
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!current()) { return '账号或帖子已变化，未继续收藏'; }
      const response: StoreOpResponse = target
        ? await this.api.addStoreThread(device, session, tid, pid)
        : await this.api.removeStoreThread(device, session, tid);
      if (!current()) { return '账号或帖子已变化，请重新读取收藏结果'; }
      if (!response.ok) {
        // 失败回滚：把显示值退回点击前
        if (current()) { this.collected = !target; }
        hilog.info(FLOW_DOMAIN, FLOW_TAG,
          'source=storeRollback tid=%{public}d reason=%{public}s',
          this.tid, response.describeFailure());
        return response.describeFailure();
      }
      hilog.info(FLOW_DOMAIN, FLOW_TAG,
        'source=storeAccepted tid=%{public}d target=%{public}s', this.tid, String(FLOW_FLAG(target)));
      return '';
    } catch (err) {
      const e: Error = err as Error;
      if (current()) { this.collected = !target; }
      hilog.info(FLOW_DOMAIN, FLOW_TAG,
        'source=storeRollback(exception) tid=%{public}d reason=%{public}s', this.tid, e.message);
      return `收藏失败：${e.message}`;
    } finally {
      this.storePending = false;
    }
  }

  /** 发送回复。成功后更新对应列表，失败保留输入；不把请求已发送视为回复已发布。 */
  async submitReply(context: common.UIAbilityContext, content: string,
    targetPid: number = 0, withTail?: boolean): Promise<string> {
    const text: string = content.trim();
    if (text.length === 0) {
      return '回复内容为空';
    }
    if (!this.currentSession().hasBduss()) {
      return '需要登录后才能回复';
    }
    if (this.replyPending) {
      hilog.info(FLOW_DOMAIN, FLOW_TAG, 'source=replyBlocked(pending) tid=%{public}d', this.tid);
      return '上一条回复还在发送中';
    }
    if (this.tid <= 0) {
      return '帖子 id 无效';
    }
    const fid: number = this.detail.forumId;
    const forumName: string = resolveForumName(this.detail.forumName, this.forumNameHint);
    if (fid <= 0 || forumName.length === 0) {
      return '帖子信息还没加载完';
    }

    const target: AddPostTarget | undefined = targetPid > 0
      ? ThreadDetailVM.buildReplyTarget(targetPid)
      : undefined;

    const session: TiebaSession = this.currentSession();
    const tid: number = this.tid;
    const account: string = `${authSession.snapshot.uid}:${authSession.snapshot.portrait}`;
    const current: () => boolean = (): boolean => this.tid === tid &&
      `${authSession.snapshot.uid}:${authSession.snapshot.portrait}` === account &&
      this.currentSession().bduss === session.bduss;
    this.replyPending = true;
    hilog.info(FLOW_DOMAIN, FLOW_TAG,
      'source=replySubmit tid=%{public}d fid=%{public}d targetPid=%{public}d len=%{public}d',
      this.tid, fid, targetPid, text.length);
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!current()) { return '账号或帖子已变化，请重新确认回复'; }
      const response: ReplyResponse = await this.api.replyToThread(
        device, session, tid, fid, forumName, text, target, withTail);
      if (!current()) { return '账号或帖子已变化，已发出的回复需在原账号确认'; }
      if (!response.ok) {
        hilog.info(FLOW_DOMAIN, FLOW_TAG, 'source=replyFailed tid=%{public}d reason=%{public}s',
          this.tid, response.describeFailure());
        return response.describeFailure();
      }
      this.lastReplyPid = response.result.pid;
      hilog.info(FLOW_DOMAIN, FLOW_TAG,
        'source=replyAccepted tid=%{public}d pid=%{public}d', this.tid, response.result.pid);
      // 刷一次首屏，让新回复由服务端数据出现（顺序由服务端排序决定，本地不插队）
      await this.refresh(context);
      if (!current()) { return '账号或帖子已变化，回复已受理，请在原账号查看'; }
      /*
       * 正序下新回复排在**最后一页**，刷首屏之后屏幕上并没有它 ——
       * 用户最容易把"发出去了但没看见"当成失败。所以这里把它找出来：
       * 切到倒序（服务端定义：倒序首屏就是最后一页），而不是自己去猜页码。
       * 只在正序时切：倒序如果还缺位说明另有原因，不该在这里折腾。
       */
      if (!this.containsPid(response.result.pid) && this.sortType === ReplySortType.ASC) {
        hilog.info(FLOW_DOMAIN, FLOW_TAG, 'source=replySortToDesc tid=%{public}d', this.tid);
        await this.switchReplySort(context, ReplySortType.DESC);
      }
      return '';
    } catch (err) {
      const e: Error = err as Error;
      hilog.info(FLOW_DOMAIN, FLOW_TAG, 'source=replyException tid=%{public}d reason=%{public}s',
        this.tid, e.message);
      return `回复失败：${e.message}`;
    } finally {
      this.replyPending = false;
    }
  }

  /** 当前列表里有没有这条 pid（pid ≤ 0 一律算没有，避免和占位 0 撞上） */
  containsPid(pid: number): boolean {
    if (pid <= 0) {
      return false;
    }
    return this.postByPid(pid) !== undefined;
  }

  /** 把"回复某楼层"包成 pb 请求需要的目标对象（空值一律不传，避免发出畸形的 post_id） */
  private static buildReplyTarget(pid: number): AddPostTarget {
    const target: AddPostTarget = new AddPostTarget();
    target.postId = String(pid);
    return target;
  }

  /** 按 pid 取当前模型里的楼层（找不到返回 undefined） */
  postByPid(pid: number): PostItem | undefined {
    for (let i = 0; i < this.posts.length; i++) {
      if (this.posts[i].pid === pid) {
        return this.posts[i];
      }
    }
    return undefined;
  }

  /** 重试某层楼中楼第一页。与 toggleSubPosts 分开，避免"重试"按钮把区域收起来 */
  async retrySubPosts(context: common.UIAbilityContext, pid: number,
    threadAuthorId: number): Promise<void> {
    const state: SubPostThreadState | undefined = this.findSubState(pid);
    if (state === undefined || state.loading || state.loadedOnce) {
      return;
    }
    state.expanded = true;
    state.errorText = '';
    this.touchSubStates();
    await this.loadSubPosts(context, pid, threadAuthorId, 1);
  }

  /** 加载更多楼中楼。失败时保留已加载内容，只在区域底部提示 */
  async loadMoreSubPosts(context: common.UIAbilityContext, pid: number,
    threadAuthorId: number): Promise<void> {
    const state: SubPostThreadState | undefined = this.findSubState(pid);
    if (state === undefined || state.loading || !state.hasMore || state.page.currentPage <= 0) {
      return;
    }
    await this.loadSubPosts(context, pid, threadAuthorId, state.page.currentPage + 1);
  }

  /** 拉某页楼中楼。page=1 替换，page>1 追加 */
  private async loadSubPosts(context: common.UIAbilityContext, pid: number,
    threadAuthorId: number, page: number): Promise<void> {
    const initial: SubPostThreadState | undefined = this.findSubState(pid);
    if (initial === undefined || initial.loading) {
      return;
    }
    const seq: number = this.requestSeq;
    const tid: number = this.tid;
    const session: TiebaSession = this.currentSession();
    const owner: string = authSession.sessionKey();
    const current: () => boolean = (): boolean => seq === this.requestSeq && tid === this.tid &&
      owner === authSession.sessionKey() && this.findSubState(pid) === initial;
    initial.loading = true;
    initial.errorText = '';
    this.touchSubStates();

    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!current()) { return; }
      const response: SubPostResponse = await this.api.fetchSubPosts(
        device, session, tid, pid, threadAuthorId, page, SUB_POST_PAGE_SIZE);
      if (!current()) { return; }
      const state: SubPostThreadState | undefined = this.findSubState(pid);
      if (state === undefined) {
        return;
      }
      if (!response.ok) {
        state.errorText = response.describeFailure();
        return;
      }

      if (response.data.currentPage !== page) { state.errorText = '返回页码不一致，请重试'; return; }
      if (page <= 1) {
        for (let i = 0; i < state.subPosts.length; i++) {
          this.subPostPages.delete(state.subPosts[i].pid);
          this.subPostParents.delete(state.subPosts[i].pid);
        }
        state.subPosts = response.data.subPosts;
      } else {
        // concat 产生新数组：即使以后把状态对象换成 @ObservedV2，也能保持同一套更新方式
        const seen: Set<number> = new Set<number>(state.subPosts.map((item: SubPostItem): number => item.pid));
        const added: SubPostItem[] = response.data.subPosts.filter((item: SubPostItem): boolean => {
          if (seen.has(item.pid)) { return false; } seen.add(item.pid); return true;
        });
        if (response.data.currentPage !== page || added.length === 0) {
          state.hasMore = false;
          state.errorText = response.data.hasMore ? '分页没有进展，请刷新后重试' : '';
          return;
        }
        state.subPosts = state.subPosts.concat(added);
      }
      for (let i = 0; i < response.data.subPosts.length; i++) {
        const sub: SubPostItem = response.data.subPosts[i];
        this.subPostPages.set(sub.pid, page);
        this.subPostParents.set(sub.pid, pid);
        const observed: AgreeState = this.subAgreeState(sub);
        if (!observed.pending && !observed.toggled) {
          observed.isAgreed = sub.isAgreed;
          observed.count = sub.agreeCount;
        }
      }
      state.page = response.data;
      state.hasMore = response.data.hasMore;
      state.loadedOnce = true;
    } catch (err) {
      const e: Error = err as Error;
      const state: SubPostThreadState | undefined = this.findSubState(pid);
      if (current() && state !== undefined) {
        state.errorText = `加载失败：${e.message}`;
      }
    } finally {
      const state: SubPostThreadState | undefined = this.findSubState(pid);
      if (current() && state !== undefined) {
        state.loading = false;
      }
      this.touchSubStates();
    }
  }

  /** 按 pid 查状态；没有返回 undefined */
  private findSubState(pid: number): SubPostThreadState | undefined {
    for (let i = 0; i < this.subStates.length; i++) {
      if (this.subStates[i].pid === pid) {
        return this.subStates[i];
      }
    }
    return undefined;
  }

  /** 让 @Trace 数组产生一次整体替换，通知 UI 重新读取状态 */
  private touchSubStates(): void {
    const next: SubPostThreadState[] = [];
    for (let i = 0; i < this.subStates.length; i++) {
      next.push(this.subStates[i]);
    }
    this.subStates = next;
  }

  /** 按当前楼层同步状态表：reset=true 时丢弃旧状态，否则保留已有状态并补充新楼层 */
  private syncSubStates(posts: PostItem[], reset: boolean): void {
    let existing: SubPostThreadState[] = [];
    if (!reset) {
      existing = this.subStates;
    }
    this.subStates = syncSubPostThreadStates(existing, posts);
  }
}
