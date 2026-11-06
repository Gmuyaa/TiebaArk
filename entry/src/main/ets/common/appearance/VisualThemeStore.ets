import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { VisualTheme, normalizeVisualTheme } from './VisualTheme';

/** 首帧前同步恢复；独立保存，切回经典时原有外观偏好仍在。 */
@ObservedV2
export class VisualThemeStore {
  @Trace theme: VisualTheme = VisualTheme.CLASSIC;
  private loaded: boolean = false;
  private themeRefresher: (() => void) | undefined = undefined;

  /** 由已初始化 ArkUI 的 Ability 注册，避免 store 与主题资源模块循环依赖。 */
  setThemeRefresher(refresher: (() => void) | undefined): void {
    this.themeRefresher = refresher;
  }

  private refreshNativeTheme(): void {
    if (this.themeRefresher !== undefined) {
      try { this.themeRefresher(); }
      catch (_) { hilog.warn(0, 'TiebaVisualTheme', 'native theme refresh failed'); }
    }
  }

  get isPaper(): boolean { return this.theme === VisualTheme.PAPER; }

  load(context: common.UIAbilityContext): void {
    if (this.loaded) { return; }
    this.loaded = true;
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(context, { name: 'tieba_visual_theme' });
      this.theme = normalizeVisualTheme(store.getSync('theme', VisualTheme.CLASSIC) as number);
    } catch (_) {
      hilog.warn(0, 'TiebaVisualTheme', 'visual theme unavailable, keep classic');
    }
  }

  /** 持久化完成才发布状态，存储失败不把当前选项伪装为已保存。 */
  setTheme(theme: VisualTheme, context: common.UIAbilityContext): boolean {
    const next: VisualTheme = normalizeVisualTheme(theme as number);
    if (next === this.theme) { return true; }
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(context, { name: 'tieba_visual_theme' });
      store.putSync('theme', next as number);
      store.flushSync();
      this.theme = next;
      this.refreshNativeTheme();
      return true;
    } catch (_) {
      hilog.warn(0, 'TiebaVisualTheme', 'visual theme save failed');
      return false;
    }
  }
}

export const visualThemeStore: VisualThemeStore = new VisualThemeStore();
