import { common } from '@kit.AbilityKit';
import { media } from '@kit.MediaKit';
import { TiebaApi } from '../api/TiebaApi';
import { VoiceClip, readVoiceBytes } from '../model/VoiceClip';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { playbackGate, PlaybackParticipant } from '../model/PlaybackGate';

export type VoicePlaybackState = 'idle' | 'loading' | 'playing' | 'paused' | 'completed' | 'error';

@ObservedV2
export class VoicePlaybackVM {
  @Trace currentId: string = '';
  @Trace state: VoicePlaybackState = 'idle';
  @Trace error: string = '';
  @Trace positionMs: number = 0;
  @Trace durationMs: number = -1;
  @Trace commanding: boolean = false;
  private epoch: number = 0;
  private player: media.AVPlayer | undefined = undefined;
  private failedPlayer: media.AVPlayer | undefined = undefined;
  private releasing: Promise<boolean> | undefined = undefined;
  private creating: Promise<media.AVPlayer | undefined> | undefined = undefined;
  private timer: number = -1;
  private api: TiebaApi = new TiebaApi();
  private participant: PlaybackParticipant = new PlaybackParticipant((): Promise<boolean> => this.stop());

  async toggle(context: common.UIAbilityContext, clip: VoiceClip): Promise<void> {
    if (this.commanding) { return; }
    if (this.currentId === clip.id && this.state === 'loading') { await this.stop(); return; }
    if (this.currentId === clip.id && this.player !== undefined &&
      (this.state === 'playing' || this.state === 'paused' || this.state === 'completed')) {
      const mine: number = this.epoch; const player: media.AVPlayer = this.player;
      this.commanding = true;
      try { if (this.state === 'playing') { await player.pause(); } else { await player.play(); } }
      catch (err) { if (this.current(mine)) { await this.fail(mine, '语音播放操作失败，请重试'); } }
      finally { if (this.current(mine)) { this.commanding = false; } }
      return;
    }
    const mine: number = ++this.epoch; this.clearTimer();
    this.currentId = clip.id; this.state = 'loading'; this.error = ''; this.commanding = false;
    this.positionMs = 0; this.durationMs = clip.durationMs;
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
          if (Number.isFinite(player.duration) && player.duration > 0) { this.durationMs = player.duration; }
          void player.play().catch(() => { void this.fail(mine, '语音播放失败，请重试'); });
        } else if (state === 'playing' || state === 'paused' || state === 'completed') {
          this.clearTimer(); this.state = state;
        } else if (state === 'error') { void this.fail(mine, '语音格式不支持或播放失败'); }
      });
      player.on('timeUpdate', (position: number): void => {
        if (this.current(mine) && Number.isFinite(position) && position >= 0) { this.positionMs = position; }
      });
      player.on('error', (): void => { void this.fail(mine, '语音格式不支持或播放失败'); });
      const bytes: Uint8Array = response.bytes;
      player.dataSrc = { fileSize: bytes.length,
        callback: (buffer: ArrayBuffer, length: number, pos?: number): number => readVoiceBytes(bytes, buffer, length, pos) };
    } catch (err) { if (this.current(mine)) { await this.fail(mine, '语音加载或播放失败，请重试'); } }
  }

  async stopFor(id: string): Promise<void> { if (this.currentId === id) { await this.stop(); } }
  async stop(): Promise<boolean> {
    const mine: number = ++this.epoch; this.clearTimer(); this.state = 'idle'; this.currentId = '';
    this.positionMs = 0; this.durationMs = -1; this.error = ''; this.commanding = false;
    const released: boolean = await this.releaseCurrent();
    if (!released && this.current(mine)) { this.state = 'error'; this.error = '播放器释放失败，请重试'; }
    return released;
  }
  private current(mine: number): boolean { return mine === this.epoch; }
  private clearTimer(): void { if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; } }
  private async fail(mine: number, message: string): Promise<void> {
    if (!this.current(mine)) { return; }
    const failureEpoch: number = ++this.epoch; this.clearTimer(); this.state = 'error'; this.error = message;
    this.commanding = false;
    if (!await this.releaseCurrent() && this.current(failureEpoch)) { this.error = `${message}；播放器释放失败，请重试`; }
  }
  private async releaseCurrent(): Promise<boolean> {
    if (this.creating !== undefined) {

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
