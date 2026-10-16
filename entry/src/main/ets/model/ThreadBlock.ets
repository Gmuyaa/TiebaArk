/** 帖子卡片的屏蔽与隐藏规则，负责解析、去重和匹配；持久化由 ThreadBlockStore 管理。 */

/** 本机隐藏的一条帖子（只存列表展示所需的字段，不存正文） */
export class HiddenThread {
  tid: number = 0;
  title: string = '';
  forumName: string = '';
  authorName: string = '';
  /** 隐藏动作发生的时间（毫秒）；管理页按它倒序展示 */
  timeMs: number = 0;
}

/** 隐藏列表上限。超出后从最旧的（尾部）开始淘汰 */
export const HIDDEN_THREAD_MAX: number = 200;

/** 本机记录的"拉黑过的用户"上限（只用于设置页展示与解除，服务端没有全量列表可读） */
export const BLOCKED_USER_MAX: number = 200;

export class BlockedUser {
  uid: number = 0;
  name: string = '';
  timeMs: number = 0;
}

/** 过滤口径：三份清单都由存储层喂进来，本文件只做判定 */
export class BlockRules {
  /** 已屏蔽的吧名（不带后缀「吧」；服务端列表 + 本机即时记录） */
  forums: string[] = [];
  /** 已拉黑的用户 uid */
  uids: number[] = [];
  /** 本机隐藏的帖子 tid */
  tids: number[] = [];
}

/** 能被过滤的最小帖子形状；`ThreadBrief` 结构性满足它 */
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

/**
 * 吧名的比较口径：**去掉首尾空白，并且去掉尾部一个「吧」**。
 *
 * 服务端 `getDislikeList` 给的是纯吧名（"异环内鬼"），而卡片上显示的是
 * 「异环内鬼吧」；用户在菜单里点到的是卡片上的吧名。两边都必须能命中，
 * 所以统一在这里归一化——**只削一个尾巴上的「吧」**，不碰吧名内部的字。
 */
export function normalizeForumName(name: string): string {
  let value: string = name.trim();
  if (value.length > 0 && value.charAt(value.length - 1) === '吧') {
    value = value.substring(0, value.length - 1);
  }
  return value.trim();
}

/** 吧名清单：去空、去「吧」后缀、去重，保持原有顺序 */
export function normalizeForumNames(names: string[]): string[] {
  const result: string[] = [];
  for (const name of names) {
    const value: string = normalizeForumName(name);
    if (value.length === 0) { continue; }
    if (result.indexOf(value) < 0) { result.push(value); }
  }
  return result;
}

/** uid 清单：只留正整数，去重 */
export function normalizeUids(uids: number[]): number[] {
  const result: number[] = [];
  for (const uid of uids) {
    if (!Number.isSafeInteger(uid) || uid <= 0) { continue; }
    if (result.indexOf(uid) < 0) { result.push(uid); }
  }
  return result;
}

/** tid 清单：只留正整数，去重 */
export function normalizeTids(tids: number[]): number[] {
  const result: number[] = [];
  for (const tid of tids) {
    if (!Number.isSafeInteger(tid) || tid <= 0) { continue; }
    if (result.indexOf(tid) < 0) { result.push(tid); }
  }
  return result;
}

/** 这条帖子要不要从列表里拿掉。规则顺序：隐藏单帖 → 拉黑作者 → 屏蔽来源吧 */
export function isBlockedThread(thread: BlockableThread, rules: BlockRules,
  applyForumBlock: boolean = true): boolean {
  if (thread.tid > 0 && rules.tids.indexOf(thread.tid) >= 0) { return true; }
  if (thread.authorId > 0 && rules.uids.indexOf(thread.authorId) >= 0) { return true; }
  if (applyForumBlock && thread.sourceForum.length > 0) {
    return rules.forums.indexOf(normalizeForumName(thread.sourceForum)) >= 0;
  }
  return false;
}

/**
 * 过滤一个列表。
 *
 * `applyForumBlock = false` 用于**该吧自己的吧页**：用户是主动进来的，
 * 「屏蔽吧」的语义是"不再推荐这个吧"，不应该把用户正在看的吧页清空。
 * 隐藏单帖与拉黑作者在吧页照样生效（那是针对具体内容的决定）。
 */
export function visibleThreads<T extends BlockableThread>(threads: T[], rules: BlockRules,
  applyForumBlock: boolean = true): T[] {
  const result: T[] = [];
  for (const thread of threads) {
    if (!isBlockedThread(thread, rules, applyForumBlock)) { result.push(thread); }
  }
  return result;
}

/** 解析本机隐藏列表；读不到/格式不对一律当空列表，不让界面崩 */
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

/**
 * 隐藏一条帖子：同一个 tid 已在列表里 → 更新为最新值并**移到最前**（去重不重复出现），
 * 超出上限从尾部淘汰。返回新数组（调用方整体替换，配合 `@Trace`）。
 */
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

/** 恢复（取消隐藏）一条帖子；tid 不存在时原样返回 */
export function removeHiddenThread(before: HiddenThread[], tid: number): HiddenThread[] {
  const result: HiddenThread[] = [];
  for (const item of before) {
    if (item.tid !== tid) { result.push(item); }
  }
  return result;
}

/** 把两份吧名清单合并成过滤口径（服务端为准，本机即时记录补充） */
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

/** 解析本机拉黑名单；读不到/格式不对一律当空列表 */
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

/** 记一条拉黑：同一 uid 更新并置顶，超出上限从尾部淘汰 */
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

/** 解除后从本机名单里删掉 */
export function removeBlockedUser(before: BlockedUser[], uid: number): BlockedUser[] {
  const result: BlockedUser[] = [];
  for (const item of before) {
    if (item.uid !== uid) { result.push(item); }
  }
  return result;
}

/** 过滤口径要的 uid 清单 */
export function blockedUserUids(items: BlockedUser[]): number[] {
  const uids: number[] = [];
  for (const item of items) { uids.push(item.uid); }
  return uids;
}
