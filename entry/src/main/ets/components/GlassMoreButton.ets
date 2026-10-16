/** 公共玻璃更多按钮，复用 GlassCircleButton。 */

import { GlassCircleButton } from './GlassCircleButton';

@ComponentV2
export struct GlassMoreButton {
  /** 点击行为，由页面传入（通常是开关顶部菜单） */
  @Param onTap: () => void = (): void => {};
  /** 圆直径，默认 40vp（与返回按钮一致） */
  @Param diameter: number = 40;
  /**
   * 图标字号，默认 20vp（比返回按钮的 24 小一档）：
   * `ellipsis_circle` 自带圆形轮廓，24 在 40 圆里留白过少、显得比返回箭头重，
   * 20 与玻璃圆的比例更接近参考图。
   */
  @Param iconSize: number = 20;

  build() {
    GlassCircleButton({
      symbol: $r('sys.symbol.dot_grid_1x2'),
      onTap: this.onTap,
      accessibilityLabel: '更多操作',
      diameter: this.diameter,
      iconSize: this.iconSize,
      iconOffsetX: -(this.iconSize * 0.093)
    })
  }
}
