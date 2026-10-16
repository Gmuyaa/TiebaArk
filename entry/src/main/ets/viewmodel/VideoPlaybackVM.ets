import { media } from '@kit.MediaKit';
import { VideoClip, videoSourceUrl } from '../model/VideoClip';
import { playbackGate, PlaybackParticipant } from '../model/PlaybackGate';
import { VideoNetworkWatch } from '../utils/VideoNetworkWatch';

export type VideoPlaybackState = 'idle' | 'loading' | 'playing' | 'paused' | 'completed' | 'error';

@ObservedV2
export class VideoPlaybackVM {
  @Trace currentId: string = '';
  @Trace state: VideoPlaybackState = 'idle';
  @Trace error: string = '';
  @Trace positionMs: number = 0;
  @Trace durationMs: number = -1;
  @Trace commanding: boolean = false;
  @Trace networkNotice: string = '';
  private network: VideoNetworkWatch | undefined = undefined;
  private epoch: number = 0;
  private player: media.AVPlayer | undefined = undefined;
  private failedPlayer: media.AVPlayer | undefined = undefined;
  private releasing: Promise<boolean> | undefined = undefined;
  private creating: Promise<media.AVPlayer | undefined> | undefined = undefined;
  private timer: number = -1;
  private surface: string = '';
  private participant: PlaybackParticipant = new PlaybackParticipant((): Promise<boolean> => this.stop());
  @Trace firstFrame: boolean = false;
  setSurface(id: string): void {
    this.surface = id;
    if (this.player !== undefined && ['initialized', 'prepared', 'playing', 'paused', 'completed', 'stopped'].indexOf(this.player.state) >= 0) {
      try { this.player.surfaceId = id; } catch (err) { void this.fail(this.epoch, '视频画面切换失败，请重试'); }
    }
  }
  seek(position: number): void {
    if (this.player === undefined || this.commanding || !Number.isFinite(position) || position < 0 || this.durationMs <= 0 || position > this.durationMs || ['playing', 'paused', 'completed'].indexOf(this.state) < 0) { return; }
    try { this.player.seek(Math.round(position)); } catch (err) { void this.fail(this.epoch, '视频定位失败，请重试'); }
  }

  async toggle(clip: VideoClip): Promise<void> {
    if (this.commanding) { return; }
    if (videoSourceUrl(clip.url).length === 0 || this.surface.length === 0) {
      this.currentId = clip.url;
      await this.fail(this.epoch, '视频地址或画面尚未准备，请重试'); return;
    }
    if (this.currentId === clip.url && this.state === 'loading') { await this.stop(); return; }
    if (this.currentId === clip.url && this.player !== undefined &&
      (this.state === 'playing' || this.state === 'paused' || this.state === 'completed')) {
      const mine: number = this.epoch; const player: media.AVPlayer = this.player;
      this.commanding = true;
      try { if (this.state === 'playing') { await player.pause(); } else { await player.play(); } }
      catch (err) { if (this.current(mine)) { await this.fail(mine, '视频播放操作失败，请重试'); } }
      finally { if (this.current(mine)) { this.commanding = false; } }
      return;
    }
    const mine: number = ++this.epoch; this.clearTimer();
    this.currentId = clip.url; this.state = 'loading'; this.error = ''; this.commanding = false;
    this.positionMs = 0; this.durationMs = -1; this.firstFrame = false; this.networkNotice = '';
    if (!await playbackGate.claim(this.participant)) {
      if (this.current(mine)) { this.state = 'error'; this.error = '音视频交接未完成，请重试'; } return;
    }
    if (!this.current(mine)) { return; }
    if (!await this.releaseCurrent()) { if (this.current(mine)) { this.state = 'error'; this.error = '播放资源释放失败，请重试'; } return; }
    if (!this.current(mine)) { return; }
    this.timer = setTimeout(() => { void this.fail(mine, '视频准备超时，请重试'); }, 25000);
    try {
      const network: VideoNetworkWatch = new VideoNetworkWatch(); this.network = network;
      const watching: boolean = await network.start((lost: boolean): void => {
        if (!this.current(mine)) { return; }
        if (lost) { void this.fail(mine, '网络连接已断开，请连接网络后重试'); }
        else { this.networkNotice = '网络已切换；若播放中断，请点按重试'; }
      });
      if (!this.current(mine)) { return; }
      if (!watching) { this.networkNotice = '暂时无法监听网络变化；播放失败时请检查网络'; }
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
          if (this.surface.length === 0) { void this.fail(mine, '视频画面尚未准备，请重试'); return; }
          try { player.surfaceId = this.surface; }
          catch (err) { void this.fail(mine, '视频画面初始化失败，请重试'); return; }
          void player.prepare().catch(() => { void this.fail(mine, '视频格式不支持或准备失败'); });
        } else if (state === 'prepared' && !starting) {
          starting = true;
          if (Number.isFinite(player.duration) && player.duration > 0) { this.durationMs = player.duration; }
          void player.play().catch(() => { void this.fail(mine, '视频播放失败，请重试'); });
        } else if (state === 'playing' || state === 'paused' || state === 'completed') {
          this.clearTimer(); this.state = state;
        } else if (state === 'error') { void this.fail(mine, '视频播放失败，请检查网络或格式后重试'); }
      });
      player.on('timeUpdate', (position: number): void => {
        if (this.current(mine) && Number.isFinite(position) && position >= 0) { this.positionMs = position; }
      });
      player.on('error', (): void => { void this.fail(mine, '视频播放失败，请检查网络或格式后重试'); });
      player.on('startRenderFrame', (): void => { if (this.current(mine)) { this.firstFrame = true; } });
      player.url = clip.url;
    } catch (err) { if (this.current(mine)) { await this.fail(mine, '视频加载或播放失败，请重试'); } }
  }

  async stopFor(id: string): Promise<void> { if (this.currentId === id) { await this.stop(); } }
  async stop(): Promise<boolean> {
    const mine: number = ++this.epoch; this.clearTimer(); this.state = 'idle'; this.currentId = '';
    this.positionMs = 0; this.durationMs = -1; this.firstFrame = false; this.error = ''; this.commanding = false;
    this.networkNotice = '';
    const released: boolean = await this.releaseCurrent();
    if (!released && this.current(mine)) { this.state = 'error'; this.error = '播放资源释放失败，请重试'; }
    return released;
  }
  private current(mine: number): boolean { return mine === this.epoch; }
  private clearTimer(): void { if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; } }
  private async fail(mine: number, message: string): Promise<void> {
    if (!this.current(mine)) { return; }
    const failureEpoch: number = ++this.epoch; this.clearTimer(); this.state = 'error'; this.error = message;
    this.commanding = false;
    if (!await this.releaseCurrent() && this.current(failureEpoch)) { this.error = `${message}；播放资源释放失败，请重试`; }
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
    const network: VideoNetworkWatch | undefined = this.network;
    const closed: boolean = network === undefined || await network.close();
    if (closed) { this.network = undefined; }
    const player: media.AVPlayer | undefined = this.player ?? this.failedPlayer;
    this.player = undefined; this.failedPlayer = undefined;
    if (player === undefined) { return closed; }
    try { await player.release(); return closed; }
    catch (err) { this.failedPlayer = player; return false; }
  }
}
export const videoPlayback: VideoPlaybackVM = new VideoPlaybackVM();
