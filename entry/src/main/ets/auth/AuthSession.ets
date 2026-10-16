/**
 * 当前登录态与会话凭据的**唯一读取点**。
 *
 * 这是 M3 登录层的中心：页面只问它"登录了吗"，接口层只问它"这次请求带什么凭据"。
 * 它自己不做落盘（`AuthStore` 负责），也不做 UI。
 *
 * 为什么必须是单例而不是各 VM 自己 new：
 * 登录前 `new TiebaSession()` 每次都是空会话，登录后只要漏掉一处，那次请求就是匿名的。
 * 本文件把"凭据从哪来"收成一个入口，`TiebaApi` 的端点签名与模型层都不用改。
 *
 * 状态用 V2（`@ObservedV2` + `@Trace`）暴露，页面能直接跟随登录/登出重绘；
 * 账本对象整体替换（TD-5：`@Trace` 只跟踪整体替换）。
 *
 * 安全：本文件永不把 BDUSS 写进日志/异常文案；`describe()` 只输出"有没有"。
 */

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

  /**
   * 登录态快照。**整体替换**触发 `@Trace`（不就地改 `snapshot` 的字段）。
   *
   * 页面只要在 `build()` 里读 `authSession.snapshot.xxx`，就会订阅到这里；
   * 登录/退出/失效都会赋一个全新对象，因此能驱动 UI 重绘。
   */
  @Trace snapshot: AuthSnapshot = AuthSnapshot.loggedOut();
  /**
   * 仅用于**本人头像图片**的展示缓存键，不改变协议 portrait 或账号身份。
   *
   * 远端头像身份变化、账号变化、账号头像页面重新进入及上传后的只读复查时推进。
   * 同一路径的图片内容也可能更新，页面进入时需用新 URL 请求图片。
   */
  @Trace avatarRevision: number = Date.now();
  /** 最近一次发布的**远端**头像身份；只有它变化才推进展示版本。 */
  private publishedIdentity: string = '';
  private profileVersion: number = 0;
  /**
   * "服务端已接收上传"的代次。只用于**隔离迟到读回**：
   * `acceptAvatarProfile(session, profile, syncOp)` 要求代次一致，
   * 上一次修改的迟到读回不能发布到第二次修改之上。
   *
   * 它**不**表示任何展示状态：本应用不再把本机候选图发布成全局头像，
   * "我的"与本人主页只显示服务端当前资料里的头像（见 KNOWN_ISSUES #18）。
   */
  private avatarSyncOps: number = 0;
  /** 已接收上传后只读复查的间隔；约 40 秒内最多 9 次，不持续轮询。 */
  private readonly avatarRecheckDelaysMs: number[] = [1500, 2000, 2000, 2000, 2500, 4000, 6000, 8000, 12000];
  /** 当前凭据（内存）。未登录时字段为空串 */
  private credentialOperation: number = 0;
  private credentials: CredentialBundle = new CredentialBundle();
  private api: TiebaApi = new TiebaApi();
  /** 恢复中的 promise：并发调用（多个 VM 同时启动）只真正恢复一次 */
  private restoring: Promise<void> | undefined = undefined;
  private profileRefreshing: Promise<void> | undefined = undefined;
  private profileRefreshRequested: boolean = false;
  /**
   * 启动上下文。**只为拉取账号资料而存**：那个端点（`/c/u/user/profile`）要签名，
   * 签名要设备身份，设备身份要 preferences，preferences 要 context。
   * 登录校验本身不需要它（走网页域 GET），所以它不参与登录流程。
   * 为空时资料拉取降级为"只取昵称/头像/uid"，见 `fetchProfileAndUpdate`。
   */
  private deviceContext: common.Context | undefined = undefined;

  /** 未登录时返回空会话——与登录功能不存在时的行为完全一致 */
  session(): TiebaSession {
    return sessionFromCredentials(this.credentials);
  }

  /**
   * 同时替换凭据与快照。
   *
   * 收成一个私有入口，是为了让"凭据变了但状态没跟着变"在结构上不可能发生——
   * 这类不一致会让界面显示"已登录"却发出匿名请求，且不报任何错。
   */
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
    // 只有资料端点**真的返回了**才算"社交数据已加载"，否则界面显示 `—` 而不是 `0`
    let socialLoaded: boolean = false;
    let verifiedUid: number = 0;
    if (this.deviceContext !== undefined) {
      const device: TiebaDevice = await DeviceIdentity.ensure(this.deviceContext);
      /*
       * 传 **portrait**（不是 uid）：`json_userinfo.data.open_uid` **不是贴吧 uid**，
       * 拿它去查只会得到一个"空壳 user"（社交计数全 0，界面就是 0/0/Lv.0）。
       * 服务端靠 `friend_uid_portrait`（自己的头像 hash）才定位到本人。
       */
      const self: UserProfileInfo | undefined =
        await this.api.fetchSelfProfile(session, device, base.portrait);
      if (self !== undefined) {
        socialLoaded = true;
        merged = mergeProfile(base, self);
        if (self.portrait.length > 0) { merged.portrait = self.portrait; }
        /** 贴吧账号 ID 以 protobuf User.id 为准，不能用 json_userinfo.open_uid 替代。 */
        if (self.uid > 0) {
          merged.uid = self.uid;
          verifiedUid = self.uid;
        }
      }
    } else {
      /*
       * 只有"忘了先 restore()"才会走到这里（正常启动路径不会）。
       * 如实记一行：否则"关注/粉丝/等级一直是 0"会被误判成端点出了问题。
       */
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

  /**
   * 远端头像**身份**变化是"图片该换一次"的唯一常规证据。
   *
   * 身份相同或无法识别时**什么都不做**：既不推进展示版本，也不下任何"图片没变"的结论
   * （同一路径的远端内容可能已经换了，但本机没有证据，见 `avatarIdentity` 的说明）。
   * 返回是否推进了展示版本。
   */
  private publishAvatarIdentity(portrait: string): boolean {
    const identity: string = avatarIdentity(portrait);
    if (identity.length === 0 || identity === this.publishedIdentity) {
      return false;
    }
    this.publishedIdentity = identity;
    this.avatarRevision = Math.max(Date.now(), this.avatarRevision + 1);
    return true;
  }

  /** 让当前资料记录里的远端头像以新 URL 重新加载；不发布本地候选图。 */
  private requestCurrentAvatarImage(): void {
    if (!this.isLoggedIn() || this.snapshot.portrait.length === 0) { return; }
    this.avatarRevision = Math.max(Date.now(), this.avatarRevision + 1);
  }

  /** 进入显示本人头像的页面：补读最新资料，并重取当前服务端头像图片。 */
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

  /**
   * 记录一次"服务端已**接收**"的上传，返回本次同步代次。
   *
   * **它只表示接收**（`code=0` 或 `300003` 审核中都算），不发布任何展示状态、
   * 不改 `avatarRevision`：本应用不再把本机候选图当成全局头像。
   * "我的"与本人主页的头像只来自服务端资料（`acceptAvatarProfile` / 普通资料刷新）。
   *
   * 返回 0 表示会话/UID 已变化，调用方不得据此认为上传已被本账号接收。
   */
  noteAvatarUploadReceived(session: TiebaSession, uid: number, traceId: number = 0): number {
    if (!this.isLoggedIn() || session.bduss !== this.credentials.bduss ||
      session.stoken !== this.credentials.stoken || !Number.isSafeInteger(uid) || uid !== this.snapshot.uid || uid <= 0) {
      return 0;
    }
    // 上传前已在途的资料刷新拿不到本次新头像：整体作废一轮，避免旧读回先落地。
    this.profileVersion++;
    this.avatarSyncOps++;
    avatarTrace('upload-received', traceId, `syncOp=${this.avatarSyncOps}`);
    return this.avatarSyncOps;
  }

  /** 当前同步代次（独立重读资料时用它声明"我就是当前这一次"）。 */
  avatarSyncOp(): number {
    return this.avatarSyncOps;
  }

  /** 供调用方区分"本次读回被更晚的头像操作取代"与"账号/会话已变化"。 */
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

  /**
   * 已接收上传后做有限次只读复查。同一 portrait 的图片也可能更新，
   * 每次复查后让当前服务端图片使用新 URL；身份变化时立即停止。
   * 审核未通过或超出窗口就停止，不把本机候选图发布到主界面。
   */
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

  /**
   * 发布已读回且 UID 确认的**服务端**资料（含头像 portrait）。
   *
   * 这是"我的"与本人主页头像的唯一来源：本机候选图不经过这里。
   * 迟到的旧读回（`syncOp` 不一致）被拒绝，不覆盖更新的发布。
   * `refreshed = true` 表示这是针对本人资料的定向读回（含头像记录对比）。
   */
  acceptAvatarProfile(session: TiebaSession, profile: UserProfileInfo,
    syncOp: number = 0, refreshed: boolean = true): boolean {
    if (!this.isLoggedIn() || session.bduss !== this.credentials.bduss ||
      session.stoken !== this.credentials.stoken || !Number.isSafeInteger(profile.uid) ||
      profile.uid <= 0 || profile.uid !== this.snapshot.uid || profile.portrait.length === 0) { return false; }
    // 上一次修改的迟到读回不得发布到第二次修改之上。
    if (syncOp !== this.avatarSyncOps) { return false; }
    this.profileVersion++;
    this.snapshot = snapshotWithProfile(this.snapshot, profile, refreshed);
    // 只有在**远端头像身份真的变了**时才推进展示缓存键（普通刷新不推进）。
    const changed: boolean = this.publishAvatarIdentity(profile.portrait);
    avatarTrace('profile-published', 0, `identityChanged=${changed} refreshed=${refreshed}`);
    return true;
  }

  /** 刷新本人资料；关系变化默认补读，普通页面展示可复用在途结果。 */
  async refreshProfile(context: common.UIAbilityContext, trailingIfBusy: boolean = true): Promise<void> {
    this.deviceContext = context;
    const busy: boolean = this.profileRefreshing !== undefined;
    // 普通页面展示可共享在途读回；关注变化和上传后的默认调用仍补读一次最新资料。
    if (!busy || trailingIfBusy) { this.profileRefreshRequested = true; }
    /*
     * 记录是否复用在途刷新、是否仍需补读；实际请求次数看 `profile-refresh` 行。
     */
    avatarTrace('profile-request', 0,
      `coalesced=${busy} pendingAfter=${this.profileRefreshRequested}`);
    if (!busy) { this.profileRefreshing = this.refreshProfileQueue(); }
    return this.profileRefreshing;
  }

  /** 刷新进行中再次改变关系时，只在当前轮结束后补刷一次最新计数。 */
  private async refreshProfileQueue(): Promise<void> {
    // 先让调用方保存共享 promise，再执行队列及其清理（包括同步异常路径）。
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

  /** 只输出状态，**不含凭据内容**。排查问题时用这个，别打印 credentials */
  describe(): string {
    return `state=${this.snapshot.isLoggedIn() ? 'LOGGED_IN' : 'LOGGED_OUT'}`
      + ` credentials=(${this.credentials.describeShape()})`
      + (this.snapshot.expiredReason.length > 0 ? ` expired=${this.snapshot.expiredReason}` : '');
  }

  /**
   * 启动时从安全存储恢复登录态。
   *
   * 失败不阻断：读不到就当未登录，只读浏览照旧可用。
   * 并发安全（多个 VM 同时起步时只真正读一次存储）。
   */
  async restore(context: common.UIAbilityContext): Promise<void> {
    // 记住上下文：资料端点要签名 → 要设备身份 → 要 preferences → 要 context。
    // 放在最前面（**在并发去重之前**）：重复调用时也要刷新它，代价只是一次赋值。
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
      // 存储异常一律按未登录处理，不让启动变脆
      if (operation === this.credentialOperation) { this.applyCredentials(new CredentialBundle()); }
    }
  }

  /**
   * 用一份 BDUSS 登录。
   *
   * 流程：校验形态 → 用 BDUSS 换 tbs（同时确认服务端是否认可）→ 落盘 → 更新状态。
   * **只有服务端认可（is_login=1 且拿到 tbs）才算登录成功**：
   * 不因为"本地存下了"就报成功——这也是本项目"不放假状态"的规矩。
   *
   * 不收 `context`：登录校验走网页域 GET，不需要 `UIAbilityContext`；
   * 收一个用不到的参数只会让调用方以为它有作用。
   */
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
    // 只记分支判定与长度，**不记凭据**。没有这行就只能靠猜失败在哪一步。
    hilog.info(0x0000, 'AuthSession',
      'login verdict: ok=%{public}s isLogin=%{public}s tbsLen=%{public}s transportErr=%{public}s',
      String(tbsResponse.ok), String(tbsResponse.isLogin), String(tbsResponse.tbs.length),
      tbsResponse.transportError.length === 0 ? '(none)' : tbsResponse.transportError);

    if (!tbsResponse.ok) {
      // 传输失败可以重试；业务失败更可能是凭据问题，文案里如实区分
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

    // Invalidate old-account profile reads before credential storage begins.
    this.profileVersion++;
    const saved: StoreResult = await AuthStore.save(bundle);
    if (operation !== this.credentialOperation) { return LoginResult.failure('登录操作已取消'); }
    // 先落盘再改内存状态：内存一旦显示"已登录"，界面就会按已登录分派
    this.applyCredentials(bundle);
    this.fetchProfileAndUpdate();
    if (!saved.ok) {
      // 落盘失败不算登录失败（本次运行可用），但必须如实告知"重启后要重新登录"
      return LoginResult.failure(`已登录，但凭据保存失败（重启后需重新登录）：${saved.message}`);
    }
    // 只记"有没有"，不记内容；STOKEN 的有无直接决定楼层点赞实验能不能做
    hilog.info(0x0000, 'AuthSession', 'login stored: authSource=%{public}s bduss=set tbs=set stoken=%{public}s',
      authSource, bundle.stoken.length > 0 ? 'set' : 'empty');
    return LoginResult.success();
  }

  /**
   * 用**用户粘贴的原文**登录：裸 BDUSS 或整条 Cookie 都接受。
   *
   * 这是"最小网页登录能力"的入口——不含浏览器、不含密码流：
   * 用户从浏览器（已登录状态）复制整条 Cookie，本方法解析出 BDUSS 与 STOKEN，
   * 再走与 `loginWithBduss` **完全相同**的校验/落盘路径（不复制第二套逻辑）。
   *
   * 为什么要整条 Cookie：实测证明 STOKEN 无法由 BDUSS 换取（见 `extractStokenFromCookie`），
   * 而 Cookie 里本来就同时带着两者。
   */
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

  /**
   * 重新获取 tbs。tbs 会失效，写操作前若发现没有 tbs 可调用它。
   * 未登录时直接返回失败，不发请求。
   */
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

  /**
   * 退出登录。
   *
   * 只清**账号**凭据与账号相关状态（BDUSS / stoken / tbs / 登录态；
   * 将来 ArkWeb 登录带来的 Cookie 也在此一并清）。
   * **不重置设备身份**（`DeviceIdentity` 的 androidId/uuid），
   * 这样退出后匿名浏览仍可用，也不会因为换设备指纹触发风控。
   */
  async logout(context: common.UIAbilityContext): Promise<StoreResult> {
    this.credentialOperation++;
    const oldUid: number = this.stableForumUid;
    this.applyCredentials(new CredentialBundle());
    const result: StoreResult = await AuthStore.clear();
    await deleteForumSnapshot(context, oldUid);
    return result;
  }

  /**
   * 标记登录失效（服务端判定凭据不可用时调用）。
   *
   * 这里**同步清掉内存凭据**：失效的凭据留着只会让后续请求继续带错。
   * 存储里的记录交给用户显式退出或下次登录覆盖——不在这里悄悄删，
   * 因为"失效"可能只是单次请求被风控，凭证本身未必真的坏了。
   */
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

/**
 * 全局唯一的登录态实例。
 *
 * 与 `DeviceIdentity` 的模块级 `cached` 同一套路（TD-5：不引入全局状态框架，
 * 页面级/会话级状态用模块级对象）。所有调用方通过这里取凭据，不自己 new。
 */
export const authSession: AuthSession = new AuthSession();
