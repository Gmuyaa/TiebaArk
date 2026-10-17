/** 全站搜索胶囊：共用内容、字号适配和沉浸光感，最小高度由宿主指定。 */
import { fontScaleStore } from '../common/appearance/FontSizeScaleStore';
import { fontSizeScaleOf } from '../common/appearance/FontSizeScale';
import { searchFieldHeight } from '../common/appearance/UiLayout';
import { HdsTabs } from '@kit.UIDesignKit';
import { AppTheme } from '../theme/Theme';
import { themeModeStore } from '../common/appearance/ThemeModeStore';
import { materialManager } from '../common/material/MaterialManager';
import { MaterialSlot, SPLIT_PILL_GRADIENT_MASK } from '../common/material/MaterialConfig';

export const SEARCH_FIELD_HEIGHT: number = 32;

@ComponentV2
export struct SearchField {
  @Param inputId: string = 'search-field-input';
  @Param text: string = '';
  @Param placeholder: string = '搜索';
  @Param editable: boolean = true;
  /** 带返回按钮的独立搜索顶栏使用 40vp；首页保留紧凑高度。 */
  @Param minimumHeight: number = SEARCH_FIELD_HEIGHT;
  @Event onChange: (value: string) => void = (_value: string): void => {};
  @Event onSubmit: () => void = (): void => {};
  @Event onTap: () => void = (): void => {};
  @Local fieldWidth: number = 0;

  private fieldHeight(): number {
    return Math.max(this.minimumHeight,
      searchFieldHeight(fontSizeScaleOf(fontScaleStore.pref, fontScaleStore.systemScale, fontScaleStore.customSize)));
  }

  @Builder
  MaterialContent() {
    Row().width('100%').height('100%')
  }

  build() {
    Stack() {
      // 只承载材质，不接受触摸；输入层不放在 tabBar 内，避免 tab 手势截获输入。
      if (this.fieldWidth > 0) {
        HdsTabs({ barPosition: BarPosition.End }) {
          TabContent() {}.tabBar(this.MaterialContent())
        }
        .barHeight(this.fieldHeight())
        .barMode(BarMode.Fixed)
        .scrollable(false)
        .animationDuration(0)
        .barOverlap(true)
        .barBackgroundColor(Color.Transparent)
        .barBackgroundBlurStyle(BlurStyle.NONE)
        .barFloatingStyle({
          barWidth: { smallWidth: this.fieldWidth, mediumWidth: this.fieldWidth,
            largeWidth: this.fieldWidth },
          barSideMargin: 0,
          barBottomMargin: 0,
          gradientMask: SPLIT_PILL_GRADIENT_MASK,
          thermoCtrl: true,
          systemMaterialEffect: materialManager.hdsEffectOf(MaterialSlot.SEARCH_BAR)
        })
        .width('100%')
        .height(this.fieldHeight())
        .borderRadius(this.fieldHeight() / 2)
        .clip(true)
        .hitTestBehavior(HitTestMode.None)
      }
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(20).maxFontScale(1)
          .fontColor([AppTheme.TAB_UNDERLINE_TEXT])
        if (this.editable) {
          TextInput({ text: this.text, placeholder: this.placeholder })
            .id(this.inputId)
            .fontSize(16)
            .fontColor(AppTheme.TEXT_MAIN)
            .placeholderColor(AppTheme.TAB_UNDERLINE_TEXT)
            .placeholderFont({ size: 16 })
            .height(this.fieldHeight())
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .padding(0)
            .enterKeyType(EnterKeyType.Search)
            .onChange((value: string) => { this.onChange(value); })
            .onSubmit(() => { this.onSubmit(); })
        } else {
          Text(this.placeholder)
            .fontSize(16)
            .fontColor(AppTheme.TAB_UNDERLINE_TEXT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
      }
      .width('100%')
      .height(this.fieldHeight())
      .padding({ left: 14, right: 14 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => { if (!this.editable) { this.onTap(); } })
    }
    .width('100%')
    .height(this.fieldHeight())
    .borderRadius(this.fieldHeight() / 2)
    .border({ width: 0.5, color: themeModeStore.isDark ?
      'rgba(255, 255, 255, 0.22)' : 'rgba(0, 0, 0, 0.04)' })
    .shadow({ radius: 10, offsetY: 2, color: themeModeStore.isDark ?
      'rgba(0, 0, 0, 0.40)' : 'rgba(0, 0, 0, 0.06)' })
    .onAreaChange((_old: Area, area: Area) => {
      const width: number = Number(area.width);
      if (width > 0 && Math.abs(width - this.fieldWidth) >= 0.5) { this.fieldWidth = width; }
    })
  }
}
