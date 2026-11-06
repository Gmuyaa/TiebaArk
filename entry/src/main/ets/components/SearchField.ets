/** 全站搜索胶囊：共用内容、字号适配和沉浸光感，最小高度由宿主指定。 */
import { fontScaleStore } from '../common/appearance/FontSizeScaleStore';
import { fontSizeScaleOf } from '../common/appearance/FontSizeScale';
import { searchFieldHeight } from '../common/appearance/UiLayout';
import { MaterialTabs } from './MaterialTabs';
import { AppTheme } from '../theme/Theme';
import { visualThemeStore } from '../common/appearance/VisualThemeStore';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { materialManager } from '../common/material/MaterialManager';

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

  build() {
    if (materialManager.useArkUI) {
      MaterialTabs({ slot: MaterialSlot.SEARCH_BAR, barHeight: this.fieldHeight(), componentMaterial: true,
        barContent: (): void => { this.ArkUIField(); } })
        .width('100%').height(this.fieldHeight())
    } else {
      this.CompatibilityField()
    }
  }

  @Builder
  CompatibilityField() {
    Stack() {
      // 只承载材质，不接受触摸；输入层不放在 tabBar 内，避免 tab 手势截获输入。
      if (this.fieldWidth > 0) {
        MaterialTabs({ slot: MaterialSlot.SEARCH_BAR, barHeight: this.fieldHeight(),
          barWidth: this.fieldWidth })
        .width('100%')
        .height(this.fieldHeight())
        .borderRadius(this.fieldHeight() / 2)
        .clip(false)
        .hitTestBehavior(HitTestMode.None)
      }
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(20).maxFontScale(1)
          .fontColor([(visualThemeStore.isPaper ? AppTheme.SEARCH_HINT : AppTheme.TAB_UNDERLINE_TEXT)])
        if (this.editable) {
          TextInput({ text: this.text, placeholder: this.placeholder })
            .id(this.inputId)
            .fontSize(16)
            .fontColor(AppTheme.TEXT_MAIN)
            .caretColor(AppTheme.ACCENT)
            .selectedBackgroundColor(AppTheme.SELECTION_BACKGROUND)
            .placeholderColor((visualThemeStore.isPaper ? AppTheme.SEARCH_HINT : AppTheme.TAB_UNDERLINE_TEXT))
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
            .fontColor((visualThemeStore.isPaper ? AppTheme.SEARCH_HINT : AppTheme.TAB_UNDERLINE_TEXT))
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
    .onAreaChange((_old: Area, area: Area) => {
      const width: number = Number(area.width);
      if (width > 0 && Math.abs(width - this.fieldWidth) >= 0.5) { this.fieldWidth = width; }
    })
  }

  @Builder
  ArkUIField() {
    Search({ value: this.text, placeholder: this.placeholder })
      .id(this.inputId)
      .width('100%').height(this.fieldHeight()).margin(0).borderRadius(this.fieldHeight() / 2)
      .textFont({ size: 16 })
      .fontColor(AppTheme.TEXT_MAIN)
      .caretStyle({ color: AppTheme.ACCENT })
      .selectedBackgroundColor(AppTheme.SELECTION_BACKGROUND)
      .placeholderColor(visualThemeStore.isPaper ? AppTheme.SEARCH_HINT : AppTheme.TAB_UNDERLINE_TEXT)
      .placeholderFont({ size: 16 })
      .searchIcon({ size: 20, color: visualThemeStore.isPaper ? AppTheme.SEARCH_HINT : AppTheme.TAB_UNDERLINE_TEXT })
      .cancelButton({ style: CancelButtonStyle.INVISIBLE })
      .enableKeyboardOnFocus(this.editable).focusable(this.editable)
      .backgroundColor(Color.Transparent)
      .systemMaterial(materialManager.officialOf(MaterialSlot.SEARCH_BAR))
      .enterKeyType(EnterKeyType.Search)
      .onChange((value: string): void => { if (this.editable) { this.onChange(value); } })
      .onSubmit((): void => { if (this.editable) { this.onSubmit(); } })
      .onClick((): void => { if (!this.editable) { this.onTap(); } })
  }
}
