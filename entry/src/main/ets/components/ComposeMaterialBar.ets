import { HdsTabs } from '@kit.UIDesignKit';
import { materialManager } from '../common/material/MaterialManager';
import { MaterialSlot, SPLIT_PILL_GRADIENT_MASK } from '../common/material/MaterialConfig';

/** 编辑页胶囊：系统材质与前景触摸分层，避免 HDS 页签截获编辑操作。 */
@ComponentV2
export struct ComposeMaterialBar {
  @Param barHeight: number = 48;
  @Local barWidth: number = 0;
  @Builder empty() {}
  @BuilderParam content: () => void = this.empty;

  @Builder backing() { Row().width('100%').height('100%') }

  build() {
    Stack() {
      if (this.barWidth > 0) {
        HdsTabs({ barPosition: BarPosition.End }) {
          TabContent() {}.tabBar(this.backing())
        }
        .barHeight(this.barHeight).barMode(BarMode.Fixed).scrollable(false).animationDuration(0)
        .barOverlap(true).barBackgroundColor(Color.Transparent).barBackgroundBlurStyle(BlurStyle.NONE)
        .barFloatingStyle({
          barWidth: { smallWidth: this.barWidth, mediumWidth: this.barWidth, largeWidth: this.barWidth },
          barSideMargin: 0, barBottomMargin: 0, gradientMask: SPLIT_PILL_GRADIENT_MASK,
          thermoCtrl: true, systemMaterialEffect: materialManager.hdsEffectOf(MaterialSlot.BOTTOM_BAR)
        })
        .width('100%').height(this.barHeight).borderRadius(this.barHeight / 2).clip(true)
        .hitTestBehavior(HitTestMode.None)
      }
      this.content()
    }
    .width('100%').height(this.barHeight).borderRadius(this.barHeight / 2)
    .shadow({ radius: 14, color: '#18000000', offsetY: 4 })
    .onAreaChange((_old: Area, area: Area): void => {
      const width: number = Number(area.width);
      if (width > 0 && Math.abs(width - this.barWidth) >= 0.5) { this.barWidth = width; }
    })
  }
}
