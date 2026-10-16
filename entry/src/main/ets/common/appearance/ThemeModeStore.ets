/** 主题偏好持久化与应用。首帧前同步加载颜色模式，避免闪色；系统主题变化时更新 isDark，通过 systemBarRefresher 刷新系统栏文字色。 */

import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant, EnvironmentCallback } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  DEFAULT_THEME_MODE_PREF, ThemeModePref, normalizeThemeModePref, themeModeIsDark, themeModeLabel
} from './ThemeMode';

const DOMAIN: number = 0x0000;
const TAG: string = 'TiebaThemeMode';

/** 持久化存储与键名 */
const STORE: string = 'tieba_theme_prefs';
const KEY_PREF: string = 'pref';

/**
 * 全局单例：App 内只有一个"深色模式"偏好。
 *
 * 与 `MaterialManager` 同一取舍：读/写失败一律静默（本次会话内仍生效，
 * 只是下次启动可能回到旧值）——偏好存储异常不该影响 App 启动。
 */
@ObservedV2
export class ThemeModeStore {
  /** 用户偏好（三态）。`@Trace` → 设置页弹层勾选态自动跟随 */
  @Trace pref: ThemeModePref = DEFAULT_THEME_MODE_PREF;

  /**
   * 当前**生效**的深浅色（true = 深色）。
   *
   * `$r` 资源引用不经过它（资源匹配是系统机制）；它只服务于**拿不到资源匹配结果**的
   * 少量调用方：EntryAbility 的系统栏内容色、以及任何 string-only 的 API。
   * `@Trace`：跟随系统切换时 EntryAbility 之外的 V2 组件也能读到新值。
   */
  @Trace isDark: boolean = false;

  private loaded: boolean = false;
  /** EntryAbility 注册的系统栏刷新回调（见文件头"系统栏跟随"） */
  private systemBarRefresher: (() => void) | undefined = undefined;

  /**
   * 启动时**同步**读偏好并立即应用（首帧前）。
   *
   * ⚠️ ohosTest 进程里 `preferences.getPreferences(getAppContext())` 会抛
   * "context is invalid"，所以**调用方要传真实 UIAbilityContext**（`EntryAbility.onCreate`）。
   * ⚠️ 任何一步失败都保持默认（跟随系统）：读不出偏好 = 老用户行为不变。
   */
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

  /**
   * 设置偏好（设置页唯一入口）：改状态 → 应用 → 落盘。
   *
   * 先改状态再落盘（同 `MaterialManager.setMode`）：界面立刻响应，落盘失败也不回滚。
   * `setColorMode` 是同步调用；资源重匹配与页面重绘由框架负责。
   */
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

  /** EntryAbility 在拿到窗口后注册；每次生效模式变化都会被调一次 */
  setSystemBarRefresher(refresher: () => void): void {
    this.systemBarRefresher = refresher;
  }

  /**
   * 把偏好应用到应用级颜色模式，并同步 `isDark`。
   *
   * `FOLLOW_SYSTEM` 映射 `COLOR_MODE_NOT_SET`（解除锁定、交还系统）；
   * 此时 `isDark` 读 `config.colorMode` —— 应用未锁定时它就是系统当前值。
   */
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

  /** 系统此刻是否深色（`config.colorMode` 未上报时按浅色处理） */
  private systemIsDark(context: common.UIAbilityContext): boolean {
    try {
      return context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } catch (e) {
      return false;
    }
  }

  /**
   * 订阅系统环境变化（跟随系统档位下系统切深浅色时更新 `isDark` 与系统栏）。
   *
   * 只在 `FOLLOW_SYSTEM` 时做事，但**每次环境变化都回调**（显式档位下系统切换
   * 与应用无关，`themeModeIsDark` 自然返回常量，更新 `isDark` 是无害幂等）。
   */
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

  /** 日志用的一行摘要 */
  describe(): string {
    return `${this.pref}(${themeModeLabel(this.pref)}), isDark=${String(this.isDark)}`;
  }
}

/** 全局单例：App 内只有一个深色模式偏好 */
export const themeModeStore: ThemeModeStore = new ThemeModeStore();
