import { HdsTabs } from '@kit.UIDesignKit';
import { materialManager } from '../common/material/MaterialManager';
import { MaterialSlot, SPLIT_PILL_GRADIENT_MASK } from '../common/material/MaterialConfig';

/** 与首页整片顶栏同一 HDS 承载方式；前景控件独立，避免原生 Tab 吞掉输入。 */
@ComponentV2
export struct SearchTopMaterial {
  @Param panelHeight: number = 100;
  @Local visibleWidth: number = 0;

  private nodeWidth(): number {
    return (this.visibleWidth > 0 ? this.visibleWidth : 300) + this.panelHeight;
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Row().width('100%').height(1)
        .onAreaChange((_old: Area, area: Area) => {
          const width: number = Number(area.width);
          if (width > 0 && Math.abs(width - this.visibleWidth) > 0.5) { this.visibleWidth = width; }
        })
      // 超宽胶囊两端的圆弧落在屏幕外，可见区是一整片矩形材质。
      HdsTabs({ barPosition: BarPosition.End }) {
        TabContent() {}.tabBar(this.EmptyBar())
      }
      .barHeight(this.panelHeight).barMode(BarMode.Fixed)
      .scrollable(false).animationDuration(0).barOverlap(true)
      .barBackgroundColor(Color.Transparent).barBackgroundBlurStyle(BlurStyle.NONE)
      .barFloatingStyle({
        barWidth: { smallWidth: this.nodeWidth(), mediumWidth: this.nodeWidth(), largeWidth: this.nodeWidth() },
        barSideMargin: 0, barBottomMargin: 0,
        gradientMask: SPLIT_PILL_GRADIENT_MASK, thermoCtrl: true,
        systemMaterialEffect: materialManager.hdsEffectOf(MaterialSlot.SEARCH_TOP_CONTINUOUS)
      })
      .borderRadius(this.panelHeight / 2).clip(true)
      .width(this.nodeWidth()).height(this.panelHeight)
    }
    .width('100%').height(this.panelHeight).clip(true)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  EmptyBar() { Row() {} }
}
