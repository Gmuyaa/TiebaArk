
import { curves, FrameCallback } from '@kit.ArkUI';
import { HdsTabs } from '@kit.UIDesignKit';
import { AppTheme } from '../theme/Theme';
import { materialManager } from '../common/material/MaterialManager';
import { MaterialSlot, SPLIT_PILL_GRADIENT_MASK } from '../common/material/MaterialConfig';
import { fontScaleStore, FontSizeScaleStore } from '../common/appearance/FontSizeScaleStore';
import { fontSizeScaleOf } from '../common/appearance/FontSizeScale';
import {
  DEFAULT_HOME_TOP_NAV_STYLE, HomeTopNavStyle, homeTopNavRowHeight, homeTopNavScrollTarget
} from '../common/appearance/HomeTopNavStyle';
import { themeModeStore } from '../common/appearance/ThemeModeStore';
import { HomeChannelPills } from './HomeChannelPills';

const CHANNEL_LABELS: string[] = ['关注', '推荐', '热榜'];

const CONTAINER_H: number = 48;

const HIT_H: number = 44;

const SELECTED_H: number = 37;

const CHANNEL_GAP: number = 6;

const CHANNEL_PADDING: number = 12;

const ANIM_MS: number = 220;

const SEARCH_BOX: number = 48;

const SEARCH_ICON: number = 23;

const ISLAND_H: number = 48;

const ISLAND_RADIUS: number = ISLAND_H / 2;

const ISLAND_GAP: number = 12;

const CHANNEL_MAX_W: number = 320;

const ISLAND_PAD: number = 4;

const ISLAND_CONTENT_INSET_X: number = 12;

const ISLAND_INNER_H: number = ISLAND_H - ISLAND_PAD * 2;

const ISLAND_FILL_INSET: number = ISLAND_PAD;

const ISLAND_SLOT_MIN: number = 48;

const ISLAND_SLOT_BREATH: number = 6;

const ISLAND_ANIM_MS: number = 200;

const ISLAND_SEARCH_ICON: number = 22;

const ISLAND_ROW_FALLBACK: number = 200;

const UNIFIED_PAD_L: number = 6;
const UNIFIED_PAD_R: number = 4;

const UNIFIED_RADIUS: number = 16;

const SCROLL_MS: number = 220;

const GLASS_SHADOW: ShadowOptions = { radius: 14, color: '#12000000', offsetY: 3 };

const FILL_ACCENT: number = 0;
const FILL_LINE: number = 1;

const FILL_ISLAND: number = 2;

class NavLayoutFrame extends FrameCallback {
  private ready: () => void;
  constructor(ready: () => void) { super(); this.ready = ready; }
  onIdle(_timeLeft: number): void { this.ready(); }
}

@ComponentV2
export struct HomeTopNav {

  @Param style: HomeTopNavStyle = DEFAULT_HOME_TOP_NAV_STYLE;
  @Param selectedChannel: string = '推荐';

  @Param hidden: boolean = false;
  @Param statusBarHeight: number = 0;
  @Param backdropInset: number = 0;
  @Event onSelectChannel: (label: string) => void = (_label: string): void => {};
  @Event onRowHeightChanged: (height: number) => void = (_height: number): void => {};
  @Local fontSettings: FontSizeScaleStore = fontScaleStore;
  @Local measuredTextH: number = 0;
  @Local contentGlobalY: number = -1;
  @Event onSearch: () => void = (): void => {};

  @Local firstWidth: number = 56;
  @Local secondWidth: number = 56;
  @Local thirdWidth: number = 56;

  @Local viewportW: number = 0;

  @Local islandsRowW: number = 0;
  private channelScroller: Scroller = new Scroller();
  private layoutVersion: number = 0;
  private mounted: boolean = false;

  aboutToAppear(): void { this.mounted = true; this.scheduleCorrection(); }
  aboutToDisappear(): void { this.mounted = false; this.layoutVersion++; }

  @Monitor('selectedChannel', 'style', 'fontSettings.pref', 'fontSettings.customSize', 'fontSettings.systemScale')
  private navigationChanged(): void {
    this.scheduleCorrection();
  }

  private scaleValue(): number {
    return fontSizeScaleOf(this.fontSettings.pref, this.fontSettings.systemScale, this.fontSettings.customSize);
  }

  private rowHeight(): number {
    return homeTopNavRowHeight(this.style, this.scaleValue(), this.measuredTextH);
  }

  private itemHeight(): number {

    if (this.isIslands()) { return ISLAND_INNER_H; }
    return Math.max(HIT_H, this.rowHeight() - 10);
  }

  private labelsContentShift(): number {
    return this.style === HomeTopNavStyle.LIGHT_LABELS
      ? Math.max(0, Math.min(5, (this.rowHeight() - this.measuredTextH) / 2 - 8)) : 0;
  }
  private itemPadding(): number {
    if (this.isIslands()) { return 0; }
    return this.style === HomeTopNavStyle.LIGHT_LABELS ? 8 : CHANNEL_PADDING;
  }
  private itemGap(): number {
    if (this.isIslands()) { return 0; }
    return this.style === HomeTopNavStyle.LIGHT_LABELS ? 8 : CHANNEL_GAP;
  }

  private isIslands(): boolean { return this.style === HomeTopNavStyle.FLOATING_ISLANDS; }

  private islandWidth(): number {
    const rowW: number = this.islandsRowW > 0 ? this.islandsRowW : ISLAND_ROW_FALLBACK;
    return Math.max(0, Math.min(CHANNEL_MAX_W, rowW - ISLAND_GAP - SEARCH_BOX));
  }

  private islandContentW(): number {
    return Math.max(0, this.islandWidth() - ISLAND_CONTENT_INSET_X * 2);
  }

  private islandSlotWidth(): number {
    const scale: number = this.scaleValue();
    const measured: number = Math.max(this.firstWidth, this.secondWidth, this.thirdWidth);
    const minimum: number = Math.max(ISLAND_SLOT_MIN,
      measured + ISLAND_SLOT_BREATH * 2, 32 * scale + ISLAND_SLOT_BREATH * 2);
    const viewport: number = this.islandContentW();
    if (viewport <= 0) { return minimum; }
    return Math.max(minimum, viewport / 3);
  }

  private islandFillX(): number {
    return this.selectedIndex() * this.islandSlotWidth() + ISLAND_FILL_INSET;
  }

  private scheduleCorrection(): void {
    const version: number = ++this.layoutVersion;
    this.getUIContext().postFrameCallback(new NavLayoutFrame((): void => {
      if (!this.mounted || version !== this.layoutVersion) { return; }
      this.onRowHeightChanged(this.rowHeight());
      this.ensureSelectedVisible();
    }));
  }

  private selectedIndex(): number {
    const index: number = CHANNEL_LABELS.indexOf(this.selectedChannel);
    return index < 0 ? 1 : index;
  }

  private channelWidth(index: number): number {

    if (this.isIslands()) { return this.islandSlotWidth(); }
    const scale: number = this.scaleValue();
    const minimum: number = Math.max(44, this.itemPadding() * 2 +
      (this.style === HomeTopNavStyle.LIGHT_LABELS ? 36 : 32) * scale);
    if (index === 0) { return Math.max(this.firstWidth, minimum); }
    if (index === 1) { return Math.max(this.secondWidth, minimum); }
    return Math.max(this.thirdWidth, minimum);
  }

  private channelStart(index: number): number {
    if (index <= 0) { return 0; }
    if (index === 1) { return this.channelWidth(0) + this.itemGap(); }
    return this.channelWidth(0) + this.channelWidth(1) + this.itemGap() * 2;
  }

  private stripWidth(): number {
    return this.channelWidth(0) + this.channelWidth(1) + this.channelWidth(2) + this.itemGap() * 2;
  }

  private selectedX(): number {
    return this.channelStart(this.selectedIndex());
  }

  private updateChannelWidth(index: number, width: number): void {
    if (width <= 0) { return; }
    let changed: boolean = false;
    if (index === 0 && Math.abs(width - this.firstWidth) > 0.5) {
      this.firstWidth = width;
      changed = true;
    }
    if (index === 1 && Math.abs(width - this.secondWidth) > 0.5) {
      this.secondWidth = width;
      changed = true;
    }
    if (index === 2 && Math.abs(width - this.thirdWidth) > 0.5) {
      this.thirdWidth = width;
      changed = true;
    }
    if (changed) {
      this.scheduleCorrection();
    }
  }

  private ensureSelectedVisible(): void {
    if (this.viewportW <= 0 || this.style <= HomeTopNavStyle.BG_HIGHLIGHT) { return; }
    const inset: number = 0;
    const current: number = this.channelScroller.currentOffset().xOffset;
    const target: number = homeTopNavScrollTarget(this.channelStart(this.selectedIndex()) + inset,
      this.channelWidth(this.selectedIndex()), this.stripWidth() + inset * 2, this.viewportW, current);
    if (Math.abs(target - current) < 0.5) { return; }
    this.channelScroller.scrollTo({ xOffset: target, yOffset: 0,
      animation: { duration: SCROLL_MS, curve: Curve.EaseInOut } });
  }

  @Builder
  ChannelItems() {
    Row({ space: this.itemGap() }) {
      ForEach(CHANNEL_LABELS, (label: string, index: number) => {
        Row() {
          Text(label)
            .fontSize(this.style === HomeTopNavStyle.LIGHT_LABELS ? 18 : 16)
            .maxFontScale(this.style === HomeTopNavStyle.LIGHT_LABELS ? Math.max(2, this.scaleValue()) : 2)
            .maxLines(1)
            .flexShrink(0)
            .fontWeight(this.selectedChannel === label ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.selectedChannel === label ? AppTheme.ACCENT : this.unselectedChannelColor())
            .padding({ left: this.itemPadding(), right: this.itemPadding() })
            .onAreaChange((_old: Area, area: Area) => {
              this.updateChannelWidth(index, Number(area.width));
              if (Math.abs(Number(area.height) - this.measuredTextH) > 0.5) {
                this.measuredTextH = Number(area.height);
                this.scheduleCorrection();
              }
            })
            .animation({ duration: this.isIslands() ? ISLAND_ANIM_MS : ANIM_MS, curve: Curve.EaseInOut })
        }
        .width(this.channelWidth(index))
        .height(this.itemHeight())
        .justifyContent(FlexAlign.Center)
        .onClick(() => { this.onSelectChannel(label); })
      }, (label: string) => label)
    }
    .height(this.itemHeight())
  }

  private unselectedChannelColor(): Resource {
    return this.isIslands() ? AppTheme.TAB_PILL_TEXT
      : (this.style === HomeTopNavStyle.LIGHT_LABELS ? AppTheme.TEXT_MAIN : AppTheme.TAB_UNDERLINE_TEXT);
  }

  @Builder
  SelectedFill(kind: number) {
    if (kind === FILL_ISLAND) {
      Row()
        .width(this.islandSlotWidth() - ISLAND_FILL_INSET * 2)
        .height(ISLAND_INNER_H)
        .borderRadius(ISLAND_INNER_H / 2)
        .backgroundColor(AppTheme.ACCENT_LIGHT)
        .margin({ top: (this.itemHeight() - ISLAND_INNER_H) / 2 })
        .translate({ x: this.islandFillX() })
        .animation({ duration: ISLAND_ANIM_MS, curve: Curve.EaseInOut })
    } else {
      Row()
        .width(kind === FILL_LINE ? 14 : this.channelWidth(this.selectedIndex()))
        .height(kind === FILL_LINE ? 3 : SELECTED_H)
        .borderRadius(kind === FILL_LINE ? 1.5 : SELECTED_H / 2)
        .backgroundColor(kind === FILL_LINE ? AppTheme.ACCENT : AppTheme.ACCENT_LIGHT)
        .opacity(kind === FILL_LINE ? 1 : 0.7)
        .margin({ top: kind === FILL_LINE
          ? (this.itemHeight() + this.measuredTextH) / 2 + 3
          : (this.itemHeight() - SELECTED_H) / 2 })
        .translate({ x: this.selectedX() + (kind === FILL_LINE
          ? (this.channelWidth(this.selectedIndex()) - 14) / 2 : 0) })
        .animation({ duration: 200, curve: Curve.EaseInOut })
    }
  }

  @Builder
  ChannelGroup(fillKind: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      this.SelectedFill(fillKind)
      this.ChannelItems()
    }
    .width(this.stripWidth())
    .height(this.itemHeight())
    .translate({ y: this.labelsContentShift() })
  }

  @Builder
  ChannelViewport(fillKind: number) {
    Scroll(this.channelScroller) {
      Row() {
        this.ChannelGroup(fillKind)
      }
      .height(this.style === HomeTopNavStyle.LIGHT_LABELS ? this.rowHeight() : CONTAINER_H)
      .alignItems(VerticalAlign.Center)
    }
    .layoutWeight(1)
    .height(this.style === HomeTopNavStyle.LIGHT_LABELS ? this.rowHeight() : CONTAINER_H)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .align(Alignment.Start)
    .onAreaChange((_old: Area, area: Area) => {
      const width: number = Number(area.width);
      if (width <= 0 || Math.abs(width - this.viewportW) < 0.5) { return; }
      this.viewportW = width;
      this.scheduleCorrection();
    })
  }

  @Builder
  FloatingChannelIsland() {
    HdsTabs({ barPosition: BarPosition.End }) {
      TabContent() {
      }
      .tabBar(this.IslandChannelTab())
    }
    .barHeight(ISLAND_H)
    .barMode(BarMode.Fixed)
    .scrollable(false)
    .animationDuration(0)
    .barOverlap(true)

    .barBackgroundColor(Color.Transparent)
    .barBackgroundBlurStyle(BlurStyle.NONE)
    .barFloatingStyle({
      barWidth: { smallWidth: this.islandWidth(), mediumWidth: this.islandWidth(),
        largeWidth: this.islandWidth() },
      barSideMargin: 0,
      barBottomMargin: 0,
      gradientMask: SPLIT_PILL_GRADIENT_MASK,
      thermoCtrl: true,
      systemMaterialEffect: materialManager.hdsEffectOf(MaterialSlot.HOME_TOP_ISLAND)
    })

    .borderRadius(ISLAND_RADIUS)
    .clip(true)
    .width(this.islandWidth())
    .height(ISLAND_H)
  }

  @Builder
  IslandChannelTab() {
    Scroll(this.channelScroller) {
      this.ChannelGroup(FILL_ISLAND)
    }
    .width('100%')
    .height('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .align(Alignment.Start)
    .onAreaChange((_old: Area, area: Area) => {
      const width: number = Number(area.width);
      if (width <= 0 || Math.abs(width - this.viewportW) < 0.5) { return; }
      this.viewportW = width;
      this.scheduleCorrection();
    })
  }

  @Builder
  FloatingSearchIsland() {
    HdsTabs({ barPosition: BarPosition.End }) {
      TabContent() {
      }
      .tabBar(this.IslandSearchTab())
    }
    .barHeight(ISLAND_H)
    .barMode(BarMode.Fixed)
    .scrollable(false)
    .animationDuration(0)
    .barOverlap(true)
    .barBackgroundColor(Color.Transparent)
    .barBackgroundBlurStyle(BlurStyle.NONE)
    .barFloatingStyle({
      barWidth: { smallWidth: SEARCH_BOX, mediumWidth: SEARCH_BOX, largeWidth: SEARCH_BOX },
      barSideMargin: 0,
      barBottomMargin: 0,
      gradientMask: SPLIT_PILL_GRADIENT_MASK,
      thermoCtrl: true,
      systemMaterialEffect: materialManager.hdsEffectOf(MaterialSlot.HOME_TOP_ISLAND)
    })
    .borderRadius(SEARCH_BOX / 2)
    .clip(true)
    .width(SEARCH_BOX)
    .height(SEARCH_BOX)

    .flexShrink(0)
    .margin({ left: ISLAND_GAP })
    .accessibilityText('搜索')
  }

  @Builder
  IslandSearchTab() {
    Row() {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(ISLAND_SEARCH_ICON)
        .fontColor([AppTheme.TAB_PILL_TEXT])
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)

    .responseRegion({ x: 0, y: -ISLAND_PAD, width: '100%', height: SEARCH_BOX })
    .accessibilityText('搜索')
    .onClick(() => { this.onSearch(); })
  }

  @Builder
  SearchGlyph() {
    Row() {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(this.style === HomeTopNavStyle.LIGHT_LABELS ? '22vp' : SEARCH_ICON)
        .fontColor([this.style === HomeTopNavStyle.LIGHT_LABELS ? AppTheme.TEXT_MAIN : AppTheme.TAB_UNDERLINE_TEXT])
    }
    .width(HIT_H)
    .height(this.itemHeight())
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .translate({ y: this.labelsContentShift() })
    .accessibilityText('搜索')
    .onClick(() => { this.onSearch(); })
  }

  @Builder
  FloatingIslandsContent() {
    this.FloatingChannelIsland()
    this.FloatingSearchIsland()
  }

  @Builder
  UnifiedGlassContent() {
    Row() {
      this.ChannelViewport(FILL_ACCENT)
      this.SearchGlyph()
    }
    .layoutWeight(1)
    .height(this.style === HomeTopNavStyle.LIGHT_LABELS ? this.rowHeight() : CONTAINER_H)
    .padding({ left: UNIFIED_PAD_L, right: UNIFIED_PAD_R })
    .borderRadius(UNIFIED_RADIUS)
    .backgroundEffect(materialManager.glassOf(MaterialSlot.NAV_BAR))
    .systemMaterial(materialManager.officialOf(MaterialSlot.NAV_BAR))
    .shadow(GLASS_SHADOW)
  }

  @Builder
  LightLabelsContent() {
    this.ChannelViewport(FILL_LINE)
    this.SearchGlyph()
  }

  build() {
    if (this.style === HomeTopNavStyle.UNDERLINE || this.style === HomeTopNavStyle.BG_HIGHLIGHT) {

      HomeChannelPills({
        selectedChannel: this.selectedChannel,
        hidden: this.hidden,
        onSelectChannel: (label: string): void => { this.onSelectChannel(label); },
        onSearch: (): void => { this.onSearch(); }
      })
    } else {

      Row() {
        Stack({ alignContent: Alignment.TopStart }) {
          if (this.style === HomeTopNavStyle.LIGHT_LABELS) {
            HomeTopNavBackdrop({ heightVp: this.statusBarHeight + this.rowHeight() + 28,
              solidUntil: (this.statusBarHeight + this.rowHeight() + 5) /
                (this.statusBarHeight + this.rowHeight() + 28) })
              .width(this.viewportW + HIT_H + this.backdropInset * 2)

              .position({ x: -this.backdropInset, y: this.statusBarHeight > 0
                ? -(this.contentGlobalY >= 0 ? this.contentGlobalY : this.statusBarHeight + 5.4) : 0 })
          }
          Row() {
            if (this.style === HomeTopNavStyle.FLOATING_ISLANDS) {
              this.FloatingIslandsContent()
            } else if (this.style === HomeTopNavStyle.UNIFIED_GLASS) {
              this.UnifiedGlassContent()
            } else {
              this.LightLabelsContent()
            }
          }
          .width('100%').height(this.rowHeight())
          .alignItems(VerticalAlign.Center)

          .justifyContent(this.isIslands() ? FlexAlign.Center : FlexAlign.Start)

          .onAreaChange((_old: Area, area: Area) => {
            const width: number = Number(area.width);
            if (width <= 0 || Math.abs(width - this.islandsRowW) < 0.5) { return; }
            this.islandsRowW = width;
            this.scheduleCorrection();
          })
        }
        .width('100%').height(this.rowHeight())
        .clip(false)
        .onAreaChange((_old: Area, area: Area) => {
          const globalY: number = Number(area.globalPosition.y);
          if (Math.abs(globalY - this.contentGlobalY) > 0.1) { this.contentGlobalY = globalY; }
        })
      }
      .width('100%')
      .height(this.rowHeight())

      .alignItems(VerticalAlign.Center)
      .scale({ x: this.hidden ? 0.04 : 1, y: this.hidden ? 0.04 : 1,
        centerX: '50%', centerY: 0 })
      .translate({ y: this.hidden ? -this.rowHeight() - 10 : 0 })
      .opacity(this.hidden ? 0 : 1)
      .animation({ duration: this.hidden ? 300 : 440,
        curve: this.hidden ? Curve.EaseIn : curves.springMotion(0.38, 0.64) })

      .hitTestBehavior(this.hidden ? HitTestMode.None : HitTestMode.Default)
    }
  }
}

@ComponentV2
export struct HomeTopNavBackdrop {
  @Param heightVp: number = 118;
  @Param solidUntil: number = 0.78;
  build() {
    Row()
      .width('100%').height(this.heightVp)
      .constraintSize({ minHeight: this.heightVp, maxHeight: this.heightVp })
      .flexShrink(0)
      .linearGradient({ angle: 180, colors: themeModeStore.isDark
        ? [['#D9101112', 0], ['#D9101112', this.solidUntil], ['#00101112', 1]]
        : [['#D9F5F5F7', 0], ['#D9F5F5F7', this.solidUntil], ['#00F5F5F7', 1]] })
      .hitTestBehavior(HitTestMode.None)
  }
}
