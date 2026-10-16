/** 首页沉浸顶栏的搜索行与频道行。收起时隐藏搜索行及其占用高度，展开时恢复；材质由外层容器提供。 */
import { AvatarComponent } from './AvatarComponent';
import { searchFieldHeight, homeChannelHeight } from '../common/appearance/UiLayout';
import { homeDualRowHeight } from '../common/appearance/HomeTopNavStyle';
import { HdsTabs } from '@kit.UIDesignKit';
import { SearchField } from './SearchField';
import { TopLabelItem } from './TopLabelItem';
import { materialManager } from '../common/material/MaterialManager';
import { MaterialSlot, SPLIT_PILL_GRADIENT_MASK } from '../common/material/MaterialConfig';
import { fontSizeScaleOf } from '../common/appearance/FontSizeScale';
import { fontScaleStore } from '../common/appearance/FontSizeScaleStore';

export const DUAL_SEARCH_ROW_H: number = 40;

export const DUAL_CHANNEL_ROW_H: number = 30;
/** 搜索行与频道行间距（vp）—— 6 → 4 → 2 */
export const DUAL_ROW_GAP: number = 2;
/** 玻璃面板内容高（搜索 + 间距 + 频道，不含状态栏与系统内容盒内距） */
export const DUAL_CONTENT_H: number = DUAL_SEARCH_ROW_H + DUAL_ROW_GAP + DUAL_CHANNEL_ROW_H;
/** 官方悬浮面内容盒上下各留的内距（真机实测，barHeight 48 → 内容盒 40） */
export const DUAL_BOX_INSET: number = 4;
/** 官方悬浮面内容盒左右各留的内距（真机实测，与栏高无关） */
const DUAL_BOX_INSET_X: number = 12;
/** 首帧可见宽度兜底（vp）：最窄宿主是设置页预览卡 */
const FALLBACK_VIS_W: number = 300;
/** 头像直径（vp） */
const AVATAR_D: number = 28;

@ComponentV2
export struct HomeDualRowTopBar {
  /** 状态栏高度（vp）：玻璃从屏幕顶铺下来，状态栏区也在玻璃内 */
  @Param statusBarHeight: number = 39;
  @Param selectedChannel: string = '推荐';

  @Param collapsed: boolean = false;
  /** 本人头像 URL（空 = 未登录，显示占位图标） */
  @Param avatarUrl: string = '';
  @Event onSelectChannel: (label: string) => void = (_label: string): void => {};
  @Event onSearch: () => void = (): void => {};
  @Event onAvatar: () => void = (): void => {};
  /** 宿主实测可见宽度（vp） */
  @Local visW: number = 0;

  // 标签配色及字号由 TopLabelItem 同源维护。
  private channelLabels(): string[] {
    return ['关注', '推荐', '热榜'];
  }

  private panelH(): number {
    // 收起态高度 = 状态栏 + 频道行 + 上下内距（搜索行整段消失，不留白）
    const content: number = this.collapsed ? homeChannelHeight(this.scaleValue()) : homeDualRowHeight(this.scaleValue());
    return this.statusBarHeight + content + DUAL_BOX_INSET * 2;
  }

  private visibleW(): number {
    return this.visW > 0 ? this.visW : FALLBACK_VIS_W;
  }

  /** 节点宽 = 可见宽 + 面板高（左右各多出半径，把两端圆弧推出屏幕） */
  private nodeW(): number {
    return this.visibleW() + this.panelH();
  }

  private scaleValue(): number {
    return fontSizeScaleOf(fontScaleStore.pref, fontScaleStore.systemScale, fontScaleStore.customSize);
  }

  build() {
    /*
     * 关键几何：**面板节点比宿主可见区宽**（左右各多出半径 = 面板高/2）。
     * Stack 的 `Alignment.Top` 让超宽节点水平居中 —— 左沿落在 −半径、右沿落在
     * 可见宽 + 半径，两端的圆弧因此整个落在可见区之外，可见区里只剩一整片
     * 上下边笔直、左右铺满的矩形玻璃。
     *
     * ⚠️ 早前版本把超宽放在父容器内用 translate 偏移，被父宽钳制（barWidth 被压回
     * 屏宽 → 变成一枚大圆角药丸）。**必须让承载节点自身的宽度就是超宽值**。
     * 垂直方向由宿主负责顶部对齐（Index 的浮层用 `.align(Alignment.Top)`）。
     */
    Stack({ alignContent: Alignment.Top }) {
      // 零高测量条：只用来拿宿主可见宽度（面板节点已超宽，量不到可见宽）
      Row()
        .width('100%')
        .height(1)
        .onAreaChange((_old: Area, area: Area) => {
          const w: number = Number(area.width);
          if (w <= 0 || Math.abs(w - this.visW) < 0.5) { return; }
          this.visW = w;
        })
      HdsTabs({ barPosition: BarPosition.End }) {
        TabContent() {
        }
        .tabBar(this.PanelContent())
      }
      .barHeight(this.panelH())
      .barMode(BarMode.Fixed)
      .scrollable(false)
      .animationDuration(0)
      .barOverlap(true)
      .barBackgroundColor(Color.Transparent)
      .barBackgroundBlurStyle(BlurStyle.NONE)
      .barFloatingStyle({
        barWidth: { smallWidth: this.nodeW(), mediumWidth: this.nodeW(), largeWidth: this.nodeW() },
        barSideMargin: 0,
        barBottomMargin: 0,
        gradientMask: SPLIT_PILL_GRADIENT_MASK,
        thermoCtrl: true,
        systemMaterialEffect: materialManager.hdsEffectOf(MaterialSlot.HOME_TOP_CONTINUOUS)
      })

      .borderRadius(this.panelH() / 2)
      .clip(true)
      .width(this.nodeW())
      .height(this.panelH())

    }
    .width('100%')
    .height(this.panelH())
  }

  @Builder
  PanelContent() {
    Column() {
      // 状态栏让位：内容盒顶部先扣掉系统内距，搜索行才落在状态栏下沿
      Blank().height(Math.max(0, this.statusBarHeight - DUAL_BOX_INSET))
      this.SearchRow()
      Blank().height(this.collapsed ? 0 : DUAL_ROW_GAP)
      this.ChannelRow()
    }
    .width(this.visibleW())
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SearchRow() {
    Row() {
      // 头像：登录显示本人头像，未登录显示占位图标；点击进**个人主页**
      AvatarComponent({ url: this.avatarUrl, avatarSize: AVATAR_D, fallbackName: '我' })
        .accessibilityText('个人主页').onClick((): void => { this.onAvatar(); })
      SearchField({
        editable: false,
        onTap: (): void => { this.onSearch(); }
      })
      .layoutWeight(1)
      .margin({ left: 12 })
    }
    .width('100%')
    /*
     * 高度随收起态在 `DUAL_SEARCH_ROW_H ↔ 0` 之间变化（不是条件渲染，见 PanelContent 注释）：
     * 内容垂直居中 + `clip(true)`，收起时搜索框上下对称地被"压扁"，
     * 与面板高度的收缩同步 —— 展开时同样长回来，不会突然跳出。
     * ⚠️ 过渡同样**不挂 `.animation()`**（会拖慢频道选中态），由宿主 `animateTo` 驱动。
     */
    .height(this.collapsed ? 0 : Math.max(DUAL_SEARCH_ROW_H, searchFieldHeight(this.scaleValue()) + 8))
    .clip(true)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  /** 频道行：三个槽位等宽展开，透明背景（玻璃由整片悬浮面承载） */
  @Builder
  ChannelRow() {
    Row() {
      ForEach(this.channelLabels(), (label: string) => {
        TopLabelItem({ label, selected: this.selectedChannel === label,
          onTap: (): void => { this.onSelectChannel(label); } })
        .layoutWeight(1)
        .height('100%')
      }, (label: string) => label)
    }
    .width('100%')
    .height(homeChannelHeight(this.scaleValue()))
    .padding({ left: DUAL_BOX_INSET_X, right: DUAL_BOX_INSET_X })
  }
}
