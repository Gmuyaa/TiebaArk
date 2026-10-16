
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const STORE: string = 'tieba_low_flow_prefs';
const ENABLED_KEY: string = 'low_flow_enabled';

@ObservedV2
export class LowFlowStore {

  @Trace enabled: boolean = false;
  private loaded: boolean = false;

  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      this.enabled = (await store.get(ENABLED_KEY, false)) === true;
    } catch (e) {
      hilog.warn(0x0, 'TiebaLowFlow', 'low flow preference load failed: %{public}s', String(e));
    }
  }

  async setEnabled(enabled: boolean, context: common.UIAbilityContext): Promise<void> {
    this.enabled = enabled;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      await store.put(ENABLED_KEY, enabled);
      await store.flush();
    } catch (e) {
      hilog.warn(0x0, 'TiebaLowFlow', 'low flow preference save failed: %{public}s', String(e));
    }
  }
}

export const lowFlowStore: LowFlowStore = new LowFlowStore();
