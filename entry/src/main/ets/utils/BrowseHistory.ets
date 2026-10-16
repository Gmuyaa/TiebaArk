/** 浏览历史的本地持久化；同一帖子合并已有字段，并按保留策略控制数量。 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'tieba_browse_history';
const KEY_HISTORY: string = 'items';

/** 历史上限。超出后从最旧的（尾部）开始淘汰 */
export const BROWSE_HISTORY_MAX: number = 200;

/** 一条浏览记录 */
export class BrowseItem {
  tid: number = 0;
  title: string = '';
  forumName: string = '';
  /** 浏览时间（毫秒） */
  timeMs: number = 0;

  coverUrl: string = '';
  /** 吧头像完整地址（详情响应 `forum.avatar` 就是完整 URL，见 `model/ThreadDetail.ets`） */
  forumAvatar: string = '';
  /** 记录时服务端就没给标题与吧名 → 帖子已删除/屏蔽。本地记录事后无法再问服务端 */
  isDeleted: boolean = false;
}

interface RawBrowseItem {
  tid?: number;
  title?: string;
  forumName?: string;
  timeMs?: number;
  coverUrl?: string;
  forumAvatar?: string;
  isDeleted?: boolean;
}

/** 读取全部历史（最近在前）。读不到/格式不对一律返回空数组，不让界面崩 */
export async function loadBrowseHistory(context: common.UIAbilityContext): Promise<BrowseItem[]> {
  try {
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
    const raw: string = (await store.get(KEY_HISTORY, '')) as string;
    if (raw.length === 0) {
      return [];
    }
    const parsed: RawBrowseItem[] = JSON.parse(raw) as RawBrowseItem[];
    const items: BrowseItem[] = [];
    for (const item of parsed) {
      if (item === null || item === undefined) {
        continue;
      }
      const tid: number = item.tid ?? 0;
      if (tid <= 0) {
        continue;
      }
      const out: BrowseItem = new BrowseItem();
      out.tid = tid;
      out.title = item.title ?? '';
      out.forumName = item.forumName ?? '';
      out.timeMs = item.timeMs ?? 0;
      out.coverUrl = item.coverUrl ?? '';
      out.forumAvatar = item.forumAvatar ?? '';
      out.isDeleted = item.isDeleted ?? false;
      items.push(out);
    }
    return items;
  } catch {
    return [];
  }
}

/** 重复记录同一帖子时，空字段不覆盖已有值，保留已知的标题、吧名与头像。 */
export function mergeBrowseEntry(existing: BrowseItem, incoming: BrowseItem): BrowseItem {
  const out: BrowseItem = new BrowseItem();
  out.tid = incoming.tid;
  out.timeMs = incoming.timeMs;
  out.title = incoming.title.length > 0 ? incoming.title : existing.title;
  out.forumName = incoming.forumName.length > 0 ? incoming.forumName : existing.forumName;
  out.coverUrl = incoming.coverUrl.length > 0 ? incoming.coverUrl : existing.coverUrl;
  out.forumAvatar = incoming.forumAvatar.length > 0 ? incoming.forumAvatar : existing.forumAvatar;
  out.isDeleted = incoming.title.length > 0 ? false : (incoming.isDeleted || existing.isDeleted);
  return out;
}

/**
 * 记录一次浏览：去重置顶 + 上限淘汰，返回**更新后的完整历史**。
 *
 * 返回值给界面直接刷新用（详情页不刷界面，所以调用方通常忽略返回值）。
 *
 * 同一个 tid 已存在时**不整条替换**，走 `mergeBrowseEntry` 逐字段合并
 * （旧的非空值不会被新的空值擦掉），合并后同样置顶。
 */
export async function addBrowseHistory(context: common.UIAbilityContext,
  item: BrowseItem): Promise<BrowseItem[]> {
  if (item.tid <= 0) {
    return loadBrowseHistory(context);
  }
  const history: BrowseItem[] = await loadBrowseHistory(context);
  let merged: BrowseItem | undefined = undefined;
  const updated: BrowseItem[] = [];
  for (const it of history) {
    if (it.tid === item.tid) {
      merged = mergeBrowseEntry(it, item);
    } else {
      updated.push(it);
    }
  }
  // 重看过的这条排到最前（与改动前"去重置顶"的语义一致）
  if (merged !== undefined) {
    updated.unshift(merged);
  } else {
    updated.unshift(item);
  }
  while (updated.length > BROWSE_HISTORY_MAX) {
    updated.pop();
  }
  try {
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
    await store.put(KEY_HISTORY, JSON.stringify(updated));
    await store.flush();
  } catch {
    // 写失败不影响浏览本身：本次会话内界面仍有 updated，下次启动可能少一条
  }
  return updated;
}

export async function markBrowseDeleted(context: common.UIAbilityContext,
  tid: number): Promise<boolean> {
  if (tid <= 0) {
    return false;
  }
  const history: BrowseItem[] = await loadBrowseHistory(context);
  let hit: boolean = false;
  for (const item of history) {
    if (item.tid === tid) {
      item.isDeleted = true;
      hit = true;
      break;
    }
  }
  if (!hit) {
    return false;
  }
  try {
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
    await store.put(KEY_HISTORY, JSON.stringify(history));
    await store.flush();
  } catch {
    // 写失败不影响展示：本次会话内界面已按新值渲染
  }
  return true;
}

/** 清空全部浏览历史 */
export async function clearBrowseHistory(context: common.UIAbilityContext): Promise<void> {
  try {
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
    await store.put(KEY_HISTORY, '');
    await store.flush();
  } catch {
    // 同上：存储失败不抛给界面
  }
}
