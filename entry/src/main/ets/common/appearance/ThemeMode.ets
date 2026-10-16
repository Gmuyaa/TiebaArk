

export enum ThemeModePref {

  FOLLOW_SYSTEM = 0,

  LIGHT = 1,

  DARK = 2
}

export const DEFAULT_THEME_MODE_PREF: ThemeModePref = ThemeModePref.FOLLOW_SYSTEM;

export const ALL_THEME_MODE_PREFS: ThemeModePref[] = [
  ThemeModePref.FOLLOW_SYSTEM,
  ThemeModePref.LIGHT,
  ThemeModePref.DARK
];

export function themeModeLabel(pref: ThemeModePref): string {
  switch (pref) {
    case ThemeModePref.LIGHT:
      return '浅色模式';
    case ThemeModePref.DARK:
      return '深色模式';
    case ThemeModePref.FOLLOW_SYSTEM:
    default:
      return '跟随系统';
  }
}

export function themeModeDesc(pref: ThemeModePref): string {
  switch (pref) {
    case ThemeModePref.LIGHT:
      return '始终使用浅色界面';
    case ThemeModePref.DARK:
      return '始终使用深色界面，玻璃胶囊外观不变，文字转为浅色';
    case ThemeModePref.FOLLOW_SYSTEM:
    default:
      return '与系统显示与亮度设置保持一致';
  }
}

export function normalizeThemeModePref(raw: number): ThemeModePref {
  switch (raw) {
    case ThemeModePref.LIGHT:
      return ThemeModePref.LIGHT;
    case ThemeModePref.DARK:
      return ThemeModePref.DARK;
    case ThemeModePref.FOLLOW_SYSTEM:
    default:
      return DEFAULT_THEME_MODE_PREF;
  }
}

export function themeModeIsDark(pref: ThemeModePref, systemDark: boolean): boolean {
  switch (pref) {
    case ThemeModePref.LIGHT:
      return false;
    case ThemeModePref.DARK:
      return true;
    case ThemeModePref.FOLLOW_SYSTEM:
    default:
      return systemDark;
  }
}

export function nextThemeModePref(pref: ThemeModePref): ThemeModePref {
  switch (normalizeThemeModePref(pref as number)) {
    case ThemeModePref.FOLLOW_SYSTEM:
      return ThemeModePref.LIGHT;
    case ThemeModePref.LIGHT:
      return ThemeModePref.DARK;
    case ThemeModePref.DARK:
    default:
      return ThemeModePref.FOLLOW_SYSTEM;
  }
}
