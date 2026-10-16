

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'tieba_browse_history';
const KEY_HISTORY: string = 'items';

export const BROWSE_HISTORY_MAX: number = 200;

export class BrowseItem {
  tid: number = 0;
  title: string = '';
  forumName: string = '';

  timeMs: number = 0;

  coverUrl: string = '';

  forumAvatar: string = '';

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

  }
  return true;
}

export async function clearBrowseHistory(context: common.UIAbilityContext): Promise<void> {
  try {
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
    await store.put(KEY_HISTORY, '');
    await store.flush();
  } catch {

  }
}
