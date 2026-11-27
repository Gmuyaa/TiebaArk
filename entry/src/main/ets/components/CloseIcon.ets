import { AppTheme } from '../theme/Theme';

/** 关闭图标容器：保持居中布局，不依赖手工定位偏移。 */
@ComponentV2
export struct CloseIcon {
  @Param iconSize: number = 20;
  @Param iconWeight: FontWeight = FontWeight.Normal;
  @Param color: ResourceColor | undefined = undefined;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r('sys.symbol.xmark')).fontSize(this.iconSize).maxFontScale(1)
        .fontWeight(this.iconWeight).fontColor([this.color ?? AppTheme.TEXT_MAIN])
    }.width(this.iconSize).height(this.iconSize).hitTestBehavior(HitTestMode.Transparent)
  }
}
