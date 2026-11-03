/** “我的”页外观图标：原生太阳、月亮；跟随系统按当前深浅切换左右半实心。 */
import { AppTheme } from '../theme/Theme';
import { ThemeModePref, normalizeThemeModePref } from '../common/appearance/ThemeMode';

@ComponentV2
export struct ThemeModeIcon {
  @Param mode: ThemeModePref = ThemeModePref.FOLLOW_SYSTEM;
  @Param isDark: boolean = false;
  @Param iconSize: number = 22;
  @Param iconColor: ResourceColor = AppTheme.ICON;

  private symbol(): Resource {
    switch (normalizeThemeModePref(this.mode as number)) {
      case ThemeModePref.LIGHT:
        return $r('sys.symbol.sun_max');
      case ThemeModePref.DARK:
        return $r('sys.symbol.moon');
      case ThemeModePref.FOLLOW_SYSTEM:
      default:
        // 左右实心随系统深浅变化，表达昼夜流转：深色左实心、浅色右实心。
        return this.isDark ? $r('sys.symbol.circle_lefthalf_inset_filled') :
          $r('sys.symbol.circle_righthalf_inset_filled');
    }
  }

  build() {
    SymbolGlyph(this.symbol())
      .fontSize(this.iconSize).maxFontScale(1)
      .fontWeight(FontWeight.Regular)
      .fontColor([this.iconColor])
      .width(this.iconSize)
      .height(this.iconSize)
  }
}
