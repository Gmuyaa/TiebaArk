/** 主题模式的枚举、文案与值归一。跟随系统、浅色和深色三态只决定颜色模式；玻璃材质由材质配置管理。 */

/**
 * 深色模式偏好。
 *
 * ⚠️ **数值就是持久化值，已有取值不许改号**（改了等于改了用户的存档）。
 */
export enum ThemeModePref {
  /** 跟随系统（默认）：不锁定应用颜色模式 */
  FOLLOW_SYSTEM = 0,
  /** 浅色模式：应用锁定浅色 */
  LIGHT = 1,
  /** 深色模式（夜间模式）：应用锁定深色 */
  DARK = 2
}

/** 默认偏好：跟随系统（不做过设置的老用户 = 维持系统行为，应用不变样） */
export const DEFAULT_THEME_MODE_PREF: ThemeModePref = ThemeModePref.FOLLOW_SYSTEM;

/** 设置页展示顺序（默认项在最前） */
export const ALL_THEME_MODE_PREFS: ThemeModePref[] = [
  ThemeModePref.FOLLOW_SYSTEM,
  ThemeModePref.LIGHT,
  ThemeModePref.DARK
];

/**
 * 产品化名称（UI 唯一出口）。
 *
 * ⚠️ **禁止**出现实现术语（`colorMode` / `NOT_SET` 这些只留在代码注释里）。
 */
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

/** 设置页弹层副文案：只说"什么时候是深色"，不解释实现 */
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

/**
 * 把持久化里读到的值归一到合法档位。
 *
 * 映射表（**这就是全部规则，不要再加分支**）：
 * ```
 *   无值 / 未知值 / NaN / 越界  → 跟随系统（默认）
 *   0                          → 跟随系统
 *   1                          → 浅色模式
 *   2                          → 深色模式
 * ```
 * 任何情况下都返回合法档：颜色模式坏了**不能**让应用渲染不出界面。
 */
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

/**
 * 判定某偏好下"当前是否应该渲染为深色"。
 *
 * `systemDark` 是"系统此刻是否深色"（读 `config.colorMode === COLOR_MODE_DARK`）。
 * 跟随系统档位完全由它决定；显式档位无视它。
 * 这是纯函数：真机侧的真实深浅由 `ThemeModeStore` 负责喂正确的 `systemDark`。
 */
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
