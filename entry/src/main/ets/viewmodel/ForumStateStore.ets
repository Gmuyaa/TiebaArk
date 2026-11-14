/**
 * 吧级身份的单一真相层（2026-11-13，1.0.268）。
 *
 * 关注关系、今日签到、贴吧等级/经验/连签原本由三处各自维护：`FollowActionVM`（关注态）、
 * `ForumHeaderVM`（签到态）、`ForumReadCache`/`FollowVM`（关注列表）。同一份数据在三个位置
 * 各有自己的"已知/读取中/已过期"标志，于是同一个吧在吧页、吧资料、进吧列表里显示不一致，
 * 而且每进一次页面就要再读一次。
 *
 * 本模块把这些状态收敛到「账号 + fid」一份实例上：
 * - 页面只持有 `forumIdentity(fid, name)` 的引用并读它的 `@Trace` 字段，不再各自发读取；
 * - 读取按新鲜期与「今日已确认签到」单调规则决定，同吧并发请求合并为一次（单飞）；
 * - 写成功（关注/签到）立即广播，关注列表、吧资料按钮、吧页头同时生效；
 * - 吧页首包（FRS 第一页同时带 `is_like` 与 `sign_in_info`）直接回填，不再单独发 rn=1 请求；
 * - 关注吧列表一次覆盖所有已关注吧的签到/等级，作为批量真相源回填；
 * - 冷启动从既有落盘快照（`utils/ForumSnapshotStore`，沿用原预算与账号隔离）预热，不新增磁盘容器。
 *
 * 边界：仅内存 + 既有快照；换号清空；日期按北京日（`forumCacheDay`）判定；
 * 失败不清空已知值；未知（undefined）不等于"未关注/未签到"。
 *
 * 生命周期（2026-11-14 定，审计 C9）：本模块**没有也刻意不提供 `dispose`**。它是进程级单例，
 * 状态按「账号 + fid」存在模块内的 `identities` 表里，唯一的失效入口是 `bind()` 检测到
 * `forumCacheSessionKey()` 变化时的整体清空——这条路径已经在换号、登出、冷启动各走过。
 * 页面（`ForumHeaderVM`、`ForumIdentity` 等）销毁时只清自己持有的引用与本页临时状态，
 * 不会、也不应该去停用共享身份：否则返回再进同一个吧就会退化成"每次重建再读一次"，
 * 正是 1.0.268 之前的状态。真要回收，只需要在 `bind()` 里加一条（例如低内存回调），
 * 不需要给每个页面一个销毁入口；在没有这样的真实需求之前不加。
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TiebaApi, ThreadListResponse } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { FORUM_FOLLOW_FRESH_MS, FORUM_IDENTITY_CACHE_ENTRIES, FORUM_SIGN_FRESH_MS } from '../model/CachePolicy';
import { FollowForumItem, FollowForumList } from '../model/FollowForum';
import { SignStats } from '../model/SignStats';
import { ForumMembership } from '../model/ThreadList';
import { TiebaDevice } from '../net/TiebaParams';
import { cachedForumFollow, cachedForumFollowStamp, cachedForumMembership, confirmForumFollow, confirmForumSign,
  forumCacheDay, readFollowForumsShared, readForumShared } from './ForumReadCache';
import { followChanges } from './FollowActionVM';
import { DeviceIdentity } from '../utils/DeviceIdentity';

/** 贴吧签到按北京时间换日；签到态只在同一天内成立。全工程只用这一处。 */
export function forumSignDay(): string {
  return forumCacheDay();
}

/** 等吧页首包回填的最长时间；超时后自行读取（列表失败时不能把按钮永远停在"读取中"）。 */
const FIRST_PACKET_WAIT_MS: number = 2500;

/** 身份级写/读变化计数：页面据此做派生动作（关注列表按 store 校正签到标记等）。 */
@ObservedV2
export class ForumStateChanges {
  @Trace signRevision: number = 0;
  @Trace followRevision: number = 0;
}
export const forumStateChanges: ForumStateChanges = new ForumStateChanges();

/** 一个吧在当前账号下的关系与统计。字段为 `undefined` 表示未知，不能当成"未关注/未签到"。 */
@ObservedV2
export class ForumIdentity {
  @Trace following: boolean | undefined = undefined;
  @Trace signed: boolean | undefined = undefined;
  @Trace signDay: string = '';
  @Trace level: number = -1;
  @Trace levelName: string = '';
  @Trace currentScore: number = -1;
  @Trace nextScore: number = -1;
  @Trace missedDays: number = -1;
  @Trace continuousCount: number = -1;
  @Trace totalCount: number = -1;
  @Trace reading: boolean = false;
  @Trace signing: boolean = false;
  @Trace pending: boolean = false;
  @Trace verifying: boolean = false;
  @Trace verificationError: string = '';
  @Trace error: string = '';
  /** 每次服务端回包或写确认应用后 +1。 */
  @Trace revision: number = 0;
  fid: number = 0;
  name: string = '';
  owner: string = '';
  /** 关注关系最近一次确认（读或写）的时刻。 */
  followAt: number = 0;
  /** 等级/签到数据最近一次应用的时刻与日期。 */
  appliedAt: number = 0;
  appliedDay: string = '';
  /** 本机写成功的签到日；当日最高优先级，不再被过期响应覆盖。 */
  confirmedSignDay: string = '';
  sequence: number = 0;

  known(): boolean { return this.following !== undefined; }
  follows(): boolean { return this.following === true; }

  /** 今日签到是否已知；跨日旧值不算。 */
  signKnown(day: string = forumSignDay()): boolean {
    return this.signed !== undefined && this.signDay === day;
  }

  /** 完成外观只使用今日已确认的签到状态。 */
  completed(day: string = forumSignDay()): boolean {
    return this.follows() && !this.pending && this.signKnown(day) && this.signed === true;
  }

  /** 关注关系是否需要重新读取。 */
  followStale(now: number = Date.now()): boolean {
    return this.following === undefined || now - this.followAt > FORUM_FOLLOW_FRESH_MS;
  }

  /**
   * 签到态是否需要重新读取。
   * 今天已确认「已签到」是单调事实（一天只能签一次），不再重读；
   * 未签到/未知则按当天新鲜期重新读取，以捕捉在其它客户端签到的情况。
   */
  signStale(day: string = forumSignDay(), now: number = Date.now()): boolean {
    if (this.signed === true && this.signDay === day) { return false; }
    if (this.signed === undefined) { return true; }
    return this.signDay !== day || now - this.appliedAt > FORUM_SIGN_FRESH_MS;
  }

  needsRead(force: boolean = false): boolean {
    if (force) { return true; }
    return this.followStale() || this.signStale();
  }
}

const identities: Map<string, ForumIdentity> = new Map<string, ForumIdentity>();
const reads: Map<string, Promise<void>> = new Map<string, Promise<void>>();
const aliases: Map<string, number> = new Map<string, number>();
/** 每个等待者带自己的超时句柄：被 `resolveWaiters` 提前唤醒时要把定时器一起清掉。 */
interface ApplyWaiter {
  finish: () => void;
  timer: number;
}
const waiters: ApplyWaiter[] = [];
const firstPages: Set<string> = new Set<string>();
let boundOwner: string = '';

function account(): string {
  return authSession.forumCacheSessionKey();
}

/** 账号会话变化即整体失效：旧身份、在途读取、别名与等待者都不能跨账号。 */
function bind(): void {
  const next: string = account();
  if (boundOwner === next) { return; }
  boundOwner = next;
  identities.clear(); reads.clear(); aliases.clear(); firstPages.clear();
  resolveWaiters();
}

function resolveWaiters(): void {
  if (waiters.length === 0) { return; }
  const pending: ApplyWaiter[] = waiters.slice();
  waiters.length = 0;
  for (const waiter of pending) {
    if (waiter.timer >= 0) { clearTimeout(waiter.timer); waiter.timer = -1; }
    waiter.finish();
  }
}

function waitForApply(timeoutMs: number): Promise<void> {
  return new Promise<void>((resolve) => {
    let done: boolean = false;
    const waiter: ApplyWaiter = {
      timer: -1,
      finish: (): void => {
        if (done) { return; }
        done = true;
        if (waiter.timer >= 0) { clearTimeout(waiter.timer); waiter.timer = -1; }
        resolve();
      }
    };
    waiters.push(waiter);
    waiter.timer = setTimeout(waiter.finish, timeoutMs);
  });
}

function current(value: ForumIdentity, sequence: number, day: string = ''): boolean {
  bind();
  if (value.owner !== boundOwner || sequence !== value.sequence) { return false; }
  return day.length === 0 || day === forumSignDay();
}

function trimIdentities(keep: string): void {
  while (identities.size > FORUM_IDENTITY_CACHE_ENTRIES) {
    const oldest: string | undefined = Array.from(identities.keys())[0];
    if (oldest === undefined || oldest === keep) { return; }
    identities.delete(oldest);
  }
}

function touchIdentity(key: string, value: ForumIdentity): void {
  identities.delete(key);
  identities.set(key, value);
  trimIdentities(key);
}

/** 冷启动/首次取用：先用既有内存缓存与落盘快照预热，避免为了"已知状态"再发请求。 */
function seedFromCache(value: ForumIdentity, fid: number): void {
  if (fid <= 0 || value.name.length === 0) { return; }
  const followed: boolean | undefined = cachedForumFollow(value.name, fid);
  if (followed !== undefined) {
    value.following = followed;
    /*
     * 新鲜期从**数据真正取得的时刻**算，不从现在算：
     * 落盘快照可能是几小时前的，记成 `Date.now()` 会让一份隔夜数据再"续命"十分钟，
     * 其它设备上的关注变更因此迟迟不生效。0 = 时间未知 → 按已过期处理，下次进吧重新确认。
     */
    value.followAt = cachedForumFollowStamp(value.name, fid);
  }
  const cached: ForumMembership | undefined = cachedForumMembership(value.name, fid);
  if (cached === undefined) { return; }
  applyMembershipFields(value, cached);
  // cachedForumMembership 只返回当天的签到值（快照、关注吧列表与写确认都按北京日过滤）。
  if (cached.signed !== undefined) {
    value.signed = cached.signed; value.signDay = forumSignDay(); value.appliedDay = value.signDay;
  }
}

function applyMembershipFields(value: ForumIdentity, membership: ForumMembership): void {
  if (membership.level >= 0) { value.level = membership.level; }
  if (membership.levelName.length > 0) { value.levelName = membership.levelName; }
  if (membership.currentScore >= 0) { value.currentScore = membership.currentScore; }
  if (membership.nextScore >= 0) { value.nextScore = membership.nextScore; }
  if (membership.continuousCount >= 0) { value.continuousCount = membership.continuousCount; }
  if (membership.totalCount >= 0) { value.totalCount = membership.totalCount; }
  if (membership.missedDays >= 0) { value.missedDays = membership.missedDays; }
}

/**
 * 取当前账号下某个吧的身份实例。同一个吧在所有页面拿到**同一个对象**：
 * 写确认与读取回填都会通知到已挂载的页面，不需要各页面自己再读一次。
 * fid 尚未取得时先按吧名占位，之后 `registerForumAlias` 会把同一实例升级到 fid 键。
 */
export function forumIdentity(fid: number, name: string): ForumIdentity {
  bind();
  const forumName: string = typeof name === 'string' ? name.trim() : '';
  const id: number = fid > 0 ? fid : (aliases.get(forumName) ?? 0);
  const key: string = id > 0 ? `${boundOwner}:${id}` : `${boundOwner}:n:${forumName}`;
  let value: ForumIdentity | undefined = identities.get(key);
  if (value === undefined && id > 0 && forumName.length > 0) {
    // 先按名登记过的实例（页面在 fid 回来之前就建了按钮）原地升级，不产生第二个"真相"。
    const provisionalKey: string = `${boundOwner}:n:${forumName}`;
    const provisional: ForumIdentity | undefined = identities.get(provisionalKey);
    if (provisional !== undefined) {
      identities.delete(provisionalKey);
      value = provisional;
    }
  }
  if (value === undefined) {
    value = new ForumIdentity();
    value.owner = boundOwner;
    value.name = forumName;
    seedFromCache(value, id);
  } else if (value.fid <= 0 && id > 0) {
    value.fid = id;
    seedFromCache(value, id);
  }
  // 吧名是缓存与落盘快照的键：以最近一次回包/调用给出的名字为准（改名后不会继续用旧名查缓存）。
  if (forumName.length > 0 && value.name !== forumName) { value.name = forumName; }
  if (id > 0 && forumName.length > 0) { aliases.set(forumName, id); }
  touchIdentity(key, value);
  return value;
}

/** 记录「吧名 → fid」：吧资料回包不带关注字段，但能把名字与 fid 对上，后续按名查同一实例。 */
export function registerForumAlias(fid: number, name: string): void {
  bind();
  const forumName: string = typeof name === 'string' ? name.trim() : '';
  if (fid <= 0 || forumName.length === 0) { return; }
  aliases.set(forumName, fid);
  const provisionalKey: string = `${boundOwner}:n:${forumName}`;
  if (identities.get(provisionalKey) !== undefined) { forumIdentity(fid, forumName); }
}

function notifyApplied(): void {
  resolveWaiters();
}

/** 把一次服务端回包写入身份：缺字段保留旧值，未知不覆盖已知。 */
function applyMembership(value: ForumIdentity, followed: boolean | undefined,
  membership: ForumMembership | undefined, day: string): void {
  const now: number = Date.now();
  if (followed !== undefined) { value.following = followed; value.followAt = now; }
  if (membership !== undefined) {
    applyMembershipFields(value, membership);
    // 本机已确认的当天签到优先于可能过期的 is_sign。
    if (value.confirmedSignDay !== day && membership.signed !== undefined) {
      value.signed = membership.signed;
    }
  }
  if (value.confirmedSignDay === day) { value.signed = true; }
  value.signDay = day;
  value.appliedDay = day;
  value.appliedAt = now;
  value.revision++;
}

/** 吧页首包 / 任意 FRS 首页回包：关注关系 + 今日签到 + 等级经验一次性取用。 */
export function applyForumRead(response: ThreadListResponse): void {
  bind();
  if (!response.ok || response.data.forum.id <= 0) { return; }
  const value: ForumIdentity = forumIdentity(response.data.forum.id, response.data.forum.name);
  applyMembership(value, response.data.forum.followed, response.data.membership, forumSignDay());
  value.error = '';
  notifyApplied();
}

/** 吧广场等列表里的关注标记（只有明确布尔才采纳）。 */
export function applyForumFollowing(fid: number, name: string, following: boolean | undefined): void {
  bind();
  if (following === undefined || fid <= 0) { return; }
  const value: ForumIdentity = forumIdentity(fid, name);
  if (value.pending || value.verifying) { return; }
  value.following = following; value.followAt = Date.now();
  value.revision++;
}

/** 关注吧列表：一份响应覆盖所有已关注吧的签到、等级与连签。 */
export function applyFollowGuide(list: FollowForumList): void {
  bind();
  const day: string = forumSignDay();
  const now: number = Date.now();
  for (const item of list.items) {
    if (item.fid <= 0) { continue; }
    const value: ForumIdentity = forumIdentity(item.fid, item.fname);
    value.following = true; value.followAt = now;
    const membership: ForumMembership = new ForumMembership();
    membership.level = item.level; membership.levelName = item.levelName;
    membership.currentScore = item.currentScore; membership.nextScore = item.nextScore;
    membership.continuousCount = item.continuousCount; membership.totalCount = item.totalCount;
    applyMembershipFields(value, membership);
    if (item.signKnown && value.confirmedSignDay !== day) {
      value.signed = item.isSigned; value.signDay = day;
    }
    if (value.confirmedSignDay === day) { value.signed = true; }
    if (value.signDay === day) { value.appliedAt = now; }
    value.appliedDay = day;
    value.revision++;
  }
  notifyApplied();
}

/** 写确认：关注关系。同步既有落盘快照、关注吧列表与"进吧"列表的刷新计数。 */
export function confirmFollow(fid: number, name: string, following: boolean): void {
  bind();
  const value: ForumIdentity = forumIdentity(fid, name);
  value.following = following; value.followAt = Date.now();
  value.verificationError = ''; value.error = ''; value.revision++;
  confirmForumFollow(value.name, fid, following);
  followChanges.forums++;
  forumStateChanges.followRevision++;
  notifyApplied();
}

/** 写确认：今日签到。当天已签是单调事实，之后不再为此重读。 */
export function confirmSign(fid: number, name: string, stats: SignStats = new SignStats()): void {
  bind();
  const value: ForumIdentity = forumIdentity(fid, name);
  const day: string = forumSignDay();
  value.signed = true; value.signDay = day; value.confirmedSignDay = day;
  if (stats.continuousCount >= 0) { value.continuousCount = stats.continuousCount; }
  if (stats.totalCount >= 0) { value.totalCount = stats.totalCount; }
  value.appliedDay = day; value.appliedAt = Date.now();
  value.error = ''; value.verificationError = ''; value.revision++;
  confirmForumSign(value.name, stats, fid);
  forumStateChanges.signRevision++;
  hilog.info(0x0000, 'ForumStateStore', 'sign confirmed fid=%{public}d name=%{public}s',
    fid, name);
  notifyApplied();
}

/** 吧页正在拉首包：本次状态读取等它回填，不再重复发一次 rn=1 的首页请求。 */
export function markFirstPageRead(name: string): void {
  bind();
  const forumName: string = name.trim();
  if (forumName.length > 0) { firstPages.add(forumName); }
}

export function clearFirstPageRead(name: string): void {
  const forumName: string = name.trim();
  if (forumName.length === 0) { return; }
  firstPages.delete(forumName);
  resolveWaiters();
}

/**
 * 保证某个吧的身份状态可用。force 用于回前台与用户点重试。
 * 同吧并发调用合并为一次网络读取；失败保留已知值并只记录错误，避免连点重复打服务端。
 */
export async function ensureForumIdentity(context: common.UIAbilityContext, fid: number, name: string,
  force: boolean = false): Promise<void> {
  bind();
  const value: ForumIdentity = forumIdentity(fid, name);
  const day: string = forumSignDay();
  if (value.pending || value.verifying || value.signing || value.reading) { return; }
  // 未登录：吧页仍可看吧简介与公开计数，但关注关系只能是"未关注"（登录后才能关注）。
  if (!authSession.isLoggedIn()) {
    if (value.following === undefined) { value.following = false; value.followAt = Date.now(); }
    return;
  }
  if (!force && !value.needsRead()) {
    hilog.info(0x0000, 'ForumStateStore', 'state reused fid=%{public}d follow=%{public}d sign=%{public}d',
      value.fid, value.following === undefined ? -1 : (value.following ? 1 : 0),
      value.signed === undefined ? -1 : (value.signed ? 1 : 0));
    return;
  }
  if (value.fid <= 0) { return; }
  if (!force && firstPages.has(value.name)) {
    await waitForApply(FIRST_PACKET_WAIT_MS);
    if (!value.needsRead()) { return; }
  }
  // 今天已经失败过一次：等用户点重试，不自动重发。
  if (!force && value.error.length > 0 && value.appliedDay === day) { return; }
  const key: string = `${boundOwner}:${value.fid}`;
  const existing: Promise<void> | undefined = reads.get(key);
  if (existing !== undefined) { await existing; return; }
  const sequence: number = ++value.sequence;
  value.reading = true;
  value.error = '';
  hilog.info(0x0000, 'ForumStateStore', 'state read started fid=%{public}d force=%{public}s',
    value.fid, String(force));
  const request: Promise<void> = (async (): Promise<void> => {
    try {
      const response: ThreadListResponse = await readForumShared(context, value.name, value.fid, force);
      if (!current(value, sequence)) { return; }
      if (!response.ok || response.data.forum.id !== value.fid) {
        value.error = response.ok ? '吧信息不匹配，请重试' : response.describeFailure();
        value.appliedDay = forumSignDay();
        return;
      }
      applyMembership(value, response.data.forum.followed, response.data.membership, forumSignDay());
      notifyApplied();
      if (!value.follows()) { return; }
      if (value.signed !== undefined) { return; }
      // FRS 偶尔省略签到段：复用已验证的关注吧只读链路，一次完整列表覆盖所有已关注吧。
      const guide: FollowForumList = await readFollowForumsShared(context, force);
      if (!current(value, sequence)) { return; }
      applyFollowGuide(guide);
    } catch (err) {
      if (current(value, sequence)) {
        value.error = '吧等级和签到状态读取失败，请重试';
        value.appliedDay = forumSignDay();
      }
    } finally {
      if (sequence === value.sequence) { value.reading = false; }
      if (current(value, sequence) && value.follows() && value.signed === undefined &&
        value.error.length === 0) {
        value.error = '签到状态暂未获取，请重试';
      }
    }
  })();
  reads.set(key, request);
  try { await request; } finally { if (reads.get(key) === request) { reads.delete(key); } }
}

/** 后台核对关注关系：写结果不明确或与目标不一致时以只读结果为准，失败置回未知。 */
async function verifyFollow(value: ForumIdentity, target: boolean | undefined,
  context: common.UIAbilityContext): Promise<void> {
  if (value.fid <= 0) { return; }
  const sequence: number = ++value.sequence;
  value.verifying = true;
  const started: number = Date.now();
  try {
    for (let attempt: number = 0; attempt < 3; attempt++) {
      if (attempt > 0) { await new Promise<void>((resolve) => { setTimeout(resolve, 500); }); }
      if (!current(value, sequence)) { return; }
      let read: boolean | undefined = undefined;
      try {
        const response: ThreadListResponse = await readForumShared(context, value.name, value.fid, true);
        if (!current(value, sequence)) { return; }
        read = response.ok && response.data.forum.id === value.fid ? response.data.forum.followed : undefined;
        if (response.ok && response.data.forum.id === value.fid) {
          applyMembership(value, undefined, response.data.membership, forumSignDay());
        }
      } catch (err) { read = undefined; }
      if (!current(value, sequence)) { return; }
      if (read !== undefined && (target === undefined || read === target)) {
        if (read !== value.following || target === undefined) {
          // 与目标一致或结果未知：以只读结果为准并同步关注列表。
          confirmFollow(value.fid, value.name, read);
        } else {
          value.verificationError = '';
          value.revision++;
        }
        return;
      }
    }
    if (!current(value, sequence)) { return; }
    value.following = undefined;
    value.verificationError = '关注状态核对失败，请点击重试';
  } finally {
    if (sequence === value.sequence) {
      value.verifying = false;
      hilog.info(0x0000, 'ForumStateStore', 'verify completed fid=%{public}d known=%{public}s ms=%{public}d',
        value.fid, String(value.known()), Date.now() - started);
    }
  }
}

/**
 * 关注/取关（吧）。只有明确业务成功才发布关系；传输超时只做只读核对，不重发写请求。
 * 返回给界面的提示语，空串表示不需要提示。
 */
export async function toggleForumFollow(context: common.UIAbilityContext, fid: number, name: string): Promise<string> {
  bind();
  const value: ForumIdentity = forumIdentity(fid, name);
  if (value.pending || value.reading || value.fid <= 0) { return ''; }
  if (!authSession.isLoggedIn()) { return '需要登录后才能关注'; }
  if (!value.known()) { await ensureForumIdentity(context, fid, name); return ''; }
  const previous: boolean = value.following === true;
  const target: boolean = !previous;
  value.pending = true;
  // 核对未回包时的再次点击：立即反向，旧核对的代次作废（与用户按钮同一语义）。
  value.verifying = false;
  value.verificationError = '';
  value.error = '';
  const sequence: number = ++value.sequence;
  const started: number = Date.now();
  let device: TiebaDevice | undefined = undefined;
  let sent: boolean = false;
  let rollback: boolean = true;
  // 即时展示点击意图；业务拒绝时回退，未知写结果只做只读核对。
  value.following = target;
  try {
    if (authSession.session().tbs.length === 0) {
      const refreshed = await authSession.refreshTbs(context);
      if (!refreshed.ok) { return refreshed.message; }
    }
    if (!current(value, sequence)) { return '账号已变化，请重新操作'; }
    device = await DeviceIdentity.ensure(context);
    if (!current(value, sequence)) { return '账号已变化，请重新操作'; }
    sent = true;
    rollback = false;
    const result = await new TiebaApi().setFollow(device, authSession.session(), 'forum',
      value.fid, '', target);
    if (!current(value, sequence)) { return ''; }
    if (!result.ok) {
      if (result.transportError.length > 0 || result.errorCode < 0) {
        value.pending = false;
        void verifyFollow(value, undefined, context);
      } else {
        rollback = true;
      }
      return result.describeFailure();
    }
    value.pending = false;
    confirmFollow(value.fid, value.name, target);
    hilog.info(0x0000, 'ForumStateStore', 'follow write confirmed fid=%{public}d following=%{public}s ms=%{public}d',
      value.fid, String(target), Date.now() - started);
    void verifyFollow(value, target, context);
    return '';
  } catch (err) {
    if (!current(value, sequence)) { return ''; }
    if (sent) {
      rollback = false;
      value.pending = false;
      void verifyFollow(value, undefined, context);
    }
    return '关注操作或状态确认失败，请点击重试';
  } finally {
    if (rollback) { value.following = previous; }
    if (current(value, sequence)) { value.pending = false; }
  }
}

/** 签到（吧）。真实写操作：业务成功后写入当日确认并广播。 */
export async function signForum(context: common.UIAbilityContext, fid: number, name: string): Promise<string> {
  bind();
  const value: ForumIdentity = forumIdentity(fid, name);
  if (value.signing || value.pending || value.reading || value.verifying || value.fid <= 0) { return ''; }
  const day: string = forumSignDay();
  if (value.signed === true && value.signDay === day) { return '今天已经签过啦'; }
  value.signing = true;
  const sequence: number = ++value.sequence;
  try {
    if (authSession.session().tbs.length === 0) {
      const result = await authSession.refreshTbs(context);
      if (!current(value, sequence, day)) { return ''; }
      if (!result.ok) { return result.message; }
    }
    const device: TiebaDevice = await DeviceIdentity.ensure(context);
    if (!current(value, sequence, day)) { return ''; }
    const response = await new TiebaApi().signForum(device, authSession.session(), value.name);
    if (!current(value, sequence, day)) { return ''; }
    if (!response.ok) { return response.describeFailure(); }
    confirmSign(value.fid, value.name, response.stats);
    return response.alreadySigned ? '今天已经签过啦' :
      (response.bonusPoint.length > 0 ? `签到成功 +${response.bonusPoint} 经验` : '签到成功');
  } catch (err) {
    return current(value, sequence, day) ? '签到失败，请重试' : '';
  } finally {
    if (sequence === value.sequence) { value.signing = false; }
  }
}

/** 仅用例调用：清空全部身份与在途状态。 */
export function resetForumIdentities(): void {
  identities.clear(); reads.clear(); aliases.clear(); firstPages.clear();
  resolveWaiters();
}
