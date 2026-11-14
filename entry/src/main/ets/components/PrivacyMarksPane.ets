
import { common } from '@kit.AbilityKit';
import { privacyMarkLabel } from '../model/PrivacyMarks';
import { PrivacyMarksVM } from '../viewmodel/PrivacyMarksVM';
import { SettingsInfoRow } from './SettingsComponents';
import { PreferencePaneScaffold } from './PreferencePaneScaffold';

@ComponentV2
export struct PrivacyMarksPane {
  @Local vm: PrivacyMarksVM = new PrivacyMarksVM();

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
      note: '仅查看标记显示状态，不代表吧务权限。',
      noteAfter: true,

      message: this.vm.error,
      onRetry: (): void => { void this.vm.load(this.context()); }
    }) {
      this.MarkRows()
    }
  }

  @Builder
  MarkRows() {
    SettingsInfoRow({
      label: '吧务标记（吧内）',
      value: this.vm.loading && !this.vm.loaded ? '正在读取…' : privacyMarkLabel(this.vm.data.inside)
    })
    SettingsInfoRow({
      label: '吧务标记（吧外）',
      value: this.vm.loading && !this.vm.loaded ? '正在读取…' : privacyMarkLabel(this.vm.data.outside),
      showDivider: false
    })
  }
}
