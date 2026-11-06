import { confirmForumFollow, invalidateForumRead, readForumShared } from './ForumReadCache';
import { FOLLOW_ACTION_CACHE_ENTRIES } from '../model/CachePolicy';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { FollowKind } from '../model/FollowOperation';
import { profilePortrait } from '../model/PageDirectory';
import { TiebaDevice } from '../net/TiebaParams';
import { DeviceIdentity } from '../utils/DeviceIdentity';

/** 账号隔离，不将凭据作为缓存键；返回旧页面也共享已确认的关系。 */
function accountKey(): string {
  return authSession.isLoggedIn() ? authSession.forumCacheSessionKey() : 'anonymous';
}

@ObservedV2
export class FollowChanges {
  @Trace forums: number = 0;
  @Trace users: number = 0;
}
export const followChanges: FollowChanges = new FollowChanges();

const READ_CACHE_MS: number = 30000;
let writeRevision: number = 0;

/** 页面请求发出时捕获账号和写版本，防止旧响应覆盖新关系。 */
export class FollowReadGuard {
  private owner: string = accountKey();
  private revision: number = writeRevision;
  current(): boolean { return this.owner === accountKey() && this.revision === writeRevision; }
}

export function seedFollowState(guard: FollowReadGuard, kind: FollowKind, id: number,
  portrait: string, name: string, value: boolean | undefined): void {
  if (!guard.current() || !authSession.isLoggedIn() || value === undefined || id <= 0) { return; }
  followAction(kind, id, portrait, name).acceptRead(value);
}

@ObservedV2
export class FollowActionVM {
  @Trace following: boolean = false;
  @Trace known: boolean = false;
  @Trace loading: boolean = false;
  @Trace pending: boolean = false;
  @Trace verifying: boolean = false;
  @Trace verificationError: string = '';
  @Trace self: boolean = false;
  private api: TiebaApi = new TiebaApi();
  private owner: string;
  private sequence: number = 0;
  private readAt: number = 0;
  private portrait: string;
  private kind: FollowKind;
  private id: number;
  private name: string;

  constructor(kind: FollowKind, id: number, portrait: string, name: string) {
    this.kind = kind;
    this.id = id;
    this.name = name;
    this.portrait = profilePortrait(portrait);
    this.owner = accountKey();
    this.self = kind === 'user' && authSession.isLoggedIn() &&
      ((id > 0 && id === authSession.snapshot.uid) ||
        (this.portrait.length > 0 && this.portrait === profilePortrait(authSession.snapshot.portrait)));
  }

  private current(): boolean { return this.owner === accountKey(); }

  /** 仅接受已验证页面响应；使正在重复读取的旧请求失效。 */
  acceptRead(value: boolean): void {
    if (!this.current() || this.pending || this.verifying) { return; }
    ++this.sequence;
    this.following = value;
    this.known = true;
    this.readAt = Date.now();
    this.loading = false;
  }

  private async read(device: TiebaDevice, context: common.UIAbilityContext, sequence: number = this.sequence): Promise<boolean | undefined> {
    const session = authSession.session();
    if (this.kind === 'forum') {
      const response = await readForumShared(context, this.name, this.id, this.verifying);
      return response.ok && response.data.forum.id === this.id ? response.data.forum.followed : undefined;
    }
    const response = await this.api.fetchPublicProfile(device, session, this.id, this.portrait);
    if (!response.ok || !this.current() || sequence !== this.sequence) { return undefined; }
    if (this.portrait.length === 0) { this.portrait = profilePortrait(response.data.portrait); }
    if (response.data.uid === authSession.snapshot.uid) { this.self = true; }
    return response.data.followed;
  }

  async load(context: common.UIAbilityContext): Promise<string> {
    if (this.loading || this.pending || this.verifying || this.self || !this.current()) { return ''; }
    if (this.known && Date.now() - this.readAt < READ_CACHE_MS) { return ''; }
    if (!authSession.isLoggedIn()) { this.known = true; this.following = false; return ''; }
    const sequence: number = ++this.sequence;
    this.loading = true;
    try {
      const value: boolean | undefined = await this.read(await DeviceIdentity.ensure(context), context, sequence);
      if (!this.current() || sequence !== this.sequence) { return ''; }
      if (value === undefined) { return '无法读取关注状态，请重试'; }
      const corrected: boolean = !this.known && this.verificationError.length > 0 && value !== this.following;
      this.following = value;
      this.known = true;
      this.readAt = Date.now();
      this.verificationError = '';
      if (corrected) { this.notifyChanged(context); }
      return '';
    } catch (err) { return '无法读取关注状态，请重试'; }
    finally { if (sequence === this.sequence) { this.loading = false; } }
  }

  /** 写响应已明确成功时，资料端点的核对与重试不再阻塞按钮。 */
  private async verify(device: TiebaDevice, target: boolean | undefined, sequence: number,
    context: common.UIAbilityContext): Promise<void> {
    this.verifying = true;
    const started: number = Date.now();
    let value: boolean | undefined = undefined;
    try {
      for (let attempt: number = 0; attempt < 3; attempt++) {
        if (attempt > 0) { await new Promise<void>((resolve) => { setTimeout(resolve, 500); }); }
        if (!this.current() || sequence !== this.sequence) { return; }
        try { value = await this.read(device, context, sequence); } catch (err) { value = undefined; }
        if (!this.current() || sequence !== this.sequence) { return; }
        if (value !== undefined && (target === undefined || value === target)) {
          const changed: boolean = value !== this.following;
          this.following = value;
          this.known = true;
          this.readAt = Date.now();
          this.verificationError = '';
          if (changed || target === undefined) { this.notifyChanged(context); }
          return;
        }
      }
      if (!this.current() || sequence !== this.sequence) { return; }
      this.known = false;
      this.verificationError = value === undefined ? '关注状态核对失败，请点击重试' :
        '服务端关注状态与操作结果不一致，请点击重试';
    } finally {
      if (sequence === this.sequence) {
        this.verifying = false;
        hilog.info(0x0000, 'FollowActionVM', 'verify completed kind=%{public}s known=%{public}s ms=%{public}d',
          this.kind, String(this.known), Date.now() - started);
        // 核对期间发出的旧页面资料也不得在核对结束后覆盖关系。
        ++writeRevision;
      }
    }
  }

  private notifyChanged(context: common.UIAbilityContext): void {
    if (this.kind === 'forum') { followChanges.forums++; } else { followChanges.users++; }
    void authSession.refreshProfile(context);
  }

  async toggle(context: common.UIAbilityContext): Promise<string> {
    if (this.pending || this.loading || this.self || !this.current()) { return ''; }
    if (!authSession.isLoggedIn()) { return '需要登录后才能关注'; }
    if (!this.known) { return this.load(context); }
    if (this.kind === 'forum') { invalidateForumRead(this.name); }
    this.pending = true;
    this.verifying = false;
    this.verificationError = '';
    ++writeRevision;
    const sequence: number = ++this.sequence;
    const previous: boolean = this.following;
    const target: boolean = !previous;
    // 即时展示点击意图；业务拒绝时回退，未知写结果只读核对。
    this.following = target;
    const started: number = Date.now();
    let device: TiebaDevice | undefined = undefined;
    let sent: boolean = false;
    let rollback: boolean = true;
    try {
      if (authSession.session().tbs.length === 0) {
        const refreshed = await authSession.refreshTbs(context);
        if (!refreshed.ok) { return refreshed.message; }
      }
      if (!this.current()) { return '账号已变化，请重新操作'; }
      device = await DeviceIdentity.ensure(context);
      if (!this.current()) { return '账号已变化，请重新操作'; }
      sent = true;
      rollback = false;
      const result = await this.api.setFollow(device, authSession.session(), this.kind,
        this.id, this.portrait, target);
      if (!this.current()) { return ''; }
      if (!result.ok) {
        // 超时或非法响应不能假定写入未执行，先只读核对再允许重写。
        if (result.transportError.length > 0 || result.errorCode < 0) {
          this.known = false;
          void this.verify(device, undefined, sequence, context);
        } else {
          rollback = true;
        }
        return result.describeFailure();
      }
      // 严格业务成功后才发布列表与统计刷新，并在后台核对。
      this.following = target;
      this.known = true;
      this.readAt = Date.now();
      if (this.kind === 'forum') { confirmForumFollow(this.name, this.id, target); }
      hilog.info(0x0000, 'FollowActionVM', 'write confirmed kind=%{public}s ms=%{public}d',
        this.kind, Date.now() - started);
      this.notifyChanged(context);
      void this.verify(device, target, sequence, context);
      return '';
    } catch (err) {
      if (!this.current()) { return ''; }
      if (sent) { this.known = false; }
      if (sent && device !== undefined) { void this.verify(device, undefined, sequence, context); }
      return '关注操作或状态确认失败，请点击重试';
    } finally {
      if (rollback) { this.following = previous; }
      ++writeRevision;
      this.pending = false;
    }
  }
}

// 弱索引保留仍被页面使用的共享实例；只有最近的有限条目被缓存强持有。
const actions: Map<string, WeakRef<FollowActionVM>> = new Map();
const recentActions: Map<string, FollowActionVM> = new Map();
let actionOwner: string = '';
function bindActions(): void {
  const owner: string = accountKey();
  if (owner !== actionOwner) {
    actions.clear(); recentActions.clear(); actionOwner = owner;
  }
  actions.forEach((reference: WeakRef<FollowActionVM>, key: string): void => {
    if (reference.deref() === undefined) { actions.delete(key); }
  });
}
export function followAction(kind: FollowKind, id: number, portrait: string, name: string): FollowActionVM {
  bindActions();
  const key: string = `${accountKey()}:${kind}:${id > 0 ? String(id) : profilePortrait(portrait)}`;
  let action: FollowActionVM | undefined = actions.get(key)?.deref();
  if (action === undefined) {
    action = new FollowActionVM(kind, id, portrait, name);
    actions.set(key, new WeakRef<FollowActionVM>(action));
  }
  recentActions.delete(key);
  recentActions.set(key, action);
  while (recentActions.size > FOLLOW_ACTION_CACHE_ENTRIES) {
    const oldest: string = Array.from(recentActions.keys())[0];
    recentActions.delete(oldest);
  }
  return action;
}
