import { MaterialTabs } from './MaterialTabs';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { materialManager } from '../common/material/MaterialManager';

/** 与首页整片顶栏同一官方材质承载；前景控件独立，避免 Tab 吞掉输入。 */
@ComponentV2
export struct SearchTopMaterial {
  @Param slot: MaterialSlot = MaterialSlot.SEARCH_TOP_CONTINUOUS;
  @Param panelHeight: number = 100;
  @Local visibleWidth: number = 0;

  private nodeWidth(): number {
    return (this.visibleWidth > 0 ? this.visibleWidth : 300) + this.panelHeight;
  }

  build() {
    if (materialManager.useArkUI) {
      MaterialTabs({ slot: this.slot, barHeight: this.panelHeight, componentMaterial: true,
        barContent: (): void => { this.ArkUIPanel(); } })
        .width('100%').height(this.panelHeight).hitTestBehavior(HitTestMode.None)
    } else {
      this.CompatibilityPanel()
    }
  }

  @Builder
  CompatibilityPanel() {
    Stack({ alignContent: Alignment.Top }) {
      Row().width('100%').height(1)
        .onAreaChange((_old: Area, area: Area) => {
          const width: number = Number(area.width);
          if (width > 0 && Math.abs(width - this.visibleWidth) > 0.5) { this.visibleWidth = width; }
        })
      // 超宽胶囊两端的圆弧落在屏幕外，可见区是一整片矩形材质。
      MaterialTabs({ slot: this.slot, barHeight: this.panelHeight,
        barWidth: this.nodeWidth() })
      .borderRadius(this.panelHeight / 2).clip(false)
      .width(this.nodeWidth()).height(this.panelHeight)
    }
    .width('100%').height(this.panelHeight).clip(false)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  ArkUIPanel() {
    Row().width('100%').height(this.panelHeight)
      .systemMaterial(materialManager.officialOf(this.slot))
  }
}
