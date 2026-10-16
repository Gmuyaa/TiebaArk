

import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant, EnvironmentCallback } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  DEFAULT_THEME_MODE_PREF, ThemeModePref, normalizeThemeModePref, themeModeIsDark, themeModeLabel
} from './ThemeMode';

const DOMAIN: number = 0x0000;
const TAG: string = 'TiebaThemeMode';

const STORE: string = 'tieba_theme_prefs';
const KEY_PREF: string = 'pref';

@ObservedV2
export class ThemeModeStore {

  @Trace pref: ThemeModePref = DEFAULT_THEME_MODE_PREF;

  @Trace isDark: boolean = false;

  private loaded: boolean = false;

  private systemBarRefresher: (() => void) | undefined = undefined;

  load(context: common.UIAbilityContext): void {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    try {
      const options: preferences.Options = { name: STORE };
      const store: preferences.Preferences = preferences.getPreferencesSync(context, options);
      const raw: number = store.getSync(KEY_PREF, DEFAULT_THEME_MODE_PREF as number) as number;
      this.pref = normalizeThemeModePref(raw);
    } catch (e) {
      this.pref = DEFAULT_THEME_MODE_PREF;
      hilog.warn(DOMAIN, TAG, 'theme pref load failed, fallback to follow-system: %{public}s',
        String(e));
    }
    this.apply(context);
    this.watchEnvironment(context);
    hilog.info(DOMAIN, TAG, 'theme mode loaded: %{public}s', this.describe());
  }

  setMode(pref: ThemeModePref, context: common.UIAbilityContext): void {
    const next: ThemeModePref = normalizeThemeModePref(pref as number);
    if (next === this.pref) {
      return;
    }
    this.pref = next;
    this.apply(context);
    hilog.info(DOMAIN, TAG, 'theme mode -> %{public}s', this.describe());
    try {
      const options: preferences.Options = { name: STORE };
      const store: preferences.Preferences = preferences.getPreferencesSync(context, options);
      store.putSync(KEY_PREF, next as number);
      store.flushSync();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'theme mode save failed: %{public}s', String(e));
    }
  }

  setSystemBarRefresher(refresher: () => void): void {
    this.systemBarRefresher = refresher;
  }

  private apply(context: common.UIAbilityContext): void {
    const appContext: common.ApplicationContext = context.getApplicationContext();
    try {
      if (this.pref === ThemeModePref.LIGHT) {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else if (this.pref === ThemeModePref.DARK) {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'setColorMode failed: %{public}s', String(e));
    }
    this.isDark = themeModeIsDark(this.pref, this.systemIsDark(context));
    this.refreshSystemBar();
  }

  private systemIsDark(context: common.UIAbilityContext): boolean {
    try {
      return context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } catch (e) {
      return false;
    }
  }

  private watchEnvironment(context: common.UIAbilityContext): void {
    try {
      const callback: EnvironmentCallback = {
        onConfigurationUpdated: () => {
          const before: boolean = this.isDark;
          this.isDark = themeModeIsDark(this.pref, this.systemIsDark(context));
          if (this.isDark !== before) {
            hilog.info(DOMAIN, TAG, 'system color mode changed -> %{public}s', this.describe());
            this.refreshSystemBar();
          }
        },
        onMemoryLevel: () => {
        }
      };
      context.getApplicationContext().on('environment', callback);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'watch environment failed: %{public}s', String(e));
    }
  }

  private refreshSystemBar(): void {
    if (this.systemBarRefresher !== undefined) {
      try {
        this.systemBarRefresher();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'system bar refresh failed: %{public}s', String(e));
      }
    }
  }

  describe(): string {
    return `${this.pref}(${themeModeLabel(this.pref)}), isDark=${String(this.isDark)}`;
  }
}

export const themeModeStore: ThemeModeStore = new ThemeModeStore();
