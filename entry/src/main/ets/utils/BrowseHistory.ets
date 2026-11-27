/** 浏览历史的账号隔离持久化；同一帖子合并已有字段，并按保留策略控制数量。 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { authSession } from '../auth/AuthSession';
import { BROWSE_HISTORY_MAX_ACCOUNTS } from '../model/CachePolicy';

const STORE_NAME: string = 'tieba_browse_history';
const KEY_LEGACY_HISTORY: string = 'items';
const KEY_BUCKET_INDEX: string = 'buckets_v1';
const KEY_ACCOUNT_PREFIX: string = 'items_acct_';

// 所有读改写共用队列，清空也必须排在已开始的写入之后。
let historyWrite: Promise<void> = Promise.resolve();
function enqueueHistory<T>(write: () => Promise<T>): Promise<T> {
  const pending: Promise<T> = historyWrite.then(write, write);
  historyWrite = pending.then((): void => {}, (): void => {});
  return pending;
}

/** 历史上限。超出后从最旧的（尾部）开始淘汰 */
export const BROWSE_HISTORY_MAX: number = 200;

function currentAccountKey(explicit?: string): string {
  if (explicit !== undefined) {
    const trimmed: string = explicit.trim();
    return trimmed.length > 0 ? trimmed : 'guest';
  }
  if (!authSession.isLoggedIn()) { return 'guest'; }
  const uid: number = authSession.snapshot.uid;
  if (Number.isSafeInteger(uid) && uid > 0) { return `u_${uid}`; }
  const forumUid: number = authSession.forumCacheUid();
  if (Number.isSafeInteger(forumUid) && forumUid > 0) { return `u_${forumUid}`; }
  const portrait: string = authSession.snapshot.portrait.trim();
  if (portrait.length > 0) { return `p_${portrait}`; }
  const userName: string = authSession.snapshot.userName.trim();
  if (userName.length > 0) { return `n_${userName}`; }
  return 'logged_in';
}

function storageKeyOf(account: string): string {
  return `${KEY_ACCOUNT_PREFIX}${account}`;
}

async function readBucketIndex(store: preferences.Preferences): Promise<string[]> {
  try {
    const raw: string = (await store.get(KEY_BUCKET_INDEX, '')) as string;
    if (raw.length === 0) { return []; }
    const parsed: string[] = JSON.parse(raw) as string[];
    if (!Array.isArray(parsed)) { return []; }
    return parsed.filter((item: string): boolean => typeof item === 'string' && item.length > 0);
  } catch {
    return [];
  }
}

async function touchAccountBucket(store: preferences.Preferences, account: string): Promise<void> {
  const index: string[] = await readBucketIndex(store);
  const updated: string[] = index.filter((item: string): boolean => item !== account);
  updated.unshift(account);
  while (updated.length > BROWSE_HISTORY_MAX_ACCOUNTS) {
    const evicted: string | undefined = updated.pop();
    if (evicted !== undefined && evicted.length > 0) {
      try {
        await store.put(storageKeyOf(evicted), '');
      } catch {
        // 清理旧桶失败不阻塞当前写入
      }
    }
  }
  await store.put(KEY_BUCKET_INDEX, JSON.stringify(updated));
}

async function readRawForAccount(store: preferences.Preferences, account: string): Promise<string> {
  const key: string = storageKeyOf(account);
  const raw: string = (await store.get(key, '')) as string;
  if (raw.length > 0) {
    return raw;
  }
  // 升级兼容：首次按账号读取时把旧全局键迁入当前账号桶，避免丢失已有历史与足迹。
  const legacy: string = (await store.get(KEY_LEGACY_HISTORY, '')) as string;
  if (legacy.length > 0) {
    try {
      await store.put(key, legacy);
      await store.put(KEY_LEGACY_HISTORY, '');
      await touchAccountBucket(store, account);
      await store.flush();
    } catch {
      // 迁移写失败仍先返回旧数据供本次展示
    }
    return legacy;
  }
  return '';
}

@ObservedV2
export class BrowseHistoryChanges {
  @Trace revision: number = 0;
}

export const browseHistoryChanges: BrowseHistoryChanges = new BrowseHistoryChanges();

export class BrowseItem {
  tid: number = 0;
  title: string = '';
  forumName: string = '';
  timeMs: number = 0;

  coverUrl: string = '';
  coverIsGif: boolean = false;
  /** 吧头像完整地址（详情响应 `forum.avatar` 就是完整 URL，见 `model/ThreadDetail.ets`） */
  forumAvatar: string = '';
  /** 记录时服务端就没给标题与吧名 → 帖子已删除/屏蔽。本地记录事后无法再问服务端 */
  isDeleted: boolean = false;
  lastFloor: number = 0;
  lastPid: number = 0;
}

export class BrowseProgress {
  floor: number = 0;
  pid: number = 0;
}

interface RawBrowseItem {
  tid?: number;
  title?: string;
  forumName?: string;
  timeMs?: number;
  coverUrl?: string;
  coverIsGif?: boolean;
  forumAvatar?: string;
  isDeleted?: boolean;
  lastFloor?: number;
  lastPid?: number;
}

/** 读取当前账号全部历史（最近在前）。读不到/格式不对一律返回空数组，不让界面崩 */
export async function loadBrowseHistory(context: common.UIAbilityContext,
  account?: string): Promise<BrowseItem[]> {
  try {
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
    const raw: string = await readRawForAccount(store, currentAccountKey(account));
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
      out.coverIsGif = item.coverIsGif === true;
      out.forumAvatar = item.forumAvatar ?? '';
      out.isDeleted = item.isDeleted ?? false;
      out.lastFloor = typeof item.lastFloor === 'number' && item.lastFloor > 0 ? Math.floor(item.lastFloor) : 0;
      out.lastPid = typeof item.lastPid === 'number' && item.lastPid > 0 ? Math.floor(item.lastPid) : 0;
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
  out.coverIsGif = incoming.coverUrl.length > 0 ? incoming.coverIsGif : existing.coverIsGif;
  out.forumAvatar = incoming.forumAvatar.length > 0 ? incoming.forumAvatar : existing.forumAvatar;
  out.isDeleted = incoming.title.length > 0 ? false : (incoming.isDeleted || existing.isDeleted);
  out.lastFloor = incoming.lastFloor > 0 ? incoming.lastFloor : existing.lastFloor;
  out.lastPid = incoming.lastFloor > 0 ? incoming.lastPid : existing.lastPid;
  return out;
}

/**
 * 记录一次浏览：去重置顶 + 上限淘汰，返回更新后的完整历史（详情页通常忽略返回值）。
 * 同一 tid 走 `mergeBrowseEntry` 逐字段合并，旧的非空值不会被新的空值擦掉。
 */
export async function addBrowseHistory(context: common.UIAbilityContext,
  item: BrowseItem, account?: string): Promise<BrowseItem[]> {
  const resolvedAccount: string = currentAccountKey(account);
  return enqueueHistory((): Promise<BrowseItem[]> => addBrowseHistoryNow(context, item, resolvedAccount));
}

async function addBrowseHistoryNow(context: common.UIAbilityContext,
  item: BrowseItem, account: string): Promise<BrowseItem[]> {
  if (item.tid <= 0) {
    return loadBrowseHistory(context, account);
  }
  const history: BrowseItem[] = await loadBrowseHistory(context, account);
  let merged: BrowseItem | undefined = undefined;
  const updated: BrowseItem[] = [];
  for (const it of history) {
    if (it.tid === item.tid) {
      merged = mergeBrowseEntry(it, item);
    } else {
      updated.push(it);
    }
  }
  // 重看过的这条排到最前
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
    await store.put(storageKeyOf(account), JSON.stringify(updated));
    await touchAccountBucket(store, account);
    await store.flush();
    browseHistoryChanges.revision++;
  } catch {
    // 写失败不影响浏览本身：本次会话内界面仍有 updated，下次启动可能少一条
  }
  return updated;
}

export async function markBrowseDeleted(context: common.UIAbilityContext,
  tid: number, account?: string): Promise<boolean> {
  const resolvedAccount: string = currentAccountKey(account);
  return enqueueHistory((): Promise<boolean> => markBrowseDeletedNow(context, tid, resolvedAccount));
}

async function markBrowseDeletedNow(context: common.UIAbilityContext,
  tid: number, account: string): Promise<boolean> {
  if (tid <= 0) {
    return false;
  }
  const history: BrowseItem[] = await loadBrowseHistory(context, account);
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
    await store.put(storageKeyOf(account), JSON.stringify(history));
    await store.flush();
  } catch {
    // 写失败不影响展示：本次会话内界面已按新值渲染
  }
  return true;
}

export async function clearBrowseHistory(context: common.UIAbilityContext,
  account?: string): Promise<void> {
  const resolvedAccount: string = currentAccountKey(account);
  return enqueueHistory((): Promise<void> => clearBrowseHistoryNow(context, resolvedAccount));
}

export async function readBrowseProgress(context: common.UIAbilityContext,
  tid: number, account?: string): Promise<BrowseProgress> {
  const out: BrowseProgress = new BrowseProgress();
  if (tid <= 0) { return out; }
  const history: BrowseItem[] = await loadBrowseHistory(context, account);
  for (const item of history) {
    if (item.tid === tid) {
      out.floor = item.lastFloor;
      out.pid = item.lastPid;
      break;
    }
  }
  return out;
}

export async function saveBrowseProgress(context: common.UIAbilityContext,
  tid: number, floor: number, pid: number, account?: string): Promise<void> {
  if (tid <= 0 || floor < 2) { return; }
  const resolvedAccount: string = currentAccountKey(account);
  return enqueueHistory((): Promise<void> => saveBrowseProgressNow(context, tid, floor, pid, resolvedAccount));
}

async function saveBrowseProgressNow(context: common.UIAbilityContext,
  tid: number, floor: number, pid: number, account: string): Promise<void> {
  const history: BrowseItem[] = await loadBrowseHistory(context, account);
  let changed: boolean = false;
  for (const item of history) {
    if (item.tid === tid) {
      const nextFloor: number = Math.floor(floor);
      const nextPid: number = pid > 0 ? Math.floor(pid) : 0;
      if (item.lastFloor !== nextFloor || item.lastPid !== nextPid) {
        item.lastFloor = nextFloor;
        item.lastPid = nextPid;
        changed = true;
      }
      break;
    }
  }
  if (!changed) { return; }
  try {
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
    await store.put(storageKeyOf(account), JSON.stringify(history));
    await store.flush();
  } catch {
    // 写失败不影响阅读
  }
}

async function clearBrowseHistoryNow(context: common.UIAbilityContext, account: string): Promise<void> {
  try {
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
    await store.put(storageKeyOf(account), '');
    await store.flush();
    browseHistoryChanges.revision++;
  } catch {
    // 同上：存储失败不抛给界面
  }
}
