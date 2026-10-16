
import { common } from '@kit.AbilityKit';
import { messageMaskLabel, messagePushLabel } from '../model/MessageSettings';
import { MessageSettingsVM } from '../viewmodel/MessageSettingsVM';
import {
  SettingsCard, SettingsEntryRow, SettingsInfoRow, SettingsNote, SettingsStatusKind, SettingsStatusLine
} from './SettingsComponents';

@ComponentV2
export struct MessageSettingsPane {
  /** 页面顶栏刷新序号：自增即触发重读（初值 0 不触发） */
  @Param refreshSeq: number = 0;
  /** 进入「官方账号消息提醒」独立页（换页由页面负责） */
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
        content: (): void => { this.MessageRows() }
      })
      SettingsNote({ text: '仅查看：修改尚未开放。' })
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
      SettingsNote({
        text: '这里读取的是贴吧账号设置，不是本机系统推送：此处的提醒状态不代表本应用已接通系统通知。'
      })
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
      summary: '仅查看',
      showDivider: false,
      onTap: this.onOpenOfficial
    })
  }
}
