/** 公共玻璃返回按钮，复用 GlassCircleButton。 */

import { GlassCircleButton } from './GlassCircleButton';

@ComponentV2
export struct GlassBackButton {
  @Param onTap: () => void = (): void => {};
  @Param diameter: number = 40;
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
