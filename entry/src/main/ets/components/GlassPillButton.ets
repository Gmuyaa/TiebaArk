import { HdsTabs } from '@kit.UIDesignKit';
import { materialManager } from '../common/material/MaterialManager';
import { MaterialSlot, SPLIT_PILL_GRADIENT_MASK } from '../common/material/MaterialConfig';
import { AppTheme } from '../theme/Theme';

/** 文字或图标文字胶囊，沿用圆按钮的 HDS 沉浸光感通道。 */
@ComponentV2
export struct GlassPillButton {
  @Param label: string = '';
  @Param accessibilityLabel: string = '';
  @Param symbol: Resource | undefined = undefined;
  @Param pillWidth: number = 64;
  @Param pillHeight: number = 40;
  @Param stacked: boolean = false;
  @Param active: boolean = true;
  @Param slot: MaterialSlot = MaterialSlot.BACK_BUTTON;
  @Event onTap: () => void = (): void => {};

  @Builder
  Content() {
    Column({ space: this.stacked ? 2 : 0 }) {
      if (this.symbol !== undefined) {
        SymbolGlyph(this.symbol).fontSize(24).maxFontScale(1).fontWeight(FontWeight.Regular)
          .fontColor([AppTheme.TEXT_MAIN])
      }
      Text(this.label).fontSize(this.stacked ? 11 : 16).maxFontScale(1)
        .fontWeight(FontWeight.Regular).fontColor(AppTheme.TEXT_MAIN).maxLines(1)
        .width('100%').textAlign(TextAlign.Center)
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .opacity(this.active ? 1 : 0.4)
      .accessibilityGroup(true).accessibilityText(this.accessibilityLabel || this.label)
      .onClick(() => { if (this.active) { this.onTap(); } })
  }

  build() {
    HdsTabs({ barPosition: BarPosition.End }) {
      TabContent() {}.tabBar(this.Content())
    }
    .barHeight(this.pillHeight).barMode(BarMode.Fixed).scrollable(false).animationDuration(0)
    .barOverlap(true).barBackgroundColor(Color.Transparent).barBackgroundBlurStyle(BlurStyle.NONE)
    .barFloatingStyle({
      barWidth: { smallWidth: this.pillWidth, mediumWidth: this.pillWidth, largeWidth: this.pillWidth },
      barSideMargin: 0, barBottomMargin: 0, gradientMask: SPLIT_PILL_GRADIENT_MASK, thermoCtrl: true,
      systemMaterialEffect: materialManager.hdsEffectOf(this.slot)
    })
    .borderRadius(this.pillHeight / 2).clip(true).width(this.pillWidth).height(this.pillHeight)
    .shadow({ radius: 14, color: '#18000000', offsetY: 3 })
  }
}
