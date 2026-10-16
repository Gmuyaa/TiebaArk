

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

const REQUEST_PAGE_SIZE: number = 30;

const SUB_POST_PAGE_SIZE: number = 30;

const AGREE_CONFIRM_DELAY_MS: number = 3000;

const FLOW_TAG: string = 'AgreeFlow';
const FLOW_DOMAIN: number = 0x0000;
const FLOW_FLAG: (v: boolean) => number = (v: boolean): number => v ? 1 : 0;

@ObservedV2
export class AgreeState {

  @Trace isAgreed: boolean = false;
  @Trace count: number = 0;

  @Trace toggled: boolean = false;

  @Trace pending: boolean = false;

  constructor(agreed: boolean, count: number) {
    this.isAgreed = agreed;
    this.count = count;
  }

  liked(): boolean {
    return resolveAgreeLiked(this.isAgreed, this.toggled);
  }

  displayCount(): number {
    return resolveAgreeCount(this.count, this.isAgreed, this.toggled);
  }
}

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

  @Trace tid: number = 0;

  @Trace loading: boolean = false;

  @Trace isRefreshing: boolean = false;

  @Trace isLoadingMore: boolean = false;
  @Trace errorText: string = '';

  @Trace lastErrorCode: number = 0;

  @Trace loadedOnce: boolean = false;

  @Trace detail: ThreadDetail = new ThreadDetail();

  @Trace posts: PostItem[] = [];
  @Trace hasMore: boolean = false;

  @Trace focusedReplyPid: number = 0;

  @Trace subStates: SubPostThreadState[] = [];

  @Trace sortType: ReplySortType = ReplySortType.ASC;

  @Trace collected: boolean = false;

  @Trace storePending: boolean = false;

  @Trace replyPending: boolean = false;

  @Trace lastReplyPid: number = 0;

  @Trace isSwitchingSort: boolean = false;

  @Trace memePics: MemePicItem[] = [];

  @Trace memeStateText: string = '';
  private memeLoadedOnce: boolean = false;

  private memeTokens: Map<string, string> = new Map<string, string>();

  memeDisplayUrl(item: MemePicItem): string {
    return item.thumbnail.length > 0 ? item.thumbnail : item.picUrl;
  }

  memeTokenFor(url: string): string {
    const hit: string | undefined = this.memeTokens.get(url);
    return hit === undefined ? '' : hit;
  }

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

  async retryMemePics(context: common.UIAbilityContext): Promise<void> {
    this.memeLoadedOnce = false;
    this.memeStateText = '';
    await this.loadMemePics(context);
  }

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

      const tokens: Map<string, string> = new Map<string, string>();
      const pics: MemePicItem[] = response.data.pics;
      for (let i = 0; i < pics.length; i++) {
        const p: MemePicItem = pics[i];
        if (p.picId.length === 0) {
          continue;
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

  private currentSession(): TiebaSession {
    return authSession.session();
  }

  private loadedPage: number = 0;

  private postPages: Map<number, number> = new Map<number, number>();

  private subPostPages: Map<number, number> = new Map<number, number>();
  private subPostParents: Map<number, number> = new Map<number, number>();

  private knownTotalPage: number = 1;

  private agreeStates: Map<number, AgreeState> = new Map<number, AgreeState>();

  private agreeWrites: Map<string, AgreeWriteState> = new Map<string, AgreeWriteState>();

  private agreeConfirmSeq: Map<number, number> = new Map<number, number>();

  private requestSeq: number = 0;

  forumNameHint: string = '';

  setForumNameHint(name: string | undefined): void {
    this.forumNameHint = name === undefined ? '' : name.trim();
  }

  private absorbDetail(source: ThreadDetail): ThreadDetail {
    source.forumName = resolveForumName(source.forumName, this.forumNameHint);
    return source;
  }

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

      this.detail = this.absorbDetail(response.data);

      this.collected = response.data.isStored;
      this.posts = response.data.posts;
      if (this.focusedReplyPid > 0) {
        this.rememberPostPages([this.posts[0]], 1, true);

        this.rememberPostPages(this.posts.slice(1), targetPage, false);
      } else {
        this.rememberPostPages(response.data.posts, response.data.page.currentPage, true);
      }
      this.hasMore = this.focusedReplyPid === 0 && response.data.page.hasMore;
      this.loadedPage = response.data.page.currentPage;
      this.knownTotalPage = Math.max(1, response.data.page.totalPage);
      this.loadedOnce = true;
      this.syncVisiblePosts();

      this.rebuildAgreeStates('reload');

      this.syncSubStates(this.posts, true);
      this.agreeFlowSnapshot('load-done');
    } catch (err) {
      const e: Error = err as Error;
      this.errorText = `加载失败：${e.message}`;
    } finally {
      this.loading = false;
    }
  }

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

  async loadMore(context: common.UIAbilityContext): Promise<void> {
    if (this.loading || this.isRefreshing || this.isLoadingMore || this.isSwitchingSort ||
      !this.hasMore || this.loadedPage <= 0) {
      return;
    }
    this.isLoadingMore = true;
    this.errorText = '';
    const seq: number = this.requestSeq;

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

        this.errorText = response.describeFailure();
        return;
      }

      this.posts = this.mergePostsByPid(this.posts, response.data.posts);
      this.rememberPostPages(response.data.posts, response.data.page.currentPage, false);
      this.updatePaging(response.data.page.currentPage, response.data.page.totalPage,
        response.data.page.hasMore);
      this.syncVisiblePosts();

      this.syncSubStates(this.posts, false);
    } catch (err) {
      const e: Error = err as Error;
      this.errorText = `加载失败：${e.message}`;
    } finally {
      this.isLoadingMore = false;
    }
  }

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

  @Trace visiblePosts: PostItem[] = [];

  private syncVisiblePosts(): void {
    this.visiblePosts = this.posts;
  }

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

    this.posts = [previousPosts[0]];
    this.syncVisiblePosts();
    this.rebuildAgreeStates('switchSort');
    this.subStates = [];

    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      const requestPage: number = this.firstPageForSort(newType);
      const response: ThreadDetailResponse = await this.api.fetchThreadDetail(
        device, this.currentSession(), this.tid, requestPage, REQUEST_PAGE_SIZE, newType);

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

  private firstPageForSort(type: ReplySortType): number {
    return type === ReplySortType.DESC ? Math.max(1, this.knownTotalPage) : 1;
  }

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

  private updatePaging(currentPage: number, totalPage: number, serverHasMore: boolean): void {
    this.loadedPage = currentPage;
    if (totalPage > 0 && (this.sortType === ReplySortType.ASC ||
      this.sortType === ReplySortType.DESC)) {
      this.knownTotalPage = totalPage;
    }
    this.hasMore = this.sortType === ReplySortType.DESC ? currentPage > 1 : serverHasMore;
  }

  subState(pid: number): SubPostThreadState {
    const found: SubPostThreadState | undefined = this.findSubState(pid);
    if (found !== undefined) {
      return found;
    }
    const fallback: SubPostThreadState = new SubPostThreadState();
    fallback.pid = pid;
    return fallback;
  }

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

  async ensureSubPostPreview(context: common.UIAbilityContext, pid: number,
    threadAuthorId: number): Promise<void> {
    const state: SubPostThreadState | undefined = this.findSubState(pid);
    if (state === undefined || state.loadedOnce || state.loading) {
      return;
    }
    await this.loadSubPosts(context, pid, threadAuthorId, 1);
  }

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

    hilog.info(FLOW_DOMAIN, FLOW_TAG,
      'source=lazyCreate pid=%{public}d isMain=%{public}s postFound=%{public}s'
        + ' created[isAgreed=%{public}s count=%{public}d]',
      pid, String(FLOW_FLAG(pid === this.detail.mainPostId)),
      String(post === undefined ? 'NO' : 'yes'),
      String(FLOW_FLAG(created.isAgreed)), created.count);
    return created;
  }

  subAgreeState(sub: SubPostItem): AgreeState {
    const found: AgreeState | undefined = this.agreeStates.get(sub.pid);
    if (found !== undefined) {
      return found;
    }
    const created: AgreeState = new AgreeState(sub.isAgreed, sub.agreeCount);
    this.agreeStates.set(sub.pid, created);
    return created;
  }

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

  isLiked(item: PostItem): boolean {
    return this.agreeState(item.pid).liked();
  }

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

  mainPost(): PostItem | undefined {
    return ThreadDetail.locateMainPost(this.detail);
  }

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

    const previous: number | undefined = this.agreeConfirmSeq.get(pid);
    this.agreeConfirmSeq.set(pid, (previous === undefined ? 0 : previous) + 1);
    const flight: AgreeWriteState = new AgreeWriteState(target, before, state, this.requestSeq);
    this.agreeWrites.set(key, flight);
    state.pending = true;
    return await this.runAgreeWrites(context, pid, objType, parentPid, key, flight,
      this.tid, this.detail.forumId);
  }

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
      return;
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
        return;
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

      this.applyServerAgree(pid, agreed, count);
    } catch (err) {
      const e: Error = err as Error;
      hilog.warn(FLOW_DOMAIN, FLOW_TAG,
        'source=confirm-read-exception pid=%{public}d reason=%{public}s', pid, e.message);
    }
  }

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

  isAgreePending(item: PostItem): boolean {
    return this.agreeState(item.pid).pending;
  }

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

      await this.refresh(context);
      if (!current()) { return '账号或帖子已变化，回复已受理，请在原账号查看'; }

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

  containsPid(pid: number): boolean {
    if (pid <= 0) {
      return false;
    }
    return this.postByPid(pid) !== undefined;
  }

  private static buildReplyTarget(pid: number): AddPostTarget {
    const target: AddPostTarget = new AddPostTarget();
    target.postId = String(pid);
    return target;
  }

  postByPid(pid: number): PostItem | undefined {
    for (let i = 0; i < this.posts.length; i++) {
      if (this.posts[i].pid === pid) {
        return this.posts[i];
      }
    }
    return undefined;
  }

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

  async loadMoreSubPosts(context: common.UIAbilityContext, pid: number,
    threadAuthorId: number): Promise<void> {
    const state: SubPostThreadState | undefined = this.findSubState(pid);
    if (state === undefined || state.loading || !state.hasMore || state.page.currentPage <= 0) {
      return;
    }
    await this.loadSubPosts(context, pid, threadAuthorId, state.page.currentPage + 1);
  }

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

  private findSubState(pid: number): SubPostThreadState | undefined {
    for (let i = 0; i < this.subStates.length; i++) {
      if (this.subStates[i].pid === pid) {
        return this.subStates[i];
      }
    }
    return undefined;
  }

  private touchSubStates(): void {
    const next: SubPostThreadState[] = [];
    for (let i = 0; i < this.subStates.length; i++) {
      next.push(this.subStates[i]);
    }
    this.subStates = next;
  }

  private syncSubStates(posts: PostItem[], reset: boolean): void {
    let existing: SubPostThreadState[] = [];
    if (!reset) {
      existing = this.subStates;
    }
    this.subStates = syncSubPostThreadStates(existing, posts);
  }
}
