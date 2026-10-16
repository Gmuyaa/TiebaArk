import { VideoClip } from '../model/VideoClip';
import { VideoPlaybackVM, videoPlayback } from '../viewmodel/VideoPlaybackVM';
import { AppTheme } from '../theme/Theme';
import { lowFlowStore } from '../common/appearance/LowFlowStore';

@ComponentV2
export struct VideoPlayer {
  @Param video: VideoClip = new VideoClip();
  @Local vm: VideoPlaybackVM = videoPlayback;
  @Local fullscreen: boolean = false;
  @Event onFullscreenChange: (shown: boolean) => void = (_shown: boolean): void => {};
  private inlineController: XComponentController = new XComponentController();
  private fullController: XComponentController = new XComponentController();
  private mounted: boolean = false;
  aboutToAppear(): void { this.mounted = true; }
  aboutToDisappear(): void { this.mounted = false; this.setFullscreen(false); void this.vm.stopFor(this.video.url); }
  private setFullscreen(shown: boolean): void {

    this.onFullscreenChange(shown);
    this.fullscreen = shown;
  }
  private active(): boolean { return this.vm.currentId === this.video.url; }
  private useInline(): void {
    if (this.mounted && !this.fullscreen) { this.vm.setSurface(this.inlineController.getXComponentSurfaceId()); }
  }
  private action(): string {
    if (!this.active()) { return '播放'; }
    if (this.vm.state === 'loading') { return '取消'; }
    return this.vm.state === 'playing' ? '暂停' : this.vm.state === 'error' ? '重试' : '播放';
  }
  @Builder
  Controls() {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Button(this.action()).enabled(!this.vm.commanding).onClick(() => { void this.vm.toggle(this.video); })
        Text(this.active() && this.vm.durationMs > 0 ?
          `${(this.vm.positionMs / 1000).toFixed(1)} / ${(this.vm.durationMs / 1000).toFixed(1)} 秒` : '时长待播放确认')
          .fontSize(12).fontColor(AppTheme.TEXT_SUB).layoutWeight(1)
        Button(this.fullscreen ? '退出全屏' : '全屏').onClick(() => { this.setFullscreen(!this.fullscreen); })
      }.width('100%')
      if (this.active() && this.vm.durationMs > 0) {
        Slider({ value: this.vm.positionMs, min: 0, max: this.vm.durationMs })
          .enabled(this.vm.state === 'playing' || this.vm.state === 'paused' || this.vm.state === 'completed')
          .onChange((value: number, mode: SliderChangeMode) => { if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) { this.vm.seek(value); } })
      }
      if (this.active() && this.vm.state === 'loading') { Text('正在准备视频…').fontColor(AppTheme.TEXT_SUB).fontSize(12) }
      if (this.active() && this.vm.error.length > 0) { Text(this.vm.error).fontColor(AppTheme.ACCENT_DARK).fontSize(12) }
      if (this.active() && this.vm.networkNotice.length > 0) { Text(this.vm.networkNotice).fontColor(AppTheme.TEXT_SUB).fontSize(12) }
    }.width('100%').padding(12).backgroundColor(AppTheme.CARD)
  }
  @Builder
  Fullscreen() {
    Column() {
      XComponent({ id: 'tieba-video-full', type: XComponentType.SURFACE, controller: this.fullController })
        .width('100%').layoutWeight(1).onLoad(() => {
          if (this.mounted && this.fullscreen) { this.vm.setSurface(this.fullController.getXComponentSurfaceId()); }
        })
      this.Controls()
    }.width('100%').height('100%').backgroundColor(Color.Black)
  }
  build() {
    Column() {
      Stack() {
        XComponent({ id: 'tieba-video-inline', type: XComponentType.SURFACE, controller: this.inlineController })
          .width('100%').height(220).onLoad(() => { if (!this.fullscreen) { this.useInline(); } })
        if ((!this.active() || !this.vm.firstFrame) && this.video.cover.length > 0 && !lowFlowStore.enabled) {
          Image(this.video.cover).width('100%').height(220).objectFit(ImageFit.Contain).hitTestBehavior(HitTestMode.None)
        }
      }.width('100%').height(220).backgroundColor(Color.Black)
      this.Controls()
    }.width('100%').borderRadius(12).clip(true)
      .bindContentCover(this.fullscreen, this.Fullscreen(), { enableSafeArea: false, backgroundColor: Color.Black,
        onDisappear: (): void => { this.setFullscreen(false); this.useInline(); } })
  }
}
