import { AppTheme } from '../theme/Theme';
import { themeModeStore } from '../common/appearance/ThemeModeStore';

/** 首页频道与搜索分类共用的文字标签：字重、极值色和小圆点表达选中。 */
@ComponentV2
export struct TopLabelItem {
  @Param label: string = '';
  @Param selected: boolean = false;
  @Event onTap: () => void = (): void => {};

  private labelFontSize(): number {
    return this.selected ? 17 : 16;
  }
  private labelColor(): ResourceColor {
    if (this.selected) { return themeModeStore.isDark ? Color.White : Color.Black; }
    return themeModeStore.isDark ? AppTheme.TEXT_MUTED : AppTheme.BAR_TAB_TEXT;
  }

  build() {
    Row({ space: 4 }) {
      Text(this.label).fontSize(this.labelFontSize())
        .fontWeight(this.selected ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.labelColor()).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
      if (this.selected) { Circle({ width: 5, height: 5 }).fill(this.labelColor()).flexShrink(0) }
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
    .accessibilityText(this.label).accessibilitySelected(this.selected)
    .onClick((): void => { this.onTap(); })
  }
}
