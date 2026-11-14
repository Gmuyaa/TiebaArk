/**
 * 会话内共享吧头像缓存，复用列表、详情和浏览历史中已经取得的头像 URL。
 *
 * 2026-11-13：除 URL 外再记一份「吧名 → fid」（同样只在内存）。反查吧头像时已知 fid
 * 就能走更轻的 `getforumdetail`（见 `api/TiebaApi.fetchForumAvatar`），不必按吧名拉整页
 * `frs/page`。fid 来自各响应本来就会带的 `forum.id`，不额外请求。
 */

import { forumAvatarCache } from './ForumAvatarCache';

/** 上限：吧数量远小于帖子量，512 足够覆盖重度使用一整天的吧 */
const MAX_ENTRIES: number = 512;

const avatars: Map<string, string> = new Map();

/** 吧名 → fid（会话内已知的吧 ID；0/未记 = 不知道） */
const ids: Map<string, number> = new Map();

const fetched: Set<string> = new Set();

/** 插入新键前按插入序淘汰最早的一条（同名覆盖不更新插入序，可接受） */
function evictAvatarIfFull(key: string): void {
  if (!avatars.has(key) && avatars.size >= MAX_ENTRIES) {
    const oldest: IteratorResult<string> = avatars.keys().next();
    if (!oldest.done) {
      avatars.delete(oldest.value);
    }
  }
}

/** 同上，fid 表用；两张表各自守自己的上限 */
function evictIdIfFull(key: string): void {
  if (!ids.has(key) && ids.size >= MAX_ENTRIES) {
    const oldest: IteratorResult<string> = ids.keys().next();
    if (!oldest.done) {
      ids.delete(oldest.value);
    }
  }
}

/**
 * 回填一个吧的头像（空名忽略；同名覆盖为最新值）。
 * 各回填点（frs/page、详情页、浏览历史预热、反查队列）都调它，幂等。
 *
 * @param forumId 已知的吧 ID；>0 时顺带记住，供之后按 ID 走轻量反查。
 */
export function putForumAvatar(forumName: string, avatarUrl: string, forumId: number = 0): void {
  const name: string = forumName.trim();
  if (name.length === 0) {
    return;
  }
  // 落盘索引（fid + URL + 写入时刻）由这里统一记账，读回时机见 utils/ForumAvatarPrefs。
  forumAvatarCache.remember(name, forumId, avatarUrl, Date.now());
  if (Number.isSafeInteger(forumId) && forumId > 0) {
    evictIdIfFull(name);
    ids.set(name, forumId);
  }
  const url: string = avatarUrl.trim();
  if (url.length === 0) {
    return;
  }
  evictAvatarIfFull(name);
  avatars.set(name, url);
}

/** 查一个吧的头像；没缓存过返回空串（调用方回退文字头像） */
export function getForumAvatar(forumName: string): string {
  const name: string = forumName.trim();
  if (name.length === 0) {
    return '';
  }
  return avatars.get(name) ?? '';
}

/** 查一个吧的 fid：先看本会话表，再回落盘索引（跨会话学到过的）；都没有返回 0（按吧名反查） */
export function getForumAvatarId(forumName: string): number {
  const name: string = forumName.trim();
  if (name.length === 0) {
    return 0;
  }
  const session: number | undefined = ids.get(name);
  if (session !== undefined && session > 0) {
    return session;
  }
  return forumAvatarCache.fidOf(name);
}

/** 可复用的落盘头像 URL（按 TTL 判新鲜；过期/没有返回空串，调用方重新请求一次） */
export function getCachedForumAvatarUrl(forumName: string, nowMs: number, ttlMs: number): string {
  return forumAvatarCache.urlOf(forumName, nowMs, ttlMs);
}

/**
 * 从网络**刚确认**到的地址：写会话表，并把落盘索引的写入时刻刷新到"现在"。
 *
 * 与 `putForumAvatar` 的区别只在时间戳：把落盘值读出来重新写回时必须走 `putForumAvatar`
 * （不续命），否则每读一次就把 TTL 往后推，永远不过期。
 */
export function recordFetchedForumAvatar(forumName: string, avatarUrl: string, forumId: number = 0): void {
  const name: string = forumName.trim();
  if (name.length === 0) {
    return;
  }
  forumAvatarCache.remember(name, forumId, avatarUrl, Date.now(), true);
  if (Number.isSafeInteger(forumId) && forumId > 0) {
    evictIdIfFull(name);
    ids.set(name, forumId);
  }
  const url: string = avatarUrl.trim();
  if (url.length === 0) {
    return;
  }
  evictAvatarIfFull(name);
  avatars.set(name, url);
}

/** 丢弃某个吧的落盘头像 URL（图片加载失败时用，避免该行被过期地址钉住） */
export function forgetCachedForumAvatar(forumName: string): void {
  forumAvatarCache.forget(forumName);
}

/** 当前缓存条数（诊断 / 测试用） */
export function forumAvatarCount(): number {
  return avatars.size;
}

/** 记下"这个吧本次会话已经真正查过一次"（成功拿到头像后由队列调用）。 */
export function markForumAvatarFetched(forumName: string): void {
  const name: string = forumName.trim();
  if (name.length > 0) { fetched.add(name); }
}

/** 这个吧本次会话是否已经真正查过一次（列表据此决定要不要再查） */
export function isForumAvatarFetched(forumName: string): boolean {
  const name: string = forumName.trim();
  return name.length > 0 && fetched.has(name);
}

/** 清空（Node 用例隔离用；生产链路不调） */
export function clearForumAvatars(): void {
  avatars.clear();
  ids.clear();
  fetched.clear();
  // 落盘索引也要清：否则用例之间会互相看到上一条用例学到的 fid。
  forumAvatarCache.clear();
}
