
import { common } from '@kit.AbilityKit';
import { OfficialMessageSetting, officialMessageStateLabel } from '../model/OfficialMessages';
import { OfficialMessagesVM } from '../viewmodel/OfficialMessagesVM';
import { SettingsInfoRow } from './SettingsComponents';
import { PreferencePaneScaffold } from './PreferencePaneScaffold';

@ComponentV2
export struct OfficialMessagesPane {
  @Local vm: OfficialMessagesVM = new OfficialMessagesVM();

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
      note: '仅查看，暂不支持系统通知。',
      message: this.vm.error,
      onRetry: (): void => { void this.vm.load(this.context()); }
    }) {
      this.OfficialRows()
    }
  }

  @Builder
  OfficialRows() {
    if (this.vm.loading && this.vm.items.length === 0) {
      // 首次加载不留白闪空态
      SettingsInfoRow({ label: '正在读取…', showDivider: false })
    } else if (this.vm.loaded && this.vm.items.length === 0) {
      SettingsInfoRow({ label: '暂无官方账号消息设置', showDivider: false })
    } else {
      ForEach(this.vm.items, (item: OfficialMessageSetting, index: number) => {
        SettingsInfoRow({
          label: item.name.trim().length > 0 ? item.name : '官方账号',
          value: officialMessageStateLabel(item.state),
          showDivider: index < this.vm.items.length - 1
        })
      }, (item: OfficialMessageSetting) => item.uid)
    }
  }
}
