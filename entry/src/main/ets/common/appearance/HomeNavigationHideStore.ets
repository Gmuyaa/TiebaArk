
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const STORE: string = 'tieba_home_navigation_prefs';
const STATUS_KEY: string = 'hide_status_bar';
const TOP_KEY: string = 'hide_top_navigation';
const BOTTOM_KEY: string = 'hide_bottom_navigation';

export enum HomeNavigationPart {
  STATUS = 0,
  TOP = 1,
  BOTTOM = 2
}

@ObservedV2
export class HomeNavigationHideStore {
  @Trace hideStatusBar: boolean = true;
  @Trace hideTopNavigation: boolean = true;
  @Trace hideBottomNavigation: boolean = true;
  private loaded: boolean = false;

  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      this.hideStatusBar = (await store.get(STATUS_KEY, true)) === true;
      this.hideTopNavigation = (await store.get(TOP_KEY, true)) === true;
      this.hideBottomNavigation = (await store.get(BOTTOM_KEY, true)) === true;
    } catch (e) {
      hilog.warn(0x0, 'TiebaNav', 'navigation preferences load failed: %{public}s', String(e));
    }
  }

  async set(part: HomeNavigationPart, enabled: boolean, context: common.UIAbilityContext): Promise<void> {
    let key: string;
    switch (part) {
      case HomeNavigationPart.STATUS:
        this.hideStatusBar = enabled;
        key = STATUS_KEY;
        break;
      case HomeNavigationPart.TOP:
        this.hideTopNavigation = enabled;
        key = TOP_KEY;
        break;
      case HomeNavigationPart.BOTTOM:
        this.hideBottomNavigation = enabled;
        key = BOTTOM_KEY;
        break;
      default:
        return;
    }
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      await store.put(key, enabled);
      await store.flush();
    } catch (e) {
      hilog.warn(0x0, 'TiebaNav', 'navigation preference save failed: %{public}s', String(e));
    }
  }
}

export const homeNavigationHideStore: HomeNavigationHideStore = new HomeNavigationHideStore();
