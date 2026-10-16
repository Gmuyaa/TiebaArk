

export class HiddenThread {
  tid: number = 0;
  title: string = '';
  forumName: string = '';
  authorName: string = '';

  timeMs: number = 0;
}

export const HIDDEN_THREAD_MAX: number = 200;

export const BLOCKED_USER_MAX: number = 200;

export class BlockedUser {
  uid: number = 0;
  name: string = '';
  timeMs: number = 0;
}

export class BlockRules {

  forums: string[] = [];

  uids: number[] = [];

  tids: number[] = [];
}

export interface BlockableThread {
  tid: number;
  authorId: number;
  sourceForum: string;
}

interface RawHiddenThread {
  tid?: number;
  title?: string;
  forumName?: string;
  authorName?: string;
  timeMs?: number;
}

export function emptyRules(): BlockRules {
  return new BlockRules();
}

export function normalizeForumName(name: string): string {
  let value: string = name.trim();
  if (value.length > 0 && value.charAt(value.length - 1) === '吧') {
    value = value.substring(0, value.length - 1);
  }
  return value.trim();
}

export function normalizeForumNames(names: string[]): string[] {
  const result: string[] = [];
  for (const name of names) {
    const value: string = normalizeForumName(name);
    if (value.length === 0) { continue; }
    if (result.indexOf(value) < 0) { result.push(value); }
  }
  return result;
}

export function normalizeUids(uids: number[]): number[] {
  const result: number[] = [];
  for (const uid of uids) {
    if (!Number.isSafeInteger(uid) || uid <= 0) { continue; }
    if (result.indexOf(uid) < 0) { result.push(uid); }
  }
  return result;
}

export function normalizeTids(tids: number[]): number[] {
  const result: number[] = [];
  for (const tid of tids) {
    if (!Number.isSafeInteger(tid) || tid <= 0) { continue; }
    if (result.indexOf(tid) < 0) { result.push(tid); }
  }
  return result;
}

export function isBlockedThread(thread: BlockableThread, rules: BlockRules,
  applyForumBlock: boolean = true): boolean {
  if (thread.tid > 0 && rules.tids.indexOf(thread.tid) >= 0) { return true; }
  if (thread.authorId > 0 && rules.uids.indexOf(thread.authorId) >= 0) { return true; }
  if (applyForumBlock && thread.sourceForum.length > 0) {
    return rules.forums.indexOf(normalizeForumName(thread.sourceForum)) >= 0;
  }
  return false;
}

export function visibleThreads<T extends BlockableThread>(threads: T[], rules: BlockRules,
  applyForumBlock: boolean = true): T[] {
  const result: T[] = [];
  for (const thread of threads) {
    if (!isBlockedThread(thread, rules, applyForumBlock)) { result.push(thread); }
  }
  return result;
}

export function parseHiddenThreads(raw: string): HiddenThread[] {
  if (raw.length === 0) { return []; }
  let parsed: RawHiddenThread[];
  try {
    parsed = JSON.parse(raw) as RawHiddenThread[];
  } catch (err) {
    return [];
  }
  if (!Array.isArray(parsed)) { return []; }
  const items: HiddenThread[] = [];
  for (const item of parsed) {
    if (item === null || item === undefined) { continue; }
    const tid: number = item.tid ?? 0;
    if (!Number.isSafeInteger(tid) || tid <= 0) { continue; }
    const out: HiddenThread = new HiddenThread();
    out.tid = tid;
    out.title = item.title ?? '';
    out.forumName = item.forumName ?? '';
    out.authorName = item.authorName ?? '';
    out.timeMs = item.timeMs ?? 0;
    items.push(out);
  }
  return items;
}

export function serializeHiddenThreads(items: HiddenThread[]): string {
  if (items.length === 0) { return ''; }
  return JSON.stringify(items);
}

export function mergeHiddenThread(before: HiddenThread[], incoming: HiddenThread): HiddenThread[] {
  if (incoming.tid <= 0) { return before.slice(); }
  const result: HiddenThread[] = [incoming];
  for (const item of before) {
    if (item.tid !== incoming.tid) { result.push(item); }
  }
  while (result.length > HIDDEN_THREAD_MAX) {
    result.pop();
  }
  return result;
}

export function removeHiddenThread(before: HiddenThread[], tid: number): HiddenThread[] {
  const result: HiddenThread[] = [];
  for (const item of before) {
    if (item.tid !== tid) { result.push(item); }
  }
  return result;
}

export function mergeRules(serverForums: string[], localForums: string[],
  uids: number[], hidden: HiddenThread[]): BlockRules {
  const rules: BlockRules = new BlockRules();
  rules.forums = normalizeForumNames(serverForums.concat(localForums));
  rules.uids = normalizeUids(uids);
  const tids: number[] = [];
  for (const item of hidden) { tids.push(item.tid); }
  rules.tids = normalizeTids(tids);
  return rules;
}

interface RawBlockedUser {
  uid?: number;
  name?: string;
  timeMs?: number;
}

export function parseBlockedUsers(raw: string): BlockedUser[] {
  if (raw.length === 0) { return []; }
  let parsed: RawBlockedUser[];
  try {
    parsed = JSON.parse(raw) as RawBlockedUser[];
  } catch (err) {
    return [];
  }
  if (!Array.isArray(parsed)) { return []; }
  const items: BlockedUser[] = [];
  for (const item of parsed) {
    if (item === null || item === undefined) { continue; }
    const uid: number = item.uid ?? 0;
    if (!Number.isSafeInteger(uid) || uid <= 0) { continue; }
    const out: BlockedUser = new BlockedUser();
    out.uid = uid;
    out.name = item.name ?? '';
    out.timeMs = item.timeMs ?? 0;
    items.push(out);
  }
  return items;
}

export function serializeBlockedUsers(items: BlockedUser[]): string {
  if (items.length === 0) { return ''; }
  return JSON.stringify(items);
}

export function mergeBlockedUser(before: BlockedUser[], incoming: BlockedUser): BlockedUser[] {
  if (incoming.uid <= 0) { return before.slice(); }
  const result: BlockedUser[] = [incoming];
  for (const item of before) {
    if (item.uid !== incoming.uid) { result.push(item); }
  }
  while (result.length > BLOCKED_USER_MAX) {
    result.pop();
  }
  return result;
}

export function removeBlockedUser(before: BlockedUser[], uid: number): BlockedUser[] {
  const result: BlockedUser[] = [];
  for (const item of before) {
    if (item.uid !== uid) { result.push(item); }
  }
  return result;
}

export function blockedUserUids(items: BlockedUser[]): number[] {
  const uids: number[] = [];
  for (const item of items) { uids.push(item.uid); }
  return uids;
}
