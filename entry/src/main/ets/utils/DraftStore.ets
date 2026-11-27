/** 发帖与回复草稿的账号隔离持久化；属用户数据，不纳入缓存清理。 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { DRAFT_MAX_ACCOUNTS, REPLY_DRAFT_MAX_ENTRIES } from '../model/CachePolicy';

const STORE_NAME: string = 'tieba_drafts';
const KEY_SNAPSHOT: string = 'snapshot_v1';
const DRAFT_TAB_COUNT: number = 4;

let draftWriteQueue: Promise<void> = Promise.resolve();
function enqueueDraft<T>(work: () => Promise<T>): Promise<T> {
  const next: Promise<T> = draftWriteQueue.then(work, work);
  draftWriteQueue = next.then((): void => {}, (): void => {});
  return next;
}

export class SavedComposeTab {
  title: string = '';
  body: string = '';
  forum: string = '';
  forumId: number = 0;
  forumAvatar: string = '';
  tabId: number = 0;
  tabName: string = '';
  topic: string = '';
  topicId: number = 0;
  visibility: string = '全场景可见';
  declaration: string = '';
  mood: string = '';
  media: string[] = [];
  video: string = '';
}

export class SavedComposeSnapshot {
  type: number = 1;
  tabs: SavedComposeTab[] = [
    new SavedComposeTab(),
    new SavedComposeTab(),
    new SavedComposeTab(),
    new SavedComposeTab()
  ];
  updatedAt: number = 0;
}

class SavedReplyEntry {
  key: string = '';
  text: string = '';
  updatedAt: number = 0;
}

class AccountDraftBucket {
  account: string = '';
  updatedAt: number = 0;
  compose: SavedComposeSnapshot | undefined = undefined;
  replies: SavedReplyEntry[] = [];
}

interface RawComposeTab {
  title?: string;
  body?: string;
  forum?: string;
  forumId?: number;
  forumAvatar?: string;
  tabId?: number;
  tabName?: string;
  topic?: string;
  topicId?: number;
  visibility?: string;
  declaration?: string;
  mood?: string;
  media?: string[];
  video?: string;
}

interface RawComposeSnapshot {
  type?: number;
  tabs?: RawComposeTab[];
  updatedAt?: number;
}

interface RawReplyEntry {
  key?: string;
  text?: string;
  updatedAt?: number;
}

interface RawAccountBucket {
  account?: string;
  updatedAt?: number;
  compose?: RawComposeSnapshot;
  replies?: RawReplyEntry[];
}

export function replyDraftKey(tid: number, pid: number, spid: number = 0): string {
  const safeTid: number = tid > 0 ? Math.floor(tid) : 0;
  const safePid: number = pid > 0 ? Math.floor(pid) : 0;
  const safeSpid: number = spid > 0 ? Math.floor(spid) : 0;
  return `${safeTid}:${safePid}:${safeSpid}`;
}

export function hasSavedComposeContent(snapshot: SavedComposeSnapshot | undefined): boolean {
  if (snapshot === undefined) { return false; }
  for (const tab of snapshot.tabs) {
    if (tab.title.trim().length > 0 || tab.body.trim().length > 0 ||
      tab.media.length > 0 || tab.video.length > 0) {
      return true;
    }
  }
  return false;
}

function normalizeAccount(account: string): string {
  const trimmed: string = account.trim();
  return trimmed.length > 0 ? trimmed : 'guest';
}

function parseComposeTab(raw: RawComposeTab | undefined): SavedComposeTab {
  const out: SavedComposeTab = new SavedComposeTab();
  if (raw === undefined) { return out; }
  out.title = typeof raw.title === 'string' ? raw.title : '';
  out.body = typeof raw.body === 'string' ? raw.body : '';
  out.forum = typeof raw.forum === 'string' ? raw.forum : '';
  out.forumId = typeof raw.forumId === 'number' && raw.forumId > 0 ? Math.floor(raw.forumId) : 0;
  out.forumAvatar = typeof raw.forumAvatar === 'string' ? raw.forumAvatar : '';
  out.tabId = typeof raw.tabId === 'number' && raw.tabId > 0 ? Math.floor(raw.tabId) : 0;
  out.tabName = typeof raw.tabName === 'string' ? raw.tabName : '';
  out.topic = typeof raw.topic === 'string' ? raw.topic : '';
  out.topicId = typeof raw.topicId === 'number' && raw.topicId > 0 ? Math.floor(raw.topicId) : 0;
  out.visibility = typeof raw.visibility === 'string' && raw.visibility.length > 0 ? raw.visibility : '全场景可见';
  out.declaration = typeof raw.declaration === 'string' ? raw.declaration : '';
  out.mood = typeof raw.mood === 'string' ? raw.mood : '';
  out.media = Array.isArray(raw.media)
    ? raw.media.filter((item: string): boolean => typeof item === 'string' && item.length > 0).slice(0, 9)
    : [];
  out.video = typeof raw.video === 'string' ? raw.video : '';
  return out;
}

function parseComposeSnapshot(raw: RawComposeSnapshot | undefined): SavedComposeSnapshot | undefined {
  if (raw === undefined) { return undefined; }
  const out: SavedComposeSnapshot = new SavedComposeSnapshot();
  const typeVal: number = typeof raw.type === 'number' ? Math.floor(raw.type) : 1;
  out.type = typeVal >= 0 && typeVal < DRAFT_TAB_COUNT ? typeVal : 1;
  out.updatedAt = typeof raw.updatedAt === 'number' && raw.updatedAt > 0 ? raw.updatedAt : 0;
  const parsedTabs: SavedComposeTab[] = [];
  for (let i = 0; i < DRAFT_TAB_COUNT; i++) {
    const item: RawComposeTab | undefined = Array.isArray(raw.tabs) ? raw.tabs[i] : undefined;
    parsedTabs.push(parseComposeTab(item));
  }
  out.tabs = parsedTabs;
  return hasSavedComposeContent(out) ? out : undefined;
}

function parseBuckets(rawText: string): AccountDraftBucket[] {
  if (rawText.length === 0) { return []; }
  try {
    const parsed: RawAccountBucket[] = JSON.parse(rawText) as RawAccountBucket[];
    if (!Array.isArray(parsed)) { return []; }
    const out: AccountDraftBucket[] = [];
    for (const item of parsed) {
      if (item === null || item === undefined || typeof item.account !== 'string' || item.account.length === 0) {
        continue;
      }
      const bucket: AccountDraftBucket = new AccountDraftBucket();
      bucket.account = item.account;
      bucket.updatedAt = typeof item.updatedAt === 'number' ? item.updatedAt : 0;
      bucket.compose = parseComposeSnapshot(item.compose);
      if (Array.isArray(item.replies)) {
        for (const r of item.replies) {
          if (r === null || r === undefined || typeof r.key !== 'string' || r.key.length === 0 ||
            typeof r.text !== 'string' || r.text.trim().length === 0) {
            continue;
          }
          const entry: SavedReplyEntry = new SavedReplyEntry();
          entry.key = r.key;
          entry.text = r.text;
          entry.updatedAt = typeof r.updatedAt === 'number' ? r.updatedAt : 0;
          bucket.replies.push(entry);
        }
        bucket.replies.sort((a: SavedReplyEntry, b: SavedReplyEntry): number => b.updatedAt - a.updatedAt);
        if (bucket.replies.length > REPLY_DRAFT_MAX_ENTRIES) {
          bucket.replies = bucket.replies.slice(0, REPLY_DRAFT_MAX_ENTRIES);
        }
      }
      if (bucket.compose !== undefined || bucket.replies.length > 0) {
        out.push(bucket);
      }
    }
    out.sort((a: AccountDraftBucket, b: AccountDraftBucket): number => b.updatedAt - a.updatedAt);
    return out.slice(0, DRAFT_MAX_ACCOUNTS);
  } catch {
    return [];
  }
}

let cachedBuckets: AccountDraftBucket[] | undefined = undefined;

async function ensureLoaded(context: common.UIAbilityContext): Promise<AccountDraftBucket[]> {
  if (cachedBuckets !== undefined) {
    return cachedBuckets;
  }
  try {
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
    const raw: string = (await store.get(KEY_SNAPSHOT, '')) as string;
    cachedBuckets = parseBuckets(raw);
  } catch {
    cachedBuckets = [];
  }
  return cachedBuckets;
}

async function flushBuckets(context: common.UIAbilityContext, buckets: AccountDraftBucket[]): Promise<void> {
  const cleaned: AccountDraftBucket[] = buckets
    .filter((b: AccountDraftBucket): boolean => b.compose !== undefined || b.replies.length > 0)
    .sort((a: AccountDraftBucket, b: AccountDraftBucket): number => b.updatedAt - a.updatedAt)
    .slice(0, DRAFT_MAX_ACCOUNTS);
  cachedBuckets = cleaned;
  try {
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
    await store.put(KEY_SNAPSHOT, cleaned.length > 0 ? JSON.stringify(cleaned) : '');
    await store.flush();
  } catch {
    // 草稿持久化失败不阻断发帖/回复流程
  }
}

function findOrCreateBucket(buckets: AccountDraftBucket[], accountKey: string, now: number): AccountDraftBucket {
  for (const bucket of buckets) {
    if (bucket.account === accountKey) {
      bucket.updatedAt = now;
      return bucket;
    }
  }
  const created: AccountDraftBucket = new AccountDraftBucket();
  created.account = accountKey;
  created.updatedAt = now;
  buckets.unshift(created);
  return created;
}

export async function loadComposeDraft(context: common.UIAbilityContext,
  account: string): Promise<SavedComposeSnapshot | undefined> {
  const key: string = normalizeAccount(account);
  const buckets: AccountDraftBucket[] = await ensureLoaded(context);
  for (const bucket of buckets) {
    if (bucket.account === key) {
      return bucket.compose;
    }
  }
  return undefined;
}

export async function saveComposeDraft(context: common.UIAbilityContext,
  account: string, snapshot: SavedComposeSnapshot): Promise<void> {
  const key: string = normalizeAccount(account);
  return enqueueDraft(async (): Promise<void> => {
    const buckets: AccountDraftBucket[] = await ensureLoaded(context);
    const now: number = Date.now();
    const hasContent: boolean = hasSavedComposeContent(snapshot);
    const bucket: AccountDraftBucket = findOrCreateBucket(buckets, key, now);
    if (hasContent) {
      snapshot.updatedAt = now;
      bucket.compose = snapshot;
    } else {
      bucket.compose = undefined;
    }
    await flushBuckets(context, buckets);
  });
}

export async function clearComposeDraft(context: common.UIAbilityContext, account: string): Promise<void> {
  const key: string = normalizeAccount(account);
  return enqueueDraft(async (): Promise<void> => {
    const buckets: AccountDraftBucket[] = await ensureLoaded(context);
    let changed: boolean = false;
    for (const bucket of buckets) {
      if (bucket.account === key && bucket.compose !== undefined) {
        bucket.compose = undefined;
        changed = true;
      }
    }
    if (changed) {
      await flushBuckets(context, buckets);
    }
  });
}

export async function warmReplyDrafts(context: common.UIAbilityContext): Promise<void> {
  await ensureLoaded(context);
}

export function peekReplyDraft(account: string, tid: number, pid: number, spid: number = 0): string {
  if (cachedBuckets === undefined || tid <= 0) { return ''; }
  const accountKey: string = normalizeAccount(account);
  const entryKey: string = replyDraftKey(tid, pid, spid);
  for (const bucket of cachedBuckets) {
    if (bucket.account !== accountKey) { continue; }
    for (const entry of bucket.replies) {
      if (entry.key === entryKey) { return entry.text; }
    }
    return '';
  }
  return '';
}

export async function loadReplyDraft(context: common.UIAbilityContext,
  account: string, tid: number, pid: number, spid: number = 0): Promise<string> {
  if (tid <= 0) { return ''; }
  await ensureLoaded(context);
  return peekReplyDraft(account, tid, pid, spid);
}

export async function saveReplyDraft(context: common.UIAbilityContext,
  account: string, tid: number, pid: number, spid: number, text: string): Promise<void> {
  if (tid <= 0) { return; }
  const accountKey: string = normalizeAccount(account);
  const entryKey: string = replyDraftKey(tid, pid, spid);
  const trimmed: string = text.trim();
  return enqueueDraft(async (): Promise<void> => {
    const buckets: AccountDraftBucket[] = await ensureLoaded(context);
    const now: number = Date.now();
    if (trimmed.length === 0) {
      let changed: boolean = false;
      for (const bucket of buckets) {
        if (bucket.account !== accountKey) { continue; }
        const before: number = bucket.replies.length;
        bucket.replies = bucket.replies.filter((item: SavedReplyEntry): boolean => item.key !== entryKey);
        if (bucket.replies.length !== before) {
          bucket.updatedAt = now;
          changed = true;
        }
      }
      if (changed) {
        await flushBuckets(context, buckets);
      }
      return;
    }
    const bucket: AccountDraftBucket = findOrCreateBucket(buckets, accountKey, now);
    bucket.replies = bucket.replies.filter((item: SavedReplyEntry): boolean => item.key !== entryKey);
    const entry: SavedReplyEntry = new SavedReplyEntry();
    entry.key = entryKey;
    entry.text = text;
    entry.updatedAt = now;
    bucket.replies.unshift(entry);
    if (bucket.replies.length > REPLY_DRAFT_MAX_ENTRIES) {
      bucket.replies = bucket.replies.slice(0, REPLY_DRAFT_MAX_ENTRIES);
    }
    await flushBuckets(context, buckets);
  });
}

export async function clearReplyDraft(context: common.UIAbilityContext,
  account: string, tid: number, pid: number, spid: number = 0): Promise<void> {
  return saveReplyDraft(context, account, tid, pid, spid, '');
}

/** 仅供单测重置内存镜像。 */
export function resetDraftStoreMemory(): void {
  cachedBuckets = undefined;
}
