import { common } from '@kit.AbilityKit';
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { TiebaApi } from '../api/TiebaApi';
import { VoiceClip, measureAmrDurationMs, readVoiceBytes } from '../model/VoiceClip';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { playbackGate, PlaybackParticipant } from '../model/PlaybackGate';

export type VoicePlaybackState = 'idle' | 'loading' | 'playing' | 'paused' | 'completed' | 'error';

/** 单一播放器；只在点按后请求/播放。代次隔离下载、创建、准备及平台旧回调。 */
@ObservedV2
export class VoicePlaybackVM {
  @Trace currentId: string = '';
  @Trace state: VoicePlaybackState = 'idle';
  @Trace error: string = '';
  @Trace positionMs: number = 0;
  @Trace durationMs: number = -1;
  @Trace commanding: boolean = false;
  @Trace seeking: boolean = false;
  @Trace seekTargetMs: number = 0;
  @Trace interruptionNotice: string = '';
  @Trace durationVersion: number = 0;
  private epoch: number = 0;
  private restarting: boolean = false;
  private confirmedDurations: Map<string, number> = new Map<string, number>();
  private player: media.AVPlayer | undefined = undefined;
  private failedPlayer: media.AVPlayer | undefined = undefined;
  private releasing: Promise<boolean> | undefined = undefined;
  private creating: Promise<media.AVPlayer | undefined> | undefined = undefined;
  private timer: number = -1;
  private seekTimer: number = -1;
  private api: TiebaApi = new TiebaApi();
  private participant: PlaybackParticipant = new PlaybackParticipant((): Promise<boolean> => this.stop());

  durationFor(clip: VoiceClip): number {
    if (this.durationVersion < 0) { return clip.durationMs; }
    if (this.currentId === clip.id && this.durationMs > 0) { return this.durationMs; }
    const confirmed: number | undefined = this.confirmedDurations.get(clip.id);
    return confirmed !== undefined ? confirmed : clip.durationMs;
  }

  seek(position: number): void {
    if (this.player === undefined || this.commanding || this.seeking || !Number.isFinite(position) ||
      this.durationMs <= 0 || ['playing', 'paused', 'completed'].indexOf(this.state) < 0) { return; }
    const mine: number = this.epoch;
    this.clearSeekTimer();
    this.seeking = true;
    this.seekTargetMs = Math.max(0, Math.min(this.durationMs, Math.round(position)));
    this.seekTimer = setTimeout(() => { void this.fail(mine, '语音定位超时，请重试'); }, 15000);
    try { this.player.seek(this.seekTargetMs, media.SeekMode.SEEK_CLOSEST); }
    catch (err) { void this.fail(mine, '语音定位失败，请重试'); }
  }

  async toggle(context: common.UIAbilityContext, clip: VoiceClip): Promise<void> {
    if (this.commanding) { return; }
    if (this.currentId === clip.id && this.state === 'loading') { await this.stop(); return; }
    if (this.currentId === clip.id && this.player !== undefined &&
      (this.state === 'playing' || this.state === 'paused' || this.state === 'completed')) {
      if (this.seeking) { return; }
      const mine: number = this.epoch; const player: media.AVPlayer = this.player;
      this.interruptionNotice = '';
      this.commanding = true;
      try {
        if (this.state === 'playing') {
          this.restarting = false;
          await player.pause();
        } else {
          if (this.state === 'completed' && this.positionMs === 0) {
            this.restarting = true;
          }
          await player.play();
        }
      }
      catch (err) { if (this.current(mine)) { await this.fail(mine, '语音播放操作失败，请重试'); } }
      finally { if (this.current(mine)) { this.commanding = false; } }
      return;
    }
    const mine: number = ++this.epoch; this.clearTimer();
    this.resetFeedback();
    this.currentId = clip.id; this.state = 'loading'; this.error = ''; this.commanding = false;
    const confirmedDuration: number | undefined = this.confirmedDurations.get(clip.id);
    this.positionMs = 0; this.durationMs = confirmedDuration !== undefined ? confirmedDuration : clip.durationMs;
    if (!await playbackGate.claim(this.participant)) {
      if (this.current(mine)) { this.state = 'error'; this.error = '音视频交接未完成，请重试'; } return;
    }
    if (!this.current(mine)) { return; }
    if (!await this.releaseCurrent()) { if (this.current(mine)) { this.state = 'error'; this.error = '播放器释放失败，请重试'; } return; }
    if (!this.current(mine)) { return; }
    this.timer = setTimeout(() => { void this.fail(mine, '语音准备超时，请重试'); }, 25000);
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!this.current(mine)) { return; }
      const response = await this.api.fetchVoiceAudio(device, clip.id);
      if (!this.current(mine)) { return; }
      if (!response.ok) { await this.fail(mine, response.describeFailure()); return; }
      const bytes: Uint8Array = response.bytes;
      const measuredMs: number = measureAmrDurationMs(bytes);
      const hasExactDuration: boolean = measuredMs > 0;
      if (hasExactDuration) { this.recordDuration(clip.id, measuredMs); }
      const creating: Promise<media.AVPlayer | undefined> = this.createCurrent(mine);
      this.creating = creating;
      const player: media.AVPlayer | undefined = await creating;
      if (this.creating === creating) { this.creating = undefined; }
      if (player === undefined || !this.current(mine)) { return; }
      let preparing: boolean = false; let starting: boolean = false;
      player.on('stateChange', (state: string): void => {
        if (!this.current(mine)) { return; }
        if (state === 'initialized' && !preparing) {
          preparing = true;
          void player.prepare().catch(() => { void this.fail(mine, '语音格式不支持或准备失败'); });
        } else if (state === 'prepared' && !starting) {
          starting = true;
          if (!hasExactDuration && Number.isFinite(player.duration) && player.duration > 0) {
            this.recordDuration(clip.id, player.duration);
          }
          void player.play().catch(() => { void this.fail(mine, '语音播放失败，请重试'); });
        } else if (state === 'playing' || state === 'paused' || state === 'completed') {
          this.clearTimer(); this.state = state;
          if (state === 'completed') {
            this.clearSeekTimer(); this.seeking = false; this.restarting = false;
            this.positionMs = 0;
          }
        } else if (state === 'stopped') { void this.fail(mine, '语音已被系统停止，请点按重试'); }
        else if (state === 'error') { void this.fail(mine, '语音格式不支持或播放失败'); }
      });
      player.on('timeUpdate', (position: number): void => {
        if (!this.current(mine) || this.state !== 'playing' || this.seeking || this.commanding ||
          !Number.isFinite(position) || position < 0) { return; }
        // 重播刚启动时过滤 AVPlayer 可能吐出的上轮末尾残余时间戳。
        if (this.restarting) {
          if (this.durationMs > 1000 && position > this.durationMs - 500) { return; }
          this.restarting = false;
        }
        this.positionMs = this.durationMs > 0 ? Math.min(this.durationMs, position) : position;
      });
      player.on('seekDone', (position: number): void => {
        if (!this.current(mine) || !this.seeking) { return; }
        this.clearSeekTimer(); this.seeking = false; this.restarting = false;
        const resolved: number = Number.isFinite(position) && position >= 0 ? position : this.seekTargetMs;
        this.positionMs = this.durationMs > 0 ? Math.min(this.durationMs, resolved) : resolved;
      });
      player.on('durationUpdate', (duration: number): void => {
        if (this.current(mine) && !hasExactDuration && Number.isFinite(duration) && duration > 0) {
          this.recordDuration(clip.id, duration);
        }
      });
      player.on('audioInterrupt', (event: audio.InterruptEvent): void => {
        if (!this.current(mine)) { return; }
        if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE ||
          event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) {
          this.interruptionNotice = '播放被系统打断，可在打断结束后点按继续';
          // 强制打断由系统执行，状态仍以 stateChange 为准；共享打断由应用响应。
          if (event.forceType === audio.InterruptForceType.INTERRUPT_SHARE && player.state === 'playing') {
            void player.pause().catch(() => { void this.fail(mine, '语音暂停失败，请重试'); });
          }
        } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_RESUME) {
          this.interruptionNotice = '系统打断已结束，点按继续播放';
        }
      });
      player.on('error', (): void => { void this.fail(mine, '语音格式不支持或播放失败'); });
      player.dataSrc = { fileSize: bytes.length,
        callback: (buffer: ArrayBuffer, length: number, pos?: number): number => readVoiceBytes(bytes, buffer, length, pos) };
    } catch (err) { if (this.current(mine)) { await this.fail(mine, '语音加载或播放失败，请重试'); } }
  }

  async stopFor(id: string): Promise<void> { if (this.currentId === id) { await this.stop(); } }
  async stop(): Promise<boolean> {
    const mine: number = ++this.epoch; this.clearTimer(); this.state = 'idle'; this.currentId = '';
    this.positionMs = 0; this.durationMs = -1; this.error = ''; this.commanding = false;
    this.resetFeedback();
    const released: boolean = await this.releaseCurrent();
    if (!released && this.current(mine)) { this.state = 'error'; this.error = '播放器释放失败，请重试'; }
    return released;
  }
  private current(mine: number): boolean { return mine === this.epoch; }
  private recordDuration(id: string, durationMs: number): void {
    if (id.length === 0 || !Number.isFinite(durationMs) || durationMs <= 0) { return; }
    if (this.currentId === id) { this.durationMs = durationMs; }
    const previous: number | undefined = this.confirmedDurations.get(id);
    if (previous === durationMs) { return; }
    if (previous === undefined && this.confirmedDurations.size >= 200) {
      const oldest: string | undefined = this.confirmedDurations.keys().next().value;
      if (oldest !== undefined) { this.confirmedDurations.delete(oldest); }
    }
    this.confirmedDurations.set(id, durationMs);
    this.durationVersion++;
  }
  private clearTimer(): void { if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; } }
  private clearSeekTimer(): void { if (this.seekTimer >= 0) { clearTimeout(this.seekTimer); this.seekTimer = -1; } }
  private resetFeedback(): void {
    this.clearSeekTimer(); this.seeking = false; this.seekTargetMs = 0;
    this.interruptionNotice = ''; this.restarting = false;
  }
  private async fail(mine: number, message: string): Promise<void> {
    if (!this.current(mine)) { return; }
    const failureEpoch: number = ++this.epoch; this.clearTimer(); this.state = 'error'; this.error = message;
    this.commanding = false;
    this.clearSeekTimer(); this.seeking = false;
    if (!await this.releaseCurrent() && this.current(failureEpoch)) { this.error = `${message}；播放器释放失败，请重试`; }
  }
  private async releaseCurrent(): Promise<boolean> {
    if (this.creating !== undefined) {
      // 创建失败由启动调用方展示；此处仍须完成可能遗留播放器的释放。
      try { await this.creating; } catch (err) { this.creating = undefined; }
    }
    if (this.releasing !== undefined) { return await this.releasing; }
    this.releasing = this.releasePlayer();
    const result: boolean = await this.releasing;
    this.releasing = undefined;
    return result;
  }
  private async createCurrent(mine: number): Promise<media.AVPlayer | undefined> {
    const player: media.AVPlayer = await media.createAVPlayer();
    if (this.current(mine)) { this.player = player; return player; }
    try { await player.release(); } catch (err) { this.failedPlayer = player; }
    return undefined;
  }
  private async releasePlayer(): Promise<boolean> {
    const player: media.AVPlayer | undefined = this.player ?? this.failedPlayer;
    this.player = undefined; this.failedPlayer = undefined;
    if (player === undefined) { return true; }
    try { await player.release(); return true; }
    catch (err) { this.failedPlayer = player; return false; }
  }
}
export const voicePlayback: VoicePlaybackVM = new VoicePlaybackVM();
