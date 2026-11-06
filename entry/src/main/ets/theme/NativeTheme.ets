import { CustomColors, CustomTheme, ThemeControl } from '@kit.ArkUI';
import { AppTheme } from './Theme';

/** 原生控件与页面使用同一套资源；dark 资源由当前应用颜色模式匹配。 */
export function nativeTheme(): CustomTheme {
  const colors: CustomColors = {
    brand: AppTheme.ACCENT,
    primary: AppTheme.ACCENT,
    onPrimary: AppTheme.ON_ACCENT,
    container: AppTheme.ACCENT_LIGHT,
    alert: AppTheme.DANGER_TEXT,
    fontPrimary: AppTheme.TEXT_MAIN,
    fontSecondary: AppTheme.TEXT_SUB,
    fontTertiary: AppTheme.TEXT_MUTED,
    fontFourth: AppTheme.TEXT_MUTED,
    fontEmphasize: AppTheme.ACCENT_DARK,
    fontOnPrimary: AppTheme.ON_ACCENT,
    fontOnSecondary: AppTheme.ON_ACCENT,
    iconPrimary: AppTheme.ICON,
    iconSecondary: AppTheme.TEXT_SUB,
    iconTertiary: AppTheme.TEXT_MUTED,
    iconFourth: AppTheme.TEXT_MUTED,
    iconEmphasize: AppTheme.ACCENT,
    iconSubEmphasize: AppTheme.ACCENT_DARK,
    iconOnPrimary: AppTheme.ON_ACCENT,
    iconOnSecondary: AppTheme.ON_ACCENT,
    backgroundPrimary: AppTheme.CARD,
    backgroundSecondary: AppTheme.BG,
    backgroundTertiary: AppTheme.SURFACE_MUTED,
    backgroundFourth: AppTheme.SURFACE_MUTED,
    backgroundEmphasize: AppTheme.ACCENT,
    compBackgroundPrimary: AppTheme.CARD,
    compBackgroundGray: AppTheme.SURFACE_MUTED,
    compBackgroundEmphasize: AppTheme.ACCENT,
    compEmphasizeSecondary: AppTheme.ACCENT_LIGHT,
    compEmphasizeTertiary: AppTheme.ACCENT_LIGHT,
    compDivider: AppTheme.DIVIDER,
    compBackgroundFocus: AppTheme.SURFACE_MUTED,
    compFocusedPrimary: AppTheme.TEXT_MAIN,
    compFocusedSecondary: AppTheme.TEXT_SUB,
    interactiveFocus: AppTheme.ACCENT,
    interactiveActive: AppTheme.ACCENT,
    interactiveSelect: AppTheme.SELECTION_BACKGROUND
  };
  // 系统 hover/press/click 与成功/警告语义沿用平台，不给普通行新增交互效果。
  return { colors: colors };
}

/** 必须在 ArkUI 已初始化的窗口回调中调用；同步更新已经打开的原生组件。 */
export function applyNativeTheme(): void {
  ThemeControl.setDefaultTheme(nativeTheme());
}
