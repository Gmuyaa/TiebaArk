/** 会话内共享吧头像缓存，复用列表、详情和浏览历史中已经取得的头像 URL。 */

/** 上限：吧数量远小于帖子量，512 足够覆盖重度使用一整天的吧 */
const MAX_ENTRIES: number = 512;

const avatars: Map<string, string> = new Map();

const fetched: Set<string> = new Set();

/**
 * 回填一个吧的头像（空名 / 空 URL 忽略；同名覆盖为最新值）。
 * 各回填点（frs/page、详情页、浏览历史预热）都调它，幂等。
 */
export function putForumAvatar(forumName: string, avatarUrl: string): void {
  const name: string = forumName.trim();
  const url: string = avatarUrl.trim();
  if (name.length === 0 || url.length === 0) {
    return;
  }
  if (!avatars.has(name) && avatars.size >= MAX_ENTRIES) {
    // 淘汰最早插入的一条（Map 迭代序 = 插入序；同名覆盖不更新插入序，可接受）
    const oldest: IteratorResult<string> = avatars.keys().next();
    if (!oldest.done) {
      avatars.delete(oldest.value);
    }
  }
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
  fetched.clear();
}
