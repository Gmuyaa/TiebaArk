import { VideoClip } from '../model/VideoClip';
import { VideoPlaybackVM, videoPlayback } from '../viewmodel/VideoPlaybackVM';
import { AppTheme } from '../theme/Theme';
import { lowFlowStore } from '../common/appearance/LowFlowStore';
import { common } from '@kit.AbilityKit';
import { VideoWindowPolicy } from '../utils/VideoWindowPolicy';

@ComponentV2
export struct VideoPlayer {
  @Param video: VideoClip = new VideoClip();
  @Param stage: boolean = false;
  @Param autoPlay: boolean = false;
  @Param controlBottomGap: number = 0;
  @Local vm: VideoPlaybackVM = videoPlayback;
  @Local fullscreen: boolean = false;
  @Local inlineWidth: number = 0;
  @Local stageWidth: number = 1;
  @Local stageHeight: number = 1;
  @Local dragging: boolean = false;
  @Local previewMs: number = 0;
  @Local windowNotice: string = '';
  @Event onFullscreenChange: (shown: boolean) => void = (_shown: boolean): void => {};
  private inlineController: XComponentController = new XComponentController();
  private fullController: XComponentController = new XComponentController();
  private mounted: boolean = false;
  private boundUrl: string = '';
  private hostContext: common.UIAbilityContext | undefined = undefined;
  private windowPolicy: VideoWindowPolicy = new VideoWindowPolicy();
  aboutToAppear(): void {
    this.boundUrl = this.video.url;
    this.hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.mounted = true; this.syncWindow();
  }
  aboutToDisappear(): void { this.mounted = false; this.dragging = false; this.setFullscreen(false); void this.vm.stopFor(this.video.url); }
  private setFullscreen(shown: boolean): void {
    // 先通知详情页，再打开覆盖层；onHidden 可能在覆盖层出现时立即触发。
    this.onFullscreenChange(shown);
    this.fullscreen = shown;
    this.dragging = false;
    this.syncWindow();
  }
  private active(): boolean { return this.vm.currentId === this.video.url; }
  @Monitor('video')
  private sourceChanged(): void {
    const previous: string = this.boundUrl; this.boundUrl = this.video.url;
    if (this.mounted && previous.length > 0 && previous !== this.video.url) {
      this.dragging = false; void this.vm.stopFor(previous);
    }
  }
  @Monitor('vm.state', 'vm.currentId')
  private playbackChanged(): void {
    if (!this.active() || this.vm.state === 'idle' || this.vm.state === 'error') { this.dragging = false; }
    this.syncWindow();
  }
  private syncWindow(): void {
    if (this.hostContext === undefined) { return; }
    void this.windowPolicy.update(this.hostContext, this.mounted && this.fullscreen, this.sourceWidth() > this.sourceHeight(),
      this.mounted && this.active() && this.vm.state === 'playing').then((): void => {
      if (this.mounted) { this.windowNotice = ''; }
    }).catch((): void => { if (this.mounted) { this.windowNotice = '窗口方向或常亮设置失败，请重试'; } });
  }
  private sourceWidth(): number { return this.active() && this.vm.videoWidth > 0 ? this.vm.videoWidth : this.video.width; }
  private sourceHeight(): number { return this.active() && this.vm.videoHeight > 0 ? this.vm.videoHeight : this.video.height; }
  private inlineHeight(): number {
    if (this.inlineWidth <= 0 || this.sourceWidth() <= 0 || this.sourceHeight() <= 0) { return 220; }
    return Math.max(120, Math.min(420, this.inlineWidth * this.sourceHeight() / this.sourceWidth()));
  }
  private stageSurfaceWidth(): number {
    const ratio: number = this.sourceWidth() > 0 && this.sourceHeight() > 0 ? this.sourceWidth() / this.sourceHeight() : 1;
    return Math.max(1, Math.min(this.stageWidth, this.stageHeight * ratio));
  }
  private stageSurfaceHeight(): number {
    const ratio: number = this.sourceWidth() > 0 && this.sourceHeight() > 0 ? this.sourceWidth() / this.sourceHeight() : 1;
    return Math.max(1, Math.min(this.stageHeight, this.stageWidth / ratio));
  }
  private progress(): number { return this.dragging ? this.previewMs : this.vm.seeking ? this.vm.seekTargetMs : this.vm.positionMs; }
  private time(ms: number): string {
    const seconds: number = Math.max(0, Math.floor(ms / 1000));
    return `${Math.floor(seconds / 60)}:${(seconds % 60).toString().padStart(2, '0')}`;
  }
  private feedback(): string {
    if (!this.active()) { return ''; }
    if (this.vm.error.length > 0) { return this.vm.error; }
    if (this.vm.state === 'loading') { return '正在准备视频…'; }
    if (this.vm.state === 'playing' && !this.vm.firstFrame) { return '正在等待视频画面…'; }
    if (this.vm.seeking) { return '正在定位…'; }
    if (this.vm.buffering && this.vm.state === 'playing') { return '正在缓冲…'; }
    return '';
  }
  private useInline(): void {
    if (this.mounted && !this.fullscreen) { this.vm.setSurface(this.inlineController.getXComponentSurfaceId()); }
  }
  private surfaceReady(): void {
    this.useInline();
    if (this.mounted && this.stage && this.autoPlay && !this.active()) { void this.vm.toggle(this.video); }
  }
  private action(): string {
    if (!this.active()) { return '播放'; }
    if (this.vm.state === 'loading') { return '取消'; }
    return this.vm.state === 'playing' ? '暂停' : this.vm.state === 'error' ? '重试' : '播放';
  }
  @Builder
  Controls(immersive: boolean = false) {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Button(this.action()).enabled(!this.vm.commanding).onClick(() => { void this.vm.toggle(this.video); })
        Text(this.active() && this.vm.durationMs > 0 ?
          `${this.time(this.progress())} / ${this.time(this.vm.durationMs)}` : '时长待播放确认')
          .fontSize(12).fontColor(immersive ? Color.White : AppTheme.TEXT_SUB).layoutWeight(1)
        Button(this.fullscreen ? '退出全屏' : '全屏').onClick(() => { this.setFullscreen(!this.fullscreen); })
      }.width('100%')
      if (this.active() && this.vm.durationMs > 0) {
        Slider({ value: this.progress(), min: 0, max: this.vm.durationMs })
          .enabled(!this.vm.seeking && (this.vm.state === 'playing' || this.vm.state === 'paused' || this.vm.state === 'completed'))
          .onChange((value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) { this.previewMs = value; this.dragging = true; }
            else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) { this.dragging = false; this.vm.seek(value); }
          })
      }
      if (this.feedback().length > 0) { Text(this.feedback()).fontColor(immersive ? Color.White : AppTheme.TEXT_SUB).fontSize(12) }
      if (this.active() && this.vm.networkNotice.length > 0) { Text(this.vm.networkNotice).fontColor(immersive ? Color.White : AppTheme.TEXT_SUB).fontSize(12) }
      if (this.active() && this.vm.interruptionNotice.length > 0) { Text(this.vm.interruptionNotice).fontColor(immersive ? Color.White : AppTheme.TEXT_SUB).fontSize(12) }
      if (this.windowNotice.length > 0) { Text(this.windowNotice).fontColor(immersive ? Color.White : AppTheme.TEXT_SUB).fontSize(12) }
    }.width('100%').padding(12).backgroundColor(immersive ? '#B3000000' : AppTheme.CARD)
  }
  @Builder
  Fullscreen() {
    Stack({ alignContent: Alignment.Bottom }) {
      XComponent({ id: 'tieba-video-full', type: XComponentType.SURFACE, controller: this.fullController })
        .width('100%').height('100%').onLoad(() => {
          if (this.mounted && this.fullscreen) { this.vm.setSurface(this.fullController.getXComponentSurfaceId()); }
        })
      if ((!this.active() || !this.vm.firstFrame) && this.video.cover.length > 0 && !lowFlowStore.enabled) {
        Image(this.video.cover).width('100%').height('100%').objectFit(ImageFit.Contain).hitTestBehavior(HitTestMode.None)
      }
      this.Controls(true)
    }.width('100%').height('100%').backgroundColor(Color.Black)
  }
  @Builder
  VideoStage() {
    Stack() {
      XComponent({ id: 'tieba-video-stage', type: XComponentType.SURFACE, controller: this.inlineController })
        .width(this.stageSurfaceWidth()).height(this.stageSurfaceHeight()).align(Alignment.Center)
        .onLoad(() => { this.surfaceReady(); })
        .onClick(() => { this.useInline(); void this.vm.toggle(this.video); })
      if ((!this.active() || !this.vm.firstFrame) && this.video.cover.length > 0 && !lowFlowStore.enabled) {
        Image(this.video.cover).width('100%').height('100%').objectFit(ImageFit.Contain).hitTestBehavior(HitTestMode.None)
      }
      if (!this.active() || this.vm.state === 'paused' || this.vm.state === 'completed' || this.vm.state === 'error') {
        SymbolGlyph($r('sys.symbol.play_fill')).fontSize(58).fontColor(['#CCFFFFFF'])
          .align(Alignment.Center).hitTestBehavior(HitTestMode.None)
      }
      Column() {
        Blank().layoutWeight(1).hitTestBehavior(HitTestMode.None)
        Column({ space: 4 }) {
        if (this.feedback().length > 0) { Text(this.feedback()).fontSize(12).fontColor(Color.White).padding(6) }
        if (this.active() && this.vm.interruptionNotice.length > 0) { Text(this.vm.interruptionNotice).fontSize(12).fontColor(Color.White) }
        if (this.windowNotice.length > 0) { Text(this.windowNotice).fontSize(12).fontColor(Color.White) }
        Slider({ value: this.active() ? this.progress() : 0, min: 0, max: Math.max(1, this.vm.durationMs) })
          .enabled(this.active() && !this.vm.seeking && this.vm.durationMs > 0 && ['playing', 'paused', 'completed'].indexOf(this.vm.state) >= 0)
          .blockColor(Color.White).selectedColor(Color.White).trackColor('#66FFFFFF').height(28)
          .blockSize({ width: 7, height: 7 }).trackThickness(2)
          .onChange((value: number, mode: SliderChangeMode): void => {
            if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) { this.previewMs = value; this.dragging = true; }
            else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) { this.dragging = false; this.vm.seek(value); }
          })
        }.width('100%')
      }.width('100%').height('100%').padding({ bottom: this.controlBottomGap }).hitTestBehavior(HitTestMode.Transparent)
    }.width('100%').height('100%').backgroundColor(Color.Black)
      .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
        this.stageWidth = Number(size.width); this.stageHeight = Number(size.height);
      })
  }
  build() {
    if (this.stage) {
      this.VideoStage()
    } else {
    Column() {
      Stack() {
        XComponent({ id: 'tieba-video-inline', type: XComponentType.SURFACE, controller: this.inlineController })
          .width('100%').height(this.inlineHeight()).onLoad(() => { if (!this.fullscreen) { this.useInline(); } })
        if ((!this.active() || !this.vm.firstFrame) && this.video.cover.length > 0 && !lowFlowStore.enabled) {
          Image(this.video.cover).width('100%').height(this.inlineHeight()).objectFit(ImageFit.Contain).hitTestBehavior(HitTestMode.None)
        }
      }.width('100%').height(this.inlineHeight()).backgroundColor(Color.Black)
        .onSizeChange((_old: SizeOptions, size: SizeOptions): void => { this.inlineWidth = Number(size.width); })
      this.Controls()
    }.width('100%').borderRadius(12).clip(true)
      .bindContentCover(this.fullscreen, this.Fullscreen(), { enableSafeArea: false, backgroundColor: Color.Black,
        onWillDismiss: (action: DismissContentCoverAction): void => { action.dismiss(); },
        onDisappear: (): void => { this.setFullscreen(false); this.useInline(); } })
    }
  }
}
