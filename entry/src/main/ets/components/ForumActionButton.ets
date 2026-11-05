import { AppTheme } from '../theme/Theme';
import { MaterialTabs } from './MaterialTabs';
import { MaterialSlot } from '../common/material/MaterialConfig';

/** 吧头与吧列表复用的玻璃操作按钮；背景上的文字随宿主选择可读颜色。 */
@ComponentV2
export struct ForumActionButton {
  @Param label: string = '';
  @Param busy: boolean = false;
  @Param disabled: boolean = false;
  @Param onHero: boolean = true;
  @Param compact: boolean = false;
  @Local buttonWidth: number = 0;
  @Event onTap: () => void = (): void => {};
  build() {
    Stack() {
    if (this.onHero && this.buttonWidth > 0) {
      MaterialTabs({ slot: MaterialSlot.FORUM_ACTION_BUTTON, barHeight: this.compact ? 28 : 36,
        barWidth: this.buttonWidth })
        .width(this.buttonWidth).height(this.compact ? 28 : 36)
        .position({ x: 0, y: 0 }).hitTestBehavior(HitTestMode.None)
    }
    Text(this.label)
      .fontSize(this.compact ? 12 : 14).fontWeight(FontWeight.Medium)
      .fontColor(this.onHero ? AppTheme.TEXT_MAIN : AppTheme.ACCENT_DARK)
      .textAlign(TextAlign.Center).height(this.compact ? 28 : 36)
      .constraintSize({ minWidth: this.compact ? 52 : 72, maxWidth: this.compact ? 84 : 116 })
      .padding({ left: this.compact ? 8 : 12, right: this.compact ? 8 : 12 }).borderRadius(this.compact ? 14 : 18)
      .border({ width: this.onHero ? 0 : 0.75, color: AppTheme.ACCENT }).clip(true)
      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      .opacity(this.busy ? 0.6 : 1).enabled(!this.disabled)
      .onClick((): void => { this.onTap(); })
      .accessibilityText(this.label)
    }.borderRadius(this.compact ? 14 : 18).clip(false)
      .onAreaChange((_old: Area, area: Area): void => {
        const width: number = Number(area.width);
        if (width > 0 && Math.abs(width - this.buttonWidth) > 0.5) { this.buttonWidth = width; }
      })
  }
}
