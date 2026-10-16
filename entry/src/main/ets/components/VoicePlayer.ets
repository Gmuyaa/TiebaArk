import { common } from '@kit.AbilityKit';
import { VoiceClip } from '../model/VoiceClip';
import { VoicePlaybackVM, voicePlayback } from '../viewmodel/VoicePlaybackVM';
import { AppTheme } from '../theme/Theme';

@ComponentV2
export struct VoicePlayer {
  @Param voice: VoiceClip = new VoiceClip();
  @Local vm: VoicePlaybackVM = voicePlayback;
  aboutToDisappear(): void { void this.vm.stopFor(this.voice.id); }
  private active(): boolean { return this.vm.currentId === this.voice.id; }
  private action(): string {
    if (!this.active()) { return '播放'; }
    if (this.vm.state === 'loading') { return '取消'; }
    if (this.vm.state === 'playing') { return '暂停'; }
    if (this.vm.state === 'error') { return '重试'; }
    return '播放';
  }
  private time(): string {
    const duration: number = this.active() ? this.vm.durationMs : this.voice.durationMs;
    const position: number = this.active() ? this.vm.positionMs : 0;
    const total: string = duration > 0 ? `${duration / 1000}秒` : '时长未确认';
    return this.active() && position > 0 ? `${(position / 1000).toFixed(1)}秒 / ${total}` : total;
  }
  build() {
    Column({ space: 5 }) {
      Row({ space: 12 }) {
        Text('语音').fontSize(14).fontColor(AppTheme.TEXT_MAIN)
        Text(this.time()).fontSize(12).fontColor(AppTheme.TEXT_SUB).layoutWeight(1)
        Button(this.action()).fontSize(13).enabled(!this.vm.commanding)
          .onClick(() => { void this.vm.toggle(this.getUIContext().getHostContext() as common.UIAbilityContext, this.voice); })
      }.width('100%')
      if (this.active() && this.vm.state === 'loading') {
        Text('正在加载语音…').fontSize(12).fontColor(AppTheme.TEXT_SUB)
      }
      if (this.active() && this.vm.error.length > 0) {
        Text(this.vm.error).fontSize(12).fontColor(AppTheme.ACCENT_DARK)
      }
    }.width('100%').padding(12).borderRadius(AppTheme.CARD_RADIUS).backgroundColor(AppTheme.CARD)
    .alignItems(HorizontalAlign.Start)
  }
}
