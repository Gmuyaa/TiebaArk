/** 全屏看图右侧长图定位条的显示偏好（本机设置，默认开启）。 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferenceGate } from './PreferenceGate';

const STORE: string = 'tieba_long_image_minimap_prefs';
const ENABLED_KEY: string = 'long_image_minimap_enabled';

@ObservedV2
export class LongImageMinimapStore {
  @Trace enabled: boolean = true;
  @Trace saveError: string = '';
  private gate: PreferenceGate = new PreferenceGate();

  async load(context: common.UIAbilityContext): Promise<void> {
    await this.gate.loadOnce(async (revision: number): Promise<void> => {
      try {
        const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
        const enabled: boolean = (await store.get(ENABLED_KEY, true)) === true;
        if (revision === this.gate.revision()) { this.enabled = enabled; }
      } catch (e) {
        hilog.warn(0x0, 'TiebaMinimapPrefs', 'long image minimap preference load failed: %{public}s', String(e));
      } finally {
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
        this.saveError = '长图定位条设置本次已生效，保存失败，重启后可能恢复旧值';
      }
      hilog.warn(0x0, 'TiebaMinimapPrefs', 'long image minimap preference save failed: %{public}s', String(e));
    }
  }
}

export const longImageMinimapStore: LongImageMinimapStore = new LongImageMinimapStore();
