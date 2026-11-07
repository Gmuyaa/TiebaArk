import { AnimatorResult } from '@kit.ArkUI';
import { visualThemeStore } from '../common/appearance/VisualThemeStore';
import { PaperLayout } from '../common/appearance/VisualTheme';
import { AppTheme } from '../theme/Theme';
/** 首页沉浸顶栏的搜索行与频道行。收起时隐藏搜索行及其占用高度，展开时恢复；材质由外层容器提供。 */
import { AvatarComponent } from './AvatarComponent';
import { searchFieldHeight, homeChannelHeight } from '../common/appearance/UiLayout';
import { homeDualRowHeight } from '../common/appearance/HomeTopNavStyle';
import { MaterialTabs } from './MaterialTabs';
import { SearchField } from './SearchField';
import { TopLabelItem } from './TopLabelItem';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { fontSizeScaleOf } from '../common/appearance/FontSizeScale';
import { fontScaleStore } from '../common/appearance/FontSizeScaleStore';
import { MotionEffect } from '../common/appearance/MotionConfig';
import { MotionStore, motionStore } from '../common/appearance/MotionStore';

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
  @Local revealProgress: number = 1;
  @Local motionPreferences: MotionStore = motionStore;
  private revealAnimator: AnimatorResult | undefined = undefined;
  private revealVersion: number = 0;

  aboutToAppear(): void { this.revealProgress = this.collapsed ? 0 : 1; }

  aboutToDisappear(): void {
    this.revealVersion++;
    this.revealAnimator?.cancel();
    this.revealAnimator = undefined;
  }

  @Monitor('collapsed', 'motionPreferences.enabled', 'motionPreferences.arkuiEnabled',
    'motionPreferences.selected', 'motionPreferences.systemReducedMotion')
  private syncReveal(): void {
    const version: number = ++this.revealVersion;
    this.revealAnimator?.cancel();
    this.revealAnimator = undefined;
    const target: number = this.collapsed ? 0 : 1;
    if (!motionStore.isOn(MotionEffect.MOVE) || Math.abs(target - this.revealProgress) < 0.001) {
      this.revealProgress = target;
      return;
    }
    // 同一个进度驱动原生材质尺寸、频道位置与搜索显隐；反向从当前帧续接，不压扁搜索控件。
    const animator: AnimatorResult = this.getUIContext().createAnimator({
      duration: Math.max(100, (this.collapsed ? 240 : 300) * Math.abs(target - this.revealProgress)),
      easing: 'cubic-bezier(0.2, 0, 0.2, 1)', delay: 0, fill: 'forwards',
      direction: 'normal', iterations: 1, begin: this.revealProgress, end: target
    });
    this.revealAnimator = animator;
    animator.onFrame = (progress: number): void => {
      if (version === this.revealVersion) { this.revealProgress = Math.max(0, Math.min(1, progress)); }
    };
    animator.onFinish = (): void => {
      if (version !== this.revealVersion) { return; }
      this.revealProgress = target;
      this.revealAnimator = undefined;
    };
    animator.play();
  }

  private searchRowH(): number {
    return Math.max(DUAL_SEARCH_ROW_H, searchFieldHeight(this.scaleValue()) + 8);
  }

  private searchAlpha(): number {
    // 收起时先淡出，展开有足够空间后再显现，避免与上移中的频道文字叠在一起。
    return motionStore.isOn(MotionEffect.FADE) ? this.revealProgress * this.revealProgress
      : (!this.collapsed && this.revealProgress >= 0.95 ? 1 : 0);
  }

  // 标签配色及字号由 TopLabelItem 同源维护。
  private channelLabels(): string[] {
    return ['关注', '推荐', '热榜'];
  }

  private panelH(): number {
    // 收起态高度 = 状态栏 + 频道行 + 上下内距（搜索行整段消失，不留白）
    const channel: number = homeChannelHeight(this.scaleValue());
    const content: number = channel + (homeDualRowHeight(this.scaleValue()) - channel) * this.revealProgress;
    return this.statusBarHeight + content + DUAL_BOX_INSET * 2 +
      (visualThemeStore.isPaper ? PaperLayout.BRAND_HEIGHT * this.revealProgress : 0);
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
    if (visualThemeStore.isPaper) {
      this.PaperHeader()
    } else {
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
      MaterialTabs({ slot: MaterialSlot.HOME_TOP_CONTINUOUS, barHeight: this.panelH(),
        barWidth: this.nodeW(),
        barContent: (): void => { this.PanelContent(); } })

      .borderRadius(this.panelH() / 2)
      .clip(false)
      .width(this.nodeW())
      .height(this.panelH())

    }
    .width('100%')
    .height(this.panelH())
    }
  }

  @Builder
  PaperHeader() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          Row({ space: 8 }) {
            Column() {
              Row().width(4).height(7).backgroundColor(AppTheme.EMPHASIS)
              Row().width(4).height(6).backgroundColor(AppTheme.GOLD)
              Row().width(4).height(7).backgroundColor(AppTheme.JADE)
            }.borderRadius(2).clip(true).accessibilityLevel('no')
            Text('TiebaArk').fontSize(22).fontWeight(FontWeight.Bold).fontColor(AppTheme.ACCENT_DARK)
              .layoutWeight(1).maxLines(1)
            AvatarComponent({ url: this.avatarUrl, avatarSize: AVATAR_D, fallbackName: '我' })
              .width(44).height(PaperLayout.BRAND_HEIGHT).accessibilityText('个人主页')
              .onClick((): void => { this.onAvatar(); })
          }.height(PaperLayout.BRAND_HEIGHT).width('100%')
          SearchField({ editable: false, placeholder: '搜索吧、帖子或用户',
            onTap: (): void => { this.onSearch(); } })
            .height(this.searchRowH())
        }
        .width('100%').height(PaperLayout.BRAND_HEIGHT + this.searchRowH())
        .position({ x: 0, y: -6 * (1 - this.revealProgress) })
      }
      .width('100%').height((PaperLayout.BRAND_HEIGHT + this.searchRowH()) * this.revealProgress)
      .opacity(this.searchAlpha()).clip(false)
      .hitTestBehavior(this.collapsed || this.revealProgress < 0.95 ? HitTestMode.None : HitTestMode.Default)
      .accessibilityLevel(this.collapsed ? 'no-hide-descendants' : 'auto')
      Blank().height(DUAL_ROW_GAP * this.revealProgress)
      this.ChannelRow()
    }
    .width('100%').height(this.panelH())
    .padding({ top: this.statusBarHeight + 4, left: 16, right: 16, bottom: 4 })
    .linearGradient({ angle: 115, colors: [[AppTheme.HEADER_START, 0], [AppTheme.HEADER_END, 1]] })
    .border({ width: { bottom: 0.5 }, color: AppTheme.DIVIDER })
    .id('paper-home-header')
  }

  @Builder
  PanelContent() {
    Column() {
      // 状态栏让位：内容盒顶部先扣掉系统内距，搜索行才落在状态栏下沿
      Blank().height(Math.max(0, this.statusBarHeight - DUAL_BOX_INSET))
      this.SearchRow()
      Blank().height(DUAL_ROW_GAP * this.revealProgress)
      this.ChannelRow()
    }
    .width(this.visibleW())
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SearchRow() {
    Stack({ alignContent: Alignment.TopStart }) {
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
      .height(this.searchRowH())
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .position({ x: 0, y: -6 * (1 - this.revealProgress) })
    }
    .width('100%').height(this.searchRowH() * this.revealProgress)
    .opacity(this.searchAlpha())
    // 搜索本体不参与高度压缩，也不裁剪官方材质阴影。
    .clip(false)
    .hitTestBehavior(this.collapsed || this.revealProgress < 0.95 ? HitTestMode.None : HitTestMode.Default)
    .accessibilityLevel(this.collapsed ? 'no-hide-descendants' : 'auto')
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
