import { MaterialTabs } from './MaterialTabs';
import { MaterialSlot } from '../common/material/MaterialConfig';

/** 编辑页胶囊：系统材质与前景触摸分层，避免 HDS 页签截获编辑操作。 */
@ComponentV2
export struct ComposeMaterialBar {
  @Param barHeight: number = 48;
  @Local barWidth: number = 0;
  @Builder empty() {}
  @BuilderParam content: () => void = this.empty;

  build() {
    Stack() {
      if (this.barWidth > 0) {
        MaterialTabs({ slot: MaterialSlot.BOTTOM_BAR, barHeight: this.barHeight, barWidth: this.barWidth })
        .width('100%').height(this.barHeight).borderRadius(this.barHeight / 2).clip(false)
        .hitTestBehavior(HitTestMode.None)
      }
      this.content()
    }
    .width('100%').height(this.barHeight).borderRadius(this.barHeight / 2)
    .onAreaChange((_old: Area, area: Area): void => {
      const width: number = Number(area.width);
      if (width > 0 && Math.abs(width - this.barWidth) >= 0.5) { this.barWidth = width; }
    })
  }
}
