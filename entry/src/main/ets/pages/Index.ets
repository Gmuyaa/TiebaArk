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
import { ChatListVM, chatListVM } from '../viewmodel/ChatListVM';
import { chatStore } from '../viewmodel/ChatStore';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { hdsEffect } from '@kit.UIDesignKit';

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
import { smartReachStore, SmartReachStore } from '../common/appearance/SmartReachStore';
import { WindowBreakpoint, windowBreakpoint } from '../common/appearance/WindowBreakpointStore';
import { MyListPage } from './MyListPage';
import { HotTopicPage } from './HotTopicPage';
import { UserPage } from './UserPage';
import { DirectoryPage } from './DirectoryPage';
import { ForumMemberPage } from './ForumMemberPage';
import { NotifyListPage } from './NotifyListPage';
import { ChatPage } from './ChatPage';
import {
  AppRoute, ChatPageParams, ComposePageParams, ForumPageParams, HotTopicParams, MyListParams, NavigationService,
  NotifyListParams, SearchResultParams, ThreadDetailParams, UserPageParams, DirectoryPageParams,
  ForumMemberPageParams
} from '../navigation/AppNavigation';
import { materialManager } from '../common/material/MaterialManager';
import { MotionEffect } from '../common/appearance/MotionConfig';
import { motionStore, MotionStore } from '../common/appearance/MotionStore';
import { motionDuration, motionSwiperCurve } from '../common/appearance/MotionPolicy';
import { MaterialTabs } from '../components/MaterialTabs';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { ForumListView } from '../components/ForumListView';

import { HomeTopNav } from '../components/HomeTopNav';
import { HomeDualRowTopBar } from '../components/HomeDualRowTopBar';
import { homeTopNavStore, HomeTopNavStore } from '../common/appearance/HomeTopNavStore';
import {
  HomeTopNavStyle, homeTopNavRowHeight
} from '../common/appearance/HomeTopNavStyle';
import { ViewerImage } from '../model/ImageLoadPolicy';
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
import { LaunchDisclaimerStore, launchDisclaimerStore } from '../utils/LaunchDisclaimerStore';
import { startPostConsentServices } from '../viewmodel/AppStartup';
import { prepareForumPage } from '../viewmodel/ForumPageStore';
import {
  LaunchDisclaimerContent, launchDisclaimerBodyMaxHeight, launchDisclaimerDialogOptions,
  launchDisclaimerDialogWidth
} from '../components/LaunchDisclaimerDialog';

/** 一个 Tab 槽位的静态描述 */
interface TabSlot {
  /** 未选中（线框版） */
  icon: Resource;
  /** 选中（实心版）。⚠️ `person_crop_circle` 无线框版 → 「我的」两态同资源，靠颜色区分 */
  iconFill: Resource;
  label: string;
}

/** 底栏首页连续点击的识别窗口；首次点击始终立即回顶。 */
const HOME_DOUBLE_TAP_MS: number = 350;

/** 主页签切换降级为时间曲线（关闭弹簧、保留位移）时的动画时长（ms）。 */
const MAIN_TAB_SWITCH_MS: number = 360;

/**
 * 收起终点的缩放比。不收到 0：栏体收成一条小胶囊停在手势条安全区**上方**，
 * 再靠透明度消失。收到底会压进手势条区域，位置容易跳，也看不到"收起"的落点。
 */
const BAR_HIDDEN_SCALE: number = 0.25;

/** 收缩过程中栏体额外下沉的距离（vp）：终点从安全区上沿再往下挪这么多，贴近手势条上方。 */
const BAR_HIDDEN_DROP: number = 28;

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
  @Local private tabTransitioning: boolean = false;
  @Local private homeOverlayActiveInTransition: boolean = false;
  @Local private homeTabSlideOffsetX: number = 0;
  @Local private tabEffectTriggers: number[] = [0, 0, 0, 0];
  @Local pageVisible: boolean = true;
  @Local motionPreferences: MotionStore = motionStore;
  @Local foreground: ForegroundRefresh = foregroundRefresh;
  @Local unread: NotifyUnreadVM = notifyUnreadVM;
  @Local chatList: ChatListVM = chatListVM;
  @Local unreadAuth: AuthSession = authSession;
  @Local private disclaimer: LaunchDisclaimerStore = launchDisclaimerStore;
  @Local private disclaimerBusy: boolean = false;
  @Local private disclaimerDialogFallback: boolean = false;
  private disclaimerDialogId: number = 0;
  private disclaimerDialogOpening: boolean = false;
  private disclaimerDialogSeq: number = 0;
  private unreadTimer: number = -1;
  private foregroundRevision: number = foregroundRefresh.revision;

  /** 外壳统一读取计数，消息页与底栏共用；不自动读取会消费未读的分类列表。 */
  @Monitor('foreground.isForeground', 'foreground.revision', 'pageVisible', 'homeNavVisible',
    'unreadAuth.snapshot', 'unread.previewRevision', 'disclaimer.acceptedVersion')
  private syncUnreadRefresh(): void {
    this.stopUnreadRefresh();
    if (!this.disclaimer.accepted) { return; }
    this.unread.syncAccount();
    if (!this.pageVisible || !this.foreground.isForeground || !authSession.isLoggedIn()) { return; }
    void this.reloadUnread();
    this.unreadTimer = setInterval((): void => {
      if (this.disclaimer.accepted && this.pageVisible && this.foreground.isForeground && authSession.isLoggedIn()) {
        void this.reloadUnread();
      }
    }, 30000);
  }

  private stopUnreadRefresh(): void {
    if (this.unreadTimer !== -1) { clearInterval(this.unreadTimer); this.unreadTimer = -1; }
  }

  private async reloadUnread(): Promise<void> {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await this.unread.refresh(context);
    void chatStore.syncOnForeground(context);
  }

  @Monitor('foreground.revision', 'pageVisible', 'homeNavVisible')
  onForegroundRefresh(): void {
    if (!this.disclaimer.accepted || !this.pageVisible || !this.homeNavVisible ||
      this.foregroundRevision === this.foreground.revision) { return; }
    this.foregroundRevision = this.foreground.revision;
    this.refreshMyProfile();
  }
  @Local viewerUrls: string[] = [];
  @Local viewerItems: ViewerImage[] = [];
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
  @Local smartReachPreferences: SmartReachStore = smartReachStore;
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
  /**
   * 首页 NavBar 是否可见（Root 导航压入子页时为 false）。必须 `@Local`：顶栏玻璃浮层要按它即时隐藏
   * （进帖子详情时不能浮在上面）。
   */
  @Local homeNavVisible: boolean = true;
  private statusBarRequestVersion: number = 0;
  private lastHomeTapMs: number = 0;
  private pendingTabClickIndex: number = -1;
  private pendingTabClickTimer: number = -1;
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
    const moveOn: boolean = motionStore.isOn(MotionEffect.MOVE);
    this.appNavStack.disableAnimation(!moveOn);
    if (!moveOn) {
      this.resetMainTabTransition();
    }
  }

  pageTransition() {
    if (!motionStore.isOn(MotionEffect.MOVE)) {
      PageTransitionEnter({ duration: 0 })
      PageTransitionExit({ duration: 0 })
    }
  }

  /** 首页查看器独占系统返回；普通内容页仍由共享导航栈处理。 */
  onBackPress(): boolean {
    if (!this.disclaimer.accepted) { return true; }
    if (this.viewerUrls.length === 0) { return false; }
    closeImageTransition(this.getUIContext(), (): void => {
      this.viewerUrls = [];
      this.viewerIndex = 0;
    });
    return true;
  }

  private refreshMyProfile(): void {
    if (!this.disclaimer.accepted || !this.pageVisible || !this.homeNavVisible || this.viewerUrls.length > 0) { return; }
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
    if (!this.disclaimer.accepted) {
      this.ensureDisclaimerDialog();
      return;
    }
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
    NavigationService.setForumPrefetcher(context, (ctx: common.UIAbilityContext, name: string): void => {
      prepareForumPage(ctx, name);
    });
    readStatusBarVp(context).then((vp: number) => { this.homeStatusBarH = vp; }).catch(() => {});

    try {
      const screen: display.Display = display.getDefaultDisplaySync();
      const ui = this.getUIContext();
      const widthVp: number = ui.px2vp(screen.width);
      const heightVp: number = ui.px2vp(screen.height);
      if (this.homeViewportWidth <= 0) { this.homeViewportWidth = widthVp; }
      if (this.homeViewportHeight <= 0) { this.homeViewportHeight = heightVp; }
      this.barSideMargin = bottomBarSideMarginVp(widthVp);
    } catch (_) {}
    if (this.disclaimer.accepted) {
      this.syncUnreadRefresh();
    }
  }

  aboutToDisappear(): void {
    this.clearPendingTabClick();
    NavigationService.setForumPrefetcher(null, null);
    if (this.disclaimerDialogId) {
      this.closeDisclaimerDialog();
    }
    this.stopUnreadRefresh();
    this.unread.reset();
  }

  private ensureDisclaimerDialog(): void {
    if (this.disclaimer.accepted || this.disclaimerDialogOpening || this.disclaimerDialogId !== 0) {
      return;
    }
    this.disclaimerDialogFallback = false;
    this.disclaimerDialogOpening = true;
    const seq: number = ++this.disclaimerDialogSeq;
    this.getUIContext().getPromptAction().openCustomDialog(
      launchDisclaimerDialogOptions(
        (): void => { this.DisclaimerDialog(); },
        this.homeViewportWidth,
        (): void => {
          if (this.disclaimerDialogSeq === seq) {
            this.disclaimerDialogId = 0;
            this.disclaimerDialogOpening = false;
          }
        }
      )
    ).then((id: number): void => {
      if (this.disclaimerDialogSeq !== seq || this.disclaimer.accepted) {
        try { this.getUIContext().getPromptAction().closeCustomDialog(id); } catch (_) {}
        return;
      }
      this.disclaimerDialogId = id;
      this.disclaimerDialogOpening = false;
    }).catch((err: Error): void => {
      hilog.warn(0x0000, 'LaunchDisclaimer', 'openCustomDialog failed: %{public}s', err.message);
      if (this.disclaimerDialogSeq === seq) {
        this.disclaimerDialogOpening = false;
        this.disclaimerDialogId = 0;
        this.disclaimerDialogFallback = true;
      }
    });
  }

  private closeDisclaimerDialog(): void {
    ++this.disclaimerDialogSeq;
    this.disclaimerDialogOpening = false;
    const id: number = this.disclaimerDialogId;
    this.disclaimerDialogId = 0;
    if (id !== 0) {
      try {
        this.getUIContext().getPromptAction().closeCustomDialog(id);
      } catch (_) {}
    }
  }

  private handleAgreeDisclaimer(): void {
    if (this.disclaimerBusy) { return; }
    this.disclaimerBusy = true;
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    const saved: boolean = launchDisclaimerStore.accept(context);
    if (!saved) {
      this.disclaimerBusy = false;
      try {
        this.getUIContext().getPromptAction().showToast({
          message: '保存确认状态失败，请重试',
          duration: 2000
        });
      } catch (_) {}
      return;
    }
    this.disclaimerDialogFallback = false;
    this.closeDisclaimerDialog();
    startPostConsentServices(context);
    this.disclaimerBusy = false;
    this.syncUnreadRefresh();
  }

  private handleDeclineDisclaimer(): void {
    if (this.disclaimerBusy) { return; }
    this.disclaimerBusy = true;
    this.closeDisclaimerDialog();
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    context.terminateSelf().catch((err: Error): void => {
      hilog.warn(0x0000, 'LaunchDisclaimer', 'terminateSelf failed: %{public}s', err.message);
      this.disclaimerBusy = false;
      if (!this.disclaimer.accepted) {
        this.ensureDisclaimerDialog();
      }
    });
  }

  @Builder
  DisclaimerDialog() {
    LaunchDisclaimerContent({
      maxBodyHeight: launchDisclaimerBodyMaxHeight(this.homeViewportHeight),
      busy: this.disclaimerBusy,
      onAgree: (): void => { this.handleAgreeDisclaimer(); },
      onDecline: (): void => { this.handleDeclineDisclaimer(); }
    })
  }

  onPageHide(): void {
    this.clearPendingTabClick();
    this.pageVisible = false;
    this.setHomeScrollHidden(false);
    this.resetMainTabTransition();
  }

  private mainTabAnimationDuration(): number {
    return motionDuration(MAIN_TAB_SWITCH_MS, MotionEffect.MOVE);
  }

  private homeChromeVisible(): boolean {
    return this.viewerUrls.length === 0 &&
      (this.currentIndex === 0 || (this.tabTransitioning && this.homeOverlayActiveInTransition));
  }

  private resetMainTabTransition(): void {
    this.tabTransitioning = false;
    this.homeOverlayActiveInTransition = false;
    this.homeTabSlideOffsetX = 0;
  }

  private clearPendingTabClick(): void {
    if (this.pendingTabClickTimer !== -1) {
      clearTimeout(this.pendingTabClickTimer);
      this.pendingTabClickTimer = -1;
    }
    this.pendingTabClickIndex = -1;
  }

  private handleMainTabAnimationStart(from: number, to: number): void {
    this.clearPendingTabClick();
    // Tabs 原生 TabBar 接管点击时不会经过自定义 Column.onClick，必须在此第 0ms 同步底栏高亮与图标动效。
    if (this.currentIndex !== to) {
      this.lastHomeTapMs = 0;
      this.currentIndex = to;
      this.tabEffectTriggers[to] = this.tabEffectTriggers[to] + 1;
      if (to !== 0) {
        this.setHomeScrollHidden(false);
      }
    }
    if (!materialManager.useArkUI || this.mainTabAnimationDuration() === 0 || from === to) {
      this.resetMainTabTransition();
      return;
    }
    const wasTransitioning: boolean = this.tabTransitioning;
    const involvesHome: boolean = from === 0 || to === 0;
    this.tabTransitioning = true;
    this.homeOverlayActiveInTransition = involvesHome;
    if (!involvesHome) {
      this.homeTabSlideOffsetX = 0;
      return;
    }
    // 静止态切回首页时先把首页浮层预置到左侧一屏外，避免 onContentDidScroll 首帧前在 x=0 闪现。
    // 半途反切打断则保留当前帧偏移，交给逐帧回调平滑回拉。
    if (!wasTransitioning) {
      this.homeTabSlideOffsetX = to === 0 && this.homeViewportWidth > 0 ? -this.homeViewportWidth : 0;
    }
  }

  private handleMainTabContentScroll(_selectedIndex: number, index: number, position: number,
    mainAxisLength: number): void {
    if (!this.tabTransitioning || !this.homeOverlayActiveInTransition || index !== 0 || mainAxisLength <= 0) {
      return;
    }
    this.homeTabSlideOffsetX = position * mainAxisLength;
  }

  private handleMainTabAnimationEnd(_index: number): void {
    this.resetMainTabTransition();
  }

  private readonly tabBounceEffect: SymbolEffect = new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.UP);
  private readonly tabScaleEffect: SymbolEffect = new ScaleSymbolEffect(EffectScope.WHOLE, EffectDirection.UP);
  private readonly tabNoEffect: SymbolEffect = new SymbolEffect();

  private handleMainTabBarClick(index: number): void {
    // ArkUI barFloatingStyle 单次点击任意底栏项会在同帧先补发一次 index=0 再发真实目标，
    // 合并 16ms 内的末次回调，避免切去他页或切回首页时误触首页重按回顶。
    this.pendingTabClickIndex = index;
    if (this.pendingTabClickTimer !== -1) {
      clearTimeout(this.pendingTabClickTimer);
    }
    this.pendingTabClickTimer = setTimeout((): void => {
      const target: number = this.pendingTabClickIndex;
      this.pendingTabClickTimer = -1;
      this.pendingTabClickIndex = -1;
      if (target >= 0) {
        this.commitMainTabBarClick(target);
      }
    }, 16);
  }

  private commitMainTabBarClick(index: number): void {
    if (index === this.currentIndex) {
      if (index === 0) {
        this.handleHomeRetap();
      }
      return;
    }
    const prev: number = this.currentIndex;
    this.lastHomeTapMs = 0;
    this.currentIndex = index;
    this.tabEffectTriggers[index] = this.tabEffectTriggers[index] + 1;
    if (index !== 0) {
      this.setHomeScrollHidden(false);
    }
    if (materialManager.useArkUI && this.mainTabAnimationDuration() > 0 && (prev === 0 || index === 0)) {
      const wasTransitioning: boolean = this.tabTransitioning;
      this.tabTransitioning = true;
      this.homeOverlayActiveInTransition = true;
      if (!wasTransitioning) {
        this.homeTabSlideOffsetX = index === 0 && this.homeViewportWidth > 0 ? -this.homeViewportWidth : 0;
      }
    }
  }

  private tabSymbolEffect(): SymbolEffect {
    if (!motionStore.isOn(MotionEffect.SCALE)) {
      return this.tabNoEffect;
    }
    return motionStore.isOn(MotionEffect.SPRING)
      ? this.tabBounceEffect
      : this.tabScaleEffect;
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

  /**
   * 收缩时栏体随缩放量同步下沉：展开态停在安全区上沿（`BAR_SAFE_H`），收到 `BAR_HIDDEN_SCALE` 时再往下
   * `BAR_HIDDEN_DROP`，停在手势条正上方。
   */
  private bottomBarBottomMargin(): number {
    const scale: number = this.bottomBarScaleFactor();
    return AppTheme.BAR_SAFE_H - (1 - scale) * BAR_HIDDEN_DROP;
  }

  private showMainTabBar(): void {
    this.animateBottomBar(false);
  }

  private hideMainTabBar(): void {
    this.animateBottomBar(true);
  }

  private animateBottomBar(hidden: boolean): void {
    if (!materialManager.useArkUI) { return; }
    // 已在目标终态就直接返回，否则终点上再来一次同向指令会让动画从终点重播一遍。
    if (!this.bottomAnimator &&
      ((hidden && this.homeBottomScale === BAR_HIDDEN_SCALE && this.bottomAlpha === 0) ||
        (!hidden && this.homeBottomScale === 1 && this.bottomAlpha === 1))) {
      return;
    }
    const version: number = ++this.bottomMotionVersion;
    this.bottomAnimator?.cancel();
    this.bottomAnimator = undefined;
    const context: UIContext = this.getUIContext();
    // 动画一开始就要让前景内容可见：它绑定 `bottomBarCollapsed`，收起态下为 Hidden，
    // 不先放开的话展开全过程只有底板在长、图标文字要等 onFinish 才冒出来。
    this.bottomBarCollapsed = false;
    /*
     * 尺寸交给 ArkUI 自带弹簧（`curves.springMotion`），透明度只能走控制器逐帧写：`animateTo` 管
     * `homeBottomScale`（barHeight/barWidth/底部偏移都挂在它上面），`createAnimator` 只管透明度。
     */
    context.animateTo({
      duration: hidden ? 300 : 560,
      curve: hidden ? curves.springMotion(0.42, 0.9) : curves.springMotion(0.38, 0.45),
      onFinish: (): void => {
        if (version !== this.bottomMotionVersion) { return; }
        this.bottomBarCollapsed = hidden && this.bottomNavigationHidden();
      }
    }, (): void => {
      this.homeBottomScale = hidden ? BAR_HIDDEN_SCALE : 1;
    });
    const alphaAnimator: AnimatorResult = context.createAnimator({
      duration: hidden ? 260 : 560, easing: 'linear',
      delay: 0, fill: 'forwards', direction: 'normal', iterations: 1, begin: 0, end: 1 });
    this.bottomAnimator = alphaAnimator;
    alphaAnimator.onFrame = (progress: number): void => {
      if (version !== this.bottomMotionVersion) { return; }
      const p: number = Math.max(0, Math.min(1, progress));
      // 收起前段就淡掉；展开后段才变实（先长出来再显形）。
      const a: number = hidden ? 1 - Math.pow(p, 0.67) : 1;
      this.bottomAlpha = a;
      this.tabsController.setTabBarOpacity(a);
    };
    alphaAnimator.onFinish = (): void => {
      if (version !== this.bottomMotionVersion) { return; }
      this.bottomAlpha = hidden ? 0 : 1;
      this.tabsController.setTabBarOpacity(hidden ? 0 : 1);
      this.bottomAnimator = undefined;
    };
    alphaAnimator.play();
  }

  private syncSystemStatusBar(hidden: boolean, version: number): void {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    window.getLastWindow(context).then(async (win: window.Window): Promise<void> => {
      if (version !== this.statusBarRequestVersion) {
        return;
      }
      await win.setSpecificSystemBarEnabled('status', !hidden, motionStore.isOn(MotionEffect.MOVE));
      if (!hidden) {
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
        const expectedHidden: boolean = this.homeNavVisible && this.statusBarHidden();
        await win.setSpecificSystemBarEnabled('status', !expectedHidden, motionStore.isOn(MotionEffect.MOVE));
      }
    }).catch((e: Error) => {
      hilog.warn(0x0, 'TiebaTop', 'status bar visibility failed: %{public}s', e.message);
      if (version === this.statusBarRequestVersion) {
        this.homeScrollHidden = false;
      }
    });
  }

  /** 首页滚动共用一个方向信号，三处区域分别按设置决定是否隐藏。 */
  private setHomeScrollHidden(hidden: boolean): void {
    const target: boolean = hidden && this.currentIndex === 0 && this.homeNavVisible;
    if (target === this.homeScrollHidden) {
      return;
    }
    const version: number = ++this.statusBarRequestVersion;
    this.getUIContext().animateTo({
      duration: motionDuration(target ? 300 : 440),
      curve: target || !motionStore.isOn(MotionEffect.MOVE) || !motionStore.isOn(MotionEffect.SPRING)
        ? Curve.EaseIn : curves.springMotion(0.38, 0.64)
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
    this.syncSystemStatusBar(target && homeNavigationHideStore.hideStatusBar, version);
  }

  build() {
    if (!this.disclaimer.accepted) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.disclaimerDialogFallback) {
          Column() {
            this.DisclaimerDialog()
          }
          .width(launchDisclaimerDialogWidth(this.homeViewportWidth))
          .backgroundColor(AppTheme.CARD)
          .borderRadius(24)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppTheme.BG)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
        [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    } else {
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
      // ArkUI 承载分支的显隐完全交给 TabBar 的 translate/opacity，栏面常驻不重建：
      // 若在这里跟着 collapsed 把 barHeight 归零，translate 失去对象，展开还得重建浮面。
      barVisible: materialManager.useArkUI ? true : !this.bottomNavigationHidden(),
      // 底栏不再叠页面底蒙层：去掉玻璃下方的渐隐过渡，内容直接压到玻璃底下。
      maskColor: Color.Transparent,
      maskHeight: 0,
      animationDuration: this.mainTabAnimationDuration(),
      animationCurve: motionSwiperCurve(),
      animationMode: motionStore.isOn(MotionEffect.MOVE)
        ? AnimationMode.CONTENT_FIRST_WITH_JUMP : AnimationMode.NO_ANIMATION,
      pages: (): void => { this.HomePages(); },
      onTabBarClick: (index: number): void => {
        this.handleMainTabBarClick(index);
      },
      onAnimationStart: (index: number, targetIndex: number): void => {
        this.handleMainTabAnimationStart(index, targetIndex);
      },
      onAnimationEnd: (index: number): void => {
        this.handleMainTabAnimationEnd(index);
      },
      onContentDidScroll: (selectedIndex: number, index: number, position: number, mainAxisLength: number): void => {
        this.handleMainTabContentScroll(selectedIndex, index, position, mainAxisLength);
      },
      onChange: (index: number): void => {
        this.clearPendingTabClick();
        if (this.currentIndex !== index) {
          this.currentIndex = index;
          this.tabEffectTriggers[index] = this.tabEffectTriggers[index] + 1;
        }
        this.refreshMyProfile();
        if (index !== 0) { this.lastHomeTapMs = 0; this.setHomeScrollHidden(false); }
        if (!materialManager.useArkUI || this.mainTabAnimationDuration() === 0) {
          this.resetMainTabTransition();
        }
      }
    })
    .width('100%')
    .height('100%')

    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor(AppTheme.BG)
      // 看图时保留材质按钮，由上层 Viewer 覆盖；发帖按钮显隐读偏好，隐藏时必须真正卸载，
      // 才能停掉握姿订阅与待换边定时器。切页滑出期间跟随首页横滑，落定后立即卸载。
      if (this.homeChromeVisible() && this.homeNavVisible && this.smartReachPreferences.homeComposeVisible) {
        // 不能在 HomeComposeButton 外直接挂 .translate：ArkUI 生成的 __Common__ 包裹层会按 BottomEnd 对齐，
        // 把内部 .position(x, y) 整体推到视口右下角之外。
        HomeComposeButton({ viewportWidth: this.homeViewportWidth, viewportHeight: this.homeViewportHeight,
          topInset: this.homeStatusBarH + this.homeTopNavRowH,
          active: this.pageVisible && this.viewerUrls.length === 0 &&
            this.currentIndex === 0 && !this.tabTransitioning,
          externalOffsetX: this.homeTabSlideOffsetX,
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
      // 进入子页时不展开已收起的底栏，避免推入转场瞬间弹出；仅恢复子页所需的系统状态栏。
      if (!isVisible) {
        if (this.statusBarHidden()) {
          this.syncSystemStatusBar(false, ++this.statusBarRequestVersion);
        }
      } else if (this.statusBarHidden()) {
        this.syncSystemStatusBar(true, ++this.statusBarRequestVersion);
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
       * 顶栏内容结构对所有样式一致（`stackBuilder` 一个入口，内部按当前样式分叉）：运行时切换样式时 builder
       * 重跑就能换内容，HDS 只在创建时固化 style 配置。官方沉浸（值 5）不在标题栏里画任何东西 ——
       * 它的玻璃由页面根 Stack 的浮层承载（见 HomeDualRowOverlay），否则标题栏顶部系统固有标题区会把双排压低。
       */
      content: {
        stackBuilder: (): void => { this.HomeTitleBarContent(); }
      }
    })
    .hideTitleBar(!this.homeChromeVisible())
    .bindToScrollable([this.homeRecommendScroller, this.homeFollowScroller, this.homeHotScroller])
    .systemBarStyle(
      { statusBarContentColor: this.viewerUrls.length > 0 || themeModeStore.isDark ? '#F2F3F4' : '#1B1B1B' },
      { statusBarContentColor: this.viewerUrls.length > 0 || themeModeStore.isDark ? '#F2F3F4' : '#1B1B1B' }
    )
    .mode(windowBreakpoint.breakpoint === WindowBreakpoint.LG ? NavigationMode.Split : NavigationMode.Stack)
    .navBarWidth('42%')
    .navBarWidthRange({ minWidth: 340, maxWidth: 480 })
    .minContentWidth(360)

      if (this.homeTopNavStyle === HomeTopNavStyle.OFFICIAL_DUAL_ROW && this.viewerUrls.length === 0) {
        this.HomeDualRowOverlay()
      }
      if (this.viewerUrls.length > 0) {
        ImageViewer({ imageUrls: this.viewerUrls, images: this.viewerItems, initialIndex: this.viewerIndex,
          onClose: (): void => { this.viewerUrls = []; this.viewerItems = []; this.viewerIndex = 0; } })
          .zIndex(100)
          .transition(imageLayerRetentionTransition())
      }
    }
    .width('100%').height('100%')
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    }
  }

  @Builder
  HomePages() {
      TabContent() {
        ForumListView({
          // 发帖按钮按压时用点光源照亮帖子卡片外边缘（受光端挂 illuminatedType，光源在按钮上）。
          // 用 BORDER（细边）而不是 DEFAULT_FEATHERING_BORDER（羽化）：羽化在近光侧会过曝并大范围外溢，
          // 远处边被压到看不见；细边只靠亮度随距离衰减，整圈都还在。
          cardLitType: hdsEffect.PointLightIlluminatedType.BORDER,
          onOpenImages: (urls: string[], index: number, images?: ViewerImage[]): void => {
            this.viewerIndex = index;
            this.viewerUrls = urls;
            this.viewerItems = images ?? [];
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

        MessageView({ bottomBarOcclusion: AppTheme.BAR_TOTAL_H,
          active: this.pageVisible && this.homeNavVisible && this.currentIndex === 2 })
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
    Stack({ alignContent: Alignment.TopStart }) {
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
    }
    .width('100%')
    // 底部留 48vp 容纳官方材质阴影；仅在横滑期间裁平左右伸出屏外的胶囊半圆弧，静止态不裁切。
    .padding({ bottom: 48 })
    .clip(this.tabTransitioning)
    // 压在看图器之下（zIndex 100）；`.position` 绝对定位到左上：垂直必须钉屏顶（根 Stack 默认垂直居中）。
    .position({ x: 0, y: 0 })
    .translate({ x: this.homeTabSlideOffsetX })
    // 子页覆盖与非首页静止期间保留材质节点，避免每次返回首页都重建整片原生材质。
    .visibility(this.homeNavVisible && this.homeChromeVisible() ? Visibility.Visible : Visibility.Hidden)
    .hitTestBehavior(this.homeNavVisible && this.currentIndex === 0 && Math.abs(this.homeTabSlideOffsetX) < 8
      ? HitTestMode.Transparent : HitTestMode.None)
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
          selectedChannel: this.homeSelectedChannel,
          hidden: this.topNavigationHidden(),
          onRowHeightChanged: (height: number): void => { this.homeTopNavRowH = height; },
          onSelectChannel: (label: string): void => { this.homeChangeChannel(label); },
          // 搜索继续走既有导航入口（NavigationService.openSearchPage）
          onSearch: (): void => { NavigationService.openSearchPage(); }
        })
        /*
         * ⚠️ 边距与状态栏避让必须由宿主下发：同样的 padding 写进 `HomeTopNav` 内部时，HDS 会把那一行压成
         * 19px 高。写法与改动前的 `HomeChannelPills` 逐字一致 —— 同样的 `width('100%')` + 同样的 padding。
         */
        .width('100%')
        .padding({ top: this.homeStatusBarH + 8 + this.homeTitleContentOffsetVp,
          left: 16, right: 16 })
      }
      .width('100%')
      .height(this.homeStatusBarH + this.homeTopNavRowH + this.homeTitleContentOffsetVp)
      .translate({ x: this.homeTabSlideOffsetX })
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
      ComposePage({ routeParams: pageInfos !== null && pageInfos !== undefined ? pageInfos as ComposePageParams : undefined })
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
    } else if (name === AppRoute.CHAT_PAGE) {
      ChatPage({ routeParams: pageInfos as ChatPageParams })
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
  TabSlotContent(label: string, index: number, slot: TabSlot) {
    if (index === 2 && (this.unread.counts.total() + (this.chatList ? this.chatList.unreadTotal : 0)) > 0) {
      Badge({ count: this.unread.counts.total() + (this.chatList ? this.chatList.unreadTotal : 0), maxCount: 99,
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

  @Builder
  tabBuilder(label: string, index: number, slot: TabSlot) {
    if (materialManager.useArkUI) {
      // ArkUI 原生 TabBar 负责切页并触发 onTabBarClick；子容器不挂 onClick，避免手势竞争导致延迟或卡页。
      Column({ space: 2 * this.bottomBarScaleFactor() }) {
        this.TabSlotContent(label, index, slot)
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
    } else {
      Column({ space: 2 * this.bottomBarScaleFactor() }) {
        this.TabSlotContent(label, index, slot)
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
        this.switchTo(index);
      })
    }
  }

  @Builder
  TabIcon(index: number, slot: TabSlot) {
    SymbolGlyph(index === this.currentIndex ? slot.iconFill : slot.icon)
      .fontSize(24 * this.bottomBarScaleFactor()).maxFontScale(1)
      .fontColor([this.slotColor(index)])
      .symbolEffect(this.tabSymbolEffect(), this.tabEffectTriggers[index])
      .accessibilityLevel('no')
  }

  private tabAccessibility(label: string, index: number): string {
    if (index !== 2) { return label; }
    const chatUnread: number = this.chatList ? this.chatList.unreadTotal : 0;
    if (!this.unread.loaded && chatUnread === 0) {
      return `${label}，未读数${this.unread.error.length > 0 ? '读取失败' : '尚未读取'}`;
    }
    const count: number = this.unread.counts.total() + chatUnread;
    return `${label}，${count > 0 ? `${count}条未读` : '没有未读消息'}` +
      (this.unread.error.length > 0 ? '，上次结果，刷新失败' : '');
  }

  /**
   * 点击某格：先改 `currentIndex`（驱动底栏配色），再让 Tabs 切页 —— 颜色先落定、页面随后跟上，
   * 避免"页面已经过去但高亮还没动"的那一帧。
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
    this.tabEffectTriggers = this.tabEffectTriggers.map((count: number, i: number): number =>
      i === idx ? count + 1 : count);
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
