/** 公共玻璃返回按钮，复用 GlassCircleButton。 */

import { GlassCircleButton } from './GlassCircleButton';

@ComponentV2
export struct GlassBackButton {
  /** 点击行为，由各页面传入（通常是 `router.back()`） */
  @Param onTap: () => void = (): void => {};
  /** 圆直径，默认 40vp */
  @Param diameter: number = 40;
  /** 图标字号，默认 24vp */
  @Param iconSize: number = 24;

  build() {
    GlassCircleButton({
      symbol: $r('sys.symbol.chevron_left'),
      onTap: this.onTap,
      accessibilityLabel: '返回',
      diameter: this.diameter,
      iconSize: this.iconSize
    })
  }
}
