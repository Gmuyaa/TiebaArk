

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ApiResult, ReplyResponse, StoreOpResponse, SubPostResponse,
  ThreadDetailResponse, TiebaApi
} from '../api/TiebaApi';
import {
  copyPostItem, PostItem, ReplySortType,
  resolveForumName, SubPostItem, SubPostPage, SubPostThreadState, ThreadDetail, ThreadReplyPermission,
  replyPermissionWriteValue, syncSubPostThreadStates
} from '../model/ThreadDetail';
import { MemePicItem } from '../model/MemeEmoji';
import { FloorDataSource } from '../model/FloorDataSource';
import { subReplyContent } from '../model/ReplyEditor';
import { EmojiPickerVM } from './EmojiPickerVM';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { AddPostTarget, AgreeObjType, TiebaDevice, TiebaSession } from '../net/TiebaParams';
import { authSession } from '../auth/AuthSession';
import { AgreeActionVM, AgreeState, AgreeTarget } from './AgreeActionVM';
import { noteContentDeleted } from './ContentDeletionRevision';

/** 只是请求意图：服务端会按自己的 page_size 返回。 */
const REQUEST_PAGE_SIZE: number = 10;
const SUB_POST_PAGE_SIZE: number = 30;
const SUB_POST_SLOW_MS: number = 1500;
const DEFAULT_FLOOR_PAGE_SIZE: number = 30;
const MAX_JUMP_SEARCH_STEPS: number = 16;

export enum FloorJumpStatus {
  FOUND = 0,
  NOT_FOUND = 1,
  FAILED = 2,
  BUSY = 3,
  CANCELLED = 4
}

export class FloorJumpResult {
  readonly status: FloorJumpStatus;
  /** 目标楼层在 visiblePosts 中的下标；仅 status === FOUND 时有效。 */
  readonly index: number;
  /** true 表示本次跳转替换了回复页，UI 需等列表同步后再滚。 */
  readonly loadedNewPage: boolean;
  readonly message: string;

  constructor(status: FloorJumpStatus, index: number = -1, loadedNewPage: boolean = false, message: string = '') {
    this.status = status;
    this.index = index;
    this.loadedNewPage = loadedNewPage;
    this.message = message;
  }
}

const FLOW_TAG: string = 'AgreeFlow';
const FLOW_DOMAIN: number = 0x0000;
const FLOW_FLAG: (v: boolean) => number = (v: boolean): number => v ? 1 : 0;

@ObservedV2
export class ThreadDetailVM {
  @Trace tid: number = 0;
  @Trace loading: boolean = false;
  @Trace isRefreshing: boolean = false;
  @Trace isLoadingMore: boolean = false;
  @Trace errorText: string = '';

  @Trace lastErrorCode: number = 0;
  @Trace loadedOnce: boolean = false;

  @Trace detail: ThreadDetail = new ThreadDetail();
/** 每次变更都整体替换。 */
  @Trace posts: PostItem[] = [];
  @Trace hasMore: boolean = false;
  /** 定位模式只展示主帖和目标回复；通过明确入口回到完整回复列表。 */
  @Trace focusedReplyPid: number = 0;
  /** 定位到楼中楼子回复时记录其 spid，页面据此自动展开所属父楼的楼中楼面板。 */
  @Trace focusedSubPostPid: number = 0;
/** 按 pid 区分；数组整体替换才触发 @Trace。 */
  @Trace subStates: SubPostThreadState[] = [];
  @Trace sortType: ReplySortType = ReplySortType.ASC;
  /**
   * 主帖收藏态。权威来源是详情响应的 `thread.is_stored`，每次 load/refresh 成功都重置；
   * 点击走“乐观翻转 → 写接口 → 失败回滚”（`toggleStore`）。放 VM 而不是 `ThreadDetail`
   * 字段：`ThreadDetail` 不是 `@ObservedV2`，就地改它的字段不会触发重绘。
   */
  @Trace collected: boolean = false;
  /**
   * 收藏写操作在途（addstore / rmstore）；在途期间禁止第二笔。
   */
  @Trace storePending: boolean = false;

  @Trace replyPending: boolean = false;
  @Trace deletePending: boolean = false;
  @Trace threadDeleted: boolean = false;
  @Trace replyPermission: ThreadReplyPermission = ThreadReplyPermission.UNKNOWN;
  @Trace replyPermissionPending: boolean = false;
  /**
   * 最近一次**发表成功**的楼层 pid（0 = 还没有），只用于发表成功后跳到该层；
   * 刷新是整页替换，页面无法自行反推位置，VM 直接递出 pid，找不到就留在原地不猜。
   */
  @Trace lastReplyPid: number = 0;
  /** 切换排序时只清空并刷新回复，主帖保持原对象不动。 */
  @Trace isSwitchingSort: boolean = false;
  @Trace isJumpingFloor: boolean = false;

  @Trace emojiPicker: EmojiPickerVM = new EmojiPickerVM();
  get memePics(): MemePicItem[] { return this.emojiPicker.memePics; }
  get memeStateText(): string { return this.emojiPicker.memeStateText; }
  memeDisplayUrl(item: MemePicItem): string { return this.emojiPicker.memeDisplayUrl(item); }
  memeTokenFor(url: string): string { return this.emojiPicker.memeTokenFor(url); }
  memeTokenTable(): Map<string, string> { return this.emojiPicker.memeTokenTable(); }
  memeUrlFor(token: string): string { return this.emojiPicker.memeUrlFor(token); }
  async retryMemePics(context: common.UIAbilityContext): Promise<void> { await this.emojiPicker.retryMemePics(context); }
  async loadMemePics(context: common.UIAbilityContext): Promise<void> { await this.emojiPicker.loadMemePics(context); }

  private api: TiebaApi = new TiebaApi();
  /**
   * 每次现取而不是构造时缓存：用户可能在本页停留期间登录/退出，缓存一份会把旧凭据一直带下去。
   */
  private currentSession(): TiebaSession {
    return authSession.session();
  }
  /** 已成功加载到第几页（服务端的楼层页页码） */
  private loadedPage: number = 0;
  /**
   * 渲染期热点：每个楼层项都要问一次“我是谁”和“我的楼中楼呢”，线性扫描的代价随已加载楼层数
   * 平方式增长。索引随数组整体替换一起重建。
   */
  private postIndex: Map<number, PostItem> = new Map<number, PostItem>();
  private subStateIndex: Map<number, SubPostThreadState> = new Map<number, SubPostThreadState>();
  /** 楼层 pid 对应的服务端页码；确认点赞时必须读回该页。 */
  private postPages: Map<number, number> = new Map<number, number>();
  /** 楼中楼 pid 所在页与所属楼层，供点赞后读回对应的 floor 页面。 */
  private subPostPages: Map<number, number> = new Map<number, number>();
  private subPostParents: Map<number, number> = new Map<number, number>();
  /** 正序第一页响应给出的服务端总页数，倒序首屏必须从最后一页开始。 */
  private knownTotalPage: number = 1;
  /** 当前排序模式下的服务端总页数（只看楼主与正序总页数不同）。 */
  private currentSortTotalPage: number = 1;
  /** 当前列表是否从首/末边界页连续加载；跳到中间页后置 false，防止拉到底误判前序页不存在。 */
  private loadedFromBoundary: boolean = false;
  private allPagesLoaded: boolean = false;
  /**
   * 每层楼的可观察点赞态。Map 本身不需要 @Trace：界面读的是 `AgreeState` 自己的 `@Trace`
   * 字段，只要对象引用稳定即可。因此这里只做 `set`，从不在同一 pid 上换新实例。
   */
  private agreeStates: Map<number, AgreeState> = new Map<number, AgreeState>();
  private agreeActions: AgreeActionVM = new AgreeActionVM();
  /** 每次“重来一次”（首次加载 / 刷新 / 切排序）+1；回来时对不上说明期间又发了请求，旧结果丢弃。 */
  private requestSeq: number = 0;
  private disposed: boolean = false;
  private deleteOperation: number = 0;
  private replyPermissionOperation: number = 0;
  /** 删除一级评论会让后续页前移，续页先补读当前末页以免跳过移入的评论。 */
  private rereadPageAfterDelete: number = 0;
  /** 最多一个待同步删除目标，直到所属页不再回显才解除；不保存内容、不落盘。 */
  private deletedPid: number = 0;
  private deletedParentPid: number = 0;
  private deletedPage: number = 1;
  private deletedSort: ReplySortType = ReplySortType.ASC;

  forumNameHint: string = '';

  /** 来源吧名兜底。空串等同没设；调用方必须“确实知道”，不许猜。 */
  setForumNameHint(name: string | undefined): void {
    this.forumNameHint = name === undefined ? '' : name.trim();
  }

  /**
   * 详情落地前的最后一道归一：把来源吧名补进空着的 `forumName`。兜底是页面语境，
   * 不进 `ThreadDetail.fromRaw`（那是“照响应建模型”的纯函数）。
   */
  private absorbDetail(source: ThreadDetail): ThreadDetail {
    source.forumName = resolveForumName(source.forumName, this.forumNameHint);
    source.posts = this.filterDeletedPosts(source.posts);
    return source;
  }

  private filterDeletedPosts(posts: PostItem[]): PostItem[] {
    return this.deletedPid > 0 && this.deletedParentPid === 0 ?
      posts.filter((post: PostItem): boolean => post.pid !== this.deletedPid) : posts;
  }

  private finishDeletionSync(): void {
    this.deletedPid = 0;
    this.deletedParentPid = 0;
    if (this.errorText.startsWith('评论已删除，')) { this.errorText = ''; }
  }

  /**
   * 服务端是否接受了这次请求的页码。`/c/f/pb/floor` 每页固定 30 条且忽略 `rn`；`pn` 超过末页
   * 不报错，而是把 `current_page` 夹到 `total_page` 并返回空列表——夹页算“已经到底”，不算错页。
   */
  private subPageAccepted(currentPage: number, totalPage: number, requested: number): boolean {
    return currentPage === requested || (totalPage > 0 && totalPage < requested && currentPage === totalPage);
  }

  private updateDeletedTotalPage(totalPage: number): void {
    if (totalPage <= 0) { return; }
    this.knownTotalPage = totalPage;
    if (this.rereadPageAfterDelete > totalPage) { this.rereadPageAfterDelete = totalPage; }
  }

  /** 加载第一页（重复调用重置到第一页）；失败写入 errorText 供界面展示，不抛异常。 */
  async load(context: common.UIAbilityContext, tid: number, targetPid: number = 0,
    targetIsSubPost: boolean = false): Promise<void> {
    /*
     * 已 dispose 的实例不得复用：页面销毁时调 dispose()，重进帖子是新的页面实例 + 新 VM。
     * 不能把 disposed 复位成 false——迟到的 load 会复活已销毁的 VM 并继续写 @Trace 状态。
     */
    if (this.disposed || this.deletePending) { return; }
    if (tid <= 0) {
      this.errorText = '帖子 id 无效';
      return;
    }
    const sameThread: boolean = this.tid === tid;
    if (!sameThread) {
      this.deletedPid = 0;
      this.deletedParentPid = 0;
      this.replyPermission = ThreadReplyPermission.UNKNOWN;
    }
    /*
     * load 是整页重置，必须同时清掉上一轮翻页的在途标记：本方法推进 requestSeq 后，在途
     * loadMore 的 finally 不再复位 isLoadingMore，而 refresh/loadMore/switchReplySort 的入口
     * 守卫都含该标记，漏清会让三处入口永久被挡。
     */
    this.isLoadingMore = false;
    this.isJumpingFloor = false;
    this.threadDeleted = false;
    this.rereadPageAfterDelete = 0;
    this.tid = tid;
    this.loading = true;
    this.errorText = '';
    this.lastErrorCode = 0;
    this.focusedReplyPid = 0;
    this.focusedSubPostPid = 0;
    this.sortType = ReplySortType.ASC;
    this.requestSeq++;
    const seq: number = this.requestSeq;

    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      const session: TiebaSession = this.currentSession();
      if (sameThread && this.deletedPid > 0) {
        await this.confirmPendingDeletion(device, session, (): boolean => seq === this.requestSeq);
      }
      let targetPage: number = 0;
      let locatedSubPage: SubPostPage | undefined = undefined;
      let locatedSubPid: number = 0;
      let response: ThreadDetailResponse;
      if (targetPid > 0) {
        let effectivePid: number = targetPid;
        let fetchedTarget: ThreadDetailResponse | undefined = undefined;
        if (targetIsSubPost) {
          const subRes: SubPostResponse = await this.api.fetchSubPostsBySpid(
            device, session, tid, targetPid, 0, SUB_POST_PAGE_SIZE);
          if (seq !== this.requestSeq) { return; }
          if (subRes.ok && subRes.data.parentPid > 0 &&
            subRes.data.subPosts.some((sub: SubPostItem): boolean => sub.pid === targetPid)) {
            effectivePid = subRes.data.parentPid;
            locatedSubPage = subRes.data;
            locatedSubPid = targetPid;
            fetchedTarget = await this.api.fetchThreadDetail(
              device, session, tid, 1, REQUEST_PAGE_SIZE, this.sortType, effectivePid);
          } else {
            effectivePid = 0;
          }
        } else {
          fetchedTarget = await this.api.fetchThreadDetail(
            device, session, tid, 1, REQUEST_PAGE_SIZE, this.sortType, targetPid);
          if (seq !== this.requestSeq) { return; }
          const directFound: boolean = fetchedTarget.ok &&
            fetchedTarget.data.posts.some((post: PostItem): boolean => post.pid === targetPid);
          if (!directFound) {
            // 未显式标记楼中楼时兜底按 spid 反查父楼层，避免漏标或旧入口无法定位。
            const subRes: SubPostResponse = await this.api.fetchSubPostsBySpid(
              device, session, tid, targetPid, 0, SUB_POST_PAGE_SIZE);
            if (seq !== this.requestSeq) { return; }
            if (subRes.ok && subRes.data.parentPid > 0 &&
              subRes.data.subPosts.some((sub: SubPostItem): boolean => sub.pid === targetPid)) {
              effectivePid = subRes.data.parentPid;
              locatedSubPage = subRes.data;
              locatedSubPid = targetPid;
              fetchedTarget = await this.api.fetchThreadDetail(
                device, session, tid, 1, REQUEST_PAGE_SIZE, this.sortType, effectivePid);
            }
          }
        }
        if (seq !== this.requestSeq) { return; }
        const targetPosts: PostItem[] = fetchedTarget !== undefined ? fetchedTarget.data.posts : [];
        const found: boolean = effectivePid > 0 && fetchedTarget !== undefined && fetchedTarget.ok &&
          targetPosts.some((post: PostItem): boolean => post.pid === effectivePid);
        const original: ThreadDetailResponse = await this.api.fetchThreadDetail(
          device, session, tid, 1, REQUEST_PAGE_SIZE, this.sortType);
        if (seq !== this.requestSeq) {
          return;
        }
        if (found && original.ok) {
          const main: PostItem | undefined = ThreadDetail.locateMainPost(original.data);
          if (main !== undefined) {
            original.data.posts = [main].concat(targetPosts.filter((post: PostItem): boolean => post.pid !== main.pid));
            this.focusedReplyPid = effectivePid;
            this.focusedSubPostPid = locatedSubPid;
            targetPage = fetchedTarget!.data.page.currentPage;
          } else {
            original.failLocal('暂时无法读取原帖内容，请稍后重试');
          }
        }
        // 未命中、已删除或暂不可见时，保留原帖阅读入口，不伪造目标楼层。
        response = original;
      } else {
        response = await this.api.fetchThreadDetail(
          device, session, tid, 1, REQUEST_PAGE_SIZE, this.sortType, 0);
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
        this.setSubStates([]);
        this.visiblePosts = [];
        this.postIndex = new Map<number, PostItem>();
        this.loadedPage = 0;
        hilog.warn(FLOW_DOMAIN, FLOW_TAG, 'source=reload-failed reason=%{public}s', this.errorText);
        return;
      }

      // 整体替换触发 @Trace（兜底吧名在这一步合并进去）
      this.detail = this.absorbDetail(response.data);
      // 收藏态跟详情一起从服务端重置（本地乐观值随权威值落地）
      this.collected = response.data.isStored;
      this.replyPermission = response.data.replyPermission;
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
      this.currentSortTotalPage = this.knownTotalPage;
      this.loadedFromBoundary = this.focusedReplyPid === 0;
      this.allPagesLoaded = this.loadedFromBoundary && !this.hasMore;
      this.loadedOnce = true;
      this.syncVisiblePosts();
      this.rebuildAgreeStates('reload');
      this.syncSubStates(this.posts, true);
      if (locatedSubPage !== undefined && this.focusedReplyPid > 0 && this.focusedSubPostPid > 0) {
        this.applyLocatedSubPage(this.focusedReplyPid, locatedSubPage);
      }
      this.agreeFlowSnapshot('load-done');
    } catch (err) {
      const e: Error = err as Error;
      this.errorText = `加载失败：${e.message}`;
    } finally {
      this.loading = false;
    }
  }

  /**
   * 刷新第一页：保留当前 tid 与排序；非正序模式保留主帖对象，只替换回复并重置分页与楼中楼状态。
   */
  async refresh(context: common.UIAbilityContext): Promise<void> {
    if (this.disposed || this.deletePending || this.threadDeleted || this.tid <= 0 || this.loading || this.isRefreshing || this.isLoadingMore ||
      this.isSwitchingSort || this.isJumpingFloor) {
      return;
    }
    if (this.focusedReplyPid > 0) {
      await this.load(context, this.tid);
      return;
    }
    this.isRefreshing = true;
    this.rereadPageAfterDelete = 0;
    this.errorText = '';
    this.requestSeq++;
    const seq: number = this.requestSeq;

    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (this.deletedPid > 0) {
        await this.confirmPendingDeletion(device, this.currentSession(), (): boolean => seq === this.requestSeq);
      }
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
      if (this.sortType === ReplySortType.ASC || response.data.replyPermission !== ThreadReplyPermission.UNKNOWN) {
        this.replyPermission = response.data.replyPermission;
      }
      this.loadedFromBoundary = true;
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
   * 加载下一页并追加。滚动到底会连续触发，必须挡住重复请求。翻页依据是**页码**而不是已加载
   * 条数：服务端会跳号，用条数推算页码迟早对不上。
   */
  async loadMore(context: common.UIAbilityContext): Promise<void> {
    if (this.disposed || this.deletePending || this.threadDeleted || this.loading || this.isRefreshing || this.isLoadingMore || this.isSwitchingSort ||
      this.isJumpingFloor || !this.hasMore || this.loadedPage <= 0) {
      return;
    }
    this.isLoadingMore = true;
    this.errorText = '';
    const seq: number = this.requestSeq;
    // 发出请求时的排序；回来时若已被切走，这一页属于旧排序，不能接上去
    const requestSort: ReplySortType = this.sortType;

    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (seq !== this.requestSeq || this.disposed || this.threadDeleted) { return; }
      const nextPage: number = this.rereadPageAfterDelete > 0 ? this.rereadPageAfterDelete :
        (this.sortType === ReplySortType.DESC ? this.loadedPage - 1 : this.loadedPage + 1);
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
      const pageBefore: number = this.loadedPage;
      const countBefore: number = this.posts.length;
      this.posts = this.mergePostsByPid(this.posts, this.filterDeletedPosts(response.data.posts));
      this.rereadPageAfterDelete = 0;
      this.rememberPostPages(response.data.posts, response.data.page.currentPage, false);
      this.updatePaging(response.data.page.currentPage, response.data.page.totalPage,
        response.data.page.hasMore);
      /*
       * 页码没推进也没有新楼层：再触底只会把同一页再要一遍（服务端 has_more 偶尔不实时）。
       * 停在原地并明说，别让“触底→加载→触底”原地打转。
       */
      if (this.hasMore && this.posts.length === countBefore && this.loadedPage === pageBefore) {
        this.hasMore = false;
        this.errorText = '这一页没有新楼层，下拉刷新可重新对齐分页';
      }
      /*
       * 尾部追加走增量通知：已有项保持原位、滚动位置不动。楼中楼预览不在这里预取——没有内联
       * 预览的层被二次请求撑高正是“顶走内容”的来源；用户点开弹层时再拉完整页。
       */
      this.syncSubStates(this.posts, false);
      this.syncVisiblePosts(countBefore - 1);
    } catch (err) {
      const e: Error = err as Error;
      if (seq === this.requestSeq) { this.errorText = `加载失败：${e.message}`; }
    } finally {
      if (seq === this.requestSeq) { this.isLoadingMore = false; }
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
  /**
   * 主帖之外的楼层，专给回复列表的 `Repeat`。单独持有是刻意的：在 build 里
   * `visiblePosts.slice(1)` 会让入参每帧都是新数组，追加一页就像“整个列表换了一遍”。
   */
  @Trace visibleReplies: PostItem[] = [];
  /**
   * 楼层列表的增量数据源（`LazyForEach` 用）。追加时只通知“末尾多了 N 项”，已有项不重建；
   * 整体替换数组会让 List 重算所有子项高度，滚动位置跟着跳。
   */
  readonly floors: FloorDataSource = new FloorDataSource();

  /**
   * 同步界面用的楼层列表。`appendFrom >= 0` 表示尾部追加：只把新楼层推给数据源；
   * 否则整表 reload（首屏、刷新、换排序、定位回复）。
   */
  private syncVisiblePosts(appendFrom: number = -1): void {
    // 列表项逐个按 pid 回查，索引跟这次整体替换一起重建
    const index: Map<number, PostItem> = new Map<number, PostItem>();
    for (let i = 0; i < this.posts.length; i++) {
      index.set(this.posts[i].pid, this.posts[i]);
    }
    this.postIndex = index;
    this.visiblePosts = this.posts;
    this.visibleReplies = this.posts.length > 1 ? this.posts.slice(1) : [];
    if (appendFrom >= 0 && appendFrom <= this.visibleReplies.length) {
      this.floors.append(this.visibleReplies.slice(appendFrom));
    } else {
      this.floors.reset(this.visibleReplies);
    }
  }

  /**
   * 切换回复排序。服务端真实能力：r=0 正序、r=1 倒序、r=2 热门、lz=1 楼主。
   * 倒序从最后一页开始逐页递减，不对当前已加载页做 reverse。
   */
  async switchReplySort(context: common.UIAbilityContext, newType: ReplySortType): Promise<void> {
    if (this.disposed || this.deletePending || this.threadDeleted || newType === this.sortType || this.tid <= 0 || this.loading || this.isRefreshing ||
      this.isLoadingMore || this.isSwitchingSort || this.isJumpingFloor || this.posts.length === 0) {
      return;
    }

    const previousType: ReplySortType = this.sortType;
    const previousPosts: PostItem[] = this.posts;
    const previousSubStates: SubPostThreadState[] = this.subStates;
    const previousPage: number = this.loadedPage;
    const previousHasMore: boolean = this.hasMore;
    this.sortType = newType;
    this.rereadPageAfterDelete = 0;
    this.isSwitchingSort = true;
    this.errorText = '';
    this.requestSeq++;
    const seq: number = this.requestSeq;
    // 保留同一个主帖对象，只清空回复。
    this.posts = [previousPosts[0]];
    this.syncVisiblePosts();
    this.rebuildAgreeStates('switchSort');
    this.setSubStates([]);

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
        this.syncVisiblePosts();
        this.loadedPage = previousPage;
        this.hasMore = previousHasMore;
        this.setSubStates(previousSubStates);
        return;
      }

      this.replaceRepliesKeepingMain(response.data.posts);
      this.focusedReplyPid = 0;
      this.focusedSubPostPid = 0;
      this.rememberPostPages(response.data.posts, response.data.page.currentPage, true);
      this.loadedFromBoundary = true;
      this.updatePaging(response.data.page.currentPage, response.data.page.totalPage,
        response.data.page.hasMore);
      this.syncVisiblePosts();
      this.syncSubStates(this.posts, true);
    } catch (err) {
      const e: Error = err as Error;
      this.errorText = `切换失败：${e.message}`;
      this.sortType = previousType;
      this.posts = previousPosts;
      this.syncVisiblePosts();
      this.loadedPage = previousPage;
      this.hasMore = previousHasMore;
      this.setSubStates(previousSubStates);
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
    incoming = this.filterDeletedPosts(incoming);
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
    if (totalPage > 0) {
      this.currentSortTotalPage = totalPage;
      if (this.sortType === ReplySortType.ASC || this.sortType === ReplySortType.DESC) {
        this.knownTotalPage = totalPage;
      }
    }
    this.hasMore = this.sortType === ReplySortType.DESC ? currentPage > 1 : serverHasMore;
    this.allPagesLoaded = this.loadedFromBoundary && !this.hasMore;
  }

  cancelJumpToFloor(): void {
    if (!this.isJumpingFloor) { return; }
    this.requestSeq++;
    this.isJumpingFloor = false;
  }

  /**
   * 跳转到指定楼层号：先查已加载列表，未命中时在当前排序分页内做估算 + 二分查页。
   * 仅命中时替换回复列表，未找到或请求失败不改动现有阅读状态。
   */
  async jumpToFloor(context: common.UIAbilityContext, targetFloor: number): Promise<FloorJumpResult> {
    if (this.disposed || this.threadDeleted || this.tid <= 0 || this.posts.length === 0) {
      return new FloorJumpResult(FloorJumpStatus.CANCELLED);
    }
    if (!Number.isSafeInteger(targetFloor) || targetFloor < 1) {
      return new FloorJumpResult(FloorJumpStatus.NOT_FOUND, -1, false, '请输入有效的楼层号');
    }
    if (this.loading || this.isRefreshing || this.isLoadingMore || this.isSwitchingSort ||
      this.deletePending || this.isJumpingFloor) {
      return new FloorJumpResult(FloorJumpStatus.BUSY, -1, false, '内容正在更新，请稍后再试');
    }

    const localIndex: number = this.findVisibleFloorIndex(targetFloor);
    if (localIndex >= 0) {
      return new FloorJumpResult(FloorJumpStatus.FOUND, localIndex, false);
    }

    const expectedSort: ReplySortType = this.sortType;
    const requestSort: ReplySortType = expectedSort === ReplySortType.HOT ? ReplySortType.ASC : expectedSort;
    if (this.allPagesLoaded && this.focusedReplyPid === 0) {
      const highestLoaded: number = this.maxFloorInPosts(this.visiblePosts, 0, true);
      return new FloorJumpResult(FloorJumpStatus.NOT_FOUND, -1, false,
        this.describeMissingFloor(targetFloor, highestLoaded, requestSort));
    }

    this.isJumpingFloor = true;
    const seq: number = ++this.requestSeq;
    const mainPid: number = this.posts[0].pid;

    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (this.disposed || this.threadDeleted || seq !== this.requestSeq || expectedSort !== this.sortType) {
        return new FloorJumpResult(FloorJumpStatus.CANCELLED);
      }

      let lo: number = 1;
      let hi: number = Math.max(1, this.currentSortTotalPage);
      let highestKnownFloor: number = 0;
      const visited: Set<number> = new Set<number>();
      let steps: number = 0;

      while (lo <= hi && steps < MAX_JUMP_SEARCH_STEPS) {
        let probePage: number;
        if (steps === 0 && requestSort !== ReplySortType.ONLY_AUTHOR) {
          const estPageSize: number = this.detail.page.pageSize > 0 ? this.detail.page.pageSize : DEFAULT_FLOOR_PAGE_SIZE;
          probePage = Math.min(hi, Math.max(lo, Math.ceil(targetFloor / estPageSize)));
        } else {
          probePage = Math.floor((lo + hi) / 2);
        }
        if (visited.has(probePage)) {
          probePage = Math.floor((lo + hi) / 2);
          if (visited.has(probePage)) { break; }
        }
        visited.add(probePage);
        steps++;

        const response: ThreadDetailResponse = await this.api.fetchThreadDetail(
          device, this.currentSession(), this.tid, probePage, REQUEST_PAGE_SIZE, requestSort);
        if (this.disposed || this.threadDeleted || seq !== this.requestSeq || expectedSort !== this.sortType) {
          return new FloorJumpResult(FloorJumpStatus.CANCELLED);
        }
        if (!response.ok) {
          return new FloorJumpResult(FloorJumpStatus.FAILED, -1, false, response.describeFailure());
        }

        const pagePosts: PostItem[] = this.filterDeletedPosts(response.data.posts);
        const serverPage: number = response.data.page.currentPage > 0 ? response.data.page.currentPage : probePage;
        const serverTotalPage: number = response.data.page.totalPage > 0 ? response.data.page.totalPage : hi;
        if (steps === 1 && serverTotalPage > hi) {
          hi = serverTotalPage;
        } else if (serverTotalPage > 0 && serverTotalPage < hi) {
          hi = serverTotalPage;
        }
        visited.add(serverPage);

        const hitInPage: boolean = pagePosts.some((post: PostItem): boolean => post.floor === targetFloor);
        if (hitInPage) {
          this.replaceRepliesKeepingMain(response.data.posts);
          this.focusedReplyPid = 0;
          this.focusedSubPostPid = 0;
          this.rereadPageAfterDelete = 0;
          if (this.posts.length > 0) {
            this.rememberPostPages([this.posts[0]], 1, true);
            this.rememberPostPages(this.posts.slice(1), serverPage, false);
          } else {
            this.rememberPostPages(response.data.posts, serverPage, true);
          }
          this.loadedFromBoundary = requestSort === ReplySortType.DESC
            ? serverPage >= serverTotalPage : serverPage <= 1;
          this.updatePaging(serverPage, serverTotalPage, response.data.page.hasMore);
          this.syncVisiblePosts();
          this.rebuildAgreeStates('jumpToFloor');
          this.syncSubStates(this.posts, true);
          const targetIndex: number = this.findVisibleFloorIndex(targetFloor);
          if (targetIndex >= 0) {
            return new FloorJumpResult(FloorJumpStatus.FOUND, targetIndex, true);
          }
          return new FloorJumpResult(FloorJumpStatus.NOT_FOUND, -1, false,
            this.describeMissingFloor(targetFloor, highestKnownFloor, requestSort));
        }

        // 服务端请求超界时会把 currentPage 夹回末页；记录其最高楼层并收缩上界。
        let minFloor: number = 0;
        let maxFloor: number = 0;
        for (let i = 0; i < pagePosts.length; i++) {
          const post: PostItem = pagePosts[i];
          if (post.floor <= 0) { continue; }
          if (serverPage > 1 && (post.floor === 1 || (mainPid > 0 && post.pid === mainPid))) {
            continue;
          }
          if (minFloor === 0 || post.floor < minFloor) { minFloor = post.floor; }
          if (post.floor > maxFloor) { maxFloor = post.floor; }
        }
        if (serverPage >= serverTotalPage && maxFloor > highestKnownFloor) {
          highestKnownFloor = maxFloor;
        }
        if (minFloor === 0) {
          hi = Math.min(hi, serverPage - 1);
          continue;
        }
        if (minFloor <= targetFloor && targetFloor <= maxFloor) {
          // 目标楼层落在本页区间内但页内不存在，说明已被删除或非当前筛选可见。
          break;
        }
        if (targetFloor < minFloor) {
          hi = Math.min(hi, serverPage - 1);
        } else {
          if (serverPage < probePage) {
            // 已被服务端夹到末页仍小于目标楼层，无需继续向右找。
            break;
          }
          lo = Math.max(lo, serverPage + 1);
        }
      }

      return new FloorJumpResult(FloorJumpStatus.NOT_FOUND, -1, false,
        this.describeMissingFloor(targetFloor, highestKnownFloor, requestSort));
    } catch (err) {
      if (this.disposed || seq !== this.requestSeq) {
        return new FloorJumpResult(FloorJumpStatus.CANCELLED);
      }
      const e: Error = err as Error;
      return new FloorJumpResult(FloorJumpStatus.FAILED, -1, false, `跳转失败：${e.message}`);
    } finally {
      if (seq === this.requestSeq) {
        this.isJumpingFloor = false;
      }
    }
  }

  private findVisibleFloorIndex(floor: number): number {
    for (let i = 0; i < this.visiblePosts.length; i++) {
      if (this.visiblePosts[i].floor === floor) { return i; }
    }
    return -1;
  }

  private maxFloorInPosts(posts: PostItem[], mainPid: number, includeMain: boolean): number {
    let maxFloor: number = 0;
    for (let i = 0; i < posts.length; i++) {
      const post: PostItem = posts[i];
      if (!includeMain && mainPid > 0 && post.pid === mainPid) { continue; }
      if (post.floor > maxFloor) { maxFloor = post.floor; }
    }
    return maxFloor;
  }

  private describeMissingFloor(targetFloor: number, highestFloor: number, sort: ReplySortType): string {
    if (sort === ReplySortType.ONLY_AUTHOR) {
      return `只看楼主模式下未找到第 ${targetFloor} 楼`;
    }
    if (highestFloor > 0 && targetFloor > highestFloor) {
      return `第 ${targetFloor} 楼不存在（当前最高 ${highestFloor} 楼）`;
    }
    return `第 ${targetFloor} 楼不存在或已被删除`;
  }

  /** 读取某楼状态。状态尚未建立时返回临时空状态，保证渲染层不必先判空 */
  subState(pid: number): SubPostThreadState {
    // 订阅由 `SubPostThreadState` 自身的 @Trace 字段承担：这里读的是 Map 索引，
    // 但返回的实例可观察，字段一变只有读过该字段的那个楼层会重画。
    const found: SubPostThreadState | undefined = this.findSubState(pid);
    if (found !== undefined) {
      return found;
    }
    const fallback: SubPostThreadState = new SubPostThreadState();
    fallback.pid = pid;
    return fallback;
  }

  /**
   * 展开/收起某层楼中楼。首次展开自动加载第一页；首次加载失败后再次点击是收起而不是重试，
   * 重试由 retrySubPosts 负责，避免“重试”按钮把区域收起来。
   */
  async toggleSubPosts(context: common.UIAbilityContext, pid: number,
    threadAuthorId: number): Promise<void> {
    if (this.disposed || this.deletePending || this.threadDeleted) { return; }
    let state: SubPostThreadState | undefined = this.findSubState(pid);
    if (state === undefined) {
      state = new SubPostThreadState();
      state.pid = pid;
      this.setSubStates(this.subStates.concat([state]));
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
   * 用户主动打开某层楼中楼详情：还没有完整第 1 页就补拉一次（不改 expanded，弹层不是就地展开）。
   * **带内联预览的层也要补**：预览只有几条、`page` 还是默认值，不补这页，后面的“加载更多”
   * 会按 currentPage+1 直接跳到第 2 页。
   */
  async ensureSubPostPage(context: common.UIAbilityContext, pid: number,
    threadAuthorId: number): Promise<void> {
    if (this.disposed || this.deletePending || this.threadDeleted) { return; }
    const state: SubPostThreadState | undefined = this.findSubState(pid);
    if (state === undefined || state.loading || state.loadedOnce) {
      return;
    }
    await this.loadSubPosts(context, pid, threadAuthorId, 1);
  }

  /**
   * 取某层的可观察点赞态，**引用稳定**：同一 pid 永远返回同一实例。这是给 UI 读的唯一入口，
   * 界面不再从 `PostItem` 派生点赞显示值（`ForEach` 复用下不会更新，见 `AgreeState`）。
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
     * AgreeFlow 追踪：惰性建项会静默造出 isAgreed=false 的默认态——若主帖 pid 不在
     * agreeStates（例如重建时主帖不在 posts 里），界面就显示为未点赞。
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
   * 用服务端数据重建全部可观察态（首次加载 / 刷新 / 切排序后调用）。这里**换新实例**是有意的：
   * 整批数据都换了，旧引用不该再被复用。`source` 仅用于 AgreeFlow 追踪。
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

  /** AgreeFlow 追踪：输出 C 层（UI/VM）四项读数；与界面读同一入口（含惰性建项的副作用）。 */
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

  /** 界面显示的点赞态，读 `AgreeState`（可观察），不从 `PostItem` 派生。 */
  isLiked(item: PostItem): boolean {
    return this.agreeState(item.pid).liked();
  }

  /** 界面显示的点赞数，读 `AgreeState`。 */
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
     * 改的若是主帖，必须同时同步 `detail`：底栏读 `detail.agreeCount` / `detail.isAgreed`，
     * 楼层列表读 `posts`，只改一边会让底栏与楼内显示分叉。按 pid 与 `mainPostId` 比对，
     * 不用数组位置。
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
   * 当前主帖（首楼）。定位规则见 `ThreadDetail.locateMainPost`：先按 `mainPostId`，缺失时才退到
   * `floor === 1`，**绝不用数组位置**；定位不到返回 undefined，调用方据此不提供该操作。
   * 有 `mainPostId` 时直接查索引：本方法在渲染期每层调一次，线性扫描会变成平方级开销。
   */
  mainPost(): PostItem | undefined {
    if (this.detail.mainPostId > 0) {
      // 索引里没有 = 本页确实没有主帖（如倒序翻到中间页），按规则不猜
      return this.postIndex.get(this.detail.mainPostId);
    }
    return ThreadDetail.locateMainPost(this.detail);
  }

  /** 菜单确认绑定账号、帖子和读取批次，旧确认框不能操作刷新后的内容。 */
  deletionOwner(): string {
    return this.disposed || !authSession.isLoggedIn() ? '' :
      `${authSession.sessionKey()}:${this.tid}:${this.requestSeq}`;
  }

  private ownsContent(uid: number): boolean {
    return !this.disposed && !this.threadDeleted && authSession.isLoggedIn() &&
      Number.isSafeInteger(uid) && uid > 0 && Number.isSafeInteger(authSession.snapshot.uid) &&
      uid === authSession.snapshot.uid;
  }

  canDeleteThread(): boolean {
    const main: PostItem | undefined = this.mainPost();
    return this.ownsContent(this.detail.author.id) && Number.isSafeInteger(this.tid) && this.tid > 0 &&
      main !== undefined && main.pid > 0 && this.postIndex.get(main.pid) !== undefined;
  }

  canManageReplyPermission(): boolean {
    return this.ownsContent(this.detail.author.id) && Number.isSafeInteger(this.tid) && this.tid > 0 &&
      this.posts.length > 0;
  }

  async setReplyPermission(context: common.UIAbilityContext, target: ThreadReplyPermission,
    confirmedOwner: string): Promise<string> {
    if (this.replyPermissionPending) { return '评论权限设置中，请稍候'; }
    if (this.deletePending || this.threadDeleted) { return '帖子状态正在变更，请稍后再试'; }
    if (confirmedOwner.length === 0 || confirmedOwner !== this.deletionOwner()) {
      return '账号或页面已变化，请重新打开评论权限';
    }
    if (!this.canManageReplyPermission()) { return '只能修改本人帖子的评论权限'; }
    if (replyPermissionWriteValue(target) <= 0) { return '评论权限选项无效'; }
    if (this.replyPermission === target) { return ''; }
    const previous: ThreadReplyPermission = this.replyPermission;
    const tid: number = this.tid;
    const owner: string = authSession.sessionKey();
    const session: TiebaSession = this.currentSession();
    const seq: number = this.requestSeq;
    const operation: number = ++this.replyPermissionOperation;
    const current: () => boolean = (): boolean => !this.disposed && !this.threadDeleted && this.tid === tid &&
      this.requestSeq === seq && authSession.matchesSession(session, owner);
    this.replyPermissionPending = true;
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!current() || !this.canManageReplyPermission()) { return '账号或页面已变化，未修改评论权限'; }
      if (this.currentSession().tbs.length === 0) {
        await authSession.refreshTbs(context).catch((): void => {});
        if (!current()) { return '账号或页面已变化，未修改评论权限'; }
      }
      const writeSession: TiebaSession = this.currentSession();
      const result: ApiResult = await this.api.setMyThreadReplyPermission(device, writeSession, tid, target);
      if (!current()) { return '账号或页面已变化，请刷新核对评论权限'; }
      if (!result.ok) { return result.describeFailure(); }
      this.replyPermission = target;
      this.detail.replyPermission = target;
      if (operation === this.replyPermissionOperation) { this.replyPermissionPending = false; }
      // 切换进出「仅自己，同时隐藏已有评论」会隐藏或恢复他人评论，须重拉列表同步（官方 PbFragment.N6）。
      if (previous === ThreadReplyPermission.SELF_ONLY || target === ThreadReplyPermission.SELF_ONLY) {
        await this.refresh(context);
      }
      return '';
    } catch (_) {
      return '评论权限设置结果未确认，请刷新核对';
    } finally {
      if (operation === this.replyPermissionOperation) { this.replyPermissionPending = false; }
    }
  }

  canDeletePost(item: PostItem): boolean {
    const main: PostItem | undefined = this.mainPost();
    return this.ownsContent(item.author.id) && Number.isSafeInteger(item.pid) && item.pid > 0 &&
      item.floor !== 1 && item.pid !== this.detail.mainPostId && item.pid !== main?.pid &&
      // 按 pid 查索引：这条必须仍在当前列表里（对象身份在副本楼层上不成立）
      this.postIndex.get(item.pid) !== undefined;
  }

  canDeleteSubPost(parentPid: number, item: SubPostItem): boolean {
    const state: SubPostThreadState | undefined = this.findSubState(parentPid);
    return this.ownsContent(item.author.id) && Number.isSafeInteger(item.pid) && item.pid > 0 &&
      Number.isSafeInteger(parentPid) && parentPid > 0 && this.containsPid(parentPid) &&
      state !== undefined && state.subPosts.some((sub: SubPostItem): boolean => sub.pid === item.pid);
  }

  async deleteThread(context: common.UIAbilityContext, confirmedOwner: string): Promise<string> {
    return this.deleteContent(context, confirmedOwner);
  }

  async deletePost(context: common.UIAbilityContext, item: PostItem, confirmedOwner: string): Promise<string> {
    return this.deleteContent(context, confirmedOwner, item);
  }

  async deleteSubPost(context: common.UIAbilityContext, parentPid: number, item: SubPostItem,
    confirmedOwner: string): Promise<string> {
    return this.deleteContent(context, confirmedOwner, undefined, parentPid, item);
  }

  /** 只有严格成功回执才移除内容；网络失败或含糊响应绝不作本地成功。 */
  private async deleteContent(context: common.UIAbilityContext, confirmedOwner: string,
    post?: PostItem, parentPid: number = 0, sub?: SubPostItem): Promise<string> {
    if (this.deletePending) { return '删除处理中，请稍候'; }
    if (confirmedOwner.length === 0 || confirmedOwner !== this.deletionOwner()) {
      return '账号或页面已变化，请重新确认删除';
    }
    if (this.loading || this.isRefreshing || this.isSwitchingSort || this.isJumpingFloor || this.replyPending) {
      return '内容正在更新，请稍后再删除';
    }
    const validTarget: () => boolean = (): boolean => sub !== undefined ? this.canDeleteSubPost(parentPid, sub) :
      (post !== undefined ? this.canDeletePost(post) : this.canDeleteThread());
    if (!validTarget()) { return '只能删除本人当前可见的内容，请刷新后重试'; }
    if (this.deletedPid > 0) { return '上一条删除仍待服务端同步，请下拉刷新核对后再删除'; }
    const fid: number = this.detail.forumId;
    if (!Number.isSafeInteger(fid) || fid <= 0) { return '帖子信息还没加载完'; }
    const tid: number = this.tid;
    const deletedPage: number = sub !== undefined ? (this.subPostPages.get(sub.pid) ?? 1) :
      (post !== undefined ? (this.postPages.get(post.pid) ?? this.loadedPage) : 1);
    const deletedSort: ReplySortType = this.sortType;
    const owner: string = authSession.sessionKey();
    const session: TiebaSession = this.currentSession();
    const seq: number = ++this.requestSeq;
    const operation: number = ++this.deleteOperation;
    const current: () => boolean = (): boolean => !this.disposed && this.tid === tid &&
      this.requestSeq === seq && authSession.matchesSession(session, owner);
    this.deletePending = true;
    this.isLoadingMore = false;
    // 此前在途的楼层/楼中楼请求已失效；释放它们的加载状态，失败后仍可重试。
    for (const state of this.subStates) { state.loading = false; }
    this.touchSubStates();
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!current() || !validTarget()) { return '账号或页面已变化，未继续删除'; }
      if (this.currentSession().tbs.length === 0) {
        const refreshed = await authSession.refreshTbs(context);
        if (!current()) { return '账号或页面已变化，未继续删除'; }
        if (!refreshed.ok) { return '登录凭据未就绪，请重新登录后删除'; }
      }
      const writeSession: TiebaSession = this.currentSession();
      const result: ApiResult = sub !== undefined
        ? await this.api.deleteMyPost(device, writeSession, fid, tid, sub.pid, true)
        : (post !== undefined ? await this.api.deleteMyPost(device, writeSession, fid, tid, post.pid, false)
          : await this.api.deleteMyThread(device, writeSession, fid, tid));
      // 即便已离页/换账号，服务端确认删除也须使其他列表的旧副本失效。
      if (result.ok) { noteContentDeleted(); }
      if (!current()) { return '账号或页面已变化，请在原账号刷新核对删除结果'; }
      if (!result.ok) { return `${result.describeFailure()}；请刷新核对后再操作`; }
      this.deletedPid = sub !== undefined ? sub.pid : (post !== undefined ? post.pid : 0);
      this.deletedParentPid = sub !== undefined ? parentPid : 0;
      this.deletedPage = Math.max(1, deletedPage);
      this.deletedSort = deletedSort;
      if (sub !== undefined) {
        this.removeDeletedSubPost(parentPid, sub.pid);
        await this.refreshRepliedFloor(context, parentPid);
      } else if (post !== undefined) {
        this.removeDeletedPost(post.pid);
      } else {
        this.threadDeleted = true;
        this.posts = [];
        this.syncVisiblePosts();
        this.detail.posts = [];
        this.setSubStates([]);
        this.hasMore = false;
        return '';
      }
      if (!current()) { return '账号或页面已变化，内容已删除，请刷新查看'; }
      if (this.deletedParentPid > 0 && this.deletedPid > 0 && this.deletedPage > 1) {
        await this.confirmPendingDeletion(device, writeSession, current);
      }
      await this.refreshDeletedReplyCount(device, writeSession, current);
      return current() ? '' : '账号或页面已变化，内容已删除，请刷新查看';
    } catch (_) {
      return '删除结果未确认，请刷新核对后再操作';
    } finally {
      if (operation === this.deleteOperation) { this.deletePending = false; }
    }
  }

  private removeDeletedPost(pid: number): void {
    const state: SubPostThreadState | undefined = this.findSubState(pid);
    if (state !== undefined) {
      for (const sub of state.subPosts) {
        this.subPostPages.delete(sub.pid);
        this.subPostParents.delete(sub.pid);
        this.agreeStates.delete(sub.pid);
      }
    }
    this.posts = this.posts.filter((post: PostItem): boolean => post.pid !== pid);
    this.detail.posts = this.posts;
    this.setSubStates(this.subStates.filter((item: SubPostThreadState): boolean => item.pid !== pid));
    this.postPages.delete(pid);
    this.agreeStates.delete(pid);
    if (this.focusedReplyPid === pid) {
      this.focusedReplyPid = 0;
      this.focusedSubPostPid = 0;
    }
    if (this.hasMore && this.sortType !== ReplySortType.DESC) { this.rereadPageAfterDelete = this.loadedPage; }
    this.syncVisiblePosts();
  }

  private removeDeletedSubPost(parentPid: number, pid: number): void {
    const previous: SubPostThreadState | undefined = this.findSubState(parentPid);
    if (previous === undefined) { return; }
    const state: SubPostThreadState = new SubPostThreadState();
    state.pid = parentPid;
    state.expanded = previous.expanded;
    state.subPosts = previous.subPosts.filter((sub: SubPostItem): boolean => sub.pid !== pid);
    state.page = new SubPostPage();
    state.page.totalCount = Math.max(state.subPosts.length, previous.page.totalCount - 1);
    // 页码可能已前移，先补读第一页。失败后保留现有内容并允许重新读取，不能继续旧页码。
    state.loadedOnce = false;
    this.setSubStates(this.subStates.map((item: SubPostThreadState): SubPostThreadState => item.pid === parentPid ? state : item));
    this.subPostPages.delete(pid);
    this.subPostParents.delete(pid);
    this.agreeStates.delete(pid);
    if (this.focusedSubPostPid === pid) { this.focusedSubPostPid = 0; }
    this.posts = this.posts.map((post: PostItem): PostItem => {
      if (post.pid !== parentPid) { return post; }
      const updated: PostItem = copyPostItem(post);
      updated.subPostCount = Math.max(state.subPosts.length, post.subPostCount - 1);
      return updated;
    });
    this.detail.posts = this.posts;
    this.syncVisiblePosts();
  }

  /** 回复总数由 pb/page 重新确认，不猜测删除父楼对楼中楼总数的影响。 */
  private async refreshDeletedReplyCount(device: TiebaDevice, session: TiebaSession,
    current: () => boolean): Promise<void> {
    if (!current()) { return; }
    if (this.deletedPid > 0 && this.deletedParentPid > 0) {
      if (this.errorText.length === 0) { this.errorText = '评论已删除，回复数暂未更新，请下拉刷新'; }
      return;
    }
    try {
      const page: number = this.deletedPid > 0 ? this.deletedPage : 1;
      const sort: ReplySortType = this.deletedPid > 0 ? this.deletedSort : ReplySortType.ASC;
      const response: ThreadDetailResponse = await this.api.fetchThreadDetail(
        device, session, this.tid, page, REQUEST_PAGE_SIZE, sort);
      if (!current()) { return; }
      if (!response.ok) { this.errorText = '评论已删除，回复数暂未更新，请下拉刷新'; return; }
      if (this.deletedPid > 0) {
        if (response.data.posts.some((post: PostItem): boolean => post.pid === this.deletedPid)) {
          this.errorText = '评论已删除，服务端列表尚未更新，请稍后下拉刷新'; return;
        }
        if (!this.subPageAccepted(response.data.page.currentPage, response.data.page.totalPage, page)) {
          this.errorText = '评论已删除，返回页码不一致，请下拉刷新核对'; return;
        }
        this.finishDeletionSync();
      }
      this.updateDeletedTotalPage(response.data.page.totalPage);
      response.data.posts = this.posts;
      this.detail = this.absorbDetail(response.data);
    } catch (_) {
      if (current()) { this.errorText = '评论已删除，回复数暂未更新，请下拉刷新'; }
    }
  }

  /** 只读一次原页确认同步，后页删除无需用户滚回原页；未确认不重发写操作。 */
  private async confirmPendingDeletion(device: TiebaDevice, session: TiebaSession,
    current: () => boolean): Promise<void> {
    if (this.deletedPid <= 0 || !current()) { return; }
    const owner: string = authSession.sessionKey();
    const pid: number = this.deletedPid;
    try {
      if (this.deletedParentPid > 0) {
        const response: SubPostResponse = await this.api.fetchSubPosts(device, session, this.tid,
          this.deletedParentPid, this.detail.author.id, this.deletedPage, SUB_POST_PAGE_SIZE);
        if (!current() || owner !== authSession.sessionKey() || pid !== this.deletedPid) { return; }
        if (response.ok && this.subPageAccepted(response.data.currentPage, response.data.totalPage, this.deletedPage) &&
          !response.data.subPosts.some((sub: SubPostItem): boolean => sub.pid === pid)) {
          const parentPid: number = this.deletedParentPid;
          const state: SubPostThreadState | undefined = this.findSubState(parentPid);
          if (state !== undefined) { state.page.totalCount = response.data.totalCount; }
          this.posts = this.posts.map((post: PostItem): PostItem => {
            if (post.pid !== parentPid) { return post; }
            const updated: PostItem = copyPostItem(post);
            updated.subPostCount = response.data.totalCount;
            return updated;
          });
          this.detail.posts = this.posts;
          this.syncVisiblePosts();
          this.touchSubStates();
          this.finishDeletionSync(); return;
        }
      } else {
        const response: ThreadDetailResponse = await this.api.fetchThreadDetail(device, session, this.tid,
          this.deletedPage, REQUEST_PAGE_SIZE, this.deletedSort);
        if (!current() || owner !== authSession.sessionKey() || pid !== this.deletedPid) { return; }
        if (response.ok && this.subPageAccepted(response.data.page.currentPage, response.data.page.totalPage, this.deletedPage) &&
          !response.data.posts.some((post: PostItem): boolean => post.pid === pid)) {
          this.updateDeletedTotalPage(response.data.page.totalPage);
          this.finishDeletionSync(); return;
        }
      }
    } catch (_) { /* 删除回执已确认，读回异常只保留待同步目标。 */ }
    if (current() && owner === authSession.sessionKey()) {
      this.errorText = '评论已删除，服务端列表尚未更新，请稍后下拉刷新';
    }
  }

  dispose(): void {
    this.disposed = true;
    this.requestSeq++;
    this.isJumpingFloor = false;
    this.deleteOperation++;
    this.deletePending = false;
    this.replyPermissionOperation++;
    this.replyPermissionPending = false;
    this.deletedPid = 0;
    this.deletedParentPid = 0;
  }

  /** 页面只提供目标身份与读回位置，写入串行化由共享状态机负责。 */
  async toggleAgree(context: common.UIAbilityContext, item: PostItem | SubPostItem,
    objType: AgreeObjType = AgreeObjType.POST, parentPid: number = 0): Promise<string> {
    const pid: number = item.pid;
    const state: AgreeState = objType === AgreeObjType.SUB_POST
      ? this.subAgreeState(item as SubPostItem) : this.agreeState(pid);
    const tid: number = this.tid;
    const seq: number = this.requestSeq;
    const target: AgreeTarget = { tid: tid, pid: pid, forumId: this.detail.forumId,
      objType: objType, parentPid: parentPid, generation: seq };
    return this.agreeActions.toggle(context, target, state,
      (): boolean => this.tid === tid && this.requestSeq === seq,
      async (current: () => boolean): Promise<void> => {
        if (objType === AgreeObjType.SUB_POST) {
          await this.confirmSubAgreeFromServer(context, pid, parentPid, current);
        } else {
          await this.confirmAgreeFromServer(context, pid, current);
        }
      });
  }

  private async confirmAgreeFromServer(context: common.UIAbilityContext, pid: number,
    current: () => boolean): Promise<void> {
    if (!current()) {
      return; // 已有点更新的读回，或期间刷新/重载/切排序过 → 过期，跳过
    }
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!current()) { return; }
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
      if (!current()) {
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
    parentPid: number, current: () => boolean): Promise<void> {
    if (!current()) { return; }
    const page: number | undefined = this.subPostPages.get(pid);
    if (page === undefined || this.subPostParents.get(pid) !== parentPid) {
      hilog.warn(FLOW_DOMAIN, FLOW_TAG, 'source=sub-confirm-skip(page-unknown) pid=%{public}d', pid);
      return;
    }
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!current()) { return; }
      const response: SubPostResponse = await this.api.fetchSubPosts(
        device, this.currentSession(), this.tid, parentPid, this.detail.author.id, page,
        SUB_POST_PAGE_SIZE);
      if (!current() || !response.ok) {
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
    targetPid: number = 0, withTail?: boolean, subPost?: SubPostItem): Promise<string> {
    if (this.disposed || this.threadDeleted) { return '页面已关闭或帖子已删除'; }
    if (this.deletePending) { return '删除处理中，请稍候'; }
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

    if (!Number.isSafeInteger(targetPid) || targetPid < 0 ||
      (subPost !== undefined && (targetPid <= 0 || !Number.isSafeInteger(subPost.pid) || subPost.pid <= 0))) {
      return '回复目标无效，请重新选择评论';
    }
    const target: AddPostTarget | undefined = targetPid > 0
      ? ThreadDetailVM.buildReplyTarget(targetPid, subPost)
      : undefined;
    const body: string = subPost === undefined ? text : subReplyContent(text, subPost);

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
        device, session, tid, fid, forumName, body, target, withTail);
      if (!current()) { return '账号或帖子已变化，已发出的回复需在原账号确认'; }
      if (!response.ok) {
        hilog.info(FLOW_DOMAIN, FLOW_TAG, 'source=replyFailed tid=%{public}d reason=%{public}s',
          this.tid, response.describeFailure());
        return response.describeFailure();
      }
      this.lastReplyPid = response.result.pid;
      hilog.info(FLOW_DOMAIN, FLOW_TAG,
        'source=replyAccepted tid=%{public}d pid=%{public}d', this.tid, response.result.pid);
      if (targetPid > 0) {
        // 回复该楼和回复子评论都落在同一楼中楼，不重建主列表或切换全帖排序。
        await this.refreshRepliedFloor(context, targetPid);
        if (!current()) { return '账号或帖子已变化，回复已受理，请在原账号查看'; }
        return '';
      }
      // 主帖评论受理后保留阅读现场；由用户主动刷新读取新评论，不重建列表或改变排序。
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
  private static buildReplyTarget(pid: number, subPost?: SubPostItem): AddPostTarget {
    const target: AddPostTarget = new AddPostTarget();
    target.postId = String(pid);
    if (subPost !== undefined) {
      target.subPostId = String(subPost.pid);
      if (Number.isSafeInteger(subPost.author.id) && subPost.author.id > 0) {
        target.replyUid = String(subPost.author.id);
      }
    }
    return target;
  }

  /** 保留已显示内容刷新本层；换状态实例使发送前在途的旧分页结果失效。 */
  private async refreshRepliedFloor(context: common.UIAbilityContext, pid: number): Promise<void> {
    const previous: SubPostThreadState | undefined = this.findSubState(pid);
    const state: SubPostThreadState = new SubPostThreadState();
    state.pid = pid;
    if (previous !== undefined) {
      state.expanded = previous.expanded;
      state.loadedOnce = previous.loadedOnce;
      state.subPosts = previous.subPosts;
      state.page = previous.page;
      state.hasMore = previous.hasMore;
    }
    this.setSubStates(previous === undefined ? this.subStates.concat([state]) :
      this.subStates.map((item: SubPostThreadState): SubPostThreadState => item.pid === pid ? state : item));
    await this.loadSubPosts(context, pid, this.detail.author.id, 1);
  }


  /** 按 pid 取当前模型里的楼层（找不到返回 undefined）；走索引，渲染期每层都会调 */
  postByPid(pid: number): PostItem | undefined {
    return this.postIndex.get(pid);
  }

  /** 重试某层楼中楼第一页。与 toggleSubPosts 分开，避免"重试"按钮把区域收起来 */
  async retrySubPosts(context: common.UIAbilityContext, pid: number,
    threadAuthorId: number): Promise<void> {
    if (this.disposed || this.deletePending || this.threadDeleted) { return; }
    const state: SubPostThreadState | undefined = this.findSubState(pid);
    if (state === undefined || state.loading || state.loadedOnce) {
      return;
    }
    state.expanded = true;
    state.errorText = '';
    this.touchSubStates();
    await this.loadSubPosts(context, pid, threadAuthorId, 1);
  }

  /**
   * 加载更多楼中楼。失败保留已加载内容，只在区域底部提示。
   *
   * **没有真实分页基线就不要从“下一页”开始**：楼层自带的内联预览铺进状态时 `page` 还是默认值
   * （currentPage=1 只是占位），按 currentPage+1 会直接请求第 2 页：只有一页的楼层会被服务端
   * 夹回第 1 页并返回空列表，两页以上的则跳过第 1 页、缺掉中间那些回复。首次翻页一律从第 1 页开始。
   */
  async loadMoreSubPosts(context: common.UIAbilityContext, pid: number,
    threadAuthorId: number): Promise<void> {
    if (this.disposed || this.deletePending || this.threadDeleted) { return; }
    const state: SubPostThreadState | undefined = this.findSubState(pid);
    if (state === undefined || state.loading) {
      return;
    }
    if (!state.loadedOnce || state.previewOnly) {
      await this.loadSubPosts(context, pid, threadAuthorId, 1);
      return;
    }
    if (!state.hasMore || state.page.currentPage <= 0) {
      return;
    }
    // 已知到达末页就不再发请求：服务端只会再夹一次（返回空列表），白跑一趟网络
    if (state.page.totalPage > 0 && state.page.currentPage >= state.page.totalPage) {
      state.hasMore = false;
      this.touchSubStates();
      return;
    }
    await this.loadSubPosts(context, pid, threadAuthorId, state.page.currentPage + 1);
  }

  /**
   * 拉某页楼中楼。page=1 替换，page>1 追加。落地后立刻刷新状态表：数据到了就得画出来，
   * 用户点开 / 重试 / 加载更多都一样。
   */
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
    const startedAt: number = Date.now();
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

      const servedPage: number = response.data.currentPage;
      if (!this.subPageAccepted(servedPage, response.data.totalPage, page)) {
        hilog.warn(FLOW_DOMAIN, FLOW_TAG,
          'subposts page mismatch pid=%{public}d request=%{public}d served=%{public}d total=%{public}d',
          pid, page, servedPage, response.data.totalPage);
        state.errorText = '返回页码不一致，请重试';
        return;
      }
      // 被夹到末页（page > total_page）：这是"已经到底"，下面按没有更多收尾
      const clamped: boolean = servedPage !== page;
      if (this.deletedPid > 0 && this.deletedParentPid === pid) {
        if (response.data.subPosts.some((sub: SubPostItem): boolean => sub.pid === this.deletedPid)) {
          state.errorText = '评论已删除，服务端列表尚未更新，请稍后重试';
          state.loadedOnce = false;
          state.hasMore = false;
          this.errorText = state.errorText;
          return;
        }
        if (page === this.deletedPage || response.data.totalPage < this.deletedPage) {
          this.finishDeletionSync();
        }
      }
      if (page <= 1) {
        for (let i = 0; i < state.subPosts.length; i++) {
          this.subPostPages.delete(state.subPosts[i].pid);
          this.subPostParents.delete(state.subPosts[i].pid);
        }
        state.subPosts = response.data.subPosts;
        // floor 接口的完整一页已覆盖内联预览，之后按正常加载路径处理。
        state.previewOnly = false;
      } else {
        // concat 产生新数组：即使以后把状态对象换成 @ObservedV2，也能保持同一套更新方式
        const seen: Set<number> = new Set<number>(state.subPosts.map((item: SubPostItem): number => item.pid));
        const added: SubPostItem[] = response.data.subPosts.filter((item: SubPostItem): boolean => {
          if (seen.has(item.pid)) { return false; } seen.add(item.pid); return true;
        });
        if (added.length === 0) {
          /*
           * 空页有两种：服务端把请求页夹回末页（评论被删/计数变小），或这页全是已加载条目。
           * 都按“到底了”收尾并保留已加载内容；只有服务端仍声称有下一页时才提示无进展。
           */
          state.page = response.data;
          state.loadedOnce = true;
          state.hasMore = false;
          state.errorText = clamped || !response.data.hasMore ? '' : '分页没有进展，请刷新后重试';
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
      // floor 返回的总数同时更新主列表预览及主帖的楼中楼入口，不凭发送回执自增。
      // 计数未变时保留主列表引用，避免滑动补拉预览反复触发整个主列表更新。
      const parent: PostItem | undefined = this.postByPid(pid);
      if (parent !== undefined && parent.subPostCount !== response.data.totalCount) {
        this.posts = this.posts.map((post: PostItem): PostItem => {
          if (post.pid !== pid) { return post; }
          const updated: PostItem = copyPostItem(post);
          updated.subPostCount = response.data.totalCount;
          return updated;
        });
        this.syncVisiblePosts();
      }
    } catch (err) {
      const e: Error = err as Error;
      const state: SubPostThreadState | undefined = this.findSubState(pid);
      if (current() && state !== undefined) {
        state.errorText = `加载失败：${e.message}`;
      }
    } finally {
      const state: SubPostThreadState | undefined = this.findSubState(pid);
      /*
       * 复位 loading **不要求 current()**：状态实例被换掉（回复后刷新本层）或在途请求被判过期时
       * 旧引用已失效，若因此跳过复位，界面会永久停在“加载中”。按 pid 查当前状态即可。
       */
      if (state !== undefined) {
        state.loading = false;
      }
      this.touchSubStates();
      const elapsed: number = Date.now() - startedAt;
      // 只在"慢"或"失败"时留一行：正常落地不刷屏。
      if (state === undefined || elapsed >= SUB_POST_SLOW_MS || state.errorText.length > 0) {
        hilog.warn(FLOW_DOMAIN, FLOW_TAG,
          'subposts pid=%{public}d page=%{public}d ms=%{public}d hasState=%{public}s loaded=%{public}s n=%{public}d err=%{public}s',
          pid, page, elapsed, String(state !== undefined),
          String(state === undefined ? false : state.loadedOnce),
          state === undefined ? -1 : state.subPosts.length,
          state === undefined ? 'nostate' : state.errorText);
      }
    }
  }

  /** 将 spid 定位阶段已拉回的楼中楼页写入父楼状态，避免展开面板时再拉第一页覆盖目标页。 */
  private applyLocatedSubPage(parentPid: number, page: SubPostPage): void {
    let state: SubPostThreadState | undefined = this.findSubState(parentPid);
    if (state === undefined) {
      state = new SubPostThreadState();
      state.pid = parentPid;
      this.setSubStates(this.subStates.concat([state]));
    }
    state.subPosts = page.subPosts;
    state.page = page;
    state.hasMore = page.hasMore;
    state.loadedOnce = true;
    state.previewOnly = false;
    state.errorText = '';
    const authorId: number = this.detail.author.id;
    for (let i = 0; i < page.subPosts.length; i++) {
      const sub: SubPostItem = page.subPosts[i];
      if (authorId > 0) {
        sub.isThreadAuthor = sub.author.id === authorId;
      }
      this.subPostPages.set(sub.pid, page.currentPage);
      this.subPostParents.set(sub.pid, parentPid);
      const observed: AgreeState = this.subAgreeState(sub);
      if (!observed.pending && !observed.toggled) {
        observed.isAgreed = sub.isAgreed;
        observed.count = sub.agreeCount;
      }
    }
    this.touchSubStates();
  }

  /** 按 pid 查状态（走索引）；没有返回 undefined */
  private findSubState(pid: number): SubPostThreadState | undefined {
    return this.subStateIndex.get(pid);
  }

  /**
   * 改状态表的唯一入口：换新数组触发 @Trace，同时重建 pid 索引。
   * 直接写 `this.subStates = ...` 会让索引和数据分叉，别忘了走这里。
   */
  private setSubStates(next: SubPostThreadState[]): void {
    const index: Map<number, SubPostThreadState> = new Map<number, SubPostThreadState>();
    for (let i = 0; i < next.length; i++) {
      index.set(next[i].pid, next[i]);
    }
    this.subStateIndex = index;
    this.subStates = next;
  }

  /** 让 @Trace 数组产生一次整体替换，通知 UI 重新读取状态 */
  private touchSubStates(): void {
    const next: SubPostThreadState[] = [];
    for (let i = 0; i < this.subStates.length; i++) {
      next.push(this.subStates[i]);
    }
    this.setSubStates(next);
  }

  /** 按当前楼层同步状态表：reset=true 时丢弃旧状态，否则保留已有状态并补充新楼层 */
  private syncSubStates(posts: PostItem[], reset: boolean): void {
    let existing: SubPostThreadState[] = [];
    if (!reset) {
      existing = this.subStates;
    } else if (posts.length > 0) {
      /*
       * 刷新时**唯独保留首楼**的楼中楼状态：普通楼层走弹层，列表上只有内联预览，重建看不出来；
       * 首楼是在地展开的（`SubPostEntry` → `SubPostList`），重建会把 `expanded` 打回 false、
       * 已加载内容退回内联简版，用户正在读的那块会被收起来。
       */
      const mainPid: number = posts[0].pid;
      for (let i = 0; i < this.subStates.length; i++) {
        const state: SubPostThreadState = this.subStates[i];
        if (state.pid === mainPid && (state.expanded || state.loadedOnce)) {
          existing.push(state);
        }
      }
    }
    const next: SubPostThreadState[] = syncSubPostThreadStates(existing, posts);
    /*
     * 楼层自带的楼中楼预览直接铺进状态：预览块在楼层落地那一刻就有内容，高度不会“先矮后高”。
     * `previewOnly` 让预取跳过这些层，同时保留“点开详情再拉完整页”的能力。
     */
    const byPid: Map<number, PostItem> = new Map<number, PostItem>();
    for (let i = 0; i < posts.length; i++) {
      byPid.set(posts[i].pid, posts[i]);
    }
    for (let i = 0; i < next.length; i++) {
      const state: SubPostThreadState = next[i];
      if (state.loadedOnce || state.previewOnly || state.subPosts.length > 0) {
        continue;
      }
      const post: PostItem | undefined = byPid.get(state.pid);
      if (post === undefined || post.inlineSubPosts.length === 0) {
        continue;
      }
      state.subPosts = post.inlineSubPosts;
      state.previewOnly = true;
      state.hasMore = post.subPostCount > post.inlineSubPosts.length;
    }
    // 诊断：这一页有多少层真正带上了内联预览
    this.setSubStates(next);
  }
}
