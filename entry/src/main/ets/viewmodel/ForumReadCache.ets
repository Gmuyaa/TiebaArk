import { common } from '@kit.AbilityKit';
import { TiebaApi, ThreadListResponse } from '../api/TiebaApi';
import { ForumMembership } from '../model/ThreadList';
import { FollowForumItem, FollowForumList } from '../model/FollowForum';
import { SignStats } from '../model/SignStats';
import { authSession } from '../auth/AuthSession';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { loadForumSnapshot, saveForumSnapshot, StoredForumHeader, StoredForumItem,
  StoredForumSnapshot } from './ForumSnapshotStore';

const FRESH_MS: number = 30000;
function account(): string {
  return authSession.forumCacheSessionKey();
}
export function forumCacheDay(): string {
  return new Date(Date.now() + 8 * 60 * 60 * 1000).toISOString().slice(0, 10);
}
class ForumSnapshot {
  response: ThreadListResponse;
  at: number = Date.now();
  serverAt: number = Date.now();
  accessedAt: number = Date.now();
  day: string = forumCacheDay();
  constructor(response: ThreadListResponse, at: number = Date.now(), day: string = forumCacheDay()) {
    this.response = response; this.at = at; this.serverAt = at; this.accessedAt = at; this.day = day;
  }
}
let owner: string = '';
let revision: number = 0;
let guideRevision: number = 0;
let storageContext: common.UIAbilityContext | undefined = undefined;
let restoredOwner: string = '';
const versions: Map<string, number> = new Map();
const confirmedSigns: Map<string, string> = new Map();
const forums: Map<string, ForumSnapshot> = new Map();
const reads: Map<string, Promise<ThreadListResponse>> = new Map();
let guide: FollowForumList | undefined = undefined;
let guideAt: number = 0;
let guideDay: string = '';
let guideServerAt: number = 0;
let guideRead: Promise<FollowForumList> | undefined = undefined;
let fetchedAt: number = 0;
function bind(): void {
  const next: string = account();
  if (owner === next) { return; }
  owner = next; revision++; forums.clear(); reads.clear(); versions.clear(); confirmedSigns.clear();
  guide = undefined; guideAt = 0; guideDay = ''; guideServerAt = 0; guideRead = undefined;
  fetchedAt = 0; restoredOwner = '';
}

function store(urgent: boolean = false): void {
  const uid: number = authSession.forumCacheUid();
  if (storageContext === undefined || uid <= 0 || fetchedAt <= 0) { return; }
  const items: StoredForumItem[] = (guide?.items ?? []).map((item: FollowForumItem): StoredForumItem => ({
    fid: item.fid, fname: item.fname, avatar: item.avatar, level: item.level,
    levelName: item.levelName, currentScore: item.currentScore, nextScore: item.nextScore,
    isSigned: item.isSigned, signKnown: item.signKnown
  }));
  const headers: StoredForumHeader[] = [];
  forums.forEach((value: ForumSnapshot, name: string): void => {
    const member: ForumMembership = value.response.data.membership ?? new ForumMembership();
    const forum = value.response.data.forum;
    headers.push({ fid: forum.id, fname: name, avatar: forum.avatar ?? '', followed: forum.followed,
      level: member.level, levelName: member.levelName, currentScore: member.currentScore,
      nextScore: member.nextScore, signed: member.signed, missedDays: member.missedDays,
      continuousCount: member.continuousCount, totalCount: member.totalCount,
      day: value.day, accessedAt: value.accessedAt, fetchedAt: value.serverAt });
  });
  saveForumSnapshot(storageContext, { version: 1, uid, fetchedAt,
    day: forumCacheDay(), guideFetchedAt: guideServerAt, guideDay, hasGuide: guide !== undefined,
    hasMore: guide?.hasMore ?? false, items, headers }, urgent);
}

/** Called after a stable UID is known; disk reads never make data fresh. */
export function restoreForumCache(context: common.UIAbilityContext): void {
  bind();
  const uid: number = authSession.forumCacheUid();
  if (owner.length === 0 || uid <= 0) { return; }
  storageContext = context;
  if (restoredOwner === owner) { return; }
  restoredOwner = owner;
  const saved: StoredForumSnapshot | undefined = loadForumSnapshot(context, uid);
  if (saved === undefined) { return; }
  fetchedAt = saved.fetchedAt;
  hilog.info(0x0000, 'ForumReadCache', 'snapshot restored rows=%{public}d headers=%{public}d',
    saved.items.length, saved.headers.length);
  if (saved.hasGuide && Date.now() - saved.guideFetchedAt <= 7 * 24 * 60 * 60 * 1000) {
    guide = new FollowForumList(); guide.hasMore = saved.hasMore;
    guide.items = saved.items.map((item: StoredForumItem): FollowForumItem => {
      const out: FollowForumItem = new FollowForumItem();
      out.fid = item.fid; out.fname = item.fname; out.avatar = item.avatar;
      out.level = item.level; out.levelName = item.levelName;
      out.currentScore = item.currentScore; out.nextScore = item.nextScore;
      out.isSigned = item.isSigned; out.signKnown = item.signKnown;
      return out;
    });
    guideAt = 0; guideServerAt = saved.guideFetchedAt; guideDay = saved.guideDay;
    if (guideDay === forumCacheDay()) {
      for (const item of guide.items) {
        if (item.signKnown && item.isSigned) { confirmedSigns.set(item.fname, guideDay); }
      }
    }
  }
  for (const item of saved.headers) {
    if (Date.now() - item.fetchedAt > 7 * 24 * 60 * 60 * 1000) { continue; }
    const response: ThreadListResponse = new ThreadListResponse(); response.ok = true;
    response.data.forum.id = item.fid; response.data.forum.name = item.fname;
    response.data.forum.avatar = item.avatar; response.data.forum.followed = item.followed;
    const member: ForumMembership = response.data.membership;
    member.level = item.level; member.levelName = item.levelName;
    member.currentScore = item.currentScore; member.nextScore = item.nextScore;
    member.signed = item.signed; member.missedDays = item.missedDays;
    member.continuousCount = item.continuousCount ?? -1;
    member.totalCount = item.totalCount ?? -1;
    const restored: ForumSnapshot = new ForumSnapshot(response, 0, item.day);
    restored.accessedAt = item.accessedAt;
    restored.serverAt = item.fetchedAt;
    forums.set(item.fname, restored);
    if (item.day === forumCacheDay() && item.signed === true) {
      confirmedSigns.set(item.fname, item.day);
    }
  }
}
export class ForumCacheGuard {
  private owner: string;
  private revision: number;
  private day: string = forumCacheDay();
  private name: string;
  private version: number;
  constructor(name: string = '') {
    bind(); this.owner = owner; this.revision = revision; this.name = name;
    this.version = name.length > 0 ? (versions.get(name) ?? 0) : guideRevision;
  }
  current(): boolean {
    bind(); return this.owner === owner && this.revision === revision && this.day === forumCacheDay() &&
      this.version === (this.name.length > 0 ? (versions.get(this.name) ?? 0) : guideRevision);
  }
}
export function publishForumRead(guard: ForumCacheGuard, name: string, response: ThreadListResponse): void {
  if (!guard.current() || owner.length === 0 || !response.ok || response.data.forum.id <= 0) { return; }
  const previous: ForumSnapshot | undefined = forums.get(name);
  if (previous !== undefined && previous.response.data.forum.id === response.data.forum.id) {
    const known: ForumMembership = previous.response.data.membership;
    // 缺字段不等于零：保留最近一次服务端返回的签到计数，直到有新值替换。
    if (response.data.membership.continuousCount < 0) { response.data.membership.continuousCount = known.continuousCount; }
    if (response.data.membership.totalCount < 0) { response.data.membership.totalCount = known.totalCount; }
  }
  if (confirmedSigns.get(name) === forumCacheDay()) { response.data.membership.signed = true; }
  forums.set(name, new ForumSnapshot(response));
  if (forums.size > 256) {
    let oldestName: string = '';
    let oldestAt: number = Number.MAX_SAFE_INTEGER;
    forums.forEach((entry: ForumSnapshot, key: string): void => {
      if (entry.accessedAt < oldestAt) { oldestAt = entry.accessedAt; oldestName = key; }
    });
    if (oldestName.length > 0) { forums.delete(oldestName); }
  }
  fetchedAt = Date.now(); store();
}
export function forumReadFresh(name: string): boolean {
  bind(); const value: ForumSnapshot | undefined = forums.get(name);
  return value !== undefined && value.day === forumCacheDay() && Date.now() - value.at < FRESH_MS;
}
export function cachedForumId(name: string): number {
  bind(); return forums.get(name)?.response.data.forum.id ??
    guide?.items.find((item: FollowForumItem): boolean => item.fname === name)?.fid ?? 0;
}
export function cachedForumAvatar(name: string, id: number): string {
  bind();
  const value: ForumSnapshot | undefined = forums.get(name);
  if (value !== undefined && (id <= 0 || value.response.data.forum.id === id)) {
    return value.response.data.forum.avatar;
  }
  return guide?.items.find((item: FollowForumItem): boolean =>
    item.fname === name && (id <= 0 || item.fid === id))?.avatar ?? '';
}
export function cachedForumFollow(name: string, id: number): boolean | undefined {
  bind(); const value: ForumSnapshot | undefined = forums.get(name);
  if (value !== undefined && value.response.data.forum.id === id) { return value.response.data.forum.followed; }
  return guide?.items.some((item: FollowForumItem): boolean => item.fid === id && item.fname === name) ? true : undefined;
}
export function cachedForumMembership(name: string, id: number): ForumMembership | undefined {
  bind(); const value: ForumSnapshot | undefined = forums.get(name);
  if (value === undefined || value.response.data.forum.id !== id) { return undefined; }
  value.accessedAt = Date.now(); store();
  const source: ForumMembership = value.response.data.membership;
  if (source === undefined) { return undefined; }
  const out: ForumMembership = new ForumMembership();
  out.level = source.level; out.levelName = source.levelName;
  out.currentScore = source.currentScore; out.nextScore = source.nextScore;
  out.continuousCount = source.continuousCount; out.totalCount = source.totalCount;
  if (value.day === forumCacheDay()) {
    out.signed = source.signed; out.missedDays = source.missedDays;
  }
  const signed: FollowForumItem | undefined = guideDay === forumCacheDay() ?
    guide?.items.find((item: FollowForumItem): boolean => item.fid === id && item.fname === name) : undefined;
  if (out.signed === undefined && signed?.signKnown) { out.signed = signed.isSigned; }
  if (confirmedSigns.get(name) === forumCacheDay()) { out.signed = true; }
  return out;
}
export async function readForumShared(context: common.UIAbilityContext, name: string,
  id: number, force: boolean = false): Promise<ThreadListResponse> {
  restoreForumCache(context);
  bind(); const value: ForumSnapshot | undefined = forums.get(name);
  if (!force && forumReadFresh(name) && value?.response.data.forum.id === id) {
    hilog.info(0x0000, 'ForumReadCache', 'forum cache hit');
    return value.response;
  }
  const guard: ForumCacheGuard = new ForumCacheGuard(name);
  const existing: Promise<ThreadListResponse> | undefined = reads.get(name);
  if (existing !== undefined) {
    if (!force) { return existing; }
    // 回前台的补读不能把切后台前已发出的请求当成最新结果。
    try { await existing; } catch (_) { /* 旧请求失败后仍允许本轮重新读取。 */ }
    if (!guard.current()) { throw new Error('账号或吧状态已变化'); }
    const trailing: Promise<ThreadListResponse> | undefined = reads.get(name);
    if (trailing !== undefined && trailing !== existing) { return trailing; }
  }
  const request: Promise<ThreadListResponse> = (async (): Promise<ThreadListResponse> => {
    const device = await DeviceIdentity.ensure(context);
    if (!guard.current()) { throw new Error('账号或吧状态已变化'); }
    hilog.info(0x0000, 'ForumReadCache', 'forum request started force=%{public}s', String(force));
    const response = await new TiebaApi().fetchThreadList(device, authSession.session(), name, 1, 1);
    if (!guard.current()) { throw new Error('账号或吧状态已变化'); }
    if (response.ok && response.data.forum.id === id) { publishForumRead(guard, name, response); }
    const signed: boolean | undefined = response.ok ? response.data.membership?.signed : undefined;
    hilog.info(0x0000, 'ForumReadCache', 'forum response ok=%{public}s sign=%{public}d',
      String(response.ok), signed === undefined ? -1 : (signed ? 1 : 0));
    return response;
  })();
  reads.set(name, request);
  try { return await request; } finally { if (reads.get(name) === request) { reads.delete(name); } }
}
export function cachedFollowForums(): FollowForumItem[] | undefined {
  bind(); if (guide === undefined) { return undefined; }
  return guide.items.map((item: FollowForumItem): FollowForumItem => {
    const out = FollowForumItem.copy(item);
    if (guideDay !== forumCacheDay()) { out.signKnown = false; out.isSigned = false; }
    const membership = cachedForumMembership(item.fname, item.fid);
    if (membership !== undefined) {
      if (membership.level >= 0) { out.level = membership.level; }
      out.levelName = membership.levelName; out.currentScore = membership.currentScore; out.nextScore = membership.nextScore;
      out.continuousCount = membership.continuousCount; out.totalCount = membership.totalCount;
      if (membership.signed !== undefined) { out.isSigned = membership.signed; out.signKnown = true; }
    }
    if (confirmedSigns.get(item.fname) === forumCacheDay()) { out.isSigned = true; out.signKnown = true; }
    return out;
  });
}
export async function readFollowForumsShared(context: common.UIAbilityContext, force: boolean = false): Promise<FollowForumList> {
  restoreForumCache(context);
  bind();
  if (!force && guide !== undefined && guideDay === forumCacheDay() && Date.now() - guideAt < FRESH_MS) {
    hilog.info(0x0000, 'ForumReadCache', 'guide cache hit');
    return guide;
  }
  const guard = new ForumCacheGuard();
  const existing: Promise<FollowForumList> | undefined = guideRead;
  if (existing !== undefined) {
    if (!force) { return existing; }
    try { await existing; } catch (_) { /* 只重试读取，不重发任何签到写请求。 */ }
    if (!guard.current()) { throw new Error('账号或吧状态已变化'); }
    if (guideRead !== undefined && guideRead !== existing) { return guideRead; }
  }
  const request: Promise<FollowForumList> = (async (): Promise<FollowForumList> => {
    if (authSession.session().tbs.length === 0) { await authSession.refreshTbs(context); }
    if (!guard.current()) { throw new Error('账号或吧状态已变化'); }
    hilog.info(0x0000, 'ForumReadCache', 'guide request started force=%{public}s', String(force));
    const api: TiebaApi = new TiebaApi();
    const seen: Set<number> = new Set<number>();
    const all: FollowForumItem[] = [];
    let complete: boolean = false;
    for (let page: number = 1; page <= 100; page++) {
      if (!guard.current()) { throw new Error('账号或吧状态已变化'); }
      const response = await api.fetchFollowForums(authSession.session(), page, 50);
      if (!guard.current()) { throw new Error('账号或吧状态已变化'); }
      if (!response.ok) { throw new Error(`关注吧第 ${page} 页读取失败：${response.describeFailure()}`); }
      const before: number = seen.size;
      for (const item of response.data.items) {
        if (item.fid <= 0 || seen.has(item.fid)) { continue; }
        seen.add(item.fid); all.push(item);
      }
      if (!response.data.hasMore) { complete = true; break; }
      if (seen.size === before) { throw new Error('关注吧分页没有新数据，无法确认完整列表'); }
    }
    if (!complete) { throw new Error('关注吧超过 100 页，无法确认完整列表'); }
    const result: FollowForumList = new FollowForumList();
    result.items = all;
    if (guard.current()) {
      result.items = result.items.map((item: FollowForumItem): FollowForumItem => {
        if (confirmedSigns.get(item.fname) !== forumCacheDay()) { return item; }
        const out: FollowForumItem = FollowForumItem.copy(item);
        out.isSigned = true; out.signKnown = true;
        return out;
      });
      guide = result; guideAt = Date.now(); guideServerAt = guideAt; guideDay = forumCacheDay();
      // 新列表的明确签到状态不能再被较旧的吧头快照覆盖；本机已确认的写成功仍优先。
      for (const item of result.items) {
        const cached: ForumSnapshot | undefined = forums.get(item.fname);
        if (cached === undefined || cached.response.data.forum.id !== item.fid) { continue; }
        const membership: ForumMembership = cached.response.data.membership;
        if (item.signKnown && cached.day === guideDay) {
          if (membership.signed !== item.isSigned) {
            cached.at = 0;
            versions.set(item.fname, (versions.get(item.fname) ?? 0) + 1);
            reads.delete(item.fname);
          }
          membership.signed = item.isSigned;
        }
        if (item.continuousCount >= 0) { membership.continuousCount = item.continuousCount; }
        if (item.totalCount >= 0) { membership.totalCount = item.totalCount; }
      }
      fetchedAt = guideAt; store();
      hilog.info(0x0000, 'ForumReadCache', 'guide response applied rows=%{public}d known=%{public}d signed=%{public}d',
        result.items.length, result.items.filter((item: FollowForumItem): boolean => item.signKnown).length,
        result.items.filter((item: FollowForumItem): boolean => item.signKnown && item.isSigned).length);
    }
    return result;
  })();
  guideRead = request;
  try { return await request; } finally { if (guideRead === request) { guideRead = undefined; } }
}
export function invalidateForumRead(name: string): void {
  bind(); versions.set(name, (versions.get(name) ?? 0) + 1); guideRevision++;
  const value: ForumSnapshot | undefined = forums.get(name);
  if (value !== undefined) { value.at = 0; }
  reads.delete(name); guideAt = 0; guideRead = undefined;
}
export function confirmForumSign(name: string, stats: SignStats = new SignStats(), id: number = 0): void {
  invalidateForumRead(name); confirmedSigns.set(name, forumCacheDay());
  let value: ForumSnapshot | undefined = forums.get(name);
  if (value === undefined) {
    const item: FollowForumItem | undefined = guide?.items.find((entry: FollowForumItem): boolean => entry.fname === name);
    const fid: number = id > 0 ? id : (item?.fid ?? 0);
    if (fid > 0) {
      const response: ThreadListResponse = new ThreadListResponse(); response.ok = true;
      response.data.forum.id = fid; response.data.forum.name = name; response.data.forum.followed = true;
      response.data.forum.avatar = item?.avatar ?? '';
      response.data.membership.level = item?.level ?? -1;
      response.data.membership.levelName = item?.levelName ?? '';
      publishForumRead(new ForumCacheGuard(name), name, response);
      value = forums.get(name);
    }
  }
  if (value !== undefined) {
    value.response.data.membership.signed = true;
    value.response.data.membership.currentScore = -1;
    value.response.data.membership.nextScore = -1;
    if (stats.continuousCount >= 0) { value.response.data.membership.continuousCount = stats.continuousCount; }
    if (stats.totalCount >= 0) { value.response.data.membership.totalCount = stats.totalCount; }
    value.at = 0;
    value.serverAt = Date.now(); value.accessedAt = value.serverAt;
    value.day = forumCacheDay();
  }
  if (guide !== undefined && guideDay === forumCacheDay()) {
    guide.items = guide.items.map((item: FollowForumItem): FollowForumItem => {
      const out = FollowForumItem.copy(item);
      if (out.fname === name) { out.isSigned = true; out.signKnown = true; }
      return out;
    });
  }
  fetchedAt = Date.now(); store(true);
}

/** A confirmed write replaces the relationship before any older read can publish. */
export function confirmForumFollow(name: string, id: number, following: boolean): void {
  invalidateForumRead(name);
  let value: ForumSnapshot | undefined = forums.get(name);
  if (value === undefined && id > 0) {
    const response: ThreadListResponse = new ThreadListResponse();
    response.ok = true; response.data.forum.id = id; response.data.forum.name = name;
    response.data.forum.avatar = ''; response.data.forum.followed = following;
    value = new ForumSnapshot(response, 0);
    value.serverAt = fetchedAt; forums.set(name, value);
  }
  if (value !== undefined) { value.response.data.forum.followed = following; }
  if (guide !== undefined) {
    guide.items = guide.items.filter((item: FollowForumItem): boolean => item.fid !== id);
    if (following && value !== undefined) {
      const item: FollowForumItem = new FollowForumItem();
      item.fid = id; item.fname = name; item.avatar = value.response.data.forum.avatar;
      item.level = value.response.data.membership.level;
      item.levelName = value.response.data.membership.levelName;
      item.currentScore = value.response.data.membership.currentScore;
      item.nextScore = value.response.data.membership.nextScore;
      guide.items.push(item);
    }
  }
  store(true);
}
