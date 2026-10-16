import { createReplyImagePreview } from '../utils/ImagePrepare';
import { ImageUploadInput } from '../model/ImageUpload';
import { common } from '@kit.AbilityKit';
import { authSession } from '../auth/AuthSession';
import { TiebaApi } from '../api/TiebaApi';
import { TiebaSession } from '../net/TiebaParams';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { avatarTrace, avatarTracePhase, avatarTraceNextId, avatarUptimeMs } from '../utils/AvatarTrace';
import { pickAvatarImage, prepareAvatarImage, AvatarPrepareResult } from '../utils/AvatarPrepare';
import { AvatarCrop, AvatarUploadInput, avatarUploadInputError } from '../model/AvatarUpload';

@ObservedV2
export class AvatarEditVM {
  @Trace preparing: boolean = false;
  /** 上传中：尚未收到服务器的结果。 */
  @Trace submitting: boolean = false;
  /** 已接收、正在读回资料；期间离开页面不需要等待。 */
  @Trace syncing: boolean = false;
  /** 两阶段之一在进行；按钮禁用与既有调用方沿用这个总标志。 */
  @Trace busy: boolean = false;
  @Trace ready: boolean = false;
  /** 本机候选预览（只在本编辑页显示；不发布到全局）。 */
  @Trace preview: string = '';
  @Trace previewVersion: number = 0;
  /** 服务端已接收这次上传（`code=0` 或 `300003` 审核中）。 */
  @Trace received: boolean = false;
  /** 服务端明确成功（`code=0`）。与 `received`/`pendingReview` 分开，不互相代替。 */
  @Trace accepted: boolean = false;
  /** 服务端"已上传、审核中"（实测 `error_code=300003`）。 */
  @Trace pendingReview: boolean = false;
  /** 已读到本人资料（不代表头像记录一定变化）。 */
  @Trace profileRead: boolean = false;
  /** 读回的 portrait 与操作前记录不同（**不**断言就是本次候选图）。 */
  @Trace portraitChanged: boolean = false;
  @Trace portrait: string = '';
  /** 中性说明：既不是失败也不是成功。 */
  @Trace note: string = '';
  /** 仅真实错误：上传失败/结果未知、读回失败、账号变化等。 */
  @Trace error: string = '';
  /** 本次（最近一次）头像操作的 trace 标识；只读给出，供测试与排查关联。 */
  traceId: number = 0;
  private uri: string = '';
  private sourceWidth: number = 0;
  private sourceHeight: number = 0;
  private input: AvatarUploadInput | undefined = undefined;
  private api: TiebaApi = new TiebaApi();
  private session: TiebaSession = new TiebaSession();
  private uid: number = 0;
  private beforePortrait: string = '';
  private epoch: number = 0;
  private disposed: boolean = false;
  /** 本地操作代次：区分同一次编辑会话里的先后两次确认（只用于隔离）。 */
  private operation: number = 0;
  /** 共享会话里"已接收上传"的代次（0 = 没有声明）。 */
  private syncOp: number = 0;
  /** 上传已接收、读回未结束：离开页面时据此决定是否交接。 */
  private syncPending: boolean = false;
  private syncContext: common.UIAbilityContext | undefined = undefined;
  /** 交接用的不可变快照：不得改读新操作的可变 context / session / traceId。 */
  private handoffContext: common.UIAbilityContext | undefined = undefined;
  private handoffSession: TiebaSession | undefined = undefined;
  private handoffTraceId: number = 0;
  /**
   * 显式停止的代次。`confirmUpload` 记下进入时的值，
   * 迟到响应只有在该值未变（期间没有用户显式停止）时才允许交接。
   */
  private stopGeneration: number = 0;
  private sameAccount(): boolean {
    const live: TiebaSession = authSession.session();
    return authSession.isLoggedIn() && Number.isSafeInteger(this.uid) && this.uid > 0 && authSession.snapshot.uid === this.uid &&
      live.bduss === this.session.bduss && live.stoken === this.session.stoken;
  }
  private current(mine: number): boolean { return !this.disposed && mine === this.epoch && this.sameAccount(); }
  /** 本次调用仍然是"当前这一次操作"（epoch 与本地操作代次都未变）。 */
  private opCurrent(mine: number, op: number): boolean { return this.current(mine) && op === this.operation; }
  /**
   * 回收阶段标志用：只看"还是不是本站当前这次操作"，**不看账号是否已变**。
   * 换号会让 `opCurrent` 为假，但那时仍必须把 submitting/syncing/busy 收回，
   * 否则界面会永远停在"正在提交"。
   */
  private ownsCall(mine: number, op: number): boolean {
    return !this.disposed && mine === this.epoch && op === this.operation;
  }
  private setPhase(submitting: boolean, syncing: boolean): void {
    this.submitting = submitting;
    this.syncing = syncing;
    this.busy = submitting || syncing;
  }
  private clear(): void {
    this.input = undefined; this.ready = false; this.preview = '';
    this.uri = ''; this.sourceWidth = 0; this.sourceHeight = 0;
    this.received = false; this.accepted = false; this.pendingReview = false;
    this.profileRead = false; this.portraitChanged = false; this.portrait = '';
    this.note = ''; this.error = '';
  }
  /** 停掉本站正在进行的处理，但不区分原因（取消与销毁共用）。 */
  private teardown(): void {
    this.epoch++; this.preparing = false; this.setPhase(false, false); this.syncPending = false; this.clear();
  }
  private begin(): number {
    this.epoch++; this.clear(); this.setPhase(false, false); this.preparing = false;
    this.uid = authSession.snapshot.uid; this.beforePortrait = authSession.snapshot.portrait;
    this.session = authSession.session(); return this.epoch;
  }
  async select(): Promise<void> { await this.prepareSelection(); }
  /** 裁剪页要显示的原图与它的像素尺寸；只读给出，裁剪结果仍由 `prepare` 重新生成 960×960。 */
  sourceUri(): string { return this.uri; }
  sourceWidthPx(): number { return this.sourceWidth; }
  sourceHeightPx(): number { return this.sourceHeight; }
  /**
   * 裁剪页点「完成」后用它换出最终 JPEG：入参是同一张原图与用户确认的裁剪区域。
   * 取消选图（`ready` 仍为 false）不发任何请求；准备阶段的失败照常落进 `error`，由界面如实显示。
   */
  async prepare(uri: string, crop: AvatarCrop): Promise<void> { await this.prepareSelection(uri, crop); }
  private async prepareSelection(uri?: string, crop?: AvatarCrop): Promise<void> {
    if (this.disposed || ((this.preparing || this.busy) && this.sameAccount())) { return; }
    const mine: number = this.begin();
    if (!this.current(mine)) { this.error = '登录并确认账号资料后才能修改头像'; return; }
    this.preparing = true;
    try {
      const result: AvatarPrepareResult = uri === undefined ? await pickAvatarImage(() => this.current(mine)) :
        await prepareAvatarImage(uri, () => this.current(mine), crop);
      if (!this.current(mine)) { return; }
      if (result.cancelled) { return; }
      if (result.input === undefined) { this.error = result.message; return; }
      const invalid: string = avatarUploadInputError(result.input);
      if (invalid.length > 0) { this.error = invalid; return; }
      const prepared: AvatarUploadInput = new AvatarUploadInput();
      prepared.bytes = result.input.bytes.slice(); prepared.width = result.input.width; prepared.height = result.input.height;
      const previewInput: ImageUploadInput = new ImageUploadInput();
      previewInput.bytes = prepared.bytes; previewInput.width = prepared.width; previewInput.height = prepared.height;
      const preview: string = await createReplyImagePreview(previewInput, () => this.current(mine));
      if (!this.current(mine)) { return; }
      if (preview.length === 0) { this.error = '头像预览未生成，请重新选择'; return; }
      this.input = prepared; this.preview = preview; this.previewVersion = mine; this.ready = true;
      this.uri = result.uri; this.sourceWidth = result.sourceWidth; this.sourceHeight = result.sourceHeight;
    } catch (err) { if (this.current(mine)) { this.error = '头像准备失败，请重新选择'; } }
    finally { if (mine === this.epoch) { this.preparing = false; this.accountFailure(); } }
  }
  /**
   * 仅显式确认后发送一次；传输开始便消耗准备内容，未知结果不可再次点击重发。
   *
   * 服务端**接收**（含审核中）后立即结束"提交中"，转为"正在同步资料"；
   * 但接收不等于生效：候选图只留在编辑流程里，全局头像要等读回的服务端资料。
   */
  async confirmUpload(context: common.UIAbilityContext): Promise<void> {
    if (this.disposed || this.busy || this.preparing) { return; }
    const mine: number = this.epoch;
    if (!this.current(mine)) { this.clear(); this.error = '账号已变化，请重新选择头像'; return; }
    if (!this.ready || this.input === undefined) { this.error = '请先选择并确认头像图片'; return; }
    const input: AvatarUploadInput = this.input;
    const op: number = ++this.operation;
    const traceId: number = avatarTraceNextId();
    const session: TiebaSession = this.session;
    const stopGeneration: number = this.stopGeneration;
    this.traceId = traceId;
    const startedMs: number = avatarUptimeMs();
    this.syncContext = context; this.handoffContext = context;
    this.handoffSession = session; this.handoffTraceId = traceId;
    this.error = ''; this.note = '';
    this.setPhase(true, false);
    avatarTrace('confirm', traceId, `bytes=${input.bytes.length}`);
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!this.opCurrent(mine, op)) { return; }
      avatarTracePhase('device-ready', traceId, startedMs, '');
      this.input = undefined; this.ready = false; this.uri = ""; this.sourceWidth = 0; this.sourceHeight = 0;
      const response = await this.api.uploadAvatar(device, session, input, traceId);
      // 服务端"已接收"含审核中（实测 300003）；它只表示接收，不代表头像已生效。
      const receivedUpload: boolean = response.ok && response.data.received();
      if (!this.opCurrent(mine, op)) {
        // 页面已离开或本次操作被取代：已接收的上传仍要读回，交给共享刷新队列。
        // 用户显式停止过（stopGeneration 变了）则不交接，也不使用新操作的任何可变状态。
        if (receivedUpload) { this.handOffSync(context, session, traceId, stopGeneration, 'left-page'); }
        return;
      }
      avatarTracePhase('upload-response', traceId, startedMs,
        `ok=${response.ok} received=${receivedUpload} accepted=${response.data.accepted()}`
          + ` pending=${response.data.pendingReview()}`);
      if (!receivedUpload) { this.error = response.describeFailure(); return; }
      this.received = true;
      this.accepted = response.data.accepted();
      this.pendingReview = response.data.pendingReview();
      // 只声明"服务端接收了这次上传"（隔离上传前在途的资料刷新），不发布任何展示状态。
      this.syncOp = authSession.noteAvatarUploadReceived(session, this.uid, traceId);
      if (this.syncOp === 0) { this.error = '账号已变化，头像结果未确认'; return; }
      // 已接收后后台有限次只读复查；页面离开后仍由共享会话持有。
      void authSession.watchAvatarAfterUpload(context, session, this.uid, this.syncOp, traceId);
      this.setPhase(false, true);
      this.syncPending = true;
      await this.readProfile(context, session, mine, op, this.syncOp, traceId);
    } catch (err) { if (this.opCurrent(mine, op)) { this.error = '头像修改结果未确认，请先读取当前资料'; } }
    finally {
      // 只有仍是本站当前这次操作才回收阶段标志与同步归属；被取消/销毁的路径由 cancel/dispose 处理。
      if (this.ownsCall(mine, op)) { this.syncPending = false; this.setPhase(false, false); this.accountFailure(); }
    }
  }
  /** 读回可独立重试，不重发上传；旧账号/销毁/取消结果均不落入当前状态。 */
  async reloadProfile(context: common.UIAbilityContext): Promise<void> {
    if (this.disposed || this.busy || this.preparing) { return; }
    const mine: number = this.epoch;
    if (!this.current(mine)) { this.clear(); this.error = '账号已变化，请重新选择头像'; return; }
    const op: number = ++this.operation;
    const traceId: number = avatarTraceNextId();
    // 独立重读声明"我就是当前这次"；期间出现更晚的上传则本次发布作废。
    const syncOp: number = authSession.avatarSyncOp();
    const session: TiebaSession = this.session;
    const startedMs: number = avatarUptimeMs();
    this.traceId = traceId;
    this.syncContext = context; this.handoffContext = context;
    this.handoffSession = session; this.handoffTraceId = traceId;
    this.setPhase(false, true);
    this.error = ''; this.note = ''; this.profileRead = false; this.portraitChanged = false; this.portrait = '';
    avatarTrace('reload-start', traceId, `syncOp=${syncOp}`);
    try { await this.readProfile(context, session, mine, op, syncOp, traceId); }
    catch (err) { if (this.opCurrent(mine, op)) { this.error = '当前头像资料读取失败'; } }
    finally { if (this.ownsCall(mine, op)) { this.setPhase(false, false); this.accountFailure(); } }
  }
  /**
   * 读回**服务端**当前资料。发布它的是 `acceptAvatarProfile`（本机候选图不参与），
   * 因此"我的"与本人主页显示的是服务端当前生效的头像。
   */
  private async readProfile(context: common.UIAbilityContext, session: TiebaSession, mine: number,
    op: number, syncOp: number, traceId: number): Promise<void> {
    const baseStart: number = avatarUptimeMs();
    const device = await DeviceIdentity.ensure(context);
    if (!this.opCurrent(mine, op)) { return; }
    const base = await this.api.fetchUserInfo(session);
    if (!this.opCurrent(mine, op)) { return; }
    avatarTracePhase('readback-base', traceId, baseStart, `portrait=${base.portrait.length > 0}`);
    if (base.portrait.length === 0) { this.error = '当前头像资料未取得，请稍后重试'; return; }
    const selfStart: number = avatarUptimeMs();
    const self = await this.api.fetchSelfProfile(session, device, base.portrait);
    if (!this.opCurrent(mine, op)) { return; }
    avatarTracePhase('readback-self', traceId, selfStart, `ok=${self !== undefined}`);
    if (self === undefined || self.uid !== this.uid || self.portrait.length === 0) {
      this.error = '当前头像资料所属账号未确认'; return;
    }
    if (!authSession.acceptAvatarProfile(session, self, syncOp)) {
      this.error = authSession.avatarOperationStale(syncOp)
        ? '本次读回已被更晚的头像操作取代' : '账号已变化，头像结果未确认';
      return;
    }
    this.portrait = self.portrait; this.profileRead = true;
    // 只比较记录是否变化；不断言变化来自本次候选图（用户可能在官方端又改过）。
    this.portraitChanged = this.beforePortrait.length > 0 && self.portrait !== this.beforePortrait;
    this.note = this.readbackNote();
    avatarTracePhase('readback-done', traceId, baseStart,
      `changed=${this.portraitChanged} received=${this.received} pending=${this.pendingReview}`);
  }
  /**
   * 读回后的中性说明：不报失败、不假装成功、不推断审核结果、不把变化归给本次候选图。
   */
  private readbackNote(): string {
    if (this.portraitChanged) {
      return '当前资料已显示头像记录变化（不区分是否本次所选图片）。';
    }
    if (this.beforePortrait.length === 0) {
      return '原头像记录缺失，无法比较是否变化；当前资料里的头像已按服务端显示。';
    }
    return this.pendingReview
      ? '已上传，审核中：当前资料尚未显示头像记录变化，审核结果未知。'
      : '服务端已接收本次上传：当前资料尚未显示头像记录变化。';
  }
  /**
   * 离开页面/被取代后仍需要同步时，把任务交给共享刷新队列。
   *
   * 入参是**发起调用时捕获的不可变快照**：不得使用新操作的 context / session / traceId。
   * 归属与清理：任务由 `AuthSession.profileRefreshing` 持有，异常在队列内吞掉，
   * 结果按 `profileVersion`/会话比对丢弃，换号、退出或新会话都会作废它。
   * 用户显式停止过（stopGeneration 已变）时直接放弃，不启动任何请求。
   */
  private handOffSync(context: common.UIAbilityContext, session: TiebaSession, traceId: number,
    stopGeneration: number, reason: string): void {
    if (stopGeneration !== this.stopGeneration) { return; }
    const live: TiebaSession = authSession.session();
    if (!authSession.isLoggedIn() || live.bduss !== session.bduss || live.stoken !== session.stoken) { return; }
    avatarTrace('sync-handoff', traceId, `reason=${reason} owner=AuthSession`);
    void authSession.refreshProfile(context);
  }
  private accountFailure(): void {
    if (!this.disposed && !this.sameAccount()) { this.clear(); this.error = '账号已变化，头像结果未确认'; }
  }
  previewFailed(version: number): void {
    if (version !== this.epoch || !this.ready || this.busy || this.preparing) { return; }
    this.cancel(); this.error = '头像预览显示失败，请重新选择图片';
  }
  /** 用户显式"停止后续处理"：本次及更早的调用此后都不得再交接同步。 */
  cancel(): void {
    this.stopGeneration++;
    this.teardown();
    this.error = '已停止后续处理，已发出的头像请求结果未确认';
  }
  dispose(): void {
    // 上传已接收、读回未结束就离开页面：用捕获的快照交接，避免"没人管的 Promise"。
    const pending: boolean = this.syncPending;
    const context: common.UIAbilityContext | undefined = this.handoffContext;
    const session: TiebaSession | undefined = this.handoffSession;
    const traceId: number = this.handoffTraceId;
    const stopGeneration: number = this.stopGeneration;
    this.teardown();
    this.disposed = true;
    this.error = '';
    if (pending && context !== undefined && session !== undefined) {
      this.handOffSync(context, session, traceId, stopGeneration, 'disposed');
    }
    this.session = new TiebaSession();
    this.syncContext = undefined; this.handoffContext = undefined; this.handoffSession = undefined;
  }
}
