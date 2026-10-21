import { AppTheme } from '../theme/Theme';
import { materialManager } from '../common/material/MaterialManager';
import { MaterialSlot } from '../common/material/MaterialConfig';

/** 吧头与吧列表复用的玻璃操作按钮；背景上的文字随宿主选择可读颜色。 */
@ComponentV2
export struct ForumActionButton {
  @Param label: string = '';
  @Param busy: boolean = false;
  @Param disabled: boolean = false;
  @Param onHero: boolean = true;
  @Param compact: boolean = false;
  @Event onTap: () => void = (): void => {};
  build() {
    Text(this.label)
      .fontSize(this.compact ? 12 : 14).fontWeight(FontWeight.Medium)
      .fontColor(this.onHero ? Color.White : AppTheme.ACCENT_DARK)
      .textAlign(TextAlign.Center).height(this.compact ? 28 : 36)
      .constraintSize({ minWidth: this.compact ? 52 : 72, maxWidth: this.compact ? 84 : 116 })
      .padding({ left: this.compact ? 8 : 12, right: this.compact ? 8 : 12 }).borderRadius(this.compact ? 14 : 18)
      .backgroundColor(this.onHero ? '#33FFFFFF' : Color.Transparent)
      .backgroundEffect(this.onHero ? materialManager.glassOf(MaterialSlot.FORUM_ACTION_BUTTON) : undefined)
      .border({ width: this.onHero ? 1 : 0.75, color: this.onHero ? '#40FFFFFF' : AppTheme.ACCENT }).clip(true)
      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      .opacity(this.busy ? 0.6 : 1).enabled(!this.disabled)
      .onClick((): void => { this.onTap(); })
      .accessibilityText(this.label)
  }
}
