/** 公共玻璃更多按钮，复用 GlassCircleButton。 */

import { GlassCircleButton } from './GlassCircleButton';

@ComponentV2
export struct GlassMoreButton {
  @Param onTap: () => void = (): void => {};
  @Param diameter: number = 40;
  /**
   * 图标字号默认 20vp，比返回按钮的 24 小一档：`ellipsis_circle` 自带圆形轮廓，24 在 40 圆里留白过少、
   * 显得比返回箭头重。
   */
  @Param iconSize: number = 20;

  build() {
    GlassCircleButton({
      symbol: $r('sys.symbol.dot_grid_1x2'),
      onTap: this.onTap,
      accessibilityLabel: '更多操作',
      diameter: this.diameter,
      iconSize: this.iconSize
    })
  }
}
