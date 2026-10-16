
import { common } from '@kit.AbilityKit';
import { privacyMarkLabel } from '../model/PrivacyMarks';
import { PrivacyMarksVM } from '../viewmodel/PrivacyMarksVM';
import { SettingsCard, SettingsInfoRow, SettingsNote, SettingsStatusKind, SettingsStatusLine } from './SettingsComponents';

@ComponentV2
export struct PrivacyMarksPane {
  /** 页面顶栏刷新序号：自增即触发重读（初值 0 不触发） */
  @Param refreshSeq: number = 0;
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
        content: (): void => { this.MarkRows() }
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
      SettingsNote({ text: '这里只表示标记是否显示，不代表账号拥有吧务权限。修改尚未开放。' })
    }
    .width('100%')
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
