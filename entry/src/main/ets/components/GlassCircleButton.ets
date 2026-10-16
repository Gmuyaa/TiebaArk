

import { HdsTabs } from '@kit.UIDesignKit';
import { materialManager } from '../common/material/MaterialManager';
import { MaterialSlot, SPLIT_PILL_GRADIENT_MASK } from '../common/material/MaterialConfig';
import { AppTheme } from '../theme/Theme';

const DIAMETER: number = 40;

const ICON_SIZE: number = 24;

const ICON_COLOR: ResourceColor = AppTheme.TEXT_MAIN;

@ComponentV2
export struct GlassCircleButton {

  @Param symbol: Resource = $r('sys.symbol.chevron_left');

  @Param label: string = '';
  @Param accessibilityLabel: string = '';
  @Param labelOffsetY: number = 0;

  @Param onTap: () => void = (): void => {};

  @Param diameter: number = DIAMETER;

  @Param iconSize: number = ICON_SIZE;

  @Param slot: MaterialSlot = MaterialSlot.BACK_BUTTON;

  @Param iconOffsetX: number = 0;

  @Param useCustomIcon: boolean = false;

  @Builder
  emptyIcon() {}
  @BuilderParam customIcon: () => void = this.emptyIcon;

  @Builder
  SymbolTab() {
    Row() {
      if (this.useCustomIcon) {

        Column() {
          this.customIcon();
        }
        .offset({ x: this.iconOffsetX })
      } else if (this.label.length > 0) {
        Text(this.label)
          .fontSize(this.iconSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(ICON_COLOR)
          .textAlign(TextAlign.Center)
          .offset({ x: this.iconOffsetX, y: this.labelOffsetY })
          .accessibilityText(this.accessibilityLabel.length > 0 ? this.accessibilityLabel : this.label)
      } else {
        SymbolGlyph(this.symbol)
          .fontSize(this.iconSize)

          .fontWeight(FontWeight.Bold)
          .fontColor([ICON_COLOR])
          .offset({ x: this.iconOffsetX })
      }
    }
    .height('100%')
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onTap();
    })
  }

  build() {

    Stack() {
      HdsTabs({ barPosition: BarPosition.End }) {
        TabContent() {
        }
        .tabBar(this.SymbolTab())
      }
      .barHeight(this.diameter)
      .barMode(BarMode.Fixed)
      .scrollable(false)
      .animationDuration(0)
      .barOverlap(true)

      .barBackgroundColor(Color.Transparent)
      .barBackgroundBlurStyle(BlurStyle.NONE)

      .barFloatingStyle({
        barWidth: { smallWidth: this.diameter, mediumWidth: this.diameter, largeWidth: this.diameter },
        barSideMargin: 0,
        barBottomMargin: 0,

        gradientMask: SPLIT_PILL_GRADIENT_MASK,
        thermoCtrl: true,
        systemMaterialEffect: materialManager.hdsEffectOf(this.slot)
      })

      .borderRadius(this.diameter / 2)
      .clip(true)
      .width(this.diameter)
      .height(this.diameter)
    }
    .width(this.diameter)
    .height(this.diameter)
    .borderRadius(this.diameter / 2)

    .shadow({ radius: 18, color: '#28000000', offsetX: 0, offsetY: 6 })
  }
}

