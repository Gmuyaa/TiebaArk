/** 个人内容列表的取数 VM，按列表类型管理加载、刷新与分页状态。 */

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { authSession } from '../auth/AuthSession';
import { TiebaApi, UserPostsResponse } from '../api/TiebaApi';
import { ApiResult } from '../api/ApiResult';
import { mergeUserReplies, StoredThread, UserPostItem, userReplyKey } from '../model/MyContent';
import { ContentPiece } from '../model/ThreadDetail';
import { UserProfileInfo } from '../model/UserProfile';
import { TiebaDevice, TiebaSession } from '../net/TiebaParams';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import {
  addBrowseHistory, BrowseItem, clearBrowseHistory, loadBrowseHistory, markBrowseDeleted
} from '../utils/BrowseHistory';
import { forgetCachedForumAvatar, getForumAvatarId, putForumAvatar } from '../model/ForumAvatarStore';
import { backfillForumAvatars, ForumAvatarBackfillPlan, ForumAvatarNeed } from '../utils/ForumAvatarBackfill';
import { formatTimeText } from '../model/TimeText';
import { noteContentDeleted } from './ContentDeletionRevision';


/** 列表类型（页面路由参数传字符串，这里做归一） */
export type MyListKind = 'history' | 'fav' | 'reply' | 'thread';

export function parseKind(raw: string): MyListKind {
  if (raw === 'fav' || raw === 'reply' || raw === 'thread') {
    return raw;
  }
  return 'history';
}

/** 标题（页面顶部与空态文案都用它） */
export function kindTitle(kind: MyListKind): string {
  if (kind === 'fav') {
    return '我的收藏';
  }
  if (kind === 'reply') {
    return '我的回复';
  }
  if (kind === 'thread') {
    return '我的帖子';
  }
  return '浏览历史';
}

/** 交给界面渲染的一行 */
export class MyListItem {
  key: string = '';
  pid: number = 0;
  pieces: ContentPiece[] = [];
  isComment: boolean = false;
  tid: number = 0;
  title: string = '';
  /** 帖子/回复正文摘要，收藏与历史为空。 */
  content: string = '';
  forumName: string = '';
  forumId: number = 0;
  postedTime: string = '';
  images: string[] = [];
  originImages: string[] = [];
  agreeCount: number = -1;
  replyCount: number = 0;
  shareCount: number = -1;
  /** 吧头像完整地址；收藏的 JSON 信封不带，由 VM 按吧名懒解析补上 */
  forumAvatar: string = '';
  /** 封面图（收藏有、浏览历史新记录有，其余为空 → 界面显示占位） */
  coverUrl: string = '';
  /** 副信息：回复数 / 浏览时间，由 VM 拼好 */
  meta: string = '';
  /**
   * 帖子已被删除（收藏端点 `is_deleted="1"`；浏览历史在**记录时**判定：服务端没给标题）。
   * 界面据此灰显标题 + 左下角换「该帖子已被删除」。
   */
  isDeleted: boolean = false;
  /**
   * 发帖时选了「个人主页不可见」。界面在卡片右上角、更多菜单左侧显示「主页不可见」，
   * 与官方「我的帖子」一致；只有主题列表有意义（回复行不带这个标志）。
   */
  hideFromProfile: boolean = false;
}

@ObservedV2
export class MyListVM {
  @Trace kind: MyListKind = 'history';
  @Trace items: MyListItem[] = [];
  @Trace loading: boolean = false;
  @Trace loadedOnce: boolean = false;
  @Trace errorText: string = '';
  @Trace loadingMore: boolean = false;
  @Trace hasMore: boolean = false;
  @Trace pagingError: string = '';
  @Trace managing: boolean = false;
  @Trace selected: number[] = [];
  @Trace removing: boolean = false;
  @Trace stoppingRemoval: boolean = false;
  @Trace threadPendingTid: number = 0;

  private favoriteOffset: number = 0;
  private selectedSnapshot: number[] = [];
  private selectedIndex: Set<number> = new Set<number>();
  private favoriteRequest: number = 0;
  private favoriteAccount: string = '';
  private disposed: boolean = false;

  private listOwner: string = '';
  private syncPrivateAccount(): boolean {
    const owner: string = authSession.sessionKey();
    if (owner === this.listOwner) { return false; }
    this.listOwner = owner; this.replyRequest++;
    this.items = []; this.replyItems = []; this.replyPage = 0;
    this.loading = false; this.loadingMore = false; this.loadedOnce = false; this.hasMore = false;
    this.errorText = ''; this.pagingError = '';
    return true;
  }
  private replyPage: number = 0;
  private replyRequest: number = 0;
  private replyItems: UserPostItem[] = [];

  private api: TiebaApi = new TiebaApi();

  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.disposed || this.threadPendingTid > 0) { return; }
    if (this.kind === 'reply' || this.kind === 'thread') { this.syncPrivateAccount(); }
    if (this.kind === 'fav') {
      await this.loadFavorites(context, false);
      return;
    }
    if (this.kind === 'reply') {
      await this.loadReplies(context, false);
      return;
    }
    this.errorText = '';
    if (this.kind === 'history') {
      await this.loadHistory(context);
      return;
    }
    if (!authSession.isLoggedIn()) {
      this.errorText = '登录后可查看';
      this.items = [];
      this.loadedOnce = true;
      return;
    }
    const owner: string = authSession.sessionKey();
    const request: number = ++this.replyRequest;
    const current = (): boolean => !this.disposed && request === this.replyRequest && owner === authSession.sessionKey();
    this.loading = true;
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!current()) { return; }
      const session = authSession.session();
      const uid: number = await this.resolveUid(context, session);
      if (!current()) { return; }
      if (uid <= 0) {
        this.errorText = '取不到账号 uid，无法拉取';
        this.items = [];
        return;
      }
      {
        const isThread: number = this.kind === 'thread' ? 1 : 0;
        const res: UserPostsResponse =
          await this.api.fetchUserPosts(device, session, uid, isThread, 1, 20);
        if (!current()) { return; }
        if (!res.ok) {
          this.errorText = res.describeFailure();
          this.items = [];
          return;
        }
        this.items = MyListVM.fromUserPosts(res.data, isThread === 1);
        this.resolveAvatars(context).catch(() => {
          // 头像补取失败不影响列表
        });
      }
    } catch (err) {
      if (current()) { this.errorText = (err as Error).message; }
    } finally {
      if (request === this.replyRequest) {
        if (owner !== authSession.sessionKey()) { this.items = []; this.errorText = '账号已变化，请重新加载'; }
        this.loading = false; this.loadedOnce = true;
      }
    }
  }

  async loadMore(context: common.UIAbilityContext): Promise<void> {
    if (this.kind === 'reply' && this.syncPrivateAccount()) { await this.load(context); return; }
    if (this.kind === 'fav') {
      await this.loadFavorites(context, true);
      return;
    }
    if (this.kind === 'reply') {
      await this.loadReplies(context, true);
    }
  }

  /** 菜单和删除确认都绑定打开时的账号，不能对切换后的账号执行。 */
  threadActionOwner(): string { return this.listOwner; }

  async manageThread(context: common.UIAbilityContext, item: MyListItem, confirmedOwner: string,
    action: 'hide' | 'show' | 'delete'): Promise<string> {
    if (this.disposed || this.kind !== 'thread' || this.loading || this.threadPendingTid > 0) { return ''; }
    if (!authSession.isLoggedIn() || confirmedOwner.length === 0 ||
      confirmedOwner !== this.listOwner || confirmedOwner !== authSession.sessionKey()) {
      return '账号已变化，请刷新后再操作';
    }
    // 刷新后的同 tid 也是新条目：旧菜单/旧确认框不能对新列表执行。
    if (!this.items.includes(item) || item.isDeleted || item.tid <= 0) { return '帖子已变化，请刷新后再操作'; }
    const hidden: boolean = action === 'hide';
    if (action !== 'delete' && hidden === item.hideFromProfile) { return ''; }
    this.threadPendingTid = item.tid;
    const request: number = this.replyRequest;
    const current = (): boolean => !this.disposed && this.kind === 'thread' &&
      request === this.replyRequest && confirmedOwner === authSession.sessionKey() && authSession.isLoggedIn();
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!current()) { return '账号或页面已变化，未继续操作'; }
      if (authSession.session().tbs.length === 0) {
        const refreshed = await authSession.refreshTbs(context);
        if (!current()) { return '账号或页面已变化，未继续操作'; }
        if (!refreshed.ok) { return '登录凭据未就绪，请重新登录后操作'; }
      }
      const session: TiebaSession = authSession.session();
      const uid: number = action === 'delete' ? 0 : await this.resolveUid(context, session);
      if (!current()) { return '账号或页面已变化，未继续操作'; }
      const result: ApiResult = action === 'delete'
        ? await this.api.deleteMyThread(device, session, item.forumId, item.tid)
        : await this.api.setMyThreadVisibility(device, session, uid, item.forumId, item.tid, item.pid, hidden);
      if (!current()) { return '账号或页面已变化，请刷新核对操作结果'; }
      if (!result.ok) { return `${result.describeFailure()}；请下拉刷新核对后再操作`; }
      if (action === 'delete') {
        this.items = this.items.filter((row: MyListItem): boolean => row.tid !== item.tid);
        await MyListVM.markDeleted(context, item.tid).catch((): void => {});
        noteContentDeleted();
        return '帖子已删除';
      }
      item.hideFromProfile = hidden;
      this.refreshItems();
      return hidden ? '已设为主页不可见' : '已设为主页可见';
    } catch (err) {
      return '操作结果未确认，请下拉刷新核对后再操作';
    } finally {
      this.threadPendingTid = 0;
      if (!this.disposed && confirmedOwner !== authSession.sessionKey()) {
        this.syncPrivateAccount();
        this.errorText = '账号已变化，请重新加载';
      }
    }
  }

  private favoriteOwner(): string {
    return authSession.isLoggedIn() ? authSession.sessionKey() : '';
  }

  private favoriteCurrent(request: number): boolean {
    return !this.disposed && request === this.favoriteRequest && this.favoriteAccount === this.favoriteOwner();
  }

  private async loadFavorites(context: common.UIAbilityContext, more: boolean): Promise<void> {
    if (this.disposed || this.removing || (more && (this.loading || this.loadingMore || !this.hasMore))) { return; }
    if (!more && this.loading) { return; }
    const account: string = this.favoriteOwner();
    if (account.length === 0 || account !== this.favoriteAccount) {
      this.favoriteRequest++;
      this.items = [];
      this.managing = false;
      this.selected = [];
      this.favoriteOffset = 0;
      this.hasMore = false;
      this.loadingMore = false;
    }
    this.favoriteAccount = account;
    if (account.length === 0) {
      this.errorText = '登录后可查看我的收藏';
      this.loadedOnce = true;
      return;
    }
    if (!more) { this.favoriteRequest++; this.loadingMore = false; }
    const request: number = this.favoriteRequest;
    // 服务端的翻页游标是条目偏移（`offset`），`pn` 它根本不看——2026-11-08 真机实测，
    // 详见 `TiebaApi.fetchStoredThreads`。游标永远从 0 起算，续页接着已取条数往后走。
    const offset: number = more ? this.favoriteOffset : 0;
    this.loading = !more;
    this.loadingMore = more;
    this.errorText = '';
    this.pagingError = '';
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!this.favoriteCurrent(request)) { return; }
      const session = authSession.session();
      const uid: number = await this.resolveUid(context, session);
      if (!this.favoriteCurrent(request)) { return; }
      if (uid <= 0) { throw new Error('暂时无法获取账号信息，请稍后重试'); }
      const res = await this.api.fetchStoredThreads(device, session, uid, offset, 20);
      if (!this.favoriteCurrent(request)) { return; }
      if (!res.ok) { throw new Error(res.describeFailure()); }
      const incoming: MyListItem[] = MyListVM.fromStored(res.data);
      const next: MyListItem[] = more ? this.items.slice() : [];
      const seen: Set<number> = new Set<number>();
      for (const item of next) { seen.add(item.tid); }
      let added: number = 0;
      for (const item of incoming) {
        if (item.tid > 0 && !seen.has(item.tid)) { next.push(item); seen.add(item.tid); added++; }
      }
      this.items = next;
      this.selected = this.selected.filter((tid: number) => seen.has(tid));
      // 游标按服务端实际回了几条推进（不是按去重后的条数），这样重复项不会把下一页顶回原处。
      this.favoriteOffset = offset + incoming.length;
      // 收藏信封没有可靠 has_more：非空且有新条目才继续探测，空页即到底。
      this.hasMore = added > 0;
      if (next.length === 0) { this.managing = false; }
      this.resolveAvatars(context).catch(() => {});
    } catch (err) {
      if (this.favoriteCurrent(request)) {
        if (more) { this.pagingError = (err as Error).message; }
        else { this.errorText = (err as Error).message; }
      }
    } finally {
      if (request === this.favoriteRequest) {
        this.loading = false; this.loadingMore = false; this.loadedOnce = true;
        if (this.favoriteAccount !== this.favoriteOwner()) {
          this.items = []; this.selected = []; this.hasMore = false;
          this.managing = false;
          this.errorText = '账号已变化，请重新加载收藏';
        }
      }
    }
  }

  toggleManaging(): void {
    if (this.disposed ||
      (!this.managing && (this.items.length === 0 || this.favoriteAccount !== this.favoriteOwner()))) { return; }
    if (this.removing) { this.stoppingRemoval = true; return; }
    this.managing = !this.managing;
    this.selected = [];
  }

  toggleSelected(tid: number): void {
    if (!this.managing || this.removing || this.disposed ||
      this.favoriteAccount !== this.favoriteOwner() || !this.items.some((item: MyListItem) => item.tid === tid)) { return; }
    this.selected = this.isSelected(tid) ? this.selected.filter((id: number) => id !== tid)
      : this.selected.concat([tid]);
  }

  isSelected(tid: number): boolean {
    if (this.selectedSnapshot !== this.selected) {
      this.selectedSnapshot = this.selected;
      this.selectedIndex = new Set<number>(this.selected);
    }
    return this.selectedIndex.has(tid);
  }

  allLoadedSelected(): boolean {
    return this.items.length > 0 && this.items.length === this.selected.length;
  }

  selectLoaded(): void {
    if (!this.managing || this.removing || this.loading || this.loadingMore ||
      this.disposed || this.favoriteAccount !== this.favoriteOwner()) { return; }
    this.selected = this.allLoadedSelected() ? [] : this.items.map((item: MyListItem) => item.tid);
  }

  selectionOwner(): string { return this.favoriteAccount; }

  /** 仅明确成功的条目移出列表；失败/超时保留，不自动重发。 */
  async removeSelected(context: common.UIAbilityContext, confirmed: number[], confirmedOwner: string): Promise<string> {
    if (this.removing || this.loading || this.loadingMore || this.disposed || !this.managing ||
      this.selected.length === 0 || this.favoriteAccount.length === 0 ||
      confirmedOwner !== this.favoriteAccount || this.favoriteAccount !== this.favoriteOwner() ||
      confirmed.length !== this.selected.length ||
      !confirmed.every((tid: number) => this.isSelected(tid))) { return ''; }
    this.removing = true;
    const request: number = ++this.favoriteRequest;
    const targets: number[] = confirmed.slice();
    const removed: Set<number> = new Set<number>();
    let failed: number = 0;
    try {
      const device = await DeviceIdentity.ensure(context);
      for (const tid of targets) {
        if (!this.favoriteCurrent(request)) { return ''; }
        if (this.stoppingRemoval) { break; }
        // 即使超时也可能已执行；这轮偏移分页必须从刷新重新建立。
        this.hasMore = false;
        try {
          const result = await this.api.removeStoreThread(device, authSession.session(), tid);
          if (!this.favoriteCurrent(request)) { return ''; }
          if (result.ok) {
            removed.add(tid);
          } else { failed++; }
        } catch (err) { failed++; }
      }
      if (!this.favoriteCurrent(request)) { return ''; }
      let message: string = `已取消${removed.size}条收藏`;
      if (failed > 0) { message += `，${failed}条结果未确认`; }
      const remaining: number = targets.length - removed.size - failed;
      if (remaining > 0) { message += `，已停止，${remaining}条未开始`; }
      return message;
    } catch (err) {
      return this.favoriteCurrent(request) ? '取消收藏未完成，请刷新核对' : '';
    } finally {
      this.stoppingRemoval = false;
      this.removing = false;
      if (this.favoriteAccount !== this.favoriteOwner()) {
        this.items = []; this.selected = []; this.hasMore = false;
        this.managing = false;
        this.errorText = '账号已变化，请重新加载收藏';
      } else if (this.favoriteCurrent(request) && removed.size > 0) {
        this.items = this.items.filter((item: MyListItem) => !removed.has(item.tid));
        this.selected = this.selected.filter((tid: number) => !removed.has(tid));
        if (this.selected.length === 0) { this.managing = false; }
      }
    }
  }

  dispose(): void {
    this.disposed = true;
    this.favoriteRequest++;
    this.replyRequest++;
  }

  private async loadReplies(context: common.UIAbilityContext, more: boolean): Promise<void> {
    if (this.disposed) { return; }
    const owner: string = authSession.sessionKey();
    const current = (): boolean => !this.disposed && request === this.replyRequest && owner === authSession.sessionKey();
    if (more && (this.loading || this.loadingMore || !this.hasMore)) {
      return;
    }
    if (!more && this.loading) {
      return;
    }
    if (!authSession.isLoggedIn()) {
      this.items = [];
      this.replyItems = [];
      this.hasMore = false;
      this.errorText = '登录后可查看我的回复';
      this.loadedOnce = true;
      return;
    }
    if (!more) {
      this.replyRequest++;
      this.loadingMore = false;
    }
    const request: number = this.replyRequest;
    const page: number = more ? this.replyPage + 1 : 1;
    this.loading = !more;
    this.loadingMore = more;
    this.errorText = '';
    this.pagingError = '';
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!current()) { return; }
      const session: TiebaSession = authSession.session();
      const uid: number = await this.resolveUid(context, session);
      if (!current()) { return; }
      if (uid <= 0) {
        throw new Error('暂时无法获取账号信息，请稍后重试');
      }
      const res: UserPostsResponse = await this.api.fetchUserPosts(device, session, uid, 0, page, 20);
      if (!current()) {
        return;
      }
      if (!res.ok) {
        throw new Error(res.describeFailure());
      }
      const oldCount: number = this.replyItems.length;
      this.replyItems = more ? mergeUserReplies(this.replyItems, res.data) : res.data;
      this.items = MyListVM.fromUserPosts(this.replyItems, false);
      this.replyPage = page;
      this.hasMore = res.hasMore && (!more || this.replyItems.length > oldCount);
      this.resolveAvatars(context).catch(() => {});
    } catch (err) {
      if (current()) {
        if (more) {
          this.pagingError = (err as Error).message;
        } else {
          this.errorText = (err as Error).message;
        }
      }
    } finally {
      if (request === this.replyRequest) {
        if (owner !== authSession.sessionKey()) { this.items = []; this.replyItems = []; this.hasMore = false; this.errorText = '账号已变化，请重新加载'; }
        this.loading = false;
        this.loadingMore = false;
        this.loadedOnce = true;
      }
    }
  }

  private async loadHistory(context: common.UIAbilityContext): Promise<void> {
    this.loading = true;
    try {
      const history: BrowseItem[] = await loadBrowseHistory(context);
      const out: MyListItem[] = [];
      for (const item of history) {
        const row: MyListItem = new MyListItem();
        row.tid = item.tid;
        row.title = item.title.length > 0 ? item.title : `帖子 ${item.tid}`;
        row.forumName = item.forumName;
        row.forumAvatar = item.forumAvatar;
        row.coverUrl = item.coverUrl;
        row.meta = item.timeMs > 0 ? formatRelativeTime(item.timeMs) : '';
        /*
         * 旧记录（加 `isDeleted` 字段之前存的）没有这个标记，但当时若帖子已不在，
         * 标题也是空的 → 这里补判一次，让老数据也能灰显。
         */
        row.isDeleted = item.isDeleted || item.title.length === 0;
        out.push(row);
      }
      this.items = out;
      this.resolveAvatars(context).catch(() => {
        // 头像补取失败不影响列表
      });
      this.verifyDeleted(context).catch(() => {
        // 存活性校验失败不影响列表
      });
    } finally {
      this.loading = false;
      this.loadedOnce = true;
    }
  }

  async clearHistory(context: common.UIAbilityContext): Promise<void> {
    await clearBrowseHistory(context);
    await this.loadHistory(context);
  }

  /**
   * 详情页调用：记一条浏览历史（本地，失败静默）。封面与吧头像由详情页从响应里取。
   *
   * `isDeleted` 由详情页在**记录时**判定（服务端既没给标题也没给吧名 = 帖子已不在），
   * 历史是本地记录，事后无法再问服务端，只能记下当时的判断。
   */
  static async record(context: common.UIAbilityContext, tid: number, title: string,
    forumName: string, coverUrl: string, forumAvatar: string,
    isDeleted: boolean = false, forumId: number = 0): Promise<void> {
    if (tid <= 0) {
      return;
    }
    const item: BrowseItem = new BrowseItem();
    item.tid = tid;
    item.title = title;
    item.forumName = forumName;
    item.coverUrl = coverUrl;
    item.forumAvatar = forumAvatar;
    item.isDeleted = isDeleted;
    item.timeMs = Date.now();

    // 顺手记下 fid（只在会话内存）：本页缺图时就能按 ID 走轻量端点，而不是按吧名拉整页。
    putForumAvatar(forumName, forumAvatar, forumId);
    await addBrowseHistory(context, item);
  }

  /**
   * 详情页调用：帖子已确认删除 → 把历史里对应那条标删（保留原标题等字段）。
   *
   * 历史里没有这条 tid 时不补记（`markBrowseDeleted` 返回 false）：
   * 删帖的响应里标题/吧名都是空的，硬记一条就是"只有 tid 的空行"，没有意义。
   */
  static async markDeleted(context: common.UIAbilityContext, tid: number): Promise<void> {
    if (tid <= 0) {
      return;
    }
    MyListVM.deletedCache.set(tid, true);
    await markBrowseDeleted(context, tid);
  }

  private static readonly MAX_DELETED_PROBE: number = 8;
  /** tid → 已删除（进程级，同一个 tid 整个会话只问一次） */
  private static deletedCache: Map<number, boolean> = new Map<number, boolean>();

  private async verifyDeleted(context: common.UIAbilityContext): Promise<void> {
    const todo: number[] = [];
    for (const item of this.items) {
      if (MyListVM.deletedCache.has(item.tid)) {
        item.isDeleted = MyListVM.deletedCache.get(item.tid) ?? false;
        continue;
      }
      /*
       * 已标删的也问一次：本地标记只是"当时的判断"（旧版本记录时标题为空就标了），
       * 服务端才是真相。命中缓存后同一 tid 整个会话只问一次，不构成轮询。
       */
      if (todo.length < MyListVM.MAX_DELETED_PROBE) {
        todo.push(item.tid);
      }
    }
    if (todo.length === 0) {
      this.refreshItems();
      return;
    }
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      const session = authSession.session();
      for (const tid of todo) {
        let deleted: boolean = false;
        try {
          deleted = await this.api.isThreadDeleted(device, session, tid);
        } catch (err) {
          // 单次失败不缓存结果：下次进页面还会再问，避免"一次没网就永久误判"
          continue;
        }
        // 删除成功后的标记优先于此前发出的存活探测。
        if (MyListVM.deletedCache.get(tid) !== true) { MyListVM.deletedCache.set(tid, deleted); }
        hilog.info(0x0000, 'MyListVM', 'alive tid=%{public}d deleted=%{public}s',
          tid, deleted ? 'y' : 'n');
      }
      for (const item of this.items) {
        if (MyListVM.deletedCache.has(item.tid)) {
          item.isDeleted = MyListVM.deletedCache.get(item.tid) ?? false;
        }
      }
      this.refreshItems();
    } catch (err) {
      // 设备指纹/会话失败就算了：列表照常显示
    }
  }

  /** 为缺少吧头像的条目补全头像，优先复用共享缓存；异步回调前检查当前账号与请求代次。 */
  private static readonly MAX_AVATAR_FETCH: number = 20;

  /** 正在重取的吧（图片加载失败自愈用，避免同一吧并发重取） */
  private retrying: Set<string> = new Set<string>();

  private async resolveAvatars(context: common.UIAbilityContext): Promise<void> {
    const needs: ForumAvatarNeed[] = [];
    for (const item of this.items) {
      if (item.forumName.length === 0 || item.forumAvatar.length > 0) { continue; }
      // 收藏条目自带 fid；历史条目没有，退到会话内记住的映射。都没有就按吧名查。
      const known: number = item.forumId > 0 ? item.forumId : getForumAvatarId(item.forumName);
      needs.push(new ForumAvatarNeed(item.forumName, known));
    }
    if (needs.length === 0) {
      this.refreshItems();
      return;
    }
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      const session = authSession.session();
      const plan: ForumAvatarBackfillPlan = new ForumAvatarBackfillPlan();
      plan.label = 'MyListVM';
      // 首屏 20 条以内：与原来的 MAX_AVATAR_FETCH 一致
      plan.maxFetch = MyListVM.MAX_AVATAR_FETCH;
      plan.stopped = (): boolean => this.disposed;
      // getforumdetail 优先、frs/page 回退，收敛在接口层（耗时由那里打点）。
      plan.fetch = async (name: string, forumId: number): Promise<string> =>
        this.api.fetchForumAvatar(device, session, name, forumId, 'mylist');
      plan.apply = (name: string, forumId: number, url: string): void => { this.applyAvatar(name, url); };
      await backfillForumAvatars(needs, plan);
      this.refreshItems();
    } catch (err) {
      // 设备指纹/会话失败就算了：列表照常显示，头像用首字占位
    }
  }

  /**
   * 图片加载失败后的自愈（方案 2 的兜底）：丢掉落盘 URL 与进程内缓存，重新取一次。
   *
   * 落盘 URL 在 TTL 内不请求，但服务端签名可能提前失效；如果失败后不给它一条
   * "作废并重取"的路，那一行就会一直停在文字兜底（文档 §1.3 记过这个坑）。
   * 同一吧在途时不重入，避免图片反复失败把请求打爆。
   */
  async retryAvatar(context: common.UIAbilityContext, forumName: string): Promise<void> {
    const name: string = forumName.trim();
    if (name.length === 0 || this.disposed || this.retrying.has(name)) {
      return;
    }
    this.retrying.add(name);
    try {
      forgetCachedForumAvatar(name);
      let touched: boolean = false;
      for (const item of this.items) {
        if (item.forumName === name && item.forumAvatar.length > 0) {
          item.forumAvatar = '';
          touched = true;
        }
      }
      if (touched) { this.refreshItems(); }
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      const known: number = getForumAvatarId(name);
      const avatar: string = await this.api.fetchForumAvatar(device, authSession.session(), name, known, 'mylist-retry');
      if (this.disposed || avatar.length === 0) {
        return;
      }
      putForumAvatar(name, avatar, known);
      this.applyAvatar(name, avatar);
    } catch (err) {
      hilog.info(0x0000, 'MyListVM', 'avatar retry %{public}s threw %{public}s', name, (err as Error).message);
    } finally {
      this.retrying.delete(name);
    }
  }

  /** 把一个吧的头像写进所有同名行并立刻整体替换 `items`（触发刷新；逐条上屏用） */
  private applyAvatar(forumName: string, avatarUrl: string): void {
    if (this.disposed || avatarUrl.length === 0) { return; }
    let touched: boolean = false;
    for (const item of this.items) {
      if (item.forumAvatar.length === 0 && item.forumName === forumName) {
        item.forumAvatar = avatarUrl;
        touched = true;
      }
    }
    if (touched) { this.refreshItems(); }
  }

  /** 整体替换 items 触发刷新（保序） */
  private refreshItems(): void {
    const next: MyListItem[] = [];
    for (const item of this.items) {
      next.push(item);
    }
    this.items = next;
  }

  /**
   * 真实 uid（`User.id`）。
   *
   * 优先用 `authSession.snapshot.uid`（"我的"页显示的就是它）；
   * 它是**异步**回填的，为 0 时退到 pb 资料通道现取一次（与 `MineProbe` 同路径）。
   */
  private async resolveUid(context: common.UIAbilityContext, session: TiebaSession): Promise<number> {
    const snapshotUid: number = authSession.snapshot.uid;
    if (snapshotUid > 0) {
      return snapshotUid;
    }
    const base: UserProfileInfo = await this.api.fetchUserInfo(session);
    const device: TiebaDevice = await DeviceIdentity.ensure(context);
    const self: UserProfileInfo | undefined =
      await this.api.fetchSelfProfile(session, device, base.portrait);
    return self === undefined ? 0 : self.uid;
  }

  private static fromStored(list: StoredThread[]): MyListItem[] {
    const out: MyListItem[] = [];
    for (const it of list) {
      const row: MyListItem = new MyListItem();
      row.tid = it.tid;
      row.title = it.title.length > 0 ? it.title : `帖子 ${it.tid}`;
      row.forumName = it.forumName;
      row.coverUrl = it.coverUrl;
      row.isDeleted = it.isDeleted;
      row.meta = it.authorName.length > 0 ? `${it.authorName} · ${it.replyNum} 回复`
        : `${it.replyNum} 回复`;
      out.push(row);
    }
    return out;
  }

  private static fromUserPosts(list: UserPostItem[], isThread: boolean): MyListItem[] {
    const out: MyListItem[] = [];
    for (const it of list) {
      const row: MyListItem = new MyListItem();
      row.tid = it.tid;
      row.pid = it.pid;
      row.key = isThread ? String(it.tid) : userReplyKey(it);
      row.pieces = it.pieces;
      row.isComment = !isThread && it.isComment;
      // 回复正文与来源帖标题分开，不再把正文伪装为标题。
      row.title = it.title;
      row.content = it.content;
      row.forumName = it.forumName;
      if (isThread) {
        row.forumId = it.forumId;
        row.postedTime = formatTimeText(it.createTimeMs, Date.now());
        row.images = it.images;
        row.originImages = it.originImages;
        row.agreeCount = it.agreeNum;
        row.replyCount = it.replyNum;
        row.shareCount = it.shareNum;
      }
      const parts: string[] = [];
      if (isThread && it.authorName.length > 0) {
        parts.push(it.authorName);
      }
      if (isThread && it.replyNum > 0) {
        parts.push(`${it.replyNum} 回复`);
      }
      if (it.createTimeMs > 0) {
        parts.push(formatRelativeTime(it.createTimeMs));
      }
      row.meta = parts.join(' · ');
      row.hideFromProfile = isThread && it.hideFromProfile;
      out.push(row);
    }
    return out;
  }
}

/**
 * 相对时间：今天 → `HH:MM`，昨天 → `昨天`，更早 → `M-D`。
 *
 * 只做展示用，**不参与排序**（列表顺序以服务端为准）。
 */
function formatRelativeTime(timeMs: number): string {
  const now: Date = new Date();
  const then: Date = new Date(timeMs);
  const sameDay: boolean = now.getFullYear() === then.getFullYear()
    && now.getMonth() === then.getMonth()
    && now.getDate() === then.getDate();
  if (sameDay) {
    const hh: string = `${then.getHours()}`.padStart(2, '0');
    const mm: string = `${then.getMinutes()}`.padStart(2, '0');
    return `${hh}:${mm}`;
  }
  const yesterday: Date = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  const isYesterday: boolean = yesterday.getFullYear() === then.getFullYear()
    && yesterday.getMonth() === then.getMonth()
    && yesterday.getDate() === then.getDate();
  if (isYesterday) {
    return '昨天';
  }
  return `${then.getMonth() + 1}-${then.getDate()}`;
}
