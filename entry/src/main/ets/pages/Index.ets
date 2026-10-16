

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
  HomeTopNavStyle, OFFICIAL_DUAL_ROW_HEIGHT
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

interface TabSlot {

  icon: Resource;

  iconFill: Resource;
  label: string;
}

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

  @Local currentIndex: number = 0;
  @Local viewerUrls: string[] = [];
  @Local viewerIndex: number = 0;
  @Local homeScrollHidden: boolean = false;
  @Local homePillRevealReady: boolean = true;
  @Local homeSelectedChannel: string = '推荐';

  @Local topNavPreferences: HomeTopNavStore = homeTopNavStore;
  @Local homeTopNavRowH: number = 54;
  @Local homeTopNavStyle: HomeTopNavStyle = homeTopNavStore.style;

  @Monitor('topNavPreferences.style')
  private syncHomeTopNavStyle(): void {
    this.homeTopNavStyle = this.topNavPreferences.style;
  }
  @Local homeStatusBarH: number = 39;

  private readonly homeTitleContentOffsetVp: number = 32;
  @Local bottomMaskVisible: boolean = true;

  @Local homeNavVisible: boolean = true;
  private statusBarRequestVersion: number = 0;
  private lastHomeTapMs: number = 0;
  private homeScrollToTop: () => void = (): void => {};
  private homeRefresh: () => void = (): void => {};
  private homeChangeChannel: (label: string) => void = (_label: string): void => {};

  @Local barSideMargin: number = AppTheme.BAR_SIDE;

  private tabsController: HdsTabsController = new HdsTabsController();

  private appNavStack: NavPathStack = new NavPathStack();
  private homeRecommendScroller: ListScroller = new ListScroller();
  private homeFollowScroller: ListScroller = new ListScroller();
  private homeHotScroller: ListScroller = new ListScroller();

  onBackPress(): boolean {
    if (this.viewerUrls.length === 0) { return false; }
    this.viewerUrls = [];
    this.viewerIndex = 0;
    return true;
  }

  private refreshMyProfile(): void {
    const showsOwnAvatar: boolean = this.currentIndex === 3 ||
      (this.currentIndex === 0 && this.homeTopNavStyle === HomeTopNavStyle.OFFICIAL_DUAL_ROW);
    if (showsOwnAvatar && authSession.isLoggedIn()) {
      void authSession.refreshOwnAvatarOnEntry(
        this.getUIContext().getHostContext() as common.UIAbilityContext);
    }
  }
  onPageShow(): void {

    avatarTrace('page-visible', 0, `page=index tab=${this.currentIndex}`);

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

  private setHomeScrollHidden(hidden: boolean): void {
    const target: boolean = hidden && this.currentIndex === 0 && this.homeNavVisible;
    if (target === this.homeScrollHidden) {
      return;
    }
    const version: number = ++this.statusBarRequestVersion;
    if (target && homeNavigationHideStore.hideBottomNavigation) {

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

    Stack() {

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
            ? OFFICIAL_DUAL_ROW_HEIGHT : this.homeTopNavRowH,
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

        FollowView({ bottomBarOcclusion: AppTheme.BAR_TOTAL_H })
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

    .barFloatingStyle({

      barSideMargin: this.barSideMargin,

      barWidth: { smallWidth: this.bottomNavigationHidden() ? 4 : this.barSideMargin * 4,
        mediumWidth: this.bottomNavigationHidden() ? 4 : this.barSideMargin * 4,
        largeWidth: this.bottomNavigationHidden() ? 4 : this.barSideMargin * 4 },

      barBottomMargin: this.bottomNavigationHidden() ? 0 : 28,

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
      }
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
        && this.currentIndex === 0 && this.homeNavVisible && this.viewerUrls.length === 0) {
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

  @Builder
  HomeDualRowOverlay() {
    HomeDualRowTopBar({
      statusBarHeight: this.homeStatusBarH,
      selectedChannel: this.homeSelectedChannel,

      collapsed: this.topNavigationHidden(),
      avatarUrl: this.homeAvatarUrl(),
      onSelectChannel: (label: string): void => { this.homeChangeChannel(label); },
      onSearch: (): void => { NavigationService.openSearchPage(); },

      onAvatar: (): void => { this.openMyProfile(); }
    })

    .position({ x: 0, y: 0 })
    .zIndex(50)
  }

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

  private homeAvatarUrl(): string {
    if (!authSession.isLoggedIn()) { return ''; }
    return portraitUrl(authSession.snapshot.portrait, authSession.avatarRevision);
  }

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

          onSearch: (): void => { NavigationService.openSearchPage(); }
        })

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

      this.currentIndex = index;
      if (index !== 0) {
        this.setHomeScrollHidden(false);
      }
      this.tabsController.changeIndex(index);
    })
  }

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
