
import { SettingsLayout } from '../common/appearance/SettingsLayout';
import { common } from '@kit.AbilityKit';
import { AppPermission, permissionStateLabel } from '../model/AppPermissions';
import { AppPermissionsVM } from '../viewmodel/AppPermissionsVM';
import {
  SettingsActionRow, SettingsCard, SettingsInfoRow, SettingsNote, SettingsStatusKind, SettingsStatusLine
} from './SettingsComponents';

@ComponentV2
export struct AppPermissionsPane {
  /** 页面顶栏刷新序号：自增即触发重读（初值 0 不触发） */
  @Param refreshSeq: number = 0;
  @Local vm: AppPermissionsVM = new AppPermissionsVM();

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    void this.vm.load();
  }

  aboutToDisappear(): void {
    this.vm.dispose();
  }

  @Monitor('refreshSeq')
  onRefreshRequested(): void {
    if (this.refreshSeq > 0) {
      this.vm.load().then((): void => {
      });
    }
  }

  build() {
    Column() {
      SettingsNote({ text: '仅查看：权限可在系统设置中管理。' })
      SettingsCard({
        content: (): void => { this.PermissionRows() }
      })
      if (this.vm.error.length > 0) {
        SettingsStatusLine({
          kind: SettingsStatusKind.ERROR,
          message: this.vm.error,
          retryLabel: '重试',
          onRetry: (): void => {
            this.vm.load();
          }
        })
      }
      if (this.vm.settingsError.length > 0) {
        SettingsStatusLine({
          kind: SettingsStatusKind.ERROR,
          message: this.vm.settingsError,
          retryLabel: '重试',
          onRetry: (): void => {
            void this.vm.openSystemSettings(this.context());
          }
        })
      }
      SettingsCard({
        marginTop: SettingsLayout.GROUP_GAP,
        content: (): void => { this.OpenSettingsRow() }
      })
      SettingsNote({ text: '打开系统设置只跳转页面，不代表权限已改变。' })
    }
    .width('100%')
  }

  @Builder
  PermissionRows() {
    if (this.vm.loading && this.vm.items.length === 0) {
      SettingsInfoRow({ label: '正在读取…', showDivider: false })
    } else {
      ForEach(this.vm.items, (item: AppPermission, index: number) => {
        SettingsInfoRow({
          label: item.label,
          value: permissionStateLabel(item),
          showDivider: index < this.vm.items.length - 1
        })
      }, (item: AppPermission) => item.name)
    }
  }

  @Builder
  OpenSettingsRow() {
    SettingsActionRow({
      label: '打开系统设置',
      busyLabel: '正在打开…',
      busy: this.vm.openingSettings,
      onTap: (): void => {
        void this.vm.openSystemSettings(this.context());
      }
    })
  }
}
