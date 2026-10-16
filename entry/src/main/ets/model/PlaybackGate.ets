/** 页面音视频共用的交接屏障；旧播放器释放成功才允许新播放器创建。 */
export class PlaybackParticipant {
  stop: () => Promise<boolean>;
  constructor(stop: () => Promise<boolean>) { this.stop = stop; }
}
export class PlaybackGate {
  private active: PlaybackParticipant | undefined = undefined;
  private epoch: number = 0;
  private pending: Promise<boolean> = Promise.resolve(true);
  claim(participant: PlaybackParticipant): Promise<boolean> {
    const mine: number = ++this.epoch;
    const previous: Promise<boolean> = this.pending;
    const next: Promise<boolean> = this.transfer(previous, mine, participant);
    this.pending = next; return next;
  }
  private async transfer(previous: Promise<boolean>, mine: number, participant: PlaybackParticipant): Promise<boolean> {
    await previous;
    if (mine !== this.epoch) { return false; }
    if (this.active !== undefined && this.active !== participant) {
      try { if (!await this.active.stop()) { return false; } }
      catch (err) { return false; }
      this.active = undefined;
    }
    if (mine !== this.epoch) { return false; }
    this.active = participant; return true;
  }
}
export const playbackGate: PlaybackGate = new PlaybackGate();
