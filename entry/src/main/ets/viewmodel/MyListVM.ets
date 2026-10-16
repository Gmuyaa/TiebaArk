

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { authSession } from '../auth/AuthSession';
import { TiebaApi, UserPostsResponse } from '../api/TiebaApi';
import { mergeUserReplies, StoredThread, UserPostItem, userReplyKey } from '../model/MyContent';
import { ContentPiece } from '../model/ThreadDetail';
import { UserProfileInfo } from '../model/UserProfile';
import { TiebaDevice, TiebaSession } from '../net/TiebaParams';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import {
  addBrowseHistory, BrowseItem, clearBrowseHistory, loadBrowseHistory, markBrowseDeleted
} from '../utils/BrowseHistory';
import { putForumAvatar } from '../model/ForumAvatarStore';

export type MyListKind = 'history' | 'fav' | 'reply' | 'thread';

export function parseKind(raw: string): MyListKind {
  if (raw === 'fav' || raw === 'reply' || raw === 'thread') {
    return raw;
  }
  return 'history';
}

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

export class MyListItem {
  key: string = '';
  pid: number = 0;
  pieces: ContentPiece[] = [];
  isComment: boolean = false;
  tid: number = 0;
  title: string = '';

  content: string = '';
  forumName: string = '';

  forumAvatar: string = '';

  coverUrl: string = '';

  meta: string = '';

  isDeleted: boolean = false;
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
  @Trace manageNotice: string = '';

  private favoritePage: number = 0;
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
      this.selected = [];
      this.favoritePage = 0;
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
    const page: number = more ? this.favoritePage + 1 : 1;
    this.loading = !more;
    this.loadingMore = more;
    this.errorText = '';
    this.pagingError = '';
    this.manageNotice = '';
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!this.favoriteCurrent(request)) { return; }
      const session = authSession.session();
      const uid: number = await this.resolveUid(context, session);
      if (!this.favoriteCurrent(request)) { return; }
      if (uid <= 0) { throw new Error('暂时无法获取账号信息，请稍后重试'); }
      const res = await this.api.fetchStoredThreads(device, session, uid, page, 20);
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
      this.favoritePage = page;

      this.hasMore = added > 0;
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
          this.errorText = '账号已变化，请重新加载收藏';
        }
      }
    }
  }

  toggleManaging(): void {
    if (this.removing) { return; }
    this.managing = !this.managing;
    this.selected = [];
    this.manageNotice = '';
  }

  toggleSelected(tid: number): void {
    if (!this.managing || this.removing || !this.items.some((item: MyListItem) => item.tid === tid)) { return; }
    this.selected = this.selected.includes(tid) ? this.selected.filter((id: number) => id !== tid)
      : this.selected.concat([tid]);
  }

  selectLoaded(): void {
    if (!this.managing || this.removing) { return; }
    this.selected = this.items.length === this.selected.length ? [] : this.items.map((item: MyListItem) => item.tid);
  }

  selectionOwner(): string { return this.favoriteAccount; }

  async removeSelected(context: common.UIAbilityContext, confirmed: number[], confirmedOwner: string): Promise<void> {
    if (this.removing || this.loading || this.loadingMore || this.disposed || !this.managing ||
      this.selected.length === 0 || this.favoriteAccount.length === 0 ||
      confirmedOwner !== this.favoriteAccount || this.favoriteAccount !== this.favoriteOwner() ||
      confirmed.length !== this.selected.length ||
      !confirmed.every((tid: number) => this.selected.includes(tid))) { return; }
    this.removing = true;
    const request: number = ++this.favoriteRequest;
    const targets: number[] = confirmed.slice();
    let removed: number = 0;
    let failed: number = 0;
    this.manageNotice = '';
    try {
      const device = await DeviceIdentity.ensure(context);
      for (const tid of targets) {
        if (!this.favoriteCurrent(request)) { return; }

        this.hasMore = false;
        try {
          const result = await this.api.removeStoreThread(device, authSession.session(), tid);
          if (!this.favoriteCurrent(request)) { return; }
          if (result.ok) {
            this.items = this.items.filter((item: MyListItem) => item.tid !== tid);
            this.selected = this.selected.filter((id: number) => id !== tid);
            removed++;

          } else { failed++; }
        } catch (err) { failed++; }
      }
      this.manageNotice = `已取消 ${removed} 条收藏` + (failed > 0
        ? `，${failed} 条结果未确认，已保留；请刷新核对后再操作` : '，下拉刷新可继续加载');
    } catch (err) {
      if (this.favoriteCurrent(request)) { this.manageNotice = '取消收藏未完成，请刷新核对后再操作'; }
    } finally {
      this.removing = false;
      if (this.favoriteAccount !== this.favoriteOwner()) {
        this.items = []; this.selected = []; this.hasMore = false;
        this.errorText = '账号已变化，请重新加载收藏';
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

        row.isDeleted = item.isDeleted || item.title.length === 0;
        out.push(row);
      }
      this.items = out;
      this.resolveAvatars(context).catch(() => {

      });
      this.verifyDeleted(context).catch(() => {

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

  static async record(context: common.UIAbilityContext, tid: number, title: string,
    forumName: string, coverUrl: string, forumAvatar: string,
    isDeleted: boolean = false): Promise<void> {
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

    putForumAvatar(forumName, forumAvatar);
    await addBrowseHistory(context, item);
  }

  static async markDeleted(context: common.UIAbilityContext, tid: number): Promise<void> {
    if (tid <= 0) {
      return;
    }
    await markBrowseDeleted(context, tid);
  }

  private static readonly MAX_DELETED_PROBE: number = 8;

  private static deletedCache: Map<number, boolean> = new Map<number, boolean>();

  private async verifyDeleted(context: common.UIAbilityContext): Promise<void> {
    const todo: number[] = [];
    for (const item of this.items) {
      if (MyListVM.deletedCache.has(item.tid)) {
        item.isDeleted = MyListVM.deletedCache.get(item.tid) ?? false;
        continue;
      }

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

          continue;
        }
        MyListVM.deletedCache.set(tid, deleted);
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

    }
  }

  private static readonly MAX_AVATAR_FETCH: number = 20;

  private static readonly AVATAR_CONCURRENCY: number = 3;

  private static avatarCache: Map<string, string> = new Map<string, string>();

  private async resolveAvatars(context: common.UIAbilityContext): Promise<void> {
    const todo: string[] = [];
    for (const item of this.items) {
      if (item.forumName.length === 0 || item.forumAvatar.length > 0) {
        continue;
      }
      if (MyListVM.avatarCache.has(item.forumName)) {
        item.forumAvatar = MyListVM.avatarCache.get(item.forumName) ?? '';
      } else if (todo.length < MyListVM.MAX_AVATAR_FETCH && !todo.includes(item.forumName)) {
        todo.push(item.forumName);
      }
    }
    if (todo.length === 0) {
      this.refreshItems();
      return;
    }
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      const session = authSession.session();
      let next: number = 0;
      const worker = async (): Promise<void> => {
        while (next < todo.length) {
          if (this.disposed) { return; }
          const name: string = todo[next++];
          if (MyListVM.avatarCache.has(name)) { continue; }
          let avatar: string = '';
          try {
            const res = await this.api.fetchThreadList(device, session, name, 1, 1);
            avatar = res.ok ? res.data.forum.avatar : '';
            hilog.info(0x0000, 'MyListVM', 'avatar %{public}s ok=%{public}s avatarLen=%{public}d err=%{public}s',
              name, res.ok ? 'y' : 'n', avatar.length, res.ok ? '' : res.describeFailure());
          } catch (err) {
            hilog.info(0x0000, 'MyListVM', 'avatar %{public}s threw %{public}s', name, (err as Error).message);
          }
          if (avatar.length > 0) { MyListVM.avatarCache.set(name, avatar); }
          if (avatar.length > 0) {

            putForumAvatar(name, avatar);
            this.applyAvatar(name, avatar);
          }
        }
      };
      const workers: Promise<void>[] = [];
      const width: number = Math.min(MyListVM.AVATAR_CONCURRENCY, todo.length);
      for (let i: number = 0; i < width; i++) { workers.push(worker()); }
      await Promise.all(workers);
      this.refreshItems();
    } catch (err) {

    }
  }

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

  private refreshItems(): void {
    const next: MyListItem[] = [];
    for (const item of this.items) {
      next.push(item);
    }
    this.items = next;
  }

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
      hilog.info(0x0000, 'MyListVM', 'fav tid=%{public}d deleted=%{public}s titleLen=%{public}d',
        it.tid, it.isDeleted ? 'y' : 'n', it.title.length);
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
      row.pid = isThread ? 0 : it.pid;
      row.key = isThread ? String(it.tid) : userReplyKey(it);
      row.pieces = isThread ? [] : it.pieces;
      row.isComment = !isThread && it.isComment;

      row.title = isThread && it.title.length > 0 ? it.title
        : (isThread ? (it.content.length > 0 ? it.content : `帖子 ${it.tid}`) : it.title);
      row.content = it.content;
      row.forumName = it.forumName;
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
      out.push(row);
    }
    return out;
  }
}

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
