
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const STORE: string = 'tieba_super_resolution_prefs';
const ENABLED_KEY: string = 'super_resolution_enabled';

@ObservedV2
export class SuperResolutionStore {

  @Trace enabled: boolean = true;
  private loaded: boolean = false;

  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);

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

      hilog.warn(0x0, 'TiebaSrPrefs', 'super resolution preference save failed: %{public}s', String(e));
    }
  }
}

export const superResolutionStore: SuperResolutionStore = new SuperResolutionStore();
