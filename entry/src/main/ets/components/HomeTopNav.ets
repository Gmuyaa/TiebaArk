/**
 * 首页与设置预览共用。四套样式：当前样式（委托 `HomeChannelPills`）/ 悬浮双岛 /
 * 一体玻璃 / 轻盈标签；后三套的几何与材质配方都集中在本文件顶部，模糊来自各自
 * 的玻璃槽位（「轻盈标签」另有一层通栏明度遮罩）。
 */
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

/** 玻璃容器 / 独立搜索按钮高度 */
const CONTAINER_H: number = 48;
/** 频道点击区最小高度 */
const HIT_H: number = 44;
/** 选中底高度（36~38vp 区间内） */
const SELECTED_H: number = 37;
/** 频道之间的间距 */
const CHANNEL_GAP: number = 6;
/** 频道文字左右内距 */
const CHANNEL_PADDING: number = 12;
/** 选中底切换动画时长 */
const ANIM_MS: number = 220;
/** 独立搜索按钮尺寸 */
const SEARCH_BOX: number = 48;
/** 搜索图标字号 */
const SEARCH_ICON: number = 23;

/** 两岛统一高度（频道岛外壳 / 搜索岛直径） */
const ISLAND_H: number = 48;
/** 频道岛圆角：整颗胶囊（48 / 2） */
const ISLAND_RADIUS: number = ISLAND_H / 2;
/** 两岛之间的固定间隔 */
const ISLAND_GAP: number = 12;
/** 频道岛最大宽度：宽屏不再无限拉伸（超出部分由 justifyContent 分到两侧，整组居中） */
const CHANNEL_MAX_W: number = 320;
/**
 * 官方悬浮面在栏内**上下各留的内距**（`barHeight 48` → 系统内容盒 40vp，真机实测）。
 *
 * 选中底就按这个内高做：高 40vp、四周各留 4vp —— 正好是需求里的
 * "选中底四周内缩 4vp、高 40vp"，而且这个 4vp **由系统承载器给**，不是我们自己 pad 的。
 */
const ISLAND_PAD: number = 4;

const ISLAND_CONTENT_INSET_X: number = 12;
/** 岛内可视内容高（= 选中底高度 40vp） */
const ISLAND_INNER_H: number = ISLAND_H - ISLAND_PAD * 2;
/** 选中底在槽位内的左右空隙（相邻两个选中底之间因此有 8vp） */
const ISLAND_FILL_INSET: number = ISLAND_PAD;
/** 频道槽位最小宽度（文字 + 左右各 6vp 呼吸）；放不下就横向滚动 */
const ISLAND_SLOT_MIN: number = 48;
/** 频道文字左右呼吸（槽位内，不是 Text 的 padding） */
const ISLAND_SLOT_BREATH: number = 6;

const ISLAND_ANIM_MS: number = 200;

const ISLAND_SEARCH_ICON: number = 22;
/**
 * 首帧的整行宽度兜底（vp）。
 *
 * 频道岛宽度要喂给 `barFloatingStyle.barWidth`（官方悬浮面**不显式钉宽就会被压到
 * 84vp 下限**，见 `pages/ThreadDetail` 的注释），所以它必须先知道本行有多宽。
 * 真值由外层 Row 的 `onAreaChange` 在首次布局时就给出；这里取 **200vp**
 * ——本项目里最窄的真实宿主是设置页预览（临时收窄到 200vp 做窄视口验证），
 * 兜底值比它再小就等于"首帧不会溢出"，宁可首帧略窄也不要把搜索岛挤出屏幕。
 */
const ISLAND_ROW_FALLBACK: number = 200;
/** 「一体玻璃」容器左右内距（搜索那侧更小，靠右但不贴边） */
const UNIFIED_PAD_L: number = 6;
const UNIFIED_PAD_R: number = 4;
/** 「一体玻璃」的圆角：柔和圆角矩形（不做成整颗胶囊，避免厚重工具面板感） */
const UNIFIED_RADIUS: number = 16;
/** 频道滚入可视范围的动画时长（超宽项居中） */
const SCROLL_MS: number = 220;
/** 一体玻璃容器的柔和阴影；选中项不重复绘制容器阴影。 */
const GLASS_SHADOW: ShadowOptions = { radius: 14, color: '#12000000', offsetY: 3 };

/** 选中底的三种形态 */
const FILL_ACCENT: number = 0;
const FILL_LINE: number = 1;
/** 「悬浮双岛」：岛内四周内缩 4vp 的浅蓝圆角底面（无投影、无描边、不单独模糊） */
const FILL_ISLAND: number = 2;

class NavLayoutFrame extends FrameCallback {
  private ready: () => void;
  constructor(ready: () => void) { super(); this.ready = ready; }
  onIdle(_timeLeft: number): void { this.ready(); }
}

@ComponentV2
export struct HomeTopNav {
  /** 当前生效的顶栏样式（来自 `homeTopNavStore.style` 或预览的本地选择） */
  @Param style: HomeTopNavStyle = DEFAULT_HOME_TOP_NAV_STYLE;
  @Param selectedChannel: string = '推荐';
  /** 滚动隐藏态：隐藏时整行缩到顶部并退出命中测试（不留可点的透明区域） */
  @Param hidden: boolean = false;
  @Param statusBarHeight: number = 0;
  @Param backdropInset: number = 0;
  @Event onSelectChannel: (label: string) => void = (_label: string): void => {};
  @Event onRowHeightChanged: (height: number) => void = (_height: number): void => {};
  @Local fontSettings: FontSizeScaleStore = fontScaleStore;
  @Local measuredTextH: number = 0;
  @Local contentGlobalY: number = -1;
  @Event onSearch: () => void = (): void => {};

  // 频道文字实测宽度；初值对应 16fp 双汉字 + 两侧各 12vp，文字缩放后按实际测量更新。
  @Local firstWidth: number = 56;
  @Local secondWidth: number = 56;
  @Local thirdWidth: number = 56;
  /** 频道区域可视宽度（实测）。窄屏 / 大字号放不下时用来把选中项滚进视野。 */
  @Local viewportW: number = 0;
  /** 「悬浮双岛」本行实测可用宽度（外层 Row）；首帧 0 = 用 `ISLAND_ROW_FALLBACK` 兜底 */
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
    // 「悬浮双岛」：点击区 = 官方悬浮面的**内容盒**（48 − 上下各 4vp = 40vp）
    if (this.isIslands()) { return ISLAND_INNER_H; }
    return Math.max(HIT_H, this.rowHeight() - 10);
  }
  // 将可见内容收向首卡，默认字号下短线到首卡约 16vp；极大字形为短线留 2vp。
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

  /**
   * 频道岛宽度（vp）：吃满本行剩余宽度，上限 `CHANNEL_MAX_W`。
   *
   * 这个值要**同时**喂给两个地方，否则官方悬浮面与节点对不上：
   *   - `HdsTabs.width(...)`：节点尺寸；
   *   - `barFloatingStyle.barWidth`：官方悬浮面尺寸（不显式钉宽会被压到 84vp 下限）。
   * 本行宽度由外层 Row 的 `onAreaChange` 实测（首帧用 `ISLAND_ROW_FALLBACK` 兜底）。
   */
  private islandWidth(): number {
    const rowW: number = this.islandsRowW > 0 ? this.islandsRowW : ISLAND_ROW_FALLBACK;
    return Math.max(0, Math.min(CHANNEL_MAX_W, rowW - ISLAND_GAP - SEARCH_BOX));
  }

  /**
   * 频道岛的**可视内容宽**（官方悬浮面左右各内缩 12vp）。
   *
   * 槽位、选中底、滚动视口全部按这个宽度算；用节点宽会多出 24vp 并把末位频道裁掉。
   */
  private islandContentW(): number {
    return Math.max(0, this.islandWidth() - ISLAND_CONTENT_INSET_X * 2);
  }

  /**
   * 「悬浮双岛」的频道槽位宽度：**三个槽位等宽**，按岛内可视宽度三等分。
   *
   * - 宽屏：`viewportW / 3` ≥ 文字所需最小宽 → 三个槽位正好铺满，`stripWidth` = 视口宽，
   *   横向滚动量恒为 0（默认手机宽度下三个频道全部可见）。
   * - 窄屏 / 大字号：`viewportW / 3` 小于最小宽 → 槽位取最小宽、总宽溢出视口，
   *   由既有 `ensureSelectedVisible` 把选中项滚进视野（**优先保证搜索岛完整可见**）。
   *
   * 文字宽度是**实测**的（`firstWidth` 等，岛内 Text 无 padding，量到的就是字形宽）；
   * 视口宽取 `islandContentW()`（官方悬浮面的内容盒，见该常量注释）。
   */
  private islandSlotWidth(): number {
    const scale: number = this.scaleValue();
    const measured: number = Math.max(this.firstWidth, this.secondWidth, this.thirdWidth);
    const minimum: number = Math.max(ISLAND_SLOT_MIN,
      measured + ISLAND_SLOT_BREATH * 2, 32 * scale + ISLAND_SLOT_BREATH * 2);
    const viewport: number = this.islandContentW();
    if (viewport <= 0) { return minimum; }
    return Math.max(minimum, viewport / 3);
  }

  /** 岛内选中底左沿（相对频道组左沿）：槽位左沿 + 槽位内空隙 */
  private islandFillX(): number {
    return this.selectedIndex() * this.islandSlotWidth() + ISLAND_FILL_INSET;
  }

  // 在下一帧完成布局后读真实 Scroller 偏移；代号使旧样式的迟到回调失效。
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
    // 「悬浮双岛」：三个槽位等宽铺满岛内（不再按文字收紧、不再靠 gap 分隔）
    if (this.isIslands()) { return this.islandSlotWidth(); }
    const scale: number = this.scaleValue();
    const minimum: number = Math.max(44, this.itemPadding() * 2 +
      (this.style === HomeTopNavStyle.LIGHT_LABELS ? 36 : 32) * scale);
    if (index === 0) { return Math.max(this.firstWidth, minimum); }
    if (index === 1) { return Math.max(this.secondWidth, minimum); }
    return Math.max(this.thirdWidth, minimum);
  }

  /** 频道文字起点（相对频道组左沿） */
  private channelStart(index: number): number {
    if (index <= 0) { return 0; }
    if (index === 1) { return this.channelWidth(0) + this.itemGap(); }
    return this.channelWidth(0) + this.channelWidth(1) + this.itemGap() * 2;
  }

  /** 频道组总宽（三个频道 + 两个间距） */
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

  /**
   * 选中底。
   *
   * `FILL_ISLAND`（悬浮双岛）：非常浅的蓝圆角底面，**高 40vp**（官方悬浮面的内容盒高，
   * 也就是"岛内四周各留 4vp"），宽度 = 槽位 − 左右各 4vp。**不加投影、不加描边、
   * 不单独模糊、不加下划线**，字号与字位都不变 —— 切换时只有底面平移 +
   * 文字颜色/字重过渡（200ms）。视觉层级：外壳给官方材质，这一层只给"选中的是哪一个"。
   *
   * ⚠️ 选中底是**前景**（画在官方材质面之上），横向只占一个槽位（约 1/3 岛宽），
   * 不会把整个材质面盖住。
   */
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

  /** 频道组：选中底 + 文字（三套新设计共用同一套测量与滑动） */
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

  /**
   * 频道区域的横向滚动视口（**一体玻璃 / 轻盈标签**用；「悬浮双岛」走
   * `FloatingChannelIsland` 的官方悬浮面，见下）。
   *
   * 默认字号下三频道全部可见（不滚动）；窄屏或大字号放不下时，搜索固定可见、
   * 频道区域横向滚动、选中项自动进入可视范围（见 `ensureSelectedVisible`）。
   * **不缩小用户字号、不截断标签。**
   */
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

  /** 频道岛的系统材质承载器，内容层只绘制文字与选中状态。 */
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
    // 让出系统自带的整块底衬（与首页底栏、详情页分离式同一处理）
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
    // 裁掉弧外楔形区里被节点 bounds 硬裁的系统软阴影
    .borderRadius(ISLAND_RADIUS)
    .clip(true)
    .width(this.islandWidth())
    .height(ISLAND_H)
  }

  /**
   * 频道岛的 tabBar 内容：横向滚动视口 + 选中底 + 三个频道。
   *
   * 系统内容盒 = 栏高 − 上下各 4vp（48 → 40vp），所以这里用 `100%` 撑满，
   * 选中底正好 40vp 高、四周各留 4vp（需求里的"内缩 4vp"由承载器天然给出）。
   * 横向也必须 `100%`：容器内内容默认水平居中，不撑满就没法按槽位等宽铺开。
   */
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

  /**
   * 「悬浮双岛」的**官方材质承载器**（搜索岛）。
   *
   * 与频道岛同一个 `HdsTabs` + 同一个 `HOME_TOP_ISLAND` 槽位，只把节点/悬浮面钉成
   * 48×48 —— 官方悬浮面是"高 = 栏高、圆角 = 半高"的胶囊，方节点即整圆。
   * 图标 22vp、容器居中；点击区覆盖整个圆（内容盒只有 40vp 高，用 `responseRegion`
   * 把命中区补回 48vp，见 `IslandSearchTab`）。
   */
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
    // 搜索岛是**辅助但不可压缩**的：窄视口下宁可让频道岛少占一点，
    // 也不能把官方悬浮面挤小（挤了之后 barWidth 与节点就对不上，材质面会错位）
    .flexShrink(0)
    .margin({ left: ISLAND_GAP })
    .accessibilityText('搜索')
  }

  /** 搜索岛的 tabBar 内容：只有一枚图标，整圆可点 */
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
    // 内容盒只有 40vp 高（系统上下各留 4vp），把命中区补回整个 48vp 圆
    .responseRegion({ x: 0, y: -ISLAND_PAD, width: '100%', height: SEARCH_BOX })
    .accessibilityText('搜索')
    .onClick(() => { this.onSearch(); })
  }

  /** 只有图标、没有独立外壳的搜索入口（一体玻璃 / 轻盈标签） */
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

  /**
   * 悬浮双岛：左侧频道玻璃岛（**吃满本行剩余宽度**，上限 320vp）+ 12vp + 右侧圆形搜索岛。
   *
   * 两个岛**都由官方 `HdsTabs` 悬浮面承载材质**（同一个 `HOME_TOP_ISLAND` 槽位映射），
   * 这里只负责把它们排成一组：同高 48vp、间隔 12vp、由外层 Row 的
   * `justifyContent(Center)` 整组居中 —— 宽屏时多出来的宽度落在组的两侧，
   * 而不是把频道岛拉长、也不是把两岛推开。
   */
  @Builder
  FloatingIslandsContent() {
    this.FloatingChannelIsland()
    this.FloatingSearchIsland()
  }

  /** 一体玻璃：频道与搜索共用一条悬浮玻璃容器（左右对齐页面边距） */
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

  /** 轻盈标签：无整条容器，文字频道与短线选中标识；搜索只显示图标 */
  @Builder
  LightLabelsContent() {
    this.ChannelViewport(FILL_LINE)
    this.SearchGlyph()
  }

  build() {
    if (this.style === HomeTopNavStyle.UNDERLINE || this.style === HomeTopNavStyle.BG_HIGHLIGHT) {
      /*
       * 当前样式：**原样委托**改动前就在跑的 `HomeChannelPills`，作为视觉对照。
       * 占位与边距由宿主给（`Index` 的 `.padding(...)`，与改动前逐字一致），
       * 首卡位置因此不变。
       */
      HomeChannelPills({
        selectedChannel: this.selectedChannel,
        hidden: this.hidden,
        onSelectChannel: (label: string): void => { this.onSelectChannel(label); },
        onSearch: (): void => { this.onSearch(); }
      })
    } else {
      // 宿主负责状态栏避让与 HDS 32vp 槽位补偿。外层 Row 保留原槽位布局；
      // 背景置于内部等高 Stack，避免被 HDS 压缩。只遮罩一次，模糊仍来自 HDS。
      Row() {
        Stack({ alignContent: Alignment.TopStart }) {
          if (this.style === HomeTopNavStyle.LIGHT_LABELS) {
            HomeTopNavBackdrop({ heightVp: this.statusBarHeight + this.rowHeight() + 28,
              solidUntil: (this.statusBarHeight + this.rowHeight() + 5) /
                (this.statusBarHeight + this.rowHeight() + 28) })
              .width(this.viewportW + HIT_H + this.backdropInset * 2)
              // 首页按内容层实测屏幕坐标把背景延伸到 y=0；预览从卡片上沿开始。
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
          // 「悬浮双岛」整组居中（宽屏时余量落在两侧，不是把两岛推开）
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
      // 隐藏后不留可点击的透明区域：整行退出命中测试，手势落到下层内容
      .hitTestBehavior(this.hidden ? HitTestMode.None : HitTestMode.Default)
    }
  }
}

/** 首页专属明度保护层：无局部模糊、无圆角。同色相透明端点避免深色发灰。 */
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
