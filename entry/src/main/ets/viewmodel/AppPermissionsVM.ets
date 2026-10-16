import { bundleManager, common } from '@kit.AbilityKit';
import { AppPermission, appPermissionItems } from '../model/AppPermissions';

@ObservedV2
export class AppPermissionsVM {
  @Trace items: AppPermission[] = [];
  @Trace loading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace error: string = '';
  @Trace openingSettings: boolean = false;
  @Trace settingsError: string = '';
  private epoch: number = 0;
  private disposed: boolean = false;

  /** 官方 application_info_entry 契约；只打开当前安装包，不申请或假定授权。 */
  async openSystemSettings(context: common.UIAbilityContext): Promise<void> {
    if (this.disposed || this.openingSettings) { return; }
    this.openingSettings = true; this.settingsError = '';
    try {
      const info = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      if (this.disposed) { return; }
      if (typeof info.name !== 'string' || info.name.trim().length === 0) {
        this.settingsError = '未能读取本应用信息，请从系统设置中找到本应用'; return;
      }
      await context.startAbility({
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        uri: 'application_info_entry', parameters: { pushParams: info.name }
      });
    } catch (err) {
      if (!this.disposed) { this.settingsError = '无法打开系统设置，请从系统设置中找到本应用'; }
    } finally { this.openingSettings = false; }
  }

  async load(): Promise<void> {
    if (this.disposed || this.loading) { return; }
    const mine: number = ++this.epoch;
    this.loaded = false; this.error = ''; this.loading = true;
    try {
      const info = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_REQUESTED_PERMISSION);
      if (this.disposed || mine !== this.epoch) { return; }
      // 仅使用 SDK 声明的一一对应数组，缺状态不猜为授权。
      const names: string[] = info.reqPermissionDetails.map((detail) => detail.name);
      this.items = appPermissionItems(names, info.permissionGrantStates); this.loaded = true; this.error = '';
    } catch (err) {
      if (!this.disposed && mine === this.epoch) { this.error = '系统权限读取失败，请重试'; }
    } finally {
      if (mine === this.epoch) { this.loading = false; }
    }
  }

  dispose(): void {
    this.disposed = true; this.epoch++; this.loading = false; this.loaded = false; this.items = [];
    this.openingSettings = false; this.settingsError = '';
  }
}
