
import { common } from '@kit.AbilityKit';
import { messageMaskLabel, messagePushLabel } from '../model/MessageSettings';
import { MessageSettingsVM } from '../viewmodel/MessageSettingsVM';
import {
  SettingsCard, SettingsEntryRow, SettingsInfoRow, SettingsStatusKind, SettingsStatusLine
} from './SettingsComponents';

@ComponentV2
export struct MessageSettingsPane {
  @Event onOpenOfficial: () => void = (): void => {};
  @Local vm: MessageSettingsVM = new MessageSettingsVM();

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
    Column() {
      SettingsCard({
        content: (): void => { this.MessageRows() }
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
    }
    .width('100%')
  }

  @Builder
  MessageRows() {
    SettingsInfoRow({
      label: '私信接收范围',
      value: this.vm.loading ? '正在读取…' : messageMaskLabel(this.vm.data.maskType)
    })
    SettingsInfoRow({
      label: '好友私信提醒',
      value: this.vm.loading ? '正在读取…' : messagePushLabel(this.vm.data.pushType)
    })
    SettingsEntryRow({
      label: '官方账号消息提醒',
      showDivider: false,
      onTap: this.onOpenOfficial
    })
  }
}
