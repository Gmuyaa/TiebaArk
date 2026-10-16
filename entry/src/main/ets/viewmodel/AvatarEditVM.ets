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

  @Trace submitting: boolean = false;

  @Trace syncing: boolean = false;

  @Trace busy: boolean = false;
  @Trace ready: boolean = false;

  @Trace preview: string = '';
  @Trace previewVersion: number = 0;

  @Trace received: boolean = false;

  @Trace accepted: boolean = false;

  @Trace pendingReview: boolean = false;

  @Trace profileRead: boolean = false;

  @Trace portraitChanged: boolean = false;
  @Trace portrait: string = '';

  @Trace note: string = '';

  @Trace error: string = '';

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

  private operation: number = 0;

  private syncOp: number = 0;

  private syncPending: boolean = false;
  private syncContext: common.UIAbilityContext | undefined = undefined;

  private handoffContext: common.UIAbilityContext | undefined = undefined;
  private handoffSession: TiebaSession | undefined = undefined;
  private handoffTraceId: number = 0;

  private stopGeneration: number = 0;
  private sameAccount(): boolean {
    const live: TiebaSession = authSession.session();
    return authSession.isLoggedIn() && Number.isSafeInteger(this.uid) && this.uid > 0 && authSession.snapshot.uid === this.uid &&
      live.bduss === this.session.bduss && live.stoken === this.session.stoken;
  }
  private current(mine: number): boolean { return !this.disposed && mine === this.epoch && this.sameAccount(); }

  private opCurrent(mine: number, op: number): boolean { return this.current(mine) && op === this.operation; }

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

  private teardown(): void {
    this.epoch++; this.preparing = false; this.setPhase(false, false); this.syncPending = false; this.clear();
  }
  private begin(): number {
    this.epoch++; this.clear(); this.setPhase(false, false); this.preparing = false;
    this.uid = authSession.snapshot.uid; this.beforePortrait = authSession.snapshot.portrait;
    this.session = authSession.session(); return this.epoch;
  }
  async select(): Promise<void> { await this.prepareSelection(); }

  sourceUri(): string { return this.uri; }
  sourceWidthPx(): number { return this.sourceWidth; }
  sourceHeightPx(): number { return this.sourceHeight; }

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

      const receivedUpload: boolean = response.ok && response.data.received();
      if (!this.opCurrent(mine, op)) {

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

      this.syncOp = authSession.noteAvatarUploadReceived(session, this.uid, traceId);
      if (this.syncOp === 0) { this.error = '账号已变化，头像结果未确认'; return; }

      void authSession.watchAvatarAfterUpload(context, session, this.uid, this.syncOp, traceId);
      this.setPhase(false, true);
      this.syncPending = true;
      await this.readProfile(context, session, mine, op, this.syncOp, traceId);
    } catch (err) { if (this.opCurrent(mine, op)) { this.error = '头像修改结果未确认，请先读取当前资料'; } }
    finally {

      if (this.ownsCall(mine, op)) { this.syncPending = false; this.setPhase(false, false); this.accountFailure(); }
    }
  }

  async reloadProfile(context: common.UIAbilityContext): Promise<void> {
    if (this.disposed || this.busy || this.preparing) { return; }
    const mine: number = this.epoch;
    if (!this.current(mine)) { this.clear(); this.error = '账号已变化，请重新选择头像'; return; }
    const op: number = ++this.operation;
    const traceId: number = avatarTraceNextId();

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

    this.portraitChanged = this.beforePortrait.length > 0 && self.portrait !== this.beforePortrait;
    this.note = this.readbackNote();
    avatarTracePhase('readback-done', traceId, baseStart,
      `changed=${this.portraitChanged} received=${this.received} pending=${this.pendingReview}`);
  }

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

  cancel(): void {
    this.stopGeneration++;
    this.teardown();
    this.error = '已停止后续处理，已发出的头像请求结果未确认';
  }
  dispose(): void {

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
