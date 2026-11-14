
import { common } from '@kit.AbilityKit';
import { TailItem, tailColor, tailSelectionLabel } from '../model/Tails';
import { TailsVM } from '../viewmodel/TailsVM';
import { SettingsInfoRow } from './SettingsComponents';
import { PreferencePaneScaffold } from './PreferencePaneScaffold';

@ComponentV2
export struct TailsPane {
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

  build() {
    PreferencePaneScaffold({
      note: '仅查看，回复暂不附加小尾巴。',
      message: this.vm.error,
      onRetry: (): void => { void this.vm.load(this.context()); }
    }) {
      this.TailRows()
    }
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
