import { AppTheme } from '../theme/Theme';

/** xmark 的绘制 em 与 advance 不同，用独立方形布局盒承载，避免父容器按 advance 居中。 */
@ComponentV2
export struct CloseIcon {
  @Param iconSize: number = 20;
  @Param iconWeight: FontWeight = FontWeight.Normal;
  @Param color: ResourceColor = AppTheme.TEXT_MAIN;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      SymbolGlyph($r('sys.symbol.xmark')).fontSize(this.iconSize).maxFontScale(1)
        .fontWeight(this.iconWeight).fontColor([this.color]).position({ x: 0, y: 0 })
    }.width(this.iconSize).height(this.iconSize).hitTestBehavior(HitTestMode.Transparent)
  }
}
