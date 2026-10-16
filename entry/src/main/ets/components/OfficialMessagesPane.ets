
import { common } from '@kit.AbilityKit';
import { OfficialMessageSetting, officialMessageStateLabel } from '../model/OfficialMessages';
import { OfficialMessagesVM } from '../viewmodel/OfficialMessagesVM';
import { SettingsCard, SettingsInfoRow, SettingsNote, SettingsStatusKind, SettingsStatusLine } from './SettingsComponents';

@ComponentV2
export struct OfficialMessagesPane {
  /** 页面顶栏刷新序号：自增即触发重读（初值 0 不触发） */
  @Param refreshSeq: number = 0;
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

  @Monitor('refreshSeq')
  onRefreshRequested(): void {
    if (this.refreshSeq > 0) {
      this.vm.load(this.context()).then((): void => {
      });
    }
  }

  build() {
    Column() {
      SettingsNote({ text: '仅查看：修改尚未开放。' })
      SettingsCard({
        content: (): void => { this.OfficialRows() }
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
      SettingsNote({ text: '此状态不代表本应用已接通系统通知。' })
    }
    .width('100%')
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
