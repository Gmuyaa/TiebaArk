

import { GlassCircleButton } from './GlassCircleButton';

@ComponentV2
export struct GlassMoreButton {

  @Param onTap: () => void = (): void => {};

  @Param diameter: number = 40;

  @Param iconSize: number = 20;

  build() {
    GlassCircleButton({
      symbol: $r('sys.symbol.dot_grid_1x2'),
      onTap: this.onTap,
      diameter: this.diameter,
      iconSize: this.iconSize,
      iconOffsetX: -(this.iconSize * 0.093)
    })
  }
}
