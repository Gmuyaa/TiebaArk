/** 从浏览历史提取最近浏览过的帖子所属吧，供进吧页「我的足迹」展示。 */

export const RECENT_FORUMS_MAX: number = 20;

export interface RecentForumSource {
  forumName: string;
  forumAvatar: string;
  timeMs: number;
}

export class RecentForumItem {
  forumName: string = '';
  avatar: string = '';
  lastVisitMs: number = 0;

  static copy(item: RecentForumItem): RecentForumItem {
    const out: RecentForumItem = new RecentForumItem();
    out.forumName = item.forumName;
    out.avatar = item.avatar;
    out.lastVisitMs = item.lastVisitMs;
    return out;
  }
}

export function displayForumName(forumName: string): string {
  const name: string = forumName.trim();
  if (name.length === 0) {
    return '';
  }
  return name.endsWith('吧') ? name : `${name}吧`;
}

export function buildRecentForums(
  history: RecentForumSource[],
  limit: number = RECENT_FORUMS_MAX,
  avatarLookup?: (forumName: string) => string
): RecentForumItem[] {
  if (limit <= 0 || history.length === 0) {
    return [];
  }
  const ordered: RecentForumSource[] = history.slice().sort(
    (a: RecentForumSource, b: RecentForumSource): number => b.timeMs - a.timeMs
  );
  const byName: Map<string, RecentForumItem> = new Map<string, RecentForumItem>();
  const result: RecentForumItem[] = [];
  for (const entry of ordered) {
    const name: string = entry.forumName.trim();
    if (name.length === 0) {
      continue;
    }
    const existing: RecentForumItem | undefined = byName.get(name);
    if (existing !== undefined) {
      // 较新记录缺头像时，借同吧较旧记录已有的头像补齐。
      if (existing.avatar.length === 0 && entry.forumAvatar.trim().length > 0) {
        existing.avatar = entry.forumAvatar.trim();
      }
      continue;
    }
    if (result.length >= limit) {
      continue;
    }
    const item: RecentForumItem = new RecentForumItem();
    item.forumName = name;
    item.lastVisitMs = entry.timeMs;
    const known: string = avatarLookup !== undefined ? avatarLookup(name).trim() : '';
    item.avatar = known.length > 0 ? known : entry.forumAvatar.trim();
    byName.set(name, item);
    result.push(item);
  }
  return result;
}

function estimateCapsuleWidth(forumName: string): number {
  const label: string = displayForumName(forumName);
  let width: number = 46;
  for (let i: number = 0; i < label.length; i++) {
    width += label.charCodeAt(i) <= 0x7F ? 8 : 14;
  }
  return width;
}

/** 胶囊布局下将「我的足迹」按估算宽度平衡分到两行，保持最近访问靠左且两行末尾接近对齐。 */
export function splitRecentTwoRows(items: RecentForumItem[]): RecentForumItem[][] {
  if (items.length === 0) {
    return [[], []];
  }
  if (items.length <= 2) {
    return [items.slice(), []];
  }
  const top: RecentForumItem[] = [];
  const bottom: RecentForumItem[] = [];
  let topWidth: number = 0;
  let bottomWidth: number = 0;
  for (let i: number = 0; i < items.length; i++) {
    const item: RecentForumItem = items[i];
    const w: number = estimateCapsuleWidth(item.forumName);
    if (topWidth <= bottomWidth) {
      top.push(item);
      topWidth += w;
    } else {
      bottom.push(item);
      bottomWidth += w;
    }
  }
  return [top, bottom];
}
