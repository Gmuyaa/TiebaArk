
import { common } from '@kit.AbilityKit';
import { imageWatermarkLabel } from '../model/ImageWatermark';
import { ImageWatermarkVM } from '../viewmodel/ImageWatermarkVM';
import { SettingsInfoRow } from './SettingsComponents';
import { PreferencePaneScaffold } from './PreferencePaneScaffold';

@ComponentV2
export struct ImageWatermarkPane {
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

  build() {
    PreferencePaneScaffold({
      note: '仅查看，暂不支持修改。',
      noteAfter: true,

      message: this.vm.error,
      onRetry: (): void => { void this.vm.load(this.context()); }
    }) {
      this.WatermarkRows()
    }
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
