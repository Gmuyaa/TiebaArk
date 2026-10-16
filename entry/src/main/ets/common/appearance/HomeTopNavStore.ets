

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  DEFAULT_HOME_TOP_NAV_STYLE, HomeTopNavStyle, homeTopNavStyleLabel, normalizeHomeTopNavStyle
} from './HomeTopNavStyle';

const DOMAIN: number = 0x0000;
const TAG: string = 'TiebaTopNav';

const STORE: string = 'tieba_topnav_prefs';
const KEY_STYLE: string = 'style';

@ObservedV2
export class HomeTopNavStore {

  @Trace style: HomeTopNavStyle = DEFAULT_HOME_TOP_NAV_STYLE;

  private loaded: boolean = false;

  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      if (await store.has(KEY_STYLE)) {
        const raw: number =
          (await store.get(KEY_STYLE, DEFAULT_HOME_TOP_NAV_STYLE as number)) as number;
        this.style = normalizeHomeTopNavStyle(raw);
        hilog.info(DOMAIN, TAG, 'home top nav style loaded: %{public}s', this.describe());
        return;
      }
      this.style = DEFAULT_HOME_TOP_NAV_STYLE;
      hilog.info(DOMAIN, TAG, 'home top nav style absent, keep default: %{public}s',
        this.describe());
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'home top nav style load failed, keep default: %{public}s',
        String(e));
    }
  }

  async setStyle(style: HomeTopNavStyle, context: common.UIAbilityContext): Promise<void> {
    const next: HomeTopNavStyle = normalizeHomeTopNavStyle(style as number);
    if (next === this.style) {
      return;
    }
    this.style = next;
    hilog.info(DOMAIN, TAG, 'home top nav style -> %{public}s', this.describe());
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      await store.put(KEY_STYLE, next as number);
      await store.flush();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'home top nav style save failed: %{public}s', String(e));
    }
  }

  describe(): string {
    return `${this.style}(${homeTopNavStyleLabel(this.style)})`;
  }
}

export const homeTopNavStore: HomeTopNavStore = new HomeTopNavStore();
