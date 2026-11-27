import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { AuthorBlockScope } from '../model/AuthorBlock';
import { DeviceIdentity } from '../utils/DeviceIdentity';

function account(): string {
  return authSession.isLoggedIn() ? `${authSession.snapshot.uid}:${authSession.snapshot.portrait}` : 'anonymous';
}

// 评论进入视口才核对，最多四个并发；同一作者共用一份账号隔离状态。
let reading: number = 0;
const waiting: (() => void)[] = [];
async function readSlot(): Promise<void> {
  if (reading < 4) { reading++; return; }
  await new Promise<void>((resolve) => { waiting.push(resolve); });
}
function releaseSlot(): void {
  const next: (() => void) | undefined = waiting.shift();
  if (next !== undefined) { next(); } else { reading--; }
}

@ObservedV2
export class AuthorBlockVM {
  @Trace known: boolean = false;
  @Trace blocked: boolean = false;
  @Trace follow: boolean = false;
  @Trace interact: boolean = false;
  @Trace chat: boolean = false;
  @Trace pending: boolean = false;
  private loading: Promise<string> | undefined = undefined;
  private api: TiebaApi = new TiebaApi();
  private owner: string = account();
  private sequence: number = 0;
  private readAt: number = 0;
  private uid: number;
  constructor(uid: number) { this.uid = uid; }
  private current(): boolean { return this.owner === account(); }

  scope(): AuthorBlockScope {
    return AuthorBlockScope.fromFlags(this.follow, this.interact, this.chat);
  }

  async load(context: common.UIAbilityContext, force: boolean = false): Promise<string> {
    if (this.loading !== undefined) { return this.loading; }
    if (!this.current() || this.pending || !authSession.isLoggedIn() || this.uid <= 0) { return ''; }
    if (!force && this.known && Date.now() - this.readAt < 30000) { return ''; }
    this.loading = this.read(context);
    try { return await this.loading; } finally { this.loading = undefined; }
  }

  private async read(context: common.UIAbilityContext): Promise<string> {
    const sequence: number = ++this.sequence;
    await readSlot();
    try {
      if (!this.current() || sequence !== this.sequence) { return ''; }
      const device = await DeviceIdentity.ensure(context);
      if (!this.current() || sequence !== this.sequence) { return ''; }
      const response = await this.api.authorBlock(device, authSession.session(), this.uid);
      if (!this.current() || sequence !== this.sequence) { return ''; }
      if (!response.ok) {
        hilog.info(0x0, 'AuthorBlock', 'read failed code=%{public}d', response.errorCode);
        return response.describeFailure();
      }
      this.follow = response.result.follow === 1;
      this.interact = response.result.interact === 1;
      this.chat = response.result.chat === 1;
      this.blocked = response.result.blocked();
      this.known = true;
      this.readAt = Date.now();
      hilog.info(0x0, 'AuthorBlock', 'read confirmed blocked=%{public}s', String(this.blocked));
      return '';
    } catch (err) { return '读取拉黑状态失败，请重试'; }
    finally { releaseSlot(); }
  }

  async set(context: common.UIAbilityContext, blocked: boolean): Promise<string> {
    return this.setScope(context, blocked ? AuthorBlockScope.all() : AuthorBlockScope.none(), blocked);
  }

  async setScope(context: common.UIAbilityContext, scope: AuthorBlockScope,
    legacyBlocked?: boolean): Promise<string> {
    if (this.pending || !this.current()) { return ''; }
    if (!authSession.isLoggedIn()) { return '需要登录后才能拉黑'; }
    if (!Number.isSafeInteger(this.uid) || this.uid <= 0 || this.uid === authSession.snapshot.uid) {
      return '不能拉黑当前作者';
    }
    const initial: string = await this.load(context);
    if (!this.current()) { return ''; }
    if (!this.known) { return initial || '拉黑状态未确认，请重试'; }
    if (legacyBlocked !== undefined) {
      if (this.blocked === legacyBlocked && this.scope().equals(scope)) { return ''; }
    } else if (this.scope().equals(scope)) {
      return '';
    }
    if (this.pending) { return ''; }
    this.pending = true;
    ++this.sequence;
    let recover: boolean = false;
    try {
      if (authSession.session().tbs.length === 0) {
        const refreshed = await authSession.refreshTbs(context);
        if (!refreshed.ok) { return refreshed.message; }
      }
      const device = await DeviceIdentity.ensure(context);
      if (!this.current()) { return ''; }
      const response = legacyBlocked !== undefined
        ? await this.api.authorBlock(device, authSession.session(), this.uid, legacyBlocked)
        : await this.api.setAuthorBlockScope(device, authSession.session(), this.uid, scope);
      if (!this.current()) { return ''; }
      if (!response.ok) {
        recover = response.transportError.length > 0 || response.errorCode < 0;
        return response.describeFailure();
      }
      this.follow = scope.follow;
      this.interact = scope.interact;
      this.chat = scope.chat;
      this.blocked = scope.interact;
      this.known = true;
      this.readAt = Date.now();
      void authSession.refreshProfile(context);
      return '';
    } catch (err) { recover = true; return '拉黑操作失败，请重试'; }
    finally {
      this.pending = false;
      if (recover && this.current()) { this.known = false; void this.load(context, true); }
    }
  }

  applySynced(blocked: boolean): void {
    this.applySyncedScope(blocked ? AuthorBlockScope.all() : AuthorBlockScope.none());
  }

  applySyncedScope(scope: AuthorBlockScope): void {
    if (!this.current() || this.pending) { return; }
    this.follow = scope.follow;
    this.interact = scope.interact;
    this.chat = scope.chat;
    this.blocked = scope.interact;
    this.known = true;
    this.readAt = Date.now();
  }
}

const blocks: Map<string, AuthorBlockVM> = new Map<string, AuthorBlockVM>();
export function authorBlockAction(uid: number): AuthorBlockVM {
  const key: string = `${account()}:${uid}`;
  let vm: AuthorBlockVM | undefined = blocks.get(key);
  if (vm === undefined) { vm = new AuthorBlockVM(uid); blocks.set(key, vm); }
  return vm;
}

/** 用官方全量黑名单刷新当前账号已缓存的作者屏蔽态，避免评论区等待 30 秒 TTL。 */
export function syncAuthorBlockCache(blockedUids: number[]): void {
  const prefix: string = `${account()}:`;
  const blockedSet: Set<number> = new Set<number>(blockedUids);
  blocks.forEach((vm: AuthorBlockVM, key: string): void => {
    if (!key.startsWith(prefix)) { return; }
    const uid: number = Number(key.substring(prefix.length));
    if (!Number.isSafeInteger(uid) || uid <= 0) { return; }
    if (blockedSet.has(uid)) {
      if (!vm.known) { vm.applySynced(true); }
    } else if (vm.known && (vm.blocked || vm.scope().any())) {
      vm.applySynced(false);
    }
  });
}

export function markAuthorBlocked(uid: number, blocked: boolean): void {
  if (!Number.isSafeInteger(uid) || uid <= 0) { return; }
  const vm: AuthorBlockVM | undefined = blocks.get(`${account()}:${uid}`);
  if (vm !== undefined) { vm.applySynced(blocked); }
}

export function syncAuthorBlockScope(uid: number, scope: AuthorBlockScope): void {
  if (!Number.isSafeInteger(uid) || uid <= 0) { return; }
  const vm: AuthorBlockVM | undefined = blocks.get(`${account()}:${uid}`);
  if (vm !== undefined) { vm.applySyncedScope(scope); }
}
