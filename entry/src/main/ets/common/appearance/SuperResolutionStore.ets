/** 全屏看图的超分入口偏好，仅作用于当前图片；结果缓存与任务生命周期由查看器管理。 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const STORE: string = 'tieba_super_resolution_prefs';
const ENABLED_KEY: string = 'super_resolution_enabled';

@ObservedV2
export class SuperResolutionStore {
  /** 打开后：全屏查看器显示超分按钮（默认开，与既有观感一致） */
  @Trace enabled: boolean = true;
  private loaded: boolean = false;

  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      // 读失败/键缺失都在 catch 或默认值里回落"开"，不会把读不到说成"关"
      this.enabled = (await store.get(ENABLED_KEY, true)) === true;
    } catch (e) {
      hilog.warn(0x0, 'TiebaSrPrefs', 'super resolution preference load failed: %{public}s', String(e));
    }
  }

  async setEnabled(enabled: boolean, context: common.UIAbilityContext): Promise<void> {
    this.enabled = enabled;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      await store.put(ENABLED_KEY, enabled);
      await store.flush();
    } catch (e) {
      // 本次会话内仍然生效，只是下次启动可能回到旧值
      hilog.warn(0x0, 'TiebaSrPrefs', 'super resolution preference save failed: %{public}s', String(e));
    }
  }
}

export const superResolutionStore: SuperResolutionStore = new SuperResolutionStore();
