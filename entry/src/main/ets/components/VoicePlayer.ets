import { common } from '@kit.AbilityKit';
import { VoiceClip } from '../model/VoiceClip';
import {
  VoicePlayerStyle,
  formatVoiceBubbleTime,
  formatVoiceSliderTime,
  formatVoiceWaveformTime,
  voiceBarWidthVp,
  voiceBubbleWidthVp,
  voiceProgressRatio,
  voiceSeekPositionFromX,
  voiceWaveformBarCount,
  voiceWaveformWeights
} from '../model/VoicePlayerStyle';
import { VoicePlayerStyleStore, voicePlayerStyleStore } from '../common/appearance/VoicePlayerStyleStore';
import { sliderMaterial } from '../common/appearance/MotionPolicy';
import { VoicePlaybackVM, voicePlayback } from '../viewmodel/VoicePlaybackVM';
import { AppTheme } from '../theme/Theme';

@ComponentV2
export struct VoicePlayer {
  @Param voice: VoiceClip = new VoiceClip();
  @Local vm: VoicePlaybackVM = voicePlayback;
  @Local styleStore: VoicePlayerStyleStore = voicePlayerStyleStore;
  @Local dragging: boolean = false;
  @Local previewMs: number = 0;
  @Local trackWidth: number = 0;
  @Local wavePhase: number = 3;
  private dragStartX: number = 0;
  private waveTimer: number = -1;

  aboutToAppear(): void { this.syncWaveAnimation(); }

  // 播放生命周期由帖子页管理；回复离开懒加载视口不应中断语音。
  aboutToDisappear(): void {
    this.dragging = false;
    this.stopWaveAnimation();
  }

  @Monitor('vm.state', 'vm.currentId', 'styleStore.style')
  private playbackChanged(): void {
    if (!this.active() || this.vm.state === 'idle' || this.vm.state === 'error' || this.vm.state === 'loading') {
      this.dragging = false;
    }
    this.syncWaveAnimation();
  }

  @Monitor('voice')
  private voiceChanged(): void {
    this.dragging = false;
    this.previewMs = 0;
    this.syncWaveAnimation();
  }

  private active(): boolean { return this.vm.currentId === this.voice.id; }

  private isBubblePlaying(): boolean {
    return this.styleStore.style === VoicePlayerStyle.BUBBLE && this.active() && this.vm.state === 'playing';
  }

  private syncWaveAnimation(): void {
    if (this.isBubblePlaying()) {
      if (this.waveTimer < 0) {
        this.wavePhase = 1;
        this.waveTimer = setInterval((): void => {
          this.wavePhase = (this.wavePhase % 3) + 1;
        }, 320);
      }
      return;
    }
    this.stopWaveAnimation();
    this.wavePhase = 3;
  }

  private stopWaveAnimation(): void {
    if (this.waveTimer >= 0) {
      clearInterval(this.waveTimer);
      this.waveTimer = -1;
    }
  }

  private durationMs(): number {
    return this.vm.durationFor(this.voice);
  }

  private progressMs(): number {
    if (!this.active()) { return 0; }
    if (this.dragging) { return this.previewMs; }
    if (this.vm.seeking) { return this.vm.seekTargetMs; }
    const duration: number = this.durationMs();
    return duration > 0 ? Math.max(0, Math.min(duration, this.vm.positionMs)) : Math.max(0, this.vm.positionMs);
  }

  private progressRatio(): number {
    return voiceProgressRatio(this.progressMs(), this.durationMs());
  }

  private showPosition(): boolean {
    if (!this.active()) { return false; }
    return this.dragging || this.vm.seeking ||
      this.vm.state === 'playing' || this.vm.state === 'paused';
  }

  private canSeek(): boolean {
    return this.active() && !this.vm.commanding && !this.vm.seeking && this.vm.durationMs > 0 &&
      (this.vm.state === 'playing' || this.vm.state === 'paused' || this.vm.state === 'completed');
  }

  private actionText(): string {
    if (!this.active()) { return '播放语音'; }
    if (this.vm.state === 'loading') { return '取消加载'; }
    if (this.vm.state === 'playing') { return '暂停语音'; }
    if (this.vm.state === 'error') { return '重试播放语音'; }
    return '播放语音';
  }

  private togglePlay(): void {
    if (this.vm.commanding) { return; }
    void this.vm.toggle(this.getUIContext().getHostContext() as common.UIAbilityContext, this.voice);
  }

  private barPlayed(index: number, count: number): boolean {
    const ratio: number = this.progressRatio();
    if (ratio <= 0 || count <= 0) { return false; }
    if (ratio >= 1) { return true; }
    return (index + 0.5) / count <= ratio;
  }

  private handleTrackTap(event: GestureEvent, playWhenInactive: boolean): void {
    if (this.canSeek()) {
      const localX: number = event.fingerList.length > 0 ? event.fingerList[0].localX : 0;
      this.vm.seek(voiceSeekPositionFromX(localX, this.trackWidth, this.durationMs()));
      return;
    }
    if (playWhenInactive && (!this.active() || this.vm.state === 'idle' || this.vm.state === 'error')) {
      this.togglePlay();
    }
  }

  private handlePanStart(event: GestureEvent): void {
    if (!this.canSeek() || this.trackWidth <= 0) { return; }
    this.dragStartX = event.fingerList.length > 0 ? event.fingerList[0].localX : 0;
    this.previewMs = voiceSeekPositionFromX(this.dragStartX, this.trackWidth, this.durationMs());
    this.dragging = true;
  }

  private handlePanUpdate(event: GestureEvent): void {
    if (!this.dragging || this.trackWidth <= 0) { return; }
    this.previewMs = voiceSeekPositionFromX(this.dragStartX + event.offsetX, this.trackWidth, this.durationMs());
  }

  private handlePanEnd(): void {
    if (!this.dragging) { return; }
    const target: number = this.previewMs;
    this.dragging = false;
    this.vm.seek(target);
  }

  private innerWavePath(): string {
    // Path 命令坐标使用物理像素，按当前密度换算成 16vp 声波弧线。
    return `M ${vp2px(6.5)} ${vp2px(5.0)} A ${vp2px(4.2)} ${vp2px(4.2)} 0 0 1 ${vp2px(6.5)} ${vp2px(11.0)}`;
  }

  private outerWavePath(): string {
    return `M ${vp2px(9.6)} ${vp2px(2.6)} A ${vp2px(7.2)} ${vp2px(7.2)} 0 0 1 ${vp2px(9.6)} ${vp2px(13.4)}`;
  }

  @Builder
  PlayActionButton(size: number, iconSize: number) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.active() && this.vm.state === 'loading') {
        LoadingProgress().width(iconSize + 2).height(iconSize + 2).color(Color.White)
      } else if (this.active() && this.vm.state === 'playing') {
        SymbolGlyph($r('sys.symbol.pause')).fontSize(iconSize).fontColor([Color.White])
      } else if (this.active() && this.vm.state === 'error') {
        SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(iconSize).fontColor([Color.White])
      } else {
        SymbolGlyph($r('sys.symbol.play_fill')).fontSize(iconSize).fontColor([Color.White]).translate({ x: 1 })
      }
    }
    .width(size)
    .height(size)
    .borderRadius(size / 2)
    .backgroundColor(this.active() && this.vm.state === 'error' ? AppTheme.DANGER_TEXT : AppTheme.ACCENT)
    .accessibilityText(this.actionText())
    .onClick(() => { this.togglePlay(); })
  }

  @Builder
  BubbleWaveIcon() {
    if (this.active() && this.vm.state === 'loading') {
      LoadingProgress().width(15).height(15).color(AppTheme.TEXT_SUB)
    } else if (this.active() && this.vm.state === 'error') {
      SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(14).fontColor([AppTheme.DANGER_TEXT])
    } else {
      Stack({ alignContent: Alignment.TopStart }) {
        Circle({ width: 3, height: 3 })
          .fill(this.isBubblePlaying() ? AppTheme.ACCENT : AppTheme.TEXT_MAIN)
          .position({ x: 2, y: 6.5 })
        if (this.wavePhase >= 2) {
          Path()
            .commands(this.innerWavePath())
            .fill(Color.Transparent)
            .stroke(this.isBubblePlaying() ? AppTheme.ACCENT : AppTheme.TEXT_MAIN)
            .strokeWidth(1.6)
            .strokeLineCap(LineCapStyle.Round)
            .width(16)
            .height(16)
        }
        if (this.wavePhase >= 3) {
          Path()
            .commands(this.outerWavePath())
            .fill(Color.Transparent)
            .stroke(this.isBubblePlaying() ? AppTheme.ACCENT : AppTheme.TEXT_MAIN)
            .strokeWidth(1.6)
            .strokeLineCap(LineCapStyle.Round)
            .width(16)
            .height(16)
        }
      }
      .width(16)
      .height(16)
    }
  }

  @Builder
  SliderStyleBar() {
    Row({ space: 6 }) {
      this.PlayActionButton(24, 11)
      Slider({
        value: this.progressMs(),
        min: 0,
        max: Math.max(1, this.durationMs()),
        style: SliderStyle.OutSet
      })
        .systemMaterial(sliderMaterial(false))
        .selectedColor(AppTheme.ACCENT)
        .blockColor(AppTheme.ACCENT)
        .trackThickness(2.5)
        .blockSize({ width: 9, height: 9 })
        .height(22)
        .layoutWeight(1)
        .enabled(this.canSeek())
        .onChange((value: number, mode: SliderChangeMode): void => {
          if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
            this.previewMs = value;
            this.dragging = true;
          } else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            this.dragging = false;
            this.vm.seek(value);
          }
        })
      Text(formatVoiceSliderTime(this.progressMs(), this.durationMs()))
        .fontSize(12)
        .fontColor(AppTheme.TEXT_SUB)
        .fontFeature('"tnum" 1')
        .maxLines(1)
    }
    .width(voiceBarWidthVp(this.durationMs()))
    .constraintSize({ minWidth: 136, maxWidth: '62%' })
    .height(34)
    .padding({ left: 6, right: 9 })
    .borderRadius(12)
    .backgroundColor(AppTheme.SURFACE_MUTED)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  WaveformStyleBar() {
    Row({ space: 8 }) {
      this.PlayActionButton(24, 11)
      Row({ space: 2.5 }) {
        ForEach(
          voiceWaveformWeights(this.voice.id, voiceWaveformBarCount(this.durationMs())),
          (weight: number, index: number) => {
            Row()
              .width(2)
              .height(Math.max(3, Math.round(16 * weight)))
              .borderRadius(1)
              .backgroundColor(
                this.barPlayed(index, voiceWaveformBarCount(this.durationMs())) ? AppTheme.ACCENT : AppTheme.TEXT_MUTED
              )
              .opacity(this.barPlayed(index, voiceWaveformBarCount(this.durationMs())) ? 1 : 0.38)
          },
          (_weight: number, index: number) => `${this.voice.id}_w_${voiceWaveformBarCount(this.durationMs())}_${index}`
        )
      }
      .height(24)
      .alignItems(VerticalAlign.Center)
      .onAreaChange((_old: Area, now: Area): void => {
        const w: number = Number(now.width);
        if (Number.isFinite(w) && w > 0) { this.trackWidth = w; }
      })
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          PanGesture({ direction: PanDirection.Horizontal, distance: 4 })
            .onActionStart((event: GestureEvent): void => { this.handlePanStart(event); })
            .onActionUpdate((event: GestureEvent): void => { this.handlePanUpdate(event); })
            .onActionEnd((): void => { this.handlePanEnd(); })
            .onActionCancel((): void => { this.dragging = false; }),
          TapGesture()
            .onAction((event: GestureEvent): void => { this.handleTrackTap(event, true); })
        )
      )
      Text(formatVoiceWaveformTime(this.progressMs(), this.durationMs(), this.showPosition()))
        .fontSize(12)
        .fontColor(AppTheme.TEXT_SUB)
        .fontFeature('"tnum" 1')
        .maxLines(1)
    }
    .constraintSize({ maxWidth: '64%' })
    .height(36)
    .padding({ left: 8, right: 11 })
    .borderRadius(12)
    .backgroundColor(AppTheme.SURFACE_MUTED)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  BubbleStyleBar() {
    Row({ space: 6 }) {
      this.BubbleWaveIcon()
      Text(formatVoiceBubbleTime(this.durationMs()))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isBubblePlaying() ? AppTheme.ACCENT : AppTheme.TEXT_MAIN)
        .fontFeature('"tnum" 1')
        .maxLines(1)
    }
    .width(voiceBubbleWidthVp(this.durationMs()))
    .constraintSize({ minWidth: 74, maxWidth: '52%' })
    .height(34)
    .padding({ left: 11, right: 13 })
    .borderRadius(17)
    .backgroundColor(AppTheme.SURFACE_MUTED)
    .alignItems(VerticalAlign.Center)
    .accessibilityText(this.actionText())
    .onClick(() => { this.togglePlay(); })
  }

  @Builder
  FeedbackLines() {
    if (this.active() && this.vm.interruptionNotice.length > 0) {
      Text(this.vm.interruptionNotice).fontSize(12).fontColor(AppTheme.TEXT_SUB)
    }
    if (this.active() && this.vm.error.length > 0) {
      Text(this.vm.error).fontSize(12).fontColor(AppTheme.DANGER_TEXT)
    }
  }

  build() {
    Column({ space: 5 }) {
      if (this.styleStore.style === VoicePlayerStyle.WAVEFORM) {
        this.WaveformStyleBar()
      } else if (this.styleStore.style === VoicePlayerStyle.BUBBLE) {
        this.BubbleStyleBar()
      } else {
        this.SliderStyleBar()
      }
      this.FeedbackLines()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
