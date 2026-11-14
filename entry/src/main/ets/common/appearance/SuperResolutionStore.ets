/** 全屏看图的超分入口偏好，仅作用于当前图片；结果缓存与任务生命周期由查看器管理。 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferenceGate } from './PreferenceGate';

const STORE: string = 'tieba_super_resolution_prefs';
const ENABLED_KEY: string = 'super_resolution_enabled';

@ObservedV2
export class SuperResolutionStore {
  /** 打开后：全屏查看器显示超分按钮（默认开，与既有观感一致） */
  @Trace enabled: boolean = true;
  @Trace saveError: string = '';
  private gate: PreferenceGate = new PreferenceGate();

  async load(context: common.UIAbilityContext): Promise<void> {
    await this.gate.loadOnce(async (revision: number): Promise<void> => {
      try {
        const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
        // 读失败/键缺失都在 catch 或默认值里回落"开"，不会把读不到说成"关"
        const enabled: boolean = (await store.get(ENABLED_KEY, true)) === true;
        if (revision === this.gate.revision()) { this.enabled = enabled; }
      } catch (e) {
        hilog.warn(0x0, 'TiebaSrPrefs', 'super resolution preference load failed: %{public}s', String(e));
      } finally {
        // 读失败也不重试：与原实现一致（原实现在 await 之前就置 loaded）。
        this.gate.markLoaded();
      }
    });
  }

  async setEnabled(enabled: boolean, context: common.UIAbilityContext): Promise<void> {
    this.enabled = enabled;
    await this.retrySave(context);
  }

  async retrySave(context: common.UIAbilityContext): Promise<void> {
    const enabled: boolean = this.enabled;
    const revision: number = this.gate.bump();
    try {
      await this.gate.enqueue(async (): Promise<void> => {
        const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
        await store.put(ENABLED_KEY, enabled);
        await store.flush();
      });
      if (revision === this.gate.revision()) { this.saveError = ''; }
    } catch (e) {
      if (revision === this.gate.revision()) {
        this.saveError = '超分按钮设置本次已生效，保存失败，重启后可能恢复旧值';
      }
      hilog.warn(0x0, 'TiebaSrPrefs', 'super resolution preference save failed: %{public}s', String(e));
    }
  }
}

export const superResolutionStore: SuperResolutionStore = new SuperResolutionStore();
