/**
 * 列表项左滑独立圆形删除按钮（鸿蒙标准删除红 `#E84026` + 白色实心垃圾桶）。
 * 供 `ListItem.swipeAction({ end: ... })` 复用，配合独立卡片使整卡左滑、按钮独立露在右侧。
 */
import { AppTheme } from '../theme/Theme';

@ComponentV2
export struct SwipeDeleteButton {
  @Param accessibilityLabel: string = '删除';
  @Param buttonEnabled: boolean = true;
  @Param diameter: number = 44;
  @Param iconSize: number = 22;
  @Event onTap: () => void = (): void => {};

  build() {
    Row() {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.trash_fill'))
          .fontSize(this.iconSize)
          .fontColor([Color.White])
      }
      .width(this.diameter)
      .height(this.diameter)
      .backgroundColor(AppTheme.SWIPE_DELETE_BG)
      .accessibilityText(this.accessibilityLabel)
      .enabled(this.buttonEnabled)
      .onClick((): void => { this.onTap(); })
    }
    .height('100%')
    .padding({ left: 12, right: 4 })
    .alignItems(VerticalAlign.Center)
  }
}
