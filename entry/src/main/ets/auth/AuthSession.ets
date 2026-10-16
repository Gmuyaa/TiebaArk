

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TbsResponse, TiebaApi } from '../api/TiebaApi';
import { TiebaDevice, TiebaSession } from '../net/TiebaParams';
import { mergeProfile, UserProfileInfo, avatarIdentity } from '../model/UserProfile';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { avatarTrace, avatarTracePhase, avatarUptimeMs } from '../utils/AvatarTrace';
import { AuthStore, StoreResult } from './AuthStore';
import { deleteForumSnapshot } from '../viewmodel/ForumSnapshotStore';
import {
  AuthSnapshot, CredentialBundle, credentialsFromUserInput, expiredSnapshot,
  loggedInSnapshotCarrying, LoginResult, normalizeBduss,
  sessionFromCredentials, snapshotForCredentials, snapshotWithProfile,
  validateBduss, validateCredentialInput
} from './AuthModel';

const AUTH_SOURCE_MANUAL: string = 'manual_cookie';
const AUTH_SOURCE_WEB: string = 'web_login';
let authSource: string = AUTH_SOURCE_MANUAL;

@ObservedV2
export class AuthSession {
  @Trace sessionRevision: number = 0;
  sessionKey(): string { return String(this.sessionRevision); }
  matchesSession(session: TiebaSession, key: string): boolean {
    return key === this.sessionKey() && this.isLoggedIn() &&
      session.bduss === this.credentials.bduss && session.stoken === this.credentials.stoken;
  }
  private stableForumUid: number = 0;
  private forumSessionVersion: number = 0;
  forumCacheUid(): number { return this.isLoggedIn() ? this.stableForumUid : 0; }
  forumCacheSessionKey(): string {
    return this.isLoggedIn() ? `${this.forumSessionVersion}:${this.stableForumUid}` : '';
  }

  @Trace snapshot: AuthSnapshot = AuthSnapshot.loggedOut();

  @Trace avatarRevision: number = Date.now();

  private publishedIdentity: string = '';
  private profileVersion: number = 0;

  private avatarSyncOps: number = 0;

  private readonly avatarRecheckDelaysMs: number[] = [1500, 2000, 2000, 2000, 2500, 4000, 6000, 8000, 12000];

  private credentialOperation: number = 0;
  private credentials: CredentialBundle = new CredentialBundle();
  private api: TiebaApi = new TiebaApi();

  private restoring: Promise<void> | undefined = undefined;
  private profileRefreshing: Promise<void> | undefined = undefined;
  private profileRefreshRequested: boolean = false;

  private deviceContext: common.Context | undefined = undefined;

  session(): TiebaSession {
    return sessionFromCredentials(this.credentials);
  }

  private applyCredentials(credentials: CredentialBundle): void {
    this.sessionRevision++;
    this.forumSessionVersion++;
    this.stableForumUid = 0;
    this.profileVersion++;
    this.avatarSyncOps++;
    this.publishedIdentity = '';
    this.avatarRevision = Math.max(Date.now(), this.avatarRevision + 1);
    this.credentials = credentials;
    this.snapshot = snapshotForCredentials(credentials);
  }

  private async fetchProfileAndUpdate(): Promise<void> {
    if (!this.credentials.isUsable()) {
      return;
    }
    const session: TiebaSession = sessionFromCredentials(this.credentials);
    const version: number = this.profileVersion;
    const startedMs: number = avatarUptimeMs();
    const beforeIdentity: string = this.publishedIdentity;
    const base: UserProfileInfo = await this.api.fetchUserInfo(session);

    let merged: UserProfileInfo = base;

    let socialLoaded: boolean = false;
    let verifiedUid: number = 0;
    if (this.deviceContext !== undefined) {
      const device: TiebaDevice = await DeviceIdentity.ensure(this.deviceContext);

      const self: UserProfileInfo | undefined =
        await this.api.fetchSelfProfile(session, device, base.portrait);
      if (self !== undefined) {
        socialLoaded = true;
        merged = mergeProfile(base, self);
        if (self.portrait.length > 0) { merged.portrait = self.portrait; }

        if (self.uid > 0) {
          merged.uid = self.uid;
          verifiedUid = self.uid;
        }
      }
    } else {

      hilog.info(0x0000, 'AuthSession',
        'profile: no context, skipped concern/fans/level (signature needs device identity)');
    }

    if (version !== this.profileVersion || session.bduss !== this.credentials.bduss ||
      session.stoken !== this.credentials.stoken || !this.isLoggedIn()) { return; }
    if (merged.hasAny()) {
      this.snapshot = snapshotWithProfile(this.snapshot, merged, socialLoaded);
      if (verifiedUid > 0) {
        this.stableForumUid = verifiedUid;
        void AuthStore.saveForumUid(verifiedUid);
      }
      this.publishAvatarIdentity(merged.portrait);
      avatarTracePhase('profile-refresh', 0, startedMs,
        `social=${socialLoaded} changed=${this.publishedIdentity !== beforeIdentity}`);
    }
  }

  private publishAvatarIdentity(portrait: string): boolean {
    const identity: string = avatarIdentity(portrait);
    if (identity.length === 0 || identity === this.publishedIdentity) {
      return false;
    }
    this.publishedIdentity = identity;
    this.avatarRevision = Math.max(Date.now(), this.avatarRevision + 1);
    return true;
  }

  private requestCurrentAvatarImage(): void {
    if (!this.isLoggedIn() || this.snapshot.portrait.length === 0) { return; }
    this.avatarRevision = Math.max(Date.now(), this.avatarRevision + 1);
  }

  async refreshOwnAvatarOnEntry(context: common.UIAbilityContext): Promise<void> {
    if (!this.isLoggedIn()) { return; }
    const session: TiebaSession = this.session();
    const uid: number = this.snapshot.uid;
    await this.refreshProfile(context);
    if (!this.isLoggedIn() || uid !== this.snapshot.uid ||
      session.bduss !== this.credentials.bduss || session.stoken !== this.credentials.stoken) { return; }
    this.requestCurrentAvatarImage();
    avatarTrace('image-entry-refresh', 0, 'source=account-portrait');
  }

  noteAvatarUploadReceived(session: TiebaSession, uid: number, traceId: number = 0): number {
    if (!this.isLoggedIn() || session.bduss !== this.credentials.bduss ||
      session.stoken !== this.credentials.stoken || !Number.isSafeInteger(uid) || uid !== this.snapshot.uid || uid <= 0) {
      return 0;
    }

    this.profileVersion++;
    this.avatarSyncOps++;
    avatarTrace('upload-received', traceId, `syncOp=${this.avatarSyncOps}`);
    return this.avatarSyncOps;
  }

  avatarSyncOp(): number {
    return this.avatarSyncOps;
  }

  avatarOperationStale(syncOp: number): boolean {
    return syncOp !== this.avatarSyncOps;
  }

  private avatarWatchCurrent(session: TiebaSession, uid: number, syncOp: number): boolean {
    return syncOp === this.avatarSyncOps && this.isLoggedIn() && uid === this.snapshot.uid &&
      session.bduss === this.credentials.bduss && session.stoken === this.credentials.stoken;
  }

  private waitForAvatarRecheck(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, ms); });
  }

  async watchAvatarAfterUpload(context: common.UIAbilityContext, session: TiebaSession,
    uid: number, syncOp: number, traceId: number): Promise<void> {
    if (!this.avatarWatchCurrent(session, uid, syncOp)) { return; }
    const baseline: string = avatarIdentity(this.snapshot.portrait);
    if (baseline.length === 0) { return; }
    avatarTrace('watch-start', traceId, `checks=${this.avatarRecheckDelaysMs.length}`);
    for (let i: number = 0; i < this.avatarRecheckDelaysMs.length; i++) {
      await this.waitForAvatarRecheck(this.avatarRecheckDelaysMs[i]);
      if (!this.avatarWatchCurrent(session, uid, syncOp)) { return; }
      if (avatarIdentity(this.snapshot.portrait) !== baseline) { return; }
      await this.refreshProfile(context);
      if (!this.avatarWatchCurrent(session, uid, syncOp)) { return; }
      const changed: boolean = avatarIdentity(this.snapshot.portrait) !== baseline;
      if (!changed) { this.requestCurrentAvatarImage(); }
      avatarTrace('watch-check', traceId, `attempt=${i + 1} changed=${changed}`);
      if (changed) { return; }
    }
    avatarTrace('watch-stop', traceId, 'reason=limit');
  }

  acceptAvatarProfile(session: TiebaSession, profile: UserProfileInfo,
    syncOp: number = 0, refreshed: boolean = true): boolean {
    if (!this.isLoggedIn() || session.bduss !== this.credentials.bduss ||
      session.stoken !== this.credentials.stoken || !Number.isSafeInteger(profile.uid) ||
      profile.uid <= 0 || profile.uid !== this.snapshot.uid || profile.portrait.length === 0) { return false; }

    if (syncOp !== this.avatarSyncOps) { return false; }
    this.profileVersion++;
    this.snapshot = snapshotWithProfile(this.snapshot, profile, refreshed);

    const changed: boolean = this.publishAvatarIdentity(profile.portrait);
    avatarTrace('profile-published', 0, `identityChanged=${changed} refreshed=${refreshed}`);
    return true;
  }

  async refreshProfile(context: common.UIAbilityContext, trailingIfBusy: boolean = true): Promise<void> {
    this.deviceContext = context;
    const busy: boolean = this.profileRefreshing !== undefined;

    if (!busy || trailingIfBusy) { this.profileRefreshRequested = true; }

    avatarTrace('profile-request', 0,
      `coalesced=${busy} pendingAfter=${this.profileRefreshRequested}`);
    if (!busy) { this.profileRefreshing = this.refreshProfileQueue(); }
    return this.profileRefreshing;
  }

  private async refreshProfileQueue(): Promise<void> {

    await Promise.resolve();
    try {
      while (this.profileRefreshRequested) {
        this.profileRefreshRequested = false;
        try { await this.fetchProfileAndUpdate(); }
        catch (err) { hilog.warn(0x0000, 'AuthSession', 'profile refresh failed'); }
      }
    } finally { this.profileRefreshing = undefined; }
  }

  isLoggedIn(): boolean {
    return this.snapshot.isLoggedIn();
  }

  describe(): string {
    return `state=${this.snapshot.isLoggedIn() ? 'LOGGED_IN' : 'LOGGED_OUT'}`
      + ` credentials=(${this.credentials.describeShape()})`
      + (this.snapshot.expiredReason.length > 0 ? ` expired=${this.snapshot.expiredReason}` : '');
  }

  async restore(context: common.UIAbilityContext): Promise<void> {

    this.deviceContext = context;
    if (this.restoring !== undefined) {
      return this.restoring;
    }
    this.restoring = this.loadFromStore();
    try {
      await this.restoring;
    } finally {
      this.restoring = undefined;
    }
  }

  private async loadFromStore(): Promise<void> {
    const operation: number = this.credentialOperation;
    try {
      const bundle: CredentialBundle = await AuthStore.load();
      if (operation !== this.credentialOperation) { return; }
      this.applyCredentials(bundle);
      if (bundle.isUsable()) {
        const uid: number = await AuthStore.loadForumUid();
        if (operation === this.credentialOperation && this.isLoggedIn()) {
          this.stableForumUid = uid;
          const restored = loggedInSnapshotCarrying(this.snapshot);
          restored.uid = uid;
          this.snapshot = restored;
        }
      }
      this.fetchProfileAndUpdate();
    } catch (err) {

      if (operation === this.credentialOperation) { this.applyCredentials(new CredentialBundle()); }
    }
  }

  async loginWithBduss(bdussInput: string, stokenInput: string = ''): Promise<LoginResult> {
    const bduss: string = normalizeBduss(bdussInput);
    const invalid: string = validateBduss(bduss);
    if (invalid.length > 0) {
      hilog.info(0x0000, 'AuthSession', 'login rejected by local validation: %{public}s', invalid);
      return LoginResult.failure(invalid);
    }

    const operation: number = ++this.credentialOperation;
    let tbsResponse: TbsResponse;
    try {
      tbsResponse = await this.api.fetchTbsWithBduss(bduss);
    } catch (err) {
      const e: Error = err as Error;
      hilog.error(0x0000, 'AuthSession', 'login threw: %{public}s', e.message);
      return LoginResult.failure(`登录校验失败：${e.message}`);
    }

    if (operation !== this.credentialOperation) { return LoginResult.failure('登录操作已取消'); }

    hilog.info(0x0000, 'AuthSession',
      'login verdict: ok=%{public}s isLogin=%{public}s tbsLen=%{public}s transportErr=%{public}s',
      String(tbsResponse.ok), String(tbsResponse.isLogin), String(tbsResponse.tbs.length),
      tbsResponse.transportError.length === 0 ? '(none)' : tbsResponse.transportError);

    if (!tbsResponse.ok) {

      const reason: string = tbsResponse.describeFailure();
      return LoginResult.failure(reason, tbsResponse.transportError.length === 0);
    }
    if (!tbsResponse.isLogin) {
      return LoginResult.failure('BDUSS 无效或已过期，请重新获取', true);
    }
    if (tbsResponse.tbs.length === 0) {
      return LoginResult.failure('服务端未返回 tbs，暂时无法进行写操作', true);
    }

    const bundle: CredentialBundle = new CredentialBundle();
    bundle.bduss = bduss;
    bundle.tbs = tbsResponse.tbs;

    bundle.stoken = stokenInput.trim();

    this.api.resetUidCache();

    this.profileVersion++;
    const saved: StoreResult = await AuthStore.save(bundle);
    if (operation !== this.credentialOperation) { return LoginResult.failure('登录操作已取消'); }

    this.applyCredentials(bundle);
    this.fetchProfileAndUpdate();
    if (!saved.ok) {

      return LoginResult.failure(`已登录，但凭据保存失败（重启后需重新登录）：${saved.message}`);
    }

    hilog.info(0x0000, 'AuthSession', 'login stored: authSource=%{public}s bduss=set tbs=set stoken=%{public}s',
      authSource, bundle.stoken.length > 0 ? 'set' : 'empty');
    return LoginResult.success();
  }

  async loginWithUserInput(input: string): Promise<LoginResult> {
    authSource = AUTH_SOURCE_MANUAL;
    const invalid: string = validateCredentialInput(input);
    if (invalid.length > 0) {
      hilog.info(0x0000, 'AuthSession', 'login rejected by local validation: %{public}s', invalid);
      return LoginResult.failure(invalid);
    }
    const parsed: CredentialBundle = credentialsFromUserInput(input);
    hilog.info(0x0000, 'AuthSession',
      'login input parsed: bduss=%{public}s stoken=%{public}s',
      parsed.bduss.length > 0 ? 'set' : 'empty', parsed.stoken.length > 0 ? 'set' : 'empty');
    return this.loginWithBduss(parsed.bduss, parsed.stoken);
  }

  async loginFromWebCookies(bduss: string, stoken: string): Promise<LoginResult> {
    authSource = AUTH_SOURCE_WEB;
    hilog.info(0x0000, 'AuthSession',
      'web_login cookies: bduss=present stoken=%{public}s', stoken.length > 0 ? 'present' : 'empty');
    return this.loginWithBduss(bduss, stoken);
  }

  async refreshTbs(context: common.UIAbilityContext): Promise<LoginResult> {
    if (!this.credentials.isUsable()) {
      return LoginResult.failure('需要登录后才能获取 tbs');
    }
    const session: TiebaSession = this.session();
    const key: string = this.sessionKey();
    const response: TbsResponse = await this.api.fetchTbsWithBduss(session.bduss);
    if (!this.matchesSession(session, key)) { return LoginResult.failure('账号已变化，请重新获取 tbs'); }
    if (!response.ok) {
      return LoginResult.failure(response.describeFailure());
    }
    if (!response.isLogin) {
      this.markExpired('登录已失效，请重新登录');
      return LoginResult.failure('登录已失效，请重新登录', true);
    }
    if (response.tbs.length === 0) {
      return LoginResult.failure('服务端未返回 tbs');
    }
    this.credentials.tbs = response.tbs;
    const saved: StoreResult = await AuthStore.saveTbs(response.tbs, session.bduss, session.stoken);
    if (!this.matchesSession(session, key)) { return LoginResult.failure('账号已变化，旧 tbs 已作废'); }
    if (!saved.ok) { return LoginResult.failure(saved.message); }

    this.deviceContext = context;
    this.snapshot = loggedInSnapshotCarrying(this.snapshot);
    return LoginResult.success();
  }

  async logout(context: common.UIAbilityContext): Promise<StoreResult> {
    this.credentialOperation++;
    const oldUid: number = this.stableForumUid;
    this.applyCredentials(new CredentialBundle());
    const result: StoreResult = await AuthStore.clear();
    await deleteForumSnapshot(context, oldUid);
    return result;
  }

  markExpired(reason: string): void {
    this.sessionRevision++;
    this.forumSessionVersion++;
    this.stableForumUid = 0;
    this.publishedIdentity = '';
    this.profileVersion++;
    this.avatarSyncOps++;
    this.credentials = new CredentialBundle();
    this.snapshot = expiredSnapshot(reason);
  }
}

export const authSession: AuthSession = new AuthSession();
