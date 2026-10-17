/**
 * 应用外壳：HdsNavigation 承载共享内容栈，HdsTabs 承载首页、关注、消息和我的。
 * 底栏使用自定义 tabBuilder 绘制图标与文字，背景和沉浸材质由 HDS 提供。
 * Settings、Login、WebLogin 继续通过 router 打开，内容页面走 AppRoute。
 */

import { fontScaleStore } from '../common/appearance/FontSizeScaleStore';
import { fontSizeScaleOf } from '../common/appearance/FontSizeScale';
import { curves, display, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { authSession } from '../auth/AuthSession';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { HdsNavigation, HdsTabs, HdsTabsController, BlurStrategy, ScrollEffectType } from '@kit.UIDesignKit';
import { ThreadDetailPage } from './ThreadDetail';
import { portraitUrl } from '../model/ThreadDetail';
import { ForumPage } from './ForumPage';
import { SearchResultPage } from './SearchResultPage';
import { SearchPage } from './SearchPage';
import { ScanPage } from './ScanPage';
import { VideoFeedPage } from './VideoFeedPage';
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
import { MaterialSlot } from '../common/material/MaterialConfig';
import { ForumListView } from '../components/ForumListView';

import { HomeTopNav } from '../components/HomeTopNav';
import { HomeDualRowTopBar } from '../components/HomeDualRowTopBar';
import { homeTopNavStore, HomeTopNavStore } from '../common/appearance/HomeTopNavStore';
import {
  HomeTopNavStyle, homeTopNavRowHeight
} from '../common/appearance/HomeTopNavStyle';
import { ImageViewer } from '../components/ImageViewer';
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
  @Local foreground: ForegroundRefresh = foregroundRefresh;
  private foregroundRevision: number = foregroundRefresh.revision;

  @Monitor('foreground.revision', 'pageVisible', 'homeNavVisible')
  onForegroundRefresh(): void {
    if (!this.pageVisible || !this.homeNavVisible || this.foregroundRevision === this.foreground.revision) { return; }
    this.foregroundRevision = this.foreground.revision;
    this.refreshMyProfile();
  }
  @Local viewerUrls: string[] = [];
  @Local viewerIndex: number = 0;
  @Local homeScrollHidden: boolean = false;
  @Local homePillRevealReady: boolean = true;
  @Local homeSelectedChannel: string = '推荐';
  /** HDS builder 的显式响应桥：同时覆盖冷启动异步读偏好与设置页即时切换。 */
  @Local topNavPreferences: HomeTopNavStore = homeTopNavStore;
  @Local homeTopNavRowH: number = 54;
  @Local homeTopNavStyle: HomeTopNavStyle = homeTopNavStore.style;

  @Monitor('topNavPreferences.style')
  private syncHomeTopNavStyle(): void {
    this.homeTopNavStyle = this.topNavPreferences.style;
  }
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
  /** 当前 HdsTabs 的控制器，供底栏点击切换页签。 */
  private tabsController: HdsTabsController = new HdsTabsController();

  private appNavStack: NavPathStack = new NavPathStack();
  private homeRecommendScroller: ListScroller = new ListScroller();
  private homeFollowScroller: ListScroller = new ListScroller();
  private homeHotScroller: ListScroller = new ListScroller();

  /** 首页查看器独占系统返回；普通内容页仍由共享导航栈处理。 */
  onBackPress(): boolean {
    if (this.viewerUrls.length === 0) { return false; }
    this.viewerUrls = [];
    this.viewerIndex = 0;
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
    this.pageVisible = true;
    // 只记"外壳页真的回到前台"（含我们页当前页签），用来和状态发布时间对齐。
    avatarTrace('page-visible', 0, `page=index tab=${this.currentIndex}`);
    // 设置页里可能刚换过顶栏样式：回前台时同步一次（值没变则不会触发重绘）
    this.homeTopNavStyle = homeTopNavStore.style;
    this.refreshMyProfile();
  }

  aboutToAppear(): void {
    NavigationService.setStack(this.appNavStack);
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    readStatusBarVp(context).then((vp: number) => { this.homeStatusBarH = vp; }).catch(() => {});

    const widthVp: number = px2vp(display.getDefaultDisplaySync().width);
    this.barSideMargin = bottomBarSideMarginVp(widthVp);
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
      duration: target ? 300 : 440,
      curve: target ? Curve.EaseIn : curves.springMotion(0.38, 0.64),
      onFinish: () => {
        if (!target && version === this.statusBarRequestVersion) {
          this.bottomMaskVisible = true;
        }
      }
    }, () => {
      this.homeScrollHidden = target;
      if (target) {
        this.homePillRevealReady = false;
      }
    });
    if (!target) {
      // 原生顶栏滚动效果恢复后再显示胶囊，避开材质首次取样的浅灰过渡帧。
      setTimeout((): void => {
        if (version === this.statusBarRequestVersion && !this.homeScrollHidden) {
          this.homePillRevealReady = true;
        }
      }, 120);
    }
    const targetStatusHidden: boolean = target && homeNavigationHideStore.hideStatusBar;
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    window.getLastWindow(context).then(async (win: window.Window): Promise<void> => {
      if (version !== this.statusBarRequestVersion) {
        return;
      }
      await win.setSpecificSystemBarEnabled('status', !targetStatusHidden, true);
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
        await win.setSpecificSystemBarEnabled('status', !this.statusBarHidden(), true);
      }
    }).catch((e: Error) => {
      hilog.warn(0x0, 'TiebaTop', 'status bar visibility failed: %{public}s', e.message);
      if (version === this.statusBarRequestVersion) {
        this.homeScrollHidden = false;
      }
    });
  }

  build() {
    /** 首页由 HdsNavigation 承载，共享栈通过 PageMap 注册内容页面。 */
    Stack() {
    // 大图浮层放在整个导航容器之外，覆盖标题栏与系统安全区。
    HdsNavigation(this.appNavStack) {
      Stack() {

    HdsTabs({ controller: this.tabsController }) {
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
              fontScaleStore.systemScale, fontScaleStore.customSize)) : this.homeTopNavRowH,
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

        MessageView()
      }
      .tabBar(this.tabBuilder('消息', 2, this.slots[2]))

      TabContent() {
        ProfileView()
      }
      .tabBar(this.tabBuilder('我的', 3, this.slots[3]))
    }
    .vertical(false)
    .barPosition(BarPosition.End)
    .barMode(BarMode.Fixed)
    .scrollable(false)
    .animationDuration(0)
    .barHeight(this.bottomNavigationHidden() ? 0 : AppTheme.BAR_CONTENT_H)
    .barOverlap(true)
    /** 底栏使用 HdsTabs 系统沉浸材质，背景保持透明，由系统处理材质渲染。 */
    .barFloatingStyle({

      barSideMargin: this.barSideMargin,
      // 宽度与栏高一起收至屏幕下缘中点；只改 sideMargin 会被 HDS 的栏宽约束裁成空胶囊。
      // 展开时用弹簧曲线，让整个胶囊从中点回弹到屏宽的 2/3。
      barWidth: { smallWidth: this.bottomNavigationHidden() ? 4 : this.barSideMargin * 4,
        mediumWidth: this.bottomNavigationHidden() ? 4 : this.barSideMargin * 4,
        largeWidth: this.bottomNavigationHidden() ? 4 : this.barSideMargin * 4 },

      barBottomMargin: this.bottomNavigationHidden() ? 0 : 28,

      // 渐变遮罩独立于 barOpacity；收起开始时立即隐藏，展开结束再恢复。
      gradientMask: {
        maskColor: this.bottomMaskVisible ? AppTheme.BOTTOM_BAR_MASK : Color.Transparent,
        maskHeight: this.bottomMaskVisible ? 92 : 0
      },
      barOpacity: this.bottomNavigationHidden() ? 0 : 1,
      thermoCtrl: true,

      systemMaterialEffect: materialManager.hdsEffectOf(MaterialSlot.BOTTOM_BAR)
    })
    .onChange((index: number) => {
      this.currentIndex = index;
      this.refreshMyProfile();
      if (index !== 0) {
        this.lastHomeTapMs = 0;
        this.setHomeScrollHidden(false);
      }
    })

    .barBackgroundColor(Color.Transparent)
    .barBackgroundBlurStyle(BlurStyle.NONE)
    .width('100%')
    .height('100%')

    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor(AppTheme.BG)
      } // Stack
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

        blurStrategy: this.homeTopNavStyle === HomeTopNavStyle.OFFICIAL_DUAL_ROW
          ? BlurStrategy.DISABLE : BlurStrategy.ADAPTIVE,
        scrollEffectOpts: {
          enableScrollEffect: false,
          scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
        },
        scrollEffectStyle: this.homeTopNavStyle === HomeTopNavStyle.OFFICIAL_DUAL_ROW
          ? { backgroundStyle: { backgroundColor: Color.Transparent, maskExtraHeight: 0, blurRadius: 0 } }
          : (this.homeTopNavStyle === HomeTopNavStyle.FLOATING_ISLANDS
            ? { backgroundStyle: { maskExtraHeight: 0, blurRadius: 0 } }
            : { backgroundStyle: { maskExtraHeight: 80, blurRadius: 120 } }),
        originalStyle: this.homeTopNavStyle === HomeTopNavStyle.OFFICIAL_DUAL_ROW
          ? { backgroundStyle: { backgroundColor: Color.Transparent, maskExtraHeight: 0, blurRadius: 0 } }
          : undefined,
        thermoCtrl: true,
        systemMaterialEffect: this.homeTopNavStyle === HomeTopNavStyle.OFFICIAL_DUAL_ROW
          ? materialManager.hdsEffectOf(MaterialSlot.HOME_TOP_CONTINUOUS)
          : undefined
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
      }
    }
    .width('100%').height('100%')
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
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
    } else if (name === AppRoute.SEARCH_RESULT_PAGE) {
      SearchResultPage({ routeParams: pageInfos as SearchResultParams })
    } else if (name === AppRoute.SEARCH_PAGE) {

      SearchPage()
    } else if (name === AppRoute.SCAN_PAGE) {
      ScanPage()
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
    return idx === this.currentIndex ? AppTheme.ACCENT : AppTheme.ICON;
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

    Column({ space: 2 }) {

      if (index === this.currentIndex) {
        SymbolGlyph(slot.iconFill)
          .fontSize(24)
          .maxFontScale(1)
          .fontColor([this.slotColor(index)])
      } else {
        SymbolGlyph(slot.icon)
          .fontSize(24)
          .maxFontScale(1)
          .fontColor([this.slotColor(index)])
      }
      Text(label)
        .fontSize(10)
        .maxFontScale(1)
        .fontColor(this.slotColor(index))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (this.currentIndex === index) {
        if (index === 0) {
          this.handleHomeRetap();
        }
        return;
      }
      this.lastHomeTapMs = 0;
      // 先改 currentIndex（驱动配色），再让 HdsTabs 切页 —— 顺序有意如此
      this.currentIndex = index;
      if (index !== 0) {
        this.setHomeScrollHidden(false);
      }
      this.tabsController.changeIndex(index);
    })
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
    this.tabsController.changeIndex(idx);
  }

}
