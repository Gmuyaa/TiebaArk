
import { common } from '@kit.AbilityKit';
import { imageWatermarkLabel } from '../model/ImageWatermark';
import { ImageWatermarkVM } from '../viewmodel/ImageWatermarkVM';
import { SettingsCard, SettingsInfoRow, SettingsNote, SettingsStatusKind, SettingsStatusLine } from './SettingsComponents';

@ComponentV2
export struct ImageWatermarkPane {

  @Param refreshSeq: number = 0;
  @Local vm: ImageWatermarkVM = new ImageWatermarkVM();

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    void this.vm.load(this.context());
  }

  aboutToDisappear(): void {
    this.vm.dispose();
  }

  @Monitor('refreshSeq')
  onRefreshRequested(): void {
    if (this.refreshSeq > 0) {
      this.vm.load(this.context()).then((): void => {
      });
    }
  }

  build() {
    Column() {
      SettingsCard({
        content: (): void => { this.WatermarkRows() }
      })
      if (this.vm.error.length > 0) {
        SettingsStatusLine({
          kind: SettingsStatusKind.ERROR,
          message: this.vm.error,
          retryLabel: '重试',
          onRetry: (): void => {
            void this.vm.load(this.context());
          }
        })
      }
      SettingsNote({ text: '修改尚未开放；图片上传与水印效果尚未验证。' })
    }
    .width('100%')
  }

  @Builder
  WatermarkRows() {
    SettingsInfoRow({
      label: '账号图片水印设置',
      value: this.vm.loading && !this.vm.loaded ? '正在读取…' : imageWatermarkLabel(this.vm.type),
      showDivider: false
    })
  }
}
