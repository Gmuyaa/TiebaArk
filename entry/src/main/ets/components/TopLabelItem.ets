import { visualThemeStore } from '../common/appearance/VisualThemeStore';
import { AppTheme } from '../theme/Theme';
import { themeModeStore } from '../common/appearance/ThemeModeStore';
import { PaperLayout, VisualTheme } from '../common/appearance/VisualTheme';

/** 首页频道与搜索分类共用的文字标签：字重与标记表达选中，纸境使用短线、经典保留圆点。 */
@ComponentV2
export struct TopLabelItem {
  @Param label: string = '';
  @Param selected: boolean = false;
  @Event onTap: () => void = (): void => {};

  private labelFontSize(): number {
    if (visualThemeStore.isPaper) { return PaperLayout.CHANNEL_LABEL_SIZE; }
    return this.selected ? 17 : 16;
  }
  private labelColor(): ResourceColor {
    if (visualThemeStore.isPaper) { return this.selected ? AppTheme.NAV_SELECTED : AppTheme.TEXT_SUB; }
    if (this.selected) {
      return visualThemeStore.theme === VisualTheme.CLASSIC
        ? (themeModeStore.isDark ? Color.White : Color.Black) : AppTheme.NAV_SELECTED;
    }
    return themeModeStore.isDark ? AppTheme.TEXT_MUTED : AppTheme.BAR_TAB_TEXT;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Row({ space: 4 }) {
        Text(this.label).fontSize(this.labelFontSize())
          .fontWeight(this.selected ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.labelColor()).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
        if (this.selected && !visualThemeStore.isPaper) { Circle({ width: 5, height: 5 }).fill(this.labelColor()).flexShrink(0) }
      }.width('100%').height('100%')
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
      if (visualThemeStore.isPaper && this.selected) {
        Row().width(20).height(2).borderRadius(1).backgroundColor(AppTheme.NAV_SELECTED)
          .position({ x: '50%', y: '100%' }).translate({ x: -10, y: -2 })
          .id('paper-channel-indicator').hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      }
    }
    .width('100%').height('100%')
    .accessibilityText(this.label).accessibilitySelected(this.selected)
    .onClick((): void => { this.onTap(); })
  }
}
