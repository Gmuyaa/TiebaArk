
import { common } from '@kit.AbilityKit';
import { TailItem, tailColor, tailSelectionLabel } from '../model/Tails';
import { TailsVM } from '../viewmodel/TailsVM';
import { SettingsCard, SettingsInfoRow, SettingsNote, SettingsStatusKind, SettingsStatusLine } from './SettingsComponents';

@ComponentV2
export struct TailsPane {
  /** 页面顶栏刷新序号：自增即触发重读（初值 0 不触发） */
  @Param refreshSeq: number = 0;
  @Local vm: TailsVM = new TailsVM();

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
      SettingsNote({ text: '仅查看：新增、编辑、删除与启用尚未开放。' })
      SettingsCard({
        content: (): void => { this.TailRows() }
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
      SettingsNote({ text: '本应用回复暂不自动附加小尾巴。' })
    }
    .width('100%')
  }

  @Builder
  TailRows() {
    if (this.vm.loading && this.vm.data.items.length === 0) {
      SettingsInfoRow({ label: '正在读取…', showDivider: false })
    } else if (this.vm.loaded && this.vm.data.items.length === 0) {
      SettingsInfoRow({ label: '账号暂无普通小尾巴', showDivider: false })
    } else {
      ForEach(this.vm.data.items, (item: TailItem, index: number) => {
        SettingsInfoRow({
          label: item.content.length > 0 ? item.content : '内容未返回',
          sub: tailSelectionLabel(item.selected),
          labelColor: tailColor(item.fontColor),
          showDivider: index < this.vm.data.items.length - 1
        })
      }, (item: TailItem) => String(item.id))
    }
  }
}
