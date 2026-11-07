import { visualThemeStore, VisualThemeStore } from '../common/appearance/VisualThemeStore';
import { PaperLayout } from '../common/appearance/VisualTheme';
/**
 * 应用外壳：HdsNavigation 承载共享内容栈，MaterialTabs 承载首页、进吧、消息和我的。
 * 底栏使用自定义 tabBuilder 绘制图标与文字，背景优先使用 ArkUI 官方材质，设备不支持时回退 HDS。
 * Settings、Login、WebLogin 继续通过 router 打开，内容页面走 AppRoute。
 */

import { fontScaleStore } from '../common/appearance/FontSizeScaleStore';
import { fontSizeScaleOf } from '../common/appearance/FontSizeScale';
import { AnimatorResult, curves, display, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { authSession, AuthSession } from '../auth/AuthSession';
import { NotifyUnreadVM, notifyUnreadVM } from '../viewmodel/NotifyUnreadVM';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { HdsNavigation, HdsTabsController, BlurStrategy, ScrollEffectType } from '@kit.UIDesignKit';
import { ThreadDetailPage } from './ThreadDetail';
import { portraitUrl } from '../model/ThreadDetail';
import { ForumPage } from './ForumPage';
import { ForumSquarePage } from './ForumSquarePage';
import { SearchResultPage } from './SearchResultPage';
import { SearchPage } from './SearchPage';
import { ScanPage } from './ScanPage';
import { VideoFeedPage } from './VideoFeedPage';
import { ComposePage } from './ComposePage';
import { HomeComposeButton } from '../components/HomeComposeButton';
import { MyListPage } from './MyListPage';
import { HotTopicPage } from './HotTopicPage';
import { UserPage } from './UserPage';
import { DirectoryPage } from './DirectoryPage';
import { ForumMemberPage } from './ForumMemberPage';
import { NotifyListPage } from './NotifyListPage';
import {
  AppRoute, ForumPageParams, HotTopicParams, MyListParams, NavigationService,
  NotifyListParams, SearchResultParams, ThreadDetailParams, UserPageParams, DirectoryPageParams,
  ForumMemberPageParams
} from '../navigation/AppNavigation';
import { materialManager } from '../common/material/MaterialManager';
import { MotionEffect } from '../common/appearance/MotionConfig';
import { motionStore, MotionStore } from '../common/appearance/MotionStore';
import { motionDuration } from '../common/appearance/MotionPolicy';
import { MaterialTabs } from '../components/MaterialTabs';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { ForumListView } from '../components/ForumListView';

import { HomeTopNav } from '../components/HomeTopNav';
import { HomeDualRowTopBar } from '../components/HomeDualRowTopBar';
import { homeTopNavStore, HomeTopNavStore } from '../common/appearance/HomeTopNavStore';
import {
  HomeTopNavStyle, homeTopNavRowHeight
} from '../common/appearance/HomeTopNavStyle';
import { ImageViewer } from '../components/ImageViewer';
import { closeImageTransition, imageLayerRetentionTransition } from '../components/ImageTransition';
import { FollowView } from '../components/FollowView';

import { MessageView } from '../components/MessageView';
import { ProfileView } from '../components/ProfileView';
import { AppTheme } from '../theme/Theme';
import { bottomBarSideMarginVp } from '../common/appearance/BottomBarWidth';
import { themeModeStore } from '../common/appearance/ThemeModeStore';
import { homeNavigationHideStore } from '../common/appearance/HomeNavigationHideStore';
import { readStatusBarVp } from '../utils/SafeArea';
import { avatarTrace } from '../utils/AvatarTrace';
import { ForegroundRefresh, foregroundRefresh } from '../viewmodel/ForegroundRefresh';

/** 一个 Tab 槽位的静态描述 */
interface TabSlot {
  /** 未选中（线框版） */
  icon: Resource;
  /** 选中（实心版）。⚠️ `person_crop_circle` 无线框版 → 「我的」两态同资源，靠颜色区分 */
  iconFill: Resource;
  label: string;
}

interface BottomBarPose {
  scale: number;
  offsetY: number;
  alpha: number;
}

/** 底栏首页连续点击的识别窗口；首次点击始终立即回顶。 */
const HOME_DOUBLE_TAP_MS: number = 350;

@Entry
@ComponentV2
struct Index {

  @Local slots: TabSlot[] = [
    { icon: $r('sys.symbol.house'), iconFill: $r('sys.symbol.house_fill'), label: '首页' },
    { icon: $r('sys.symbol.heart'), iconFill: $r('sys.symbol.heart_fill'), label: '进吧' },
    { icon: $r('sys.symbol.envelope'), iconFill: $r('sys.symbol.envelope_fill'), label: '消息' },
    { icon: $r('sys.symbol.person_crop_circle_fill'), iconFill: $r('sys.symbol.person_crop_circle_fill'), label: '我的' }
  ];

  /** 当前页签，与 HDS Tab 切换同步，用于保持页面状态 */
  @Local currentIndex: number = 0;
  @Local pageVisible: boolean = true;
  @Local motionPreferences: MotionStore = motionStore;
  @Local foreground: ForegroundRefresh = foregroundRefresh;
  @Local unread: NotifyUnreadVM = notifyUnreadVM;
  @Local unreadAuth: AuthSession = authSession;
  private unreadTimer: number = -1;
  private foregroundRevision: number = foregroundRefresh.revision;

  /** 外壳统一读取计数，消息页与底栏共用；不自动读取会消费未读的分类列表。 */
  @Monitor('foreground.isForeground', 'foreground.revision', 'pageVisible', 'homeNavVisible',
    'unreadAuth.snapshot', 'unread.previewRevision')
  private syncUnreadRefresh(): void {
    this.stopUnreadRefresh();
    this.unread.syncAccount();
    if (!this.pageVisible || !this.foreground.isForeground || !authSession.isLoggedIn()) { return; }
    void this.reloadUnread();
    this.unreadTimer = setInterval((): void => {
      if (this.pageVisible && this.foreground.isForeground && authSession.isLoggedIn()) {
        void this.reloadUnread();
      }
    }, 30000);
  }

  private stopUnreadRefresh(): void {
    if (this.unreadTimer !== -1) { clearInterval(this.unreadTimer); this.unreadTimer = -1; }
  }

  private async reloadUnread(): Promise<void> {
    await this.unread.refresh(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

  @Monitor('foreground.revision', 'pageVisible', 'homeNavVisible')
  onForegroundRefresh(): void {
    if (!this.pageVisible || !this.homeNavVisible || this.foregroundRevision === this.foreground.revision) { return; }
    this.foregroundRevision = this.foreground.revision;
    this.refreshMyProfile();
  }
  @Local viewerUrls: string[] = [];
  @Local viewerIndex: number = 0;
  @Local homeScrollHidden: boolean = false;
  @Local private homeBottomScale: number = 1;
  @Local private bottomBarCollapsed: boolean = false;
  private bottomMotionVersion: number = 0;
  private bottomAnimator: AnimatorResult | undefined = undefined;
  @Local private bottomOffsetY: number = 0;
  private bottomAlpha: number = 1;
  @Local homePillRevealReady: boolean = true;
  @Local homeSelectedChannel: string = '推荐';
  /** HDS builder 的显式响应桥：同时覆盖冷启动异步读偏好与设置页即时切换。 */
  @Local topNavPreferences: HomeTopNavStore = homeTopNavStore;
  @Local visualPreferences: VisualThemeStore = visualThemeStore;
  @Local homeTopNavRowH: number = 54;
  @Local homeTopNavStyle: HomeTopNavStyle = homeTopNavStore.style;

  @Monitor('topNavPreferences.style', 'visualPreferences.theme')
  private syncHomeTopNavStyle(): void {
    this.homeTopNavStyle = visualThemeStore.isPaper ? HomeTopNavStyle.OFFICIAL_DUAL_ROW : this.topNavPreferences.style;
  }
  @Local homeViewportWidth: number = 0;
  @Local homeViewportHeight: number = 0;
  @Local homeStatusBarH: number = 39;
  /** HDS 会将超高的自定义内容居中；额外补 32vp 后频道行回到安全区下方。 */
  private readonly homeTitleContentOffsetVp: number = 32;
  @Local bottomMaskVisible: boolean = true;
  /**
   * 首页 NavBar 是否可见（Root 导航压入子页时为 false）。
   * `@Local` 而非普通成员：值 5 的顶栏玻璃浮层要按它即时隐藏（进帖子详情时不能浮在上面）。
   */
  @Local homeNavVisible: boolean = true;
  private statusBarRequestVersion: number = 0;
  private lastHomeTapMs: number = 0;
  private homeScrollToTop: () => void = (): void => {};
  private homeRefresh: () => void = (): void => {};
  private homeChangeChannel: (label: string) => void = (_label: string): void => {};

  @Local barSideMargin: number = AppTheme.BAR_SIDE;
  /** ArkUI 与 HDS 各使用自己的控制器，避免兼容承载器截获原生页签切换。 */
  private tabsController: TabsController = new TabsController();
  private fallbackTabsController: HdsTabsController = new HdsTabsController();

  private appNavStack: NavPathStack = new NavPathStack();
  private homeRecommendScroller: ListScroller = new ListScroller();
  private homeFollowScroller: ListScroller = new ListScroller();
  private homeHotScroller: ListScroller = new ListScroller();

  @Monitor('motionPreferences.enabled', 'motionPreferences.arkuiEnabled', 'motionPreferences.selected',
    'motionPreferences.systemReducedMotion')
  private onMotionPreferenceChanged(): void {
    this.appNavStack.disableAnimation(!motionStore.isOn(MotionEffect.MOVE));
    if (this.bottomAnimator !== undefined) { this.animateBottomBar(this.bottomNavigationHidden()); }
  }

  pageTransition() {
    if (!motionStore.isOn(MotionEffect.MOVE)) {
      PageTransitionEnter({ duration: 0 })
      PageTransitionExit({ duration: 0 })
    }
  }

  /** 首页查看器独占系统返回；普通内容页仍由共享导航栈处理。 */
  onBackPress(): boolean {
    if (this.viewerUrls.length === 0) { return false; }
    closeImageTransition(this.getUIContext(), (): void => {
      this.viewerUrls = [];
      this.viewerIndex = 0;
    });
    return true;
  }

  private refreshMyProfile(): void {
    if (!this.pageVisible || !this.homeNavVisible || this.viewerUrls.length > 0) { return; }
    const showsOwnAvatar: boolean = this.currentIndex === 3 ||
      (this.currentIndex === 0 && this.homeTopNavStyle === HomeTopNavStyle.OFFICIAL_DUAL_ROW);
    if (showsOwnAvatar && authSession.isLoggedIn()) {
      void this.foreground.refreshAvatar(
        this.getUIContext().getHostContext() as common.UIAbilityContext);
    }
  }
  onPageShow(): void {
    this.appNavStack.disableAnimation(!motionStore.isOn(MotionEffect.MOVE));
    // uiMaterial 的能力查询依赖当前 UI 容器，不能放在 Ability.onCreate 的偏好加载中。
    this.getUIContext().runScopedTask((): void => { materialManager.refreshCapabilities(); });
    this.pageVisible = true;
    // 只记"外壳页真的回到前台"（含我们页当前页签），用来和状态发布时间对齐。
    avatarTrace('page-visible', 0, `page=index tab=${this.currentIndex}`);
    // 设置页里可能刚换过顶栏样式：回前台时同步一次（值没变则不会触发重绘）
    this.syncHomeTopNavStyle();
    this.refreshMyProfile();
  }

  aboutToAppear(): void {
    this.syncHomeTopNavStyle();
    NavigationService.setStack(this.appNavStack);
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    readStatusBarVp(context).then((vp: number) => { this.homeStatusBarH = vp; }).catch(() => {});

    const widthVp: number = px2vp(display.getDefaultDisplaySync().width);
    this.barSideMargin = bottomBarSideMarginVp(widthVp);
    this.syncUnreadRefresh();
  }

  aboutToDisappear(): void {
    this.stopUnreadRefresh();
    this.unread.reset();
  }

  onPageHide(): void {
    this.pageVisible = false;
    this.setHomeScrollHidden(false);
  }

  private statusBarHidden(): boolean {
    return this.homeScrollHidden && homeNavigationHideStore.hideStatusBar;
  }

  private topNavigationHidden(): boolean {
    return (this.homeScrollHidden || !this.homePillRevealReady) &&
      homeNavigationHideStore.hideTopNavigation;
  }

  private bottomNavigationHidden(): boolean {
    return this.homeScrollHidden && homeNavigationHideStore.hideBottomNavigation;
  }

  private bottomBarScaleFactor(): number {
    return materialManager.useArkUI && motionStore.isOn(MotionEffect.SCALE) ? this.homeBottomScale : 1;
  }

  /** 浮面统一以展开时的中心定位；补偿缩小后的半高差，避免底边锚点与控制器平移叠加。 */
  private bottomBarBottomMargin(): number {
    if (!materialManager.useArkUI) { return AppTheme.BAR_SAFE_H; }
    return AppTheme.BAR_SAFE_H + AppTheme.BAR_CONTENT_H * (1 - this.bottomBarScaleFactor()) / 2 -
      (motionStore.isOn(MotionEffect.MOVE) ? this.bottomOffsetY : 0);
  }

  /** 宽高、前景与底距共用声明进度；控制器仅调整透明度，不再参与定位。 */
  private setBottomBarPose(scale: number, offsetY: number, alpha: number): void {
    this.homeBottomScale = scale;
    this.bottomOffsetY = offsetY;
    this.bottomAlpha = alpha;
    this.tabsController.setTabBarOpacity(motionStore.isOn(MotionEffect.FADE) ? alpha : 1);
  }

  private animateBottomBar(hidden: boolean): void {
    if (!materialManager.useArkUI) { return; }
    if (!hidden && !this.bottomAnimator && this.homeBottomScale === 1 &&
      this.bottomOffsetY === 0 && this.bottomAlpha === 1) { return; }
    const interrupted: boolean = this.bottomAnimator !== undefined;
    const version: number = ++this.bottomMotionVersion;
    this.bottomAnimator?.cancel();
    this.bottomAnimator = undefined;
    this.bottomBarCollapsed = false;
    const hiddenY: number = AppTheme.BAR_CONTENT_H + AppTheme.BAR_SAFE_H;
    const context: UIContext = this.getUIContext();
    if (!motionStore.isOn(MotionEffect.MOVE) && !motionStore.isOn(MotionEffect.SCALE) && !motionStore.isOn(MotionEffect.FADE)) {
      context.animateTo({ duration: 0 }, (): void => {
        this.setBottomBarPose(hidden ? 0.25 : 1, hidden ? hiddenY : 0, hidden ? 0 : 1);
        this.tabsController.setTabBarOpacity(hidden ? 0 : 1);
        this.bottomBarCollapsed = hidden;
      });
      return;
    }
    // 中途反向直接续接当前姿态，不重新提起/放大到固定关键帧。
    const spring: boolean = motionStore.isOn(MotionEffect.SPRING) && !interrupted;
    const start: BottomBarPose = { scale: this.homeBottomScale, offsetY: this.bottomOffsetY, alpha: this.bottomAlpha };
    const animator: AnimatorResult = context.createAnimator({ duration: spring ? (hidden ? 370 : 500) : 280,
      easing: 'linear', delay: 0, fill: 'forwards', direction: 'normal', iterations: 1, begin: 0, end: 1 });
    this.bottomAnimator = animator;
    animator.onFrame = (progress: number): void => {
      if (version === this.bottomMotionVersion) { this.renderBottomBarFrame(progress, hidden, spring, start); }
    };
    animator.onFinish = (): void => {
      if (version !== this.bottomMotionVersion) { return; }
      this.setBottomBarPose(hidden ? 0.25 : 1, hidden ? hiddenY : 0, hidden ? 0 : 1);
      if (hidden && this.bottomNavigationHidden()) { this.tabsController.setTabBarOpacity(0); }
      // 控制器变换会被后续浮面布局重置；完成后以声明状态同时撤销栏面、布局与前景。
      this.bottomBarCollapsed = hidden && this.bottomNavigationHidden();
      if (!hidden && !this.homeScrollHidden) { this.bottomMaskVisible = true; }
      this.bottomAnimator = undefined;
    };
    animator.play();
  }

  /** 同机酷安参考：轻提后向下缩淡；展开上提放大后回落。每帧同步原生尺寸与前景，避免跨组件关键帧跳变。 */
  private renderBottomBarFrame(progress: number, hidden: boolean, spring: boolean, start: BottomBarPose): void {
    const end: BottomBarPose = { scale: hidden ? 0.25 : 1,
      offsetY: hidden ? AppTheme.BAR_CONTENT_H + AppTheme.BAR_SAFE_H : 0, alpha: hidden ? 0 : 1 };
    const split: number = hidden ? 190 / 370 : 200 / 500;
    const lift: BottomBarPose = { scale: hidden ? 0.95 : 1.015, offsetY: hidden ? -16 : -18, alpha: 1 };
    const first: boolean = !spring || progress <= split;
    const from: BottomBarPose = first ? start : lift;
    const to: BottomBarPose = !spring || !first ? end : lift;
    const raw: number = Math.max(0, Math.min(1, !spring ? progress : (first ? progress / split : (progress - split) / (1 - split))));
    const blend: number = spring && !first && hidden ? raw * raw : 1 - Math.pow(1 - raw, 3);
    this.setBottomBarPose(from.scale + (to.scale - from.scale) * blend,
      from.offsetY + (to.offsetY - from.offsetY) * blend, from.alpha + (to.alpha - from.alpha) * blend);
  }

  /** 首页滚动共用一个方向信号，三处区域分别按设置决定是否隐藏。 */
  private setHomeScrollHidden(hidden: boolean): void {
    const target: boolean = hidden && this.currentIndex === 0 && this.homeNavVisible;
    if (target === this.homeScrollHidden) {
      return;
    }
    const version: number = ++this.statusBarRequestVersion;
    if (target && homeNavigationHideStore.hideBottomNavigation) {
      // HDS 的 gradientMask 不随栏体的 opacity 消失，收起前先立即撤掉浅色蒙层。
      animateTo({ duration: 0 }, () => {
        this.bottomMaskVisible = false;
      });
    }
    animateTo({
      duration: motionDuration(target ? 300 : 440),
      curve: target || !motionStore.isOn(MotionEffect.MOVE) || !motionStore.isOn(MotionEffect.SPRING)
        ? Curve.EaseIn : curves.springMotion(0.38, 0.64),
      onFinish: () => {
        if (version !== this.statusBarRequestVersion) { return; }
        if (!target) {
          this.bottomMaskVisible = true;
        }
      }
    }, () => {
      this.homeScrollHidden = target;
      if (target) {
        this.homePillRevealReady = false;
      }
    });
    this.animateBottomBar(target && homeNavigationHideStore.hideBottomNavigation);
    if (!target) {
      // 原生顶栏滚动效果恢复后再显示胶囊，避开材质首次取样的浅灰过渡帧。
      setTimeout((): void => {
        if (version === this.statusBarRequestVersion && !this.homeScrollHidden) {
          this.homePillRevealReady = true;
        }
      }, motionDuration(120));
    }
    const targetStatusHidden: boolean = target && homeNavigationHideStore.hideStatusBar;
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    window.getLastWindow(context).then(async (win: window.Window): Promise<void> => {
      if (version !== this.statusBarRequestVersion) {
        return;
      }
      await win.setSpecificSystemBarEnabled('status', !targetStatusHidden, motionStore.isOn(MotionEffect.MOVE));
      if (!targetStatusHidden) {
        let contentColor: string;
        try {
          const color: number = context.resourceManager
            .getColorSync($r('app.color.app_status_bar_content').id);
          contentColor = `#${(color & 0xFFFFFF).toString(16).padStart(6, '0').toUpperCase()}`;
        } catch (e) {
          contentColor = themeModeStore.isDark ? '#F2F3F4' : '#1B1B1B';
        }
        await win.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          statusBarContentColor: contentColor
        });
      }
      if (version !== this.statusBarRequestVersion) {
        await win.setSpecificSystemBarEnabled('status', !this.statusBarHidden(), motionStore.isOn(MotionEffect.MOVE));
      }
    }).catch((e: Error) => {
      hilog.warn(0x0, 'TiebaTop', 'status bar visibility failed: %{public}s', e.message);
      if (version === this.statusBarRequestVersion) {
        this.homeScrollHidden = false;
        this.animateBottomBar(false);
      }
    });
  }

  build() {
    /** 首页由 HdsNavigation 承载，共享栈通过 PageMap 注册内容页面。 */
    Stack() {
    // 大图浮层放在整个导航容器之外，覆盖标题栏与系统安全区。
    HdsNavigation(this.appNavStack) {
      Stack({ alignContent: Alignment.BottomEnd }) {

    MaterialTabs({ controller: this.tabsController, fallbackController: this.fallbackTabsController,
      slot: MaterialSlot.BOTTOM_BAR,
      barHeight: AppTheme.BAR_CONTENT_H * this.bottomBarScaleFactor(),
      barWidth: this.barSideMargin * 4 * this.bottomBarScaleFactor(),
      barSideMargin: this.barSideMargin, barBottomMargin: this.bottomBarBottomMargin(),
      barVisible: materialManager.useArkUI ? !this.bottomBarCollapsed : !this.bottomNavigationHidden(),
      maskColor: this.bottomMaskVisible ? AppTheme.BOTTOM_BAR_MASK : Color.Transparent,
      maskHeight: this.bottomMaskVisible ? 92 : 0,
      pages: (): void => { this.HomePages(); },
      onChange: (index: number): void => {
        this.currentIndex = index;
        this.refreshMyProfile();
        if (index !== 0) { this.lastHomeTapMs = 0; this.setHomeScrollHidden(false); }
      }
    })
    .width('100%')
    .height('100%')

    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor(AppTheme.BG)
      // 看图时保留材质按钮，由上层 Viewer 覆盖；关图不重新创建阴影承载层。
      if (this.currentIndex === 0 && this.homeNavVisible) {
        HomeComposeButton({ viewportWidth: this.homeViewportWidth, viewportHeight: this.homeViewportHeight,
          topInset: this.homeStatusBarH + this.homeTopNavRowH,
          active: this.pageVisible && this.viewerUrls.length === 0,
          onCompose: (): void => { NavigationService.openCompose(); } })
      }
      } // Stack
      .onAreaChange((_old: Area, area: Area): void => {
        this.homeViewportWidth = Number(area.width);
        this.homeViewportHeight = Number(area.height);
      })
    }
    .navDestination(this.PageMap)
    .onNavBarStateChange((isVisible: boolean) => {
      this.homeNavVisible = isVisible;
      if (!isVisible) {
        this.setHomeScrollHidden(false);
      }
    })

    .titleBar({
      style: {

        // 所有首页材质由 MaterialTabs 提供，导航标题栏不再叠加另一层 HDS 背景。
        blurStrategy: BlurStrategy.DISABLE,
        scrollEffectOpts: { enableScrollEffect: false,
          scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR },
        scrollEffectStyle: { backgroundStyle: { backgroundColor: Color.Transparent,
          maskExtraHeight: 0, blurRadius: 0 } },
        originalStyle: { backgroundStyle: { backgroundColor: Color.Transparent,
          maskExtraHeight: 0, blurRadius: 0 } }

      },
      /*
       * 顶栏内容**结构对所有样式一致**（`stackBuilder` 一个入口，内部按当前样式分叉）：
       * 这样运行时切换样式时 builder 重跑就能换内容 —— HDS 只在创建时固化 style 配置，
       * builder 内容本身是响应式的（0~4 四套样式即时切换就是靠这条）。
       * 「官方沉浸」（值 5）**不在标题栏里画任何东西**：它的玻璃由页面根 Stack 的
       * 浮层承载（见 build 里的 HomeDualRowOverlay），避免标题栏顶部那段系统固有
       * 标题区（真机实测 73vp）把双排整体压低、首卡被压在玻璃后面。
       */
      content: {
        stackBuilder: (): void => { this.HomeTitleBarContent(); }
      }
    })
    .hideTitleBar(this.currentIndex !== 0 || this.viewerUrls.length > 0)
    .bindToScrollable([this.homeRecommendScroller, this.homeFollowScroller, this.homeHotScroller])
    .systemBarStyle(
      { statusBarContentColor: this.viewerUrls.length > 0 || themeModeStore.isDark ? '#F2F3F4' : '#1B1B1B' },
      { statusBarContentColor: this.viewerUrls.length > 0 || themeModeStore.isDark ? '#F2F3F4' : '#1B1B1B' }
    )
    .mode(NavigationMode.Stack)

      if (this.homeTopNavStyle === HomeTopNavStyle.OFFICIAL_DUAL_ROW
        && this.currentIndex === 0 && this.viewerUrls.length === 0) {
        this.HomeDualRowOverlay()
      }
      if (this.viewerUrls.length > 0) {
        ImageViewer({ imageUrls: this.viewerUrls, initialIndex: this.viewerIndex,
          onClose: (): void => { this.viewerUrls = []; this.viewerIndex = 0; } })
          .zIndex(100)
          .transition(imageLayerRetentionTransition())
      }
    }
    .width('100%').height('100%')
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  HomePages() {
      TabContent() {
        ForumListView({
          onOpenImages: (urls: string[], index: number): void => {
            this.viewerIndex = index;
            this.viewerUrls = urls;
          },
          recommendScroller: this.homeRecommendScroller,
          followScroller: this.homeFollowScroller,
          hotScroller: this.homeHotScroller,

          topNavigationRowHeight: this.homeTopNavStyle === HomeTopNavStyle.OFFICIAL_DUAL_ROW
            ? homeTopNavRowHeight(this.homeTopNavStyle, fontSizeScaleOf(fontScaleStore.pref,
              fontScaleStore.systemScale, fontScaleStore.customSize)) +
              (visualThemeStore.isPaper ? PaperLayout.BRAND_HEIGHT : 0) : this.homeTopNavRowH,
          topNavigationHidden: this.topNavigationHidden(),
          scrollNavigationHidden: this.homeScrollHidden,
          onScrollNavigationHiddenChange: (hidden: boolean): void => {
            this.setHomeScrollHidden(hidden);
          },
          onHomeActionsReady: (scrollTop: () => void, refresh: () => void): void => {
            this.homeScrollToTop = scrollTop;
            this.homeRefresh = refresh;
          },
          onChannelActionsReady: (change: (label: string) => void): void => {
            this.homeChangeChannel = change;
          },
          onChannelChanged: (label: string): void => { this.homeSelectedChannel = label; }
        })
      }
      .tabBar(this.tabBuilder('首页', 0, this.slots[0]))

      TabContent() {

        FollowView({ bottomBarOcclusion: AppTheme.BAR_TOTAL_H,
          active: this.pageVisible && this.homeNavVisible && this.currentIndex === 1 })
      }
      .tabBar(this.tabBuilder('进吧', 1, this.slots[1]))

      TabContent() {

        MessageView({ active: this.pageVisible && this.homeNavVisible && this.currentIndex === 2 })
      }
      .tabBar(this.tabBuilder('消息', 2, this.slots[2]))

      TabContent() {
        ProfileView()
      }
      .tabBar(this.tabBuilder('我的', 3, this.slots[3]))
  }

  /** 整片沉浸顶栏的浮层容器，高度随搜索行收起状态变化。 */
  @Builder
  HomeDualRowOverlay() {
    HomeDualRowTopBar({
      statusBarHeight: this.homeStatusBarH,
      selectedChannel: this.homeSelectedChannel,
      // 上滑收起：只留频道行（沿用「隐藏顶部导航栏」开关与既有滚动方向信号）
      collapsed: this.topNavigationHidden(),
      avatarUrl: this.homeAvatarUrl(),
      onSelectChannel: (label: string): void => { this.homeChangeChannel(label); },
      onSearch: (): void => { NavigationService.openSearchPage(); },

      onAvatar: (): void => { this.openMyProfile(); }
    })
    // 压在内容层之上（大图查看器 zIndex 100 仍在其上）；
    // `.position` 绝对定位到屏幕左上：面板比屏幕宽（两端圆弧推出可见区），
    // 水平方向由组件内部 Stack 居中，垂直方向必须钉在屏幕顶（根 Stack 默认垂直居中）。
    .position({ x: 0, y: 0 })
    // 子页覆盖期间保留材质节点，返回时恢复显示，避免每次 pop 都重建整片原生材质。
    .visibility(this.homeNavVisible ? Visibility.Visible : Visibility.Hidden)
    .hitTestBehavior(this.homeNavVisible ? HitTestMode.Default : HitTestMode.None)
    .zIndex(50)
  }

  /** 右上角头像的去处：登录 → 个人主页；未登录 → 「我的」页签（登录引导） */
  private openMyProfile(): void {
    if (!authSession.isLoggedIn()) {
      this.switchTo(3);
      return;
    }
    NavigationService.openUser({
      uid: authSession.snapshot.uid,
      portrait: authSession.snapshot.portrait,
      name: authSession.snapshot.nickname.length > 0
        ? authSession.snapshot.nickname : authSession.snapshot.userName
    });
  }

  /** 本人头像 URL（未登录返回空串 → 组件显示占位图标） */
  private homeAvatarUrl(): string {
    if (!authSession.isLoggedIn()) { return ''; }
    return portraitUrl(authSession.snapshot.portrait, authSession.avatarRevision);
  }

  /** 自定义顶栏内容由 HomeTopNav 承载，页面负责位置与滚动联动。 */
  @Builder
  HomeTitleBarContent() {
    if (this.homeTopNavStyle !== HomeTopNavStyle.OFFICIAL_DUAL_ROW) {
      Stack({ alignContent: Alignment.TopStart }) {
        HomeTopNav({
          style: this.homeTopNavStyle,
          statusBarHeight: this.homeStatusBarH,
          backdropInset: 16,
          selectedChannel: this.homeSelectedChannel,
          hidden: this.topNavigationHidden(),
          onRowHeightChanged: (height: number): void => { this.homeTopNavRowH = height; },
          onSelectChannel: (label: string): void => { this.homeChangeChannel(label); },
          // 搜索继续走既有导航入口（NavigationService.openSearchPage）
          onSearch: (): void => { NavigationService.openSearchPage(); }
        })
        /*
         * ⚠️ 边距与状态栏避让**必须由宿主下发**：同样的 padding 写进 `HomeTopNav` 内部时，
         * HDS 会把那一行压成 19px 高（真机实测，见该组件 build() 的注释）。写法与改动前的
         * `HomeChannelPills` 逐字一致 —— 同样的 `width('100%')` + 同样的 padding。
         */
        .width('100%')
        .padding({ top: this.homeStatusBarH + 8 + this.homeTitleContentOffsetVp,
          left: 16, right: 16 })
      }
      .width('100%')
      .height(this.homeStatusBarH + this.homeTopNavRowH + this.homeTitleContentOffsetVp)
    }
  }

  @Builder
  PageMap(name: string, pageInfos: Object) {
    if (name === AppRoute.USER_PAGE) {
      UserPage({ routeParams: pageInfos as UserPageParams })
    } else if (name === AppRoute.DIRECTORY_PAGE) {
      DirectoryPage({ routeParams: pageInfos as DirectoryPageParams })
    } else if (name === AppRoute.THREAD_DETAIL) {
      ThreadDetailPage({ routeParams: pageInfos as ThreadDetailParams })
    } else if (name === AppRoute.FORUM_PAGE) {
      ForumPage({ routeParams: pageInfos as ForumPageParams })
    } else if (name === AppRoute.FORUM_SQUARE_PAGE) {
      ForumSquarePage()
    } else if (name === AppRoute.SEARCH_RESULT_PAGE) {
      SearchResultPage({ routeParams: pageInfos as SearchResultParams })
    } else if (name === AppRoute.SEARCH_PAGE) {

      SearchPage()
    } else if (name === AppRoute.SCAN_PAGE) {
      ScanPage()
    } else if (name === AppRoute.COMPOSE_PAGE) {
      ComposePage()
    } else if (name === AppRoute.VIDEO_FEED_PAGE) {
      VideoFeedPage()
    } else if (name === AppRoute.MY_LIST_PAGE) {
      MyListPage({ routeParams: pageInfos as MyListParams })
    } else if (name === AppRoute.HOT_TOPIC_PAGE) {
      HotTopicPage({ routeParams: pageInfos as HotTopicParams })
    } else if (name === AppRoute.FORUM_MEMBER_PAGE) {
      ForumMemberPage({ routeParams: pageInfos as ForumMemberPageParams })
    } else if (name === AppRoute.NOTIFY_LIST_PAGE) {
      NotifyListPage({ routeParams: pageInfos as NotifyListParams })
    }
  }

  private slotColor(idx: number): ResourceColor {
    return idx === this.currentIndex ? AppTheme.NAV_SELECTED : AppTheme.NAV_TEXT;
  }

  /** 已在首页时，单击回顶；窗口内第二次点击刷新当前频道。 */
  private handleHomeRetap(): void {
    const now: number = Date.now();
    if (this.lastHomeTapMs > 0 && now - this.lastHomeTapMs <= HOME_DOUBLE_TAP_MS) {
      this.lastHomeTapMs = 0;
      this.homeRefresh();
      return;
    }
    this.lastHomeTapMs = now;
    this.homeScrollToTop();
  }

  @Builder
  tabBuilder(label: string, index: number, slot: TabSlot) {

    Column({ space: 2 * this.bottomBarScaleFactor() }) {
      if (index === 2 && this.unread.counts.total() > 0) {
        Badge({ count: this.unread.counts.total(), maxCount: 99,
          position: { x: 17 * this.bottomBarScaleFactor(), y: -4 * this.bottomBarScaleFactor() },
          style: { badgeSize: 16 * this.bottomBarScaleFactor(), fontSize: 10 * this.bottomBarScaleFactor(),
            fontWeight: FontWeight.Medium,
            badgeColor: AppTheme.NOTIFY_BADGE_BACKGROUND, color: AppTheme.NOTIFY_BADGE_TEXT } }) {
          this.TabIcon(index, slot)
        }.width(24 * this.bottomBarScaleFactor()).height(24 * this.bottomBarScaleFactor())
        .accessibilityLevel('no')
      } else {
        this.TabIcon(index, slot)
      }
      Text(label)
        .fontSize(10 * this.bottomBarScaleFactor())
        .fontWeight(visualThemeStore.isPaper ? (index === this.currentIndex ? FontWeight.Bold : FontWeight.Medium) : FontWeight.Normal)
        .maxFontScale(1)
        .fontColor(this.slotColor(index))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .id(`main-tab-${index}`)
    .accessibilityGroup(true)
    .accessibilityText(this.tabAccessibility(label, index))
    .accessibilitySelected(this.currentIndex === index)
    .visibility(this.bottomBarCollapsed ? Visibility.Hidden : Visibility.Visible)
    .hitTestBehavior(this.bottomNavigationHidden() ? HitTestMode.None : HitTestMode.Default)
    .onClick(() => {
      if (this.currentIndex === index) {
        if (index === 0) {
          this.handleHomeRetap();
        }
        return;
      }
      this.lastHomeTapMs = 0;
      // 先改 currentIndex（驱动配色），再让页签承载器切页 —— 顺序有意如此
      this.currentIndex = index;
      if (index !== 0) {
        this.setHomeScrollHidden(false);
      }
      this.changeTabIndex(index);
    })
  }

  @Builder
  TabIcon(index: number, slot: TabSlot) {
    SymbolGlyph(index === this.currentIndex ? slot.iconFill : slot.icon)
      .fontSize(24 * this.bottomBarScaleFactor()).maxFontScale(1)
      .fontColor([this.slotColor(index)]).accessibilityLevel('no')
  }

  private tabAccessibility(label: string, index: number): string {
    if (index !== 2) { return label; }
    if (!this.unread.loaded) { return `${label}，未读数${this.unread.error.length > 0 ? '读取失败' : '尚未读取'}`; }
    const count: number = this.unread.counts.total();
    return `${label}，${count > 0 ? `${count}条未读` : '没有未读消息'}` +
      (this.unread.error.length > 0 ? '，上次结果，刷新失败' : '');
  }

  /**
   * 点击某格：**先改 `currentIndex`（驱动底栏配色），再让 Tabs 切页**。
   * 顺序有意如此 —— 颜色先落定、页面随后跟上，避免"页面已经过去但高亮还没动"的那一帧。
   */
  private switchTo(idx: number): void {
    if (idx === this.currentIndex) {
      if (idx === 0) {
        this.handleHomeRetap();
      }
      return;
    }
    this.lastHomeTapMs = 0;
    this.currentIndex = idx;
    if (idx !== 0) {
      this.setHomeScrollHidden(false);
    }
    this.changeTabIndex(idx);
  }

  private changeTabIndex(index: number): void {
    if (materialManager.useArkUI) { this.tabsController.changeIndex(index); }
    else { this.fallbackTabsController.changeIndex(index); }
  }

}
