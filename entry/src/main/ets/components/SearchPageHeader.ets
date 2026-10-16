import { UiLayout } from '../common/appearance/UiLayout';
import { STATUS_BAR_FALLBACK_VP } from '../utils/SafeArea';
import { GlassBackButton } from './GlassBackButton';
import { SearchField } from './SearchField';
import { SearchTopMaterial } from './SearchTopMaterial';

/** 搜索历史、全站结果和吧内结果共用同一顶栏几何及背景。 */
@ComponentV2
export struct SearchPageHeader {
  @Param text: string = '';
  @Param placeholder: string = '搜索';
  @Param statusBarHeight: number = STATUS_BAR_FALLBACK_VP;
  @Param secondaryHeight: number = 0;
  @BuilderParam secondary: () => void = this.EmptySecondary;
  @Local measuredHeight: number = 0;
  @Event onChange: (value: string) => void = (_value: string): void => {};
  @Event onSubmit: () => void = (): void => {};
  @Event onBack: () => void = (): void => {};
  @Event onHeightChange: (height: number) => void = (_height: number): void => {};

  @Builder
  EmptySecondary() {}

  private panelHeight(): number {
    return this.measuredHeight > 0 ? this.measuredHeight : this.statusBarHeight + 58 + this.secondaryHeight;
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      SearchTopMaterial({ panelHeight: this.panelHeight() })
        .position({ x: 0, y: 0 })
      Column() {
        Row({ space: 8 }) {
          GlassBackButton({ onTap: (): void => { this.onBack(); } })
            .id('search-header-back').flexShrink(0)
          SearchField({ text: this.text, placeholder: this.placeholder, minimumHeight: 40,
            onChange: (value: string): void => { this.onChange(value); },
            onSubmit: (): void => { this.onSubmit(); } })
            .id('search-header-field').layoutWeight(1)
        }
        .width('100%').alignItems(VerticalAlign.Center)
        .padding({ left: UiLayout.PAGE_GUTTER, right: UiLayout.PAGE_GUTTER,
          top: this.statusBarHeight + 6, bottom: 12 })
        this.secondary()
      }
      .width('100%')
      // 背景绝对定位，不参与测量；前景自然撑高，避免固定高度压住次级行。
      .onAreaChange((_old: Area, area: Area) => {
        const height: number = Number(area.height);
        if (height > 0 && Math.abs(height - this.measuredHeight) > 0.5) {
          this.measuredHeight = height;
          this.onHeightChange(height);
        }
      })
    }
    .width('100%')
    .id('search-page-header')
  }
}
