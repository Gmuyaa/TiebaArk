import { motionStore } from '../common/appearance/MotionStore';
import { MotionEffect } from '../common/appearance/MotionConfig';
import { motionDuration, motionSpringCurve, motionSwiperCurve } from '../common/appearance/MotionPolicy';
import { visualThemeStore } from '../common/appearance/VisualThemeStore';
import { ThreadCardLayout } from '../common/appearance/ThreadCardLayout';
import { PageState, ListFooter } from '../components/PageState';
import { RefreshSpinner, FORUM_REFRESH_OFFSET } from '../components/RefreshSpinner';
import { ForumIdentity, FORUM_AVATAR_FRAME_SIZE, FORUM_IDENTITY_INTRO_GAP, FORUM_IDENTITY_INTRO_HEIGHT, FORUM_IDENTITY_TITLE_TOP } from '../components/ForumIdentity';
import { ForumRefreshButton } from '../components/ForumRefreshButton';
import { FloatingForumTabs } from '../components/FloatingForumTabs';
import { ForumAvatarImage, forumAvatarRadius } from '../components/ForumAvatarImage';
/**
 * 吧页面：某个吧的帖子列表。数据走 `/c/f/frs/page`（`TiebaApi.fetchThreadList`），列表状态复用 `ThreadListVM`，
 * 吧头关注/签到由 `ForumIdentity` 与 `ForumHeaderVM` 承接；配色沿用首页信息流那套 `AppTheme`，
 * 详情页的 `DetailTheme` 不在这里用。
 */

import { openUserByIdentity } from '../navigation/UserNavigation';
import { common } from '@kit.AbilityKit';
import { DirectoryKind } from '../model/PageDirectory';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction, AnimatorResult, FrameCallback, curves } from '@kit.ArkUI';
import { HdsNavDestination, hdsEffect } from '@kit.UIDesignKit';
import { ForumTab, ThreadBrief, threadBriefIdentity } from '../model/ThreadList';
import { ThreadBriefDataSource } from '../model/ThreadBriefDataSource';
import { feedImageInfo } from '../model/HomeFeedPresentation';
import { formatTimeText } from '../model/TimeText';
import { ThreadListVM } from '../viewmodel/ThreadListVM';
import { clearFirstPageRead, markFirstPageRead } from '../viewmodel/ForumStateStore';
import { AppTheme } from '../theme/Theme';
import { ImageViewer } from '../components/ImageViewer';
import { GlassPillButton } from '../components/GlassPillButton';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { closeImageTransition, imageLayerRetentionTransition } from '../components/ImageTransition';
import { ThreadPreviewCard } from '../components/ThreadPreviewCard';
import { TaggedThreadText } from '../components/TaggedThreadText';
import { HelpThreadCard } from '../components/HelpThreadCard';
import { ThreadCardActionState, ThreadCardActionsVM } from '../viewmodel/ThreadCardActionsVM';
import { AvatarComponent } from '../components/AvatarComponent';
import { imageLoadStore } from '../common/appearance/ImageLoadStore';
import { ViewerImage, viewerImagesForFeed } from '../model/ImageLoadPolicy';
import { buildThreadCardMenu } from '../components/ThreadCardMenu';
import { visibleThreads } from '../model/ThreadBlock';
import { threadBlockStore, ThreadBlockStore } from '../utils/ThreadBlockStore';
import {
  FORUM_HERO_PATTERN_COLOR_FILTER, FORUM_HERO_PATTERN_OPACITY, ForumHeroPalette, forumHeroPalette
} from '../common/appearance/ForumHeroStyle';
import { GlassBackButton } from '../components/GlassBackButton';
import { GlassCircleButton } from '../components/GlassCircleButton';
import { SearchField } from '../components/SearchField';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { ForumPageParams, NavigationService, SearchResultParams } from '../navigation/AppNavigation';
import { forumDefaultTabStore } from '../common/appearance/ForumDefaultTabStore';
import { smartReachStore, SmartReachStore, ForumTabsStyle } from '../common/appearance/SmartReachStore';
import { themeModeStore } from '../common/appearance/ThemeModeStore';
import { ForumDefaultTab } from '../model/ForumDefaultTab';

class ForumTabFrameCallback extends FrameCallback {
  private ready: () => void;
  constructor(ready: () => void) { super(); this.ready = ready; }
  onIdle(_timeLeft: number): void { this.ready(); }
}

/** 仅缓存吧页返回所需的 VM 与滚动偏移，不引入全局状态框架。 */
class ForumPageState {
  vm: ThreadListVM = new ThreadListVM();
  scrollOffset: number = 0;
  defaultTab: ForumDefaultTab = ForumDefaultTab.HOT;
}

const FORUM_PAGE_STATES: Map<string, ForumPageState> = new Map<string, ForumPageState>();
const FORUM_IDENTITY_MIN_HEIGHT: number = 116;
/** 顶部工具栏里的圆按钮尺寸（vp）：按钮底端 = TOOLBAR − (TOOLBAR − 本值) / 2。 */
const FORUM_TOOLBAR_BUTTON_SIZE: number = 40;
const FORUM_IDENTITY_BOTTOM_GAP: number = 12;
const FORUM_IDENTITY_CARD_GAP: number = 0;
/** 吧页头图高（vp）；只有纯色/平滑背景会把身份与帖子前移 */
const FORUM_COVER_FULL_HEIGHT: number = 202;

// 图与内容的重叠量（vp）：取 20 = 内容区顶部圆角半径，使圆角切点正好落在图片底边上，角内露的是图片底角而非页底楔形。
const FORUM_COVER_OVERLAP: number = 20;
const FORUM_IDENTITY_PANEL_RADIUS: number = 16;
/** 顶部工具栏内容行高；内容列表视口从其下沿开始。 */
const FORUM_TOOLBAR_HEIGHT: number = 56;
const FORUM_PANEL_RADIUS: number = 16;
const FORUM_POST_ORDER_HEIGHT: number = 28;
/** 顶部模式分类胶囊：胶囊高 / 左右内边距 / 相邻间距 / 行首尾内缩（vp）。 */
const FORUM_TAB_PILL_HEIGHT: number = 36;
const FORUM_TAB_PILL_PADDING: number = 16;
const FORUM_TAB_PILL_GAP: number = 8;
const FORUM_TAB_PILL_INSET: number = 16;
// 胶囊到面板顶边的距离 = 3/4 个圆角半径（面板顶角 20vp）；底部留白 5vp，整行高 = 36 + 15 + 5。
const FORUM_TAB_PILL_TOP_GAP: number = 15;
const FORUM_TAB_PILL_BOTTOM_GAP: number = 5;
const FORUM_TAB_ROW_HEIGHT: number = FORUM_TAB_PILL_HEIGHT + FORUM_TAB_PILL_TOP_GAP + FORUM_TAB_PILL_BOTTOM_GAP;
/** 常规吸顶那一行的行高：文字行本身 + 上下留白各取胶囊行的一半。 */
const FORUM_TAB_STICKY_ROW_HEIGHT: number = 41;
const FORUM_TAB_STICKY_GAP: number = 24;
const FORUM_TAB_STICKY_INDICATOR_WIDTH: number = 18;
const FORUM_TAB_SILK_CURVE: ICurve = curves.cubicBezierCurve(0.2, 0, 0, 1);

@ComponentV2
export struct ForumPage {
  @Local cardActions: ThreadCardActionsVM = new ThreadCardActionsVM();
  @Local vm: ThreadListVM = new ThreadListVM();
  /** PageMap 注入的路由参数，唯一定义见 navigation/AppNavigation.ets 的 ForumPageParams */
  @Param routeParams: ForumPageParams | undefined = undefined;
  /** 从路由取到的吧名，同时用作顶栏标题（未加载完也能显示） */
  @Local forumName: string = '';
  @Local refreshing: boolean = false;
  @Local pullDistance: number = 0;
  private pullEligible: boolean = false;
  @Local headerRefreshRevision: number = 0;
  /** 吧头随签到统计、简介和字号变化，列表占位使用实际内容高度。 */
  @Local forumIdentityHeight: number = FORUM_IDENTITY_MIN_HEIGHT;
  /** 吧简介是否显示（由 ForumIdentity 回调）：未关注才有，决定身份块高度与上下留白。 */
  @Local identityIntroVisible: boolean = false;
  @Local forumSearchExpanded: boolean = false;
  @Local forumSearchProgress: number = 0;
  @Local forumSearchText: string = '';
  @Local forumSearchSlotWidth: number = 40;
  @Local restorePending: boolean = false;
  @Local pinnedExpanded: boolean = false;
  /**
   * 状态栏高度（vp）。窗口全屏布局下页面从 y=0 起排，Hero 的内容要自己让出这一段，否则返回键压在状态栏上
   * （既重叠又点不到，状态栏会吃掉那片触摸）。封面仍从 y=0 铺起，工具栏内容整体下移。
   */
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;
  /** 吧信息滚出视口的进度 0~1，驱动顶部分类提示条和圆角收拢。 */
  @Local tabsNavProgress: number = 0;
  @Local categoryScrollRevision: number = 0;
  @Local categoriesAtTop: boolean = true;
  /**
   * 分类行是否已贴到工具栏下沿（吸顶生效）。参考「我的华为」社区页：胶囊随内容上滑、贴住工具栏那一刻
   * 瞬间换成官方沉浸材质底带，此前保持透明。
   */
  @Local tabsDocked: boolean = false;
  /** 顶栏背板完全盖住吧头像后为 true：英雄区头像退出、顶栏头像进场（共享元素转场）。 */
  @Local identityCovered: boolean = false;
  @Local categoryPrefs: SmartReachStore = smartReachStore;
  private topTabsScroller: Scroller = new Scroller();
  private topTabWidths: Map<number, number> = new Map<number, number>();
  @Local topTabWidthRevision: number = 0;
  @Local refreshOwnsCollision: boolean = false;
  @Local refreshButtonX: number = -1;
  @Local refreshButtonY: number = -1;
  @Local categoryX: number = 0;
  @Local categoryY: number = 0;
  @Local categoryWidth: number = 0;
  @Local categoryHeight: number = 0;
  private categoryScrollNotified: boolean = false;
  @Local contentScrollOffset: number = 0;
  @Local contentHeight: number = 500;
  @Local pageVisible: boolean = true;
  @Local viewportWidth: number = 0;
  @Local viewportHeight: number = 0;
  @Local previewTabId: number = 0;
  private active: boolean = true;
  private tabSwitchRevision: number = 0;
  private swiperReady: boolean = false;
  private lastSyncedHeaderOffset: number = -1;
  private tabSwiper: SwiperController = new SwiperController();
  private tabScrollers: Map<number, ListScroller> = new Map<number, ListScroller>();
  private tabSources: Map<number, ThreadBriefDataSource> = new Map<number, ThreadBriefDataSource>();

  aboutToDisappear(): void {
    this.active = false;
    this.resetTabTransition();
  }

  private resetTabTransition(): void {
    ++this.tabSwitchRevision;
    this.previewTabId = 0;
  }

  private activeTabId(): number {
    return this.vm.selectedTabId > 0 ? this.vm.selectedTabId : 0;
  }

  private displaySelectedTabId(): number {
    return this.previewTabId > 0 ? this.previewTabId : this.vm.targetTabId();
  }

  private displayTabs(): ForumTab[] {
    if (this.vm.tabs.length > 0) { return this.vm.tabs; }
    return [new ForumTab()];
  }

  private selectedTabIndex(): number {
    const targetId: number = this.displaySelectedTabId();
    const index: number = this.vm.tabs.findIndex((tab: ForumTab): boolean => tab.id === targetId);
    return index >= 0 ? index : 0;
  }

  private scrollerForTab(tabId: number): ListScroller {
    let scroller: ListScroller | undefined = this.tabScrollers.get(tabId);
    if (scroller === undefined) {
      scroller = new ListScroller();
      this.tabScrollers.set(tabId, scroller);
    }
    return scroller;
  }

  private activeScroller(): ListScroller {
    return this.scrollerForTab(this.activeTabId());
  }

  private sourceForTab(tabId: number): ThreadBriefDataSource {
    let source: ThreadBriefDataSource | undefined = this.tabSources.get(tabId);
    if (source === undefined) {
      source = new ThreadBriefDataSource();
      source.sync(this.regularThreadsForTab(tabId));
      this.tabSources.set(tabId, source);
    }
    return source;
  }
  /**
   * 每条帖子一个横向图片列表控制器（与首页 ForumListView 同一模式）：
   * 各帖各自维护图集滚动位置，互不串位。
   */
  private imageScrollers: Map<number, ListScroller> = new Map<number, ListScroller>();
  /** 全屏看图（与本页帖子导航分离，点图片只开查看器、不进帖） */
  @Local viewerUrls: string[] = [];
  @Local viewerItems: ViewerImage[] = [];
  @Local viewerIndex: number = 0;

  private pageState: ForumPageState | undefined = undefined;

  aboutToAppear(): void {
    this.active = true;
    this.categoryPrefs.load(this.hostContext());

    let name: string = '';
    if (this.routeParams !== undefined && this.routeParams.forumName !== undefined) {
      name = this.routeParams.forumName.trim();
    }
    hilog.info(0x0, 'ForumPageNav', 'aboutToAppear forumName=%{public}s', name);
    this.forumName = name;
    readStatusBarVp(this.hostContext()).then((vp: number) => {
      this.statusBarH = vp;
    }).catch(() => {
      // 拿不到就保持兜底值，Hero 只偏差几像素
    });
    // 吧名为空就不发请求：空论坛名在服务端只会换来一次 110001，走"没拿到吧名"的空态更诚实
    if (name.length === 0) {
      return;
    }

    void threadBlockStore.load(this.hostContext());
    let state: ForumPageState | undefined = FORUM_PAGE_STATES.get(name);
    if (state === undefined) {
      state = new ForumPageState();
      FORUM_PAGE_STATES.set(name, state);
    }
    const pageState: ForumPageState = state;
    this.pageState = pageState;
    this.vm = pageState.vm;
    /* 复用缓存进入时数据已在 VM 里：先把数据源对齐，避免 LazyForEach 首帧是空的。 */
    this.syncThreadSource();
    this.restorePending = pageState.scrollOffset > 0;
    // 返回本页复用缓存；偏好变更后再次进入同一吧时重新按新默认分区加载。
    const context: common.UIAbilityContext = this.hostContext();
    // 首包马上要拉：先登记，吧头状态直接等这份回包（FRS 首页同时带关注与签到段），不再另发 rn=1 请求。
    if (!this.vm.loadedOnce) { markFirstPageRead(name); }
    void forumDefaultTabStore.load(context).then(() => {
      if (!this.active || this.pageState !== pageState) { return; }
      if (pageState.defaultTab !== forumDefaultTabStore.value) {
        pageState.defaultTab = forumDefaultTabStore.value;
        pageState.scrollOffset = 0;
        this.restorePending = false;
        this.vm.selectedTabId = 0;
        this.vm.loadedOnce = false;
      }
      if (!this.vm.loadedOnce && !this.vm.loading) {
        void this.vm.refresh(context, name);
      } else if (this.vm.loadedOnce) {
        // 有缓存直接复用、不再刷新：撤销登记，避免吧头空等首包。
        clearFirstPageRead(name);
      }
    }).catch(() => {});
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private openForumDirectory(kind: DirectoryKind): void {
    if (this.vm.forum.id <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '吧资料尚未加载，请稍后重试' });
      return;
    }
    this.saveScrollPosition();
    NavigationService.openDirectory({ kind, id: this.vm.forum.id, forumName: this.titleText() });
  }

  /**
   * 打开吧成员页。与 `openForumDirectory` 同一前置：`getMemberInfo` 只认 `forum_id`，拿不到 fid 就如实提示，
   * 不发必然失败的请求。
   */
  private openForumMember(): void {
    if (this.vm.forum.id <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '吧成员尚未加载，请稍后重试' });
      return;
    }
    this.saveScrollPosition();
    NavigationService.openForumMember({ forumId: this.vm.forum.id, forumName: this.titleText() });
  }

  /** 顶栏与正文一律以路由里的吧名为准；接口回包里的吧名只用于兜底 */
  private titleText(): string {
    if (this.forumName.length > 0) {
      return this.forumName;
    }
    return this.vm.forum.name.length > 0 ? this.vm.forum.name : '吧';
  }

  private openForumSearch(): void {
    if (this.forumSearchExpanded) { return; }
    this.forumSearchExpanded = true;
    this.getUIContext().animateTo({ duration: motionDuration(260, MotionEffect.MOVE), curve: Curve.EaseOut }, (): void => {
      this.forumSearchProgress = 1;
    });
    setTimeout((): void => {
      if (this.active && this.pageVisible && this.forumSearchExpanded) {
        this.getUIContext().getFocusController().requestFocus('forum-search-input');
      }
    }, 280);
  }

  private closeForumSearch(): void {
    this.getUIContext().getFocusController().clearFocus();
    this.forumSearchExpanded = false;
    this.getUIContext().animateTo({ duration: motionDuration(220, MotionEffect.MOVE), curve: Curve.EaseOut }, (): void => {
      this.forumSearchProgress = 0;
    });
  }

  private submitForumSearch(): void {
    const word: string = this.forumSearchText.trim();
    if (word.length === 0) { return; }
    const name: string = this.forumName.trim();
    if (name.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '吧名尚未加载，请稍后重试' });
      return;
    }
    this.saveScrollPosition();
    this.getUIContext().getFocusController().clearFocus();
    NavigationService.openSearchResult({ forumName: name, word } as SearchResultParams);
  }

  private async handleRefresh(scrollToContentTop: boolean = false): Promise<void> {
    if (this.refreshing || this.vm.loading || this.vm.isLoadingMore || this.vm.switchingTab) {
      if (!this.refreshing) { this.settlePullDistance(0); }
      return;
    }
    this.refreshing = true;
    this.settlePullDistance(FORUM_REFRESH_OFFSET);
    // 悬浮刷新按钮：先回顶再刷新。回顶是点击后的即时反馈，等网络回来再滚会让"点了没反应"和"出来先蹦一下"同时发生。
    if (scrollToContentTop) { this.scrollToThreadsTop(); }
    try {
      await this.vm.refresh(this.hostContext(), this.forumName, this.vm.loadedOnce);
      if (this.vm.errorText.length > 0) {
        promptAction.showToast({ message: this.vm.errorText, duration: 1800 });
      }
    } finally {
      // 内容区刷新动画随请求结束收起。
      this.refreshing = false;
      if (this.active) { this.settlePullDistance(0); }
    }
  }

  /**
   * 帖子区顶部在 List 内的偏移 = 第一项「图下露出段」的高度（`coverSpacerHeight`）。
   * 不能用 `heroHeight() - FORUM_TOOLBAR_HEIGHT`：heroHeight() 含吧信息本体高与两处间距，而本体画在 hero 浮层里、
   * 不占列表高度，回顶会多滚一段并被吸顶分类栏盖住（表现为「回顶后最顶上那张卡的头像行看不见」）。
   */
  private contentTopOffset(): number {
    return this.coverSpacerHeight();
  }

  /** 滚到帖子区顶部（头图与工具栏之下）；不带动画时直接落位，避免长列表顶着旧内容滑。 */
  private scrollToThreadsTop(): void {
    if (!this.active) { return; }
    const top: number = this.contentTopOffset();
    this.activeScroller().scrollTo({ xOffset: 0, yOffset: top, animation: motionStore.isOn(MotionEffect.MOVE) });
    if (this.pageState !== undefined) { this.pageState.scrollOffset = top; }
  }

  /** 超过刷新带高后连续减小跟手比例，避免固定封顶形成硬挡板。 */
  private dampedPullDistance(offset: number): number {
    const raw: number = Math.max(0, offset * 0.4);
    if (raw <= FORUM_REFRESH_OFFSET) { return raw; }
    const resistance: number = 64;
    return FORUM_REFRESH_OFFSET + resistance * Math.log(1 + (raw - FORUM_REFRESH_OFFSET) / resistance);
  }

  private settlePullDistance(distance: number): void {
    this.getUIContext().animateTo({ duration: motionDuration(420), curve: motionSpringCurve() }, () => {
      this.pullDistance = distance;
    });
  }

  private saveScrollPosition(): void {
    if (this.pageState === undefined) {
      return;
    }
    try {
      this.pageState.scrollOffset = this.activeScroller().currentOffset().yOffset;
    } catch (err) {
      // List 尚未绑定时保持已有位置，不影响跳转。
    }
  }

  private restoreScrollPosition(): void {
    if (!this.restorePending || this.pageState === undefined) {
      return;
    }
    this.restorePending = false;
    if (this.pageState.scrollOffset > 0) {
      this.activeScroller().scrollTo({
        xOffset: 0,
        yOffset: this.pageState.scrollOffset,
        animation: false
      });
    }
  }

  /** 同步非当前分类的折叠头滚动位置，保证 Swiper 横滑时头图与吸顶栏纹丝不动。 */
  private syncInactiveTabHeaders(activeId: number, headerOffset: number): void {
    const dock: number = this.coverSpacerHeight();
    const clamped: number = Math.max(0, Math.min(headerOffset, dock));
    this.tabScrollers.forEach((scroller: ListScroller, id: number): void => {
      if (id === activeId) { return; }
      try {
        const current: number = scroller.currentOffset().yOffset;
        if (clamped < dock - 0.5) {
          if (Math.abs(current - clamped) > 0.5) {
            scroller.scrollTo({ xOffset: 0, yOffset: clamped, animation: false });
          }
        } else if (current < dock - 0.5) {
          scroller.scrollTo({ xOffset: 0, yOffset: dock, animation: false });
        }
      } catch (_err) {
        // 邻页 List 尚未挂载时忽略，挂载时由 alignTabScrollerOnAppear 对齐。
      }
    });
  }

  private alignTabScrollerOnAppear(tabId: number): void {
    const headerOffset: number = Math.min(this.contentScrollOffset, this.coverSpacerHeight());
    if (headerOffset <= 0.5) { return; }
    try {
      const scroller: ListScroller = this.scrollerForTab(tabId);
      const current: number = scroller.currentOffset().yOffset;
      if (current < headerOffset - 0.5) {
        scroller.scrollTo({ xOffset: 0, yOffset: headerOffset, animation: false });
      }
    } catch (_err) {}
  }

  /** 吧信息与帖子同列表滚动；分类吸顶位置是工具栏下沿。 */
  private syncTabsSticky(tabId: number = this.activeTabId()): void {
    if (tabId !== this.activeTabId()) { return; }
    let offset: number = 0;
    try {
      offset = this.scrollerForTab(tabId).currentOffset().yOffset;
    } catch (_err) {
      return;
    }
    const distance: number = this.heroHeight() - FORUM_TOOLBAR_HEIGHT;
    this.contentScrollOffset = Math.max(0, offset);
    this.categoriesAtTop = offset <= 2;
    // 贴住工具栏下沿即切换材质底带；用内容顶部偏移做判据，不引动画（瞬间切换）。
    const docked: boolean = offset >= this.contentTopOffset() - 0.5;
    // 顶栏完全盖住吧头像这一刻：头像+吧名用共享元素转场进顶栏。
    const covered: boolean = offset >= this.avatarCoverOffset();
    if (covered !== this.identityCovered) {
      this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, (): void => {
        this.identityCovered = covered;
      });
    }
    if (docked !== this.tabsDocked) { this.tabsDocked = docked; }
    const progress: number = Math.max(0, Math.min(1, offset / distance));
    if (Math.abs(progress - this.tabsNavProgress) > 0.001) { this.tabsNavProgress = progress; }
    const headerOffset: number = Math.min(this.contentScrollOffset, this.coverSpacerHeight());
    if (Math.abs(headerOffset - this.lastSyncedHeaderOffset) > 0.5) {
      this.lastSyncedHeaderOffset = headerOffset;
      this.syncInactiveTabHeaders(tabId, headerOffset);
    }
  }

  /**
   * 「顶栏完全盖住吧头像」对应的滚动量。hero 整体被 translate(-offset)，头像底边的屏幕 y = 布局 y - offset，
   * 压到顶栏下沿（statusBarH + 工具栏高）即交接点。全部用现有几何常量直接算，不依赖运行时测量。
   */
  private avatarCoverOffset(): number {
    const avatarBottom: number = this.coverHeight() - FORUM_COVER_OVERLAP - this.identityGap();
    return Math.max(0, avatarBottom - FORUM_TOOLBAR_HEIGHT);
  }

  private goBack(): void {
    if (this.forumSearchExpanded) { this.closeForumSearch(); return; }
    NavigationService.back();
  }

  private openThread(item: ThreadBrief): void {

    this.saveScrollPosition();

    NavigationService.openThreadDetail({
      tid: item.tid, replyCount: item.replyCount, forumName: this.forumName
    });
  }

  private imageScroller(tid: number): ListScroller {
    let scroller: ListScroller | undefined = this.imageScrollers.get(tid);
    if (!scroller) { scroller = new ListScroller(); this.imageScrollers.set(tid, scroller); }
    return scroller;
  }

  /**
   * 点开某张预览图：查看器里看的是原图（服务端给了 `origin` 就用它），
   * 与首页 `openFeedImages` 同一口径。导航仍由本页负责（点帖子标题/卡片才进帖）。
   */
  private openImages(images: string[], index: number): void {
    this.viewerUrls = images.map((url: string): string => feedImageInfo(url).origin || url);
    this.viewerItems = viewerImagesForFeed(images);
    this.viewerIndex = index;
  }

  private pinnedThreadsForTab(tabId: number): ThreadBrief[] {
    void this.vm.tabSnapshotRevision;
    return visibleThreads(this.vm.threadsForTab(tabId), threadBlockStore.rules(), false)
      .filter((item: ThreadBrief) => item.isTop && !item.isVideo);
  }

  private regularThreadsForTab(tabId: number): ThreadBrief[] {
    void this.vm.tabSnapshotRevision;
    return visibleThreads(this.vm.threadsForTab(tabId), threadBlockStore.rules(), false)
      .filter((item: ThreadBrief) => !item.isTop && !item.isVideo);
  }

  @Local blocks: ThreadBlockStore = threadBlockStore;

  @Monitor('vm.threads', 'vm.tabSnapshotRevision', 'blocks.hidden', 'blocks.blockedForums', 'blocks.blockedUsers')
  syncThreadSource(): void {
    const activeId: number = this.activeTabId();
    this.sourceForTab(activeId).sync(this.regularThreadsForTab(activeId));
    this.tabSources.forEach((source: ThreadBriefDataSource, tabId: number): void => {
      if (tabId !== activeId) {
        source.sync(this.regularThreadsForTab(tabId));
      }
    });
  }

  @Monitor('vm.tabs', 'vm.selectedTabId')
  syncSwiperSelection(): void {
    if (!this.swiperReady || this.previewTabId > 0) { return; }
    const index: number = this.vm.tabs.findIndex((tab: ForumTab): boolean => tab.id === this.vm.selectedTabId);
    if (index >= 0) {
      this.tabSwiper.changeIndex(index, false);
    }
  }

  /**
   * 卡片键值：对象身份 + 递增号，与首页 `ForumListView.cardKey` 同口径。
   * `ThreadCard` 是 @Builder 值传递，只有键变了 `Repeat` 才会把刷新后的新对象当成新项重建，
   * 否则同 tid 的新数据会沿用旧节点内容（见官方"与 @Builder 混用时状态变量未刷新"）。
   */
  private cardKeys: WeakMap<ThreadBrief, string> = new WeakMap();
  private nextCardKey: number = 0;

  private cardKey(item: ThreadBrief): string {
    let key: string | undefined = this.cardKeys.get(item);
    if (key === undefined) {
      key = `${threadBriefIdentity(item)}-${++this.nextCardKey}`;
      this.cardKeys.set(item, key);
    }
    return key;
  }

  private visiblePinnedThreads(items: ThreadBrief[]): ThreadBrief[] {
    return this.pinnedExpanded ? items : items.slice(0, 1);
  }

  private lightStatusBar(): boolean {
    // 首载为主题底；封面在顶部时使用浅色状态栏字，收拢后跟随页面主题。
    return themeModeStore.isDark || this.viewerUrls.length > 0 ||
      (this.forumName.length > 0 && !(this.vm.loading && !this.vm.loadedOnce) && this.toolbarBackgroundProgress() < 1);
  }

  build() {
    // 工具栏固定；吧信息、分类和帖子在同一列表中滚动。
    HdsNavDestination() {
      /*
       * 图片查看器挂在本页内容之上的 Stack 层（与 ThreadDetail 同一挂法）：
       * 触点在图片上时由图片的 onClick 消费，卡片自身的"进帖"点击不会被触发。
       */
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          if (this.forumName.length > 0) {
            if (this.vm.loading && !this.vm.loadedOnce) {

              this.FullPageLoading()
            } else {
              this.ThreadList()
            }
          } else {
            this.TopBar()
            this.StatusView('没有拿到吧名')
          }
        }
        .width('100%')
        .height(LayoutPolicy.matchParent)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
        .clip(false)
        .backgroundColor(AppTheme.BG)

        // Viewer 覆盖已有控件，避免关图重建材质与重播刷新按钮入场动画。
        if (this.forumName.length > 0 && this.vm.loadedOnce) {
          if (this.categoryPrefs.forumTabsFloating) {
          FloatingForumTabs({ tabs: this.vm.tabs, selectedId: this.displaySelectedTabId(),
            viewportWidth: this.viewportWidth, viewportHeight: this.viewportHeight,
            sideInset: visualThemeStore.isPaper ? 0 : 8,
            topInset: this.statusBarH + FORUM_TOOLBAR_HEIGHT,
            initialY: this.viewportHeight - AppTheme.BAR_TOTAL_H,
            scrollRevision: this.categoryScrollRevision, atTop: this.categoriesAtTop,
            busy: this.vm.loading || this.vm.switchingTab || this.vm.isLoadingMore,
            selectionEnabled: !this.vm.loading || this.vm.switchingTab,
            active: this.pageVisible && this.viewerUrls.length === 0,
            refreshOwnsCollision: this.refreshOwnsCollision,
            refreshX: this.refreshButtonX, refreshY: this.refreshButtonY,
            onMoveStart: (): void => { this.refreshOwnsCollision = false; },
            onBoundsChanged: (x: number, y: number, width: number, height: number): void => {
              this.categoryX = x; this.categoryY = y; this.categoryWidth = width; this.categoryHeight = height;
            },
            onSelect: (tab: ForumTab, index: number): void => { void this.selectForumTab(tab, index); } })
          }
          ForumRefreshButton({ viewportWidth: this.viewportWidth, viewportHeight: this.viewportHeight,
            topInset: this.statusBarH + FORUM_TOOLBAR_HEIGHT,
            active: this.pageVisible && this.viewerUrls.length === 0,
            busy: this.refreshing || this.vm.loading || this.vm.isLoadingMore || this.vm.switchingTab,
            obstacleX: this.categoryX, obstacleY: this.categoryY,
            obstacleWidth: this.categoryPrefs.forumTabsFloating ? this.categoryWidth : 0,
            obstacleHeight: this.categoryPrefs.forumTabsFloating ? this.categoryHeight : 0,
            onMoveStart: (): void => { this.refreshOwnsCollision = true; },
            onPositionChanged: (x: number, y: number): void => { this.refreshButtonX = x; this.refreshButtonY = y; },
            onRefresh: (): void => {
              if (!this.refreshing && !this.vm.loading && !this.vm.isLoadingMore && !this.vm.switchingTab) {
                void this.handleRefresh(true);
              }
            } })
        }

        if (this.viewerUrls.length > 0) {
          ImageViewer({ imageUrls: this.viewerUrls, images: this.viewerItems, initialIndex: this.viewerIndex,
            onClose: (): void => { this.viewerUrls = []; this.viewerItems = []; this.viewerIndex = 0; } })
            .zIndex(100)
            .transition(imageLayerRetentionTransition())
        }
      }
      .width('100%')
      .height(LayoutPolicy.matchParent)
      .onAreaChange((_old: Area, area: Area): void => {
        this.viewportWidth = Number(area.width); this.viewportHeight = Number(area.height);
      })
    }
    // 固定工具栏独立绘制，吧信息与帖子共用列表滚动。
    .hideTitleBar(true)
    .systemBarStyle(
      { statusBarContentColor: this.lightStatusBar() ? '#F2F3F4' : '#1B1B1B' },
      { statusBarContentColor: this.lightStatusBar() ? '#F2F3F4' : '#1B1B1B' }
    )
    .onShown((): void => { this.pageVisible = true; })
    .onHidden((): void => { this.pageVisible = false; this.resetTabTransition(); })
    .onBackPressed((): boolean => {
      if (this.viewerUrls.length > 0) {
        closeImageTransition(this.getUIContext(), (): void => {
          this.viewerUrls = [];
          this.viewerIndex = 0;
        });
        return true;
      }
      if (!this.forumSearchExpanded) { return false; }
      this.closeForumSearch();
      return true;
    })
  }

  /** 无有效吧名时使用的普通顶栏。同样要让出状态栏（页面从 y=0 起排） */
  @Builder
  TopBar() {
    Row({ space: 10 }) {
      // 返回：全站统一的玻璃圆按钮（`components/GlassBackButton.ets`）
      GlassBackButton({
        onTap: (): void => {
          this.goBack();
        }
      })

      Text(this.titleText().endsWith('吧') ? this.titleText() : `${this.titleText()}吧`)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_MAIN)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      .layoutWeight(1)
    }
    .width('100%')
    .height(60 + this.statusBarH)
    .padding({ left: 4, right: 14, top: this.statusBarH })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(AppTheme.CARD)
  }

  @Builder
  ForumHeroBackdrop() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 背景尺寸和裁切不随检测变化，只有前景List的留白按内容决定。
      Column()
        .width('100%')
        .height(this.coverHeight() + this.statusBarH)
        .backgroundColor(this.heroPalette().topColor)

      if (this.vm.heroHeadline.length > 0) {
        this.ForumHeadlineImage(this.vm.heroHeadline)
        Column().width('100%').height(this.coverHeight() + this.statusBarH).backgroundColor('#40000000')
          .hitTestBehavior(HitTestMode.None)
      }

      if (this.vm.heroHeadline.length === 0 && this.vm.forum.heroImage.length > 0) {
        Image(this.vm.forum.heroImage)
          .width('100%')
          .height(this.coverHeight() + this.statusBarH)
          .objectFit(ImageFit.Cover)
          .interpolation(ImageInterpolation.High)
          .colorFilter(FORUM_HERO_PATTERN_COLOR_FILTER)
          .opacity(FORUM_HERO_PATTERN_OPACITY)
      }

      // 吧信息直接落在图上：白字，头像白描边、不跨界。
      // 图保持原样式（184 高 + 24 重叠）。用 bottom 定位让浮层底边贴住图的下沿，
      // 内容向上生长——无论排多高都不会越过图边被裁（顶部方向曾被裁，见 lay_k 实测）。
      Column() {
        // 身份块整块吸收点击，关掉签到/关注按钮的点击穿透。
        // hero 层是 HitTestMode.None，身份块空白处的点击会继续落到列表里的「查看完整封面」行，
        // 于是点签到/关注按钮的边角会连带把封面大图打开。这里用一个空点击把身份块范围内的
        // 触摸留在本层：只吸收点击，不拦拖动，列表仍可从身份块上起手滚动。
        Column() {
          ForumIdentity({ forumId: this.vm.forum.id, forumName: this.titleText(), avatar: this.vm.forum.avatar,
            active: this.pageVisible && this.viewerUrls.length === 0,
            refreshRevision: this.headerRefreshRevision, memberCount: this.vm.forum.memberCount,
            // 简介是否显示决定身份块高度（多 6 + 24vp），页面据此重算上下等距留白。
            avatarVisible: !this.identityCovered,
            onIntroductionVisible: (visible: boolean): void => { this.identityIntroVisible = visible; },
            onOpenInformation: (): void => { this.openForumDirectory('forum'); } })
            .padding({ left: 14, right: 14 })
            .onAreaChange((_old: Area, area: Area): void => {
              const height: number = Math.max(FORUM_IDENTITY_MIN_HEIGHT, Math.ceil(Number(area.height)));
              if (Number.isFinite(height) && height !== this.forumIdentityHeight) {
                this.forumIdentityHeight = height;
                this.syncTabsSticky();
              }
            })
        }
        .width('100%')
        .hitTestBehavior(HitTestMode.Default)
        .onClick((): void => {})
      }
      .width('100%')
      .height(this.coverHeight() + this.statusBarH)
      // 身份块底边落在「面板顶 − identityGap()」；顶部留白与它相等（见 identityGap 注释）。
      .padding({ bottom: FORUM_COVER_OVERLAP + this.identityGap() })
      .justifyContent(FlexAlign.End)
      .clip(false).id('forum-hero-identity')
      .hitTestBehavior(HitTestMode.Default)
    }
    .width('100%')
    .height(this.coverHeight() + this.statusBarH)
    .clip(true)
    .backgroundColor(this.heroPalette().topColor)
    .translate({ y: -this.contentScrollOffset })
    .id('forum-hero-cover')
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private ForumHeadlineImage(url: string) {
    Image(url)
      .id('forum-hero-image')
      .width('100%')
      .height(this.coverHeight() + this.statusBarH)
      .objectFit(ImageFit.Cover)
      .interpolation(ImageInterpolation.High)
  }

  @Builder
  ForumToolbar() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column().width('100%').height(this.statusBarH + FORUM_TOOLBAR_HEIGHT)
        .backgroundColor(AppTheme.BG)
        .opacity(this.toolbarBackgroundProgress()).hitTestBehavior(HitTestMode.None)

      Column() {
        Row({ space: 10 }) {

          GlassBackButton({
            onTap: (): void => {
              this.goBack();
            }
          })
          Stack({ alignContent: Alignment.End }) {
            Row({ space: 8 }) {
              /*
               * 顶栏身份块（2026-11-12 重写）：不再用滚动进度做透明度淡入。
               * 顶栏完全盖住吧头像之后（identityCovered），头像以共享元素（out=英雄区头像）
               * 飞进顶栏，吧名随同一帧淡入；回滚越过阈值反向播放。
               */
              Stack() {
                if (this.identityCovered) {
                  ForumAvatarImage({ url: this.vm.forum.avatar, forumName: this.titleText(),
                    avatarSize: 28, radius: forumAvatarRadius(28) })
                    .geometryTransition('forum-avatar')
                }
              }
              .width(28).height(28)
              Text(this.titleText().endsWith('吧') ? this.titleText() : `${this.titleText()}吧`)
                .fontSize(17).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT_MAIN)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                .opacity(this.identityCovered ? 1 : 0)
                .animation({ duration: motionDuration(220), curve: Curve.EaseOut })
            }
            .width('100%').padding({ right: 50 })
            .hitTestBehavior(this.identityCovered && !this.forumSearchExpanded ? HitTestMode.Default : HitTestMode.None)
            .onClick(() => { this.openForumDirectory('forum'); })

            Stack({ alignContent: Alignment.End }) {
              SearchField({ inputId: 'forum-search-input', text: this.forumSearchText,
                placeholder: '搜索吧内帖子', minimumHeight: 40,
                onChange: (value: string): void => { this.forumSearchText = value; },
                onSubmit: (): void => { this.submitForumSearch(); } })
                .opacity(this.forumSearchProgress)
                .hitTestBehavior(this.forumSearchExpanded ? HitTestMode.Default : HitTestMode.None)
              GlassCircleButton({ symbol: $r('sys.symbol.magnifyingglass'), iconSize: 22,
                accessibilityLabel: '搜索吧内帖子', onTap: (): void => { this.openForumSearch(); } })
                .opacity(1 - this.forumSearchProgress)
                .hitTestBehavior(this.forumSearchExpanded ? HitTestMode.None : HitTestMode.Default)
            }
            .width(40 + Math.max(0, this.forumSearchSlotWidth - 40) * this.forumSearchProgress)
            // 圆形按钮自行裁剪材质；外层保留阴影，避免被40vp矩形截成方块。
            .height(40).clip(false).id('forum-search-expand')
          }
          .layoutWeight(1).height(40)
          .onAreaChange((_old: Area, area: Area): void => {
            const width: number = Number(area.width);
            if (width > 0 && Math.abs(width - this.forumSearchSlotWidth) > 0.5) { this.forumSearchSlotWidth = width; }
          })
        }
        .width('100%')
        .height(56)
        .padding({ left: 4, right: 16 })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%').padding({ top: this.statusBarH })
    }
    .width('100%').height(this.statusBarH + FORUM_TOOLBAR_HEIGHT)
    .id('forum-fixed-toolbar').zIndex(5)
  }

  /**
   * 吧信息本体在 hero 层（`forum-hero-identity`，底边贴图下沿向上生长），
   * 此 Builder 只保留图下露出段的占位；吧信息不再计入列表高度，
   * tabs 紧跟图底，中间不再出现整段空白。
   *
   * 点击穿透：占位行在 z 序上盖住 hero 身份块，
   * 若整条占位行都可点，吧名与关注/签到按钮会**整块**被它吞掉（真机命中日志只看到
   * `forum-cover-open` 接受点击）。所以只把身份块上方那条带做成可点，
   * 身份块所在高度留一条不可点的占位行，让点击落到 hero 层的身份块上。
   */
  @Builder
  ForumHeaderIdentity() {
    Column() {
      Row().width('100%').height(this.coverClickHeight())
        .id('forum-cover-open').accessibilityText('查看完整封面')
        .hitTestBehavior(this.vm.heroHeadline.length > 0 ? HitTestMode.Default : HitTestMode.None)
        .onClick(() => {
          if (this.vm.heroHeadline.length > 0) {
            this.viewerUrls = [this.vm.heroHeadline];
            this.viewerItems = [];
            this.viewerIndex = 0;
          }
        })
      Row().width('100%').height(Math.max(0, this.coverSpacerHeight() - this.coverClickHeight()))
    }
    .width('100%')
    .clip(false)
    .id('forum-scroll-identity')
  }

  private coverHeight(): number {
    return FORUM_COVER_FULL_HEIGHT;
  }

  private coverSpacerHeight(): number {
    return this.coverHeight() - FORUM_TOOLBAR_HEIGHT - FORUM_COVER_OVERLAP;
  }

  /**
   * 「查看完整封面」的可点高度：身份块上方那条带。
   * 身份块底边在占位行底上方 `identityGap()`，块高取实测值（首帧未测量时用几何值，
   * 避免第一次布局就把按钮算进可点带）。不盖住身份块，才能让吧名/签到按钮接到点击。
   */
  private coverClickHeight(): number {
    const block: number = this.forumIdentityHeight > FORUM_IDENTITY_MIN_HEIGHT
      ? this.forumIdentityHeight : this.identityBlockHeight();
    return Math.max(0, Math.min(this.coverSpacerHeight(),
      this.coverSpacerHeight() - this.identityGap() - block));
  }

  private heroHeight(): number {
    return this.coverHeight() - FORUM_COVER_OVERLAP + this.forumIdentityHeight + FORUM_IDENTITY_BOTTOM_GAP + FORUM_IDENTITY_CARD_GAP;
  }

  /** 身份块可见高度：头像框；未关注再加「6vp 间距 + 24vp 简介胶囊」。 */
  private identityBlockHeight(): number {
    return FORUM_AVATAR_FRAME_SIZE +
      (this.identityIntroVisible ? FORUM_IDENTITY_INTRO_GAP + FORUM_IDENTITY_INTRO_HEIGHT : 0);
  }

  /**
   * 身份块上方（头像顶 → 顶部按钮底端）与下方（块底 → 内容面板顶）的留白，二者相等。
   * 可分配区间 = 面板顶 − 按钮底端 = (封面高 − 压图重叠) − [56 − (56 − 40) / 2] = 134vp；
   * 未关注多一行简介时头像随之上移，两侧各 16；不显简介时各 31。
   */
  private identityGap(): number {
    const panelTop: number = this.coverHeight() - FORUM_COVER_OVERLAP;
    const buttonBottom: number = FORUM_TOOLBAR_HEIGHT - (FORUM_TOOLBAR_HEIGHT - FORUM_TOOLBAR_BUTTON_SIZE) / 2;
    return Math.max(0, (panelTop - buttonBottom - this.identityBlockHeight()) / 2);
  }

  /** Hero 配色：由协议吧主题色派生。无主题色时返回既有深蓝兜底（见 ForumHeroStyle） */
  private heroPalette(): ForumHeroPalette {
    const palette: ForumHeroPalette = forumHeroPalette(this.vm.forum.heroColor);
    if (visualThemeStore.isPaper && !palette.hasThemeColor) {
      palette.topColor = '#2E6B73'; palette.bottomColor = '#193C40';
    }
    return palette;
  }

  /** 贴住工具栏后官方材质胶囊的宽度：沿用常规胶囊实测宽度，未测到前按字数估算。 */
  private tabPillWidth(tab: ForumTab): number {
    void this.topTabWidthRevision;
    const measured: number | undefined = this.topTabWidths.get(tab.id);
    return measured ?? (tab.name.length * 15 + FORUM_TAB_PILL_PADDING * 2);
  }

  private topTabGap(): number {
    return this.stickyTabs() ? FORUM_TAB_STICKY_GAP : FORUM_TAB_PILL_GAP;
  }

  private hasValidSelectedTopTab(): boolean {
    const targetId: number = this.displaySelectedTabId();
    return this.vm.tabs.some((tab: ForumTab): boolean => tab.id === targetId);
  }

  private stickyIndicatorX(): number {
    void this.topTabWidthRevision;
    const targetId: number = this.displaySelectedTabId();
    let start: number = FORUM_TAB_PILL_INSET;
    for (const tab of this.vm.tabs) {
      const width: number = this.topTabWidths.get(tab.id) ?? tab.name.length * 15;
      if (tab.id === targetId) {
        return start + (width - FORUM_TAB_STICKY_INDICATOR_WIDTH) / 2;
      }
      start += width + FORUM_TAB_STICKY_GAP;
    }
    return FORUM_TAB_PILL_INSET;
  }

  private capsuleIndicatorX(): number {
    void this.topTabWidthRevision;
    const targetId: number = this.displaySelectedTabId();
    let start: number = 0;
    for (const tab of this.vm.tabs) {
      const width: number = this.tabPillWidth(tab);
      if (tab.id === targetId) {
        return start;
      }
      start += width + FORUM_TAB_PILL_GAP;
    }
    return 0;
  }

  private capsuleIndicatorWidth(): number {
    void this.topTabWidthRevision;
    const targetId: number = this.displaySelectedTabId();
    const tab: ForumTab | undefined = this.vm.tabs.find((item: ForumTab): boolean => item.id === targetId);
    return tab !== undefined ? this.tabPillWidth(tab) : 0;
  }

  /**
   * 分类行悬浮层的屏幕 y：在列表里自然位置 = 工具栏下沿 + 图下露出段 − 当前滚动量，
   * 到达工具栏下沿后夹住不动（等价吸顶）。不依赖 List 的 sticky，因此没有那条固定接缝。
   */
  private tabsOverlayY(): number {
    const base: number = this.statusBarH + FORUM_TOOLBAR_HEIGHT;
    return Math.max(base, base + this.coverSpacerHeight() - this.contentScrollOffset);
  }

  /** 常规吸顶（分类栏样式三选一里的第一种）：分类栏固定在工具栏下、文字 + 选中下划线。 */
  private stickyTabs(): boolean {
    return this.categoryPrefs.forumTabsStyle === ForumTabsStyle.STICKY;
  }

  /**
   * 常规吸顶分类行：纯文字 + 选中下划线，无胶囊、无材质。
   * 这一行由外层悬浮层固定在工具栏下沿，所以背板必须铺面板色，否则内容会从字缝里穿过。
   */
  @Builder
  StickyTabsRow() {
    Scroll(this.topTabsScroller) {
      Stack({ alignContent: Alignment.BottomStart }) {
        Row({ space: FORUM_TAB_STICKY_GAP }) {
          ForEach(this.vm.tabs, (tab: ForumTab, index: number) => {
            Column() {
              Text(tab.name).fontSize(15).maxFontScale(1.25)
                .fontWeight(tab.id === this.displaySelectedTabId() ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(tab.id === this.displaySelectedTabId() ? AppTheme.TEXT_MAIN : AppTheme.TEXT_SUB)
                .maxLines(1)
            }
            .height(FORUM_TAB_STICKY_ROW_HEIGHT)
            .justifyContent(FlexAlign.End)
            .padding({ bottom: 11 })
            .accessibilityText(`分类 ${tab.name}${tab.id === this.displaySelectedTabId() ? '，已选中' : ''}`)
            .onClick((): void => { this.selectForumTab(tab, index); })
            .onAreaChange((_old: Area, area: Area): void => {
              const width: number = Number(area.width);
              if (this.topTabWidths.get(tab.id) !== width) {
                this.topTabWidths.set(tab.id, width);
                this.topTabWidthRevision = (this.topTabWidthRevision || 0) + 1;
                if (tab.id === this.vm.targetTabId()) { this.revealTopCategory(); }
              }
            })
          }, (tab: ForumTab) => String(tab.id))
        }
        .height(FORUM_TAB_STICKY_ROW_HEIGHT)
        .padding({ left: FORUM_TAB_PILL_INSET, right: FORUM_TAB_PILL_INSET })
        .alignItems(VerticalAlign.Center)

        if (this.hasValidSelectedTopTab()) {
          Row()
            .width(FORUM_TAB_STICKY_INDICATOR_WIDTH)
            .height(3)
            .borderRadius(1.5)
            .backgroundColor(AppTheme.ACCENT)
            .margin({ bottom: 6 })
            .translate({ x: this.stickyIndicatorX() })
            .animation({ duration: motionDuration(240, MotionEffect.MOVE), curve: FORUM_TAB_SILK_CURVE })
            .hitTestBehavior(HitTestMode.None)
        }
      }
      .height(FORUM_TAB_STICKY_ROW_HEIGHT)
    }
    .width('100%').height(FORUM_TAB_STICKY_ROW_HEIGHT)
    .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.Start)
  }

  private forumHeaderHeight(): number {
    if (this.categoryPrefs.forumTabsFloating) { return 0; }
    return this.stickyTabs() ? FORUM_TAB_STICKY_ROW_HEIGHT : FORUM_TAB_ROW_HEIGHT;
  }
  private revealTopCategory(): void {
    if (this.categoryPrefs.forumTabsFloating) { return; }
    this.getUIContext().postFrameCallback(new ForumTabFrameCallback((): void => {
      if (!this.active || this.categoryPrefs.forumTabsFloating) { return; }
      const gap: number = this.topTabGap();
      let start: number = FORUM_TAB_PILL_INSET;
      for (const tab of this.vm.tabs) {
        const width: number = this.topTabWidths.get(tab.id) ?? (this.stickyTabs() ? tab.name.length * 15 : tab.name.length * 15 + FORUM_TAB_PILL_PADDING * 2);
        if (tab.id === this.displaySelectedTabId()) {
          this.topTabsScroller.scrollTo({ xOffset: Math.max(0, start + width / 2 - this.viewportWidth / 2),
            yOffset: 0, animation: { duration: motionDuration(260, MotionEffect.MOVE), curve: Curve.EaseOut } });
          return;
        }
        start += width + gap;
      }
    }));
  }

  /** 两种模式共用分类数据与选择行为；顶部模式为实心胶囊分段（选中=强调色实底白字）。 */
  @Builder
  ForumTabs() {
    Column() {
      if (!this.categoryPrefs.forumTabsFloating) {
        if (this.stickyTabs()) {
          this.StickyTabsRow()
        } else {
          Scroll(this.topTabsScroller) {
            if (this.tabsDocked && !this.categoryPrefs.forumTabsFloating) {
              Row({ space: FORUM_TAB_PILL_GAP }) {
                ForEach(this.vm.tabs, (tab: ForumTab, index: number) => {
                  GlassPillButton({ label: tab.name,
                    accessibilityLabel: `分类 ${tab.name}${tab.id === this.displaySelectedTabId() ? '，已选中' : ''}`,
                    pillWidth: this.tabPillWidth(tab), pillHeight: FORUM_TAB_PILL_HEIGHT,
                    slot: tab.id === this.displaySelectedTabId() ? MaterialSlot.FORUM_TAB_SELECTION : MaterialSlot.BACK_BUTTON,
                    applyShadow: true, clipToPill: true, clipOutset: 0, staticMaterial: true,
                    textColor: tab.id === this.displaySelectedTabId() ? AppTheme.ACCENT_DARK : AppTheme.TEXT_MAIN,
                    textWeight: tab.id === this.displaySelectedTabId() ? FontWeight.Medium : FontWeight.Regular,
                    onTap: (): void => { this.selectForumTab(tab, index); } })
                }, (tab: ForumTab) => String(tab.id))
              }.height(FORUM_TAB_ROW_HEIGHT).alignItems(VerticalAlign.Top)
                .padding({ left: FORUM_TAB_PILL_INSET, right: FORUM_TAB_PILL_INSET, top: FORUM_TAB_PILL_TOP_GAP })
            } else {
              Stack({ alignContent: Alignment.TopStart }) {
                Row({ space: FORUM_TAB_PILL_GAP }) {
                  ForEach(this.vm.tabs, (tab: ForumTab) => {
                    Row()
                      .width(this.tabPillWidth(tab))
                      .height(FORUM_TAB_PILL_HEIGHT)
                      .borderRadius(FORUM_TAB_PILL_HEIGHT / 2)
                      .backgroundColor(AppTheme.CARD)
                  }, (tab: ForumTab) => String(tab.id))
                }
                .height(FORUM_TAB_PILL_HEIGHT)
                .hitTestBehavior(HitTestMode.None)

                if (this.hasValidSelectedTopTab()) {
                  Row()
                    .width(this.capsuleIndicatorWidth())
                    .height(FORUM_TAB_PILL_HEIGHT)
                    .borderRadius(FORUM_TAB_PILL_HEIGHT / 2)
                    .backgroundColor(AppTheme.ACCENT)
                    .translate({ x: this.capsuleIndicatorX() })
                    .animation({ duration: motionDuration(240, MotionEffect.MOVE), curve: FORUM_TAB_SILK_CURVE })
                    .hitTestBehavior(HitTestMode.None)
                }

                Row({ space: FORUM_TAB_PILL_GAP }) {
                  ForEach(this.vm.tabs, (tab: ForumTab, index: number) => {
                    Row() {
                      Text(tab.name).fontSize(15).maxFontScale(1.25)
                        .fontWeight(tab.id === this.displaySelectedTabId() ? FontWeight.Medium : FontWeight.Normal)
                        .fontColor(tab.id === this.displaySelectedTabId() ? Color.White : AppTheme.TEXT_MAIN)
                        .maxLines(1)
                    }
                    .height(FORUM_TAB_PILL_HEIGHT)
                    .padding({ left: FORUM_TAB_PILL_PADDING, right: FORUM_TAB_PILL_PADDING })
                    .borderRadius(FORUM_TAB_PILL_HEIGHT / 2)
                    .backgroundColor(Color.Transparent)
                    .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
                    .accessibilityText(`分类 ${tab.name}${tab.id === this.displaySelectedTabId() ? '，已选中' : ''}`)
                    .onClick((): void => { this.selectForumTab(tab, index); })
                    .onAreaChange((_old: Area, area: Area): void => {
                      const width: number = Number(area.width);
                      // 横向滚动也会改变标签位置；只在宽度变化时重新定位，避免拖动时被拉回选中项。
                      if (this.topTabWidths.get(tab.id) !== width) {
                        this.topTabWidths.set(tab.id, width);
                        this.topTabWidthRevision = (this.topTabWidthRevision || 0) + 1;
                        if (tab.id === this.vm.targetTabId()) { this.revealTopCategory(); }
                      }
                    })
                  }, (tab: ForumTab) => String(tab.id))
                }
                .height(FORUM_TAB_PILL_HEIGHT)
              }
              .height(FORUM_TAB_ROW_HEIGHT)
              .padding({ left: FORUM_TAB_PILL_INSET, right: FORUM_TAB_PILL_INSET, top: FORUM_TAB_PILL_TOP_GAP })
            }
          }.width('100%').height(FORUM_TAB_ROW_HEIGHT).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.Start)
        }
      }
    // 分类行底色：整条横带始终不铺（对照「我的华为」社区页）；
    // 贴住工具栏后只把**胶囊本身**换成官方沉浸材质（见 ForumTabs 里 tabsDocked 分支）。
    }.width('100%')
      // 常规吸顶要铺面板色 + 细分割线：它固定在工具栏下，内容会从底下穿过。
      .backgroundColor(this.stickyTabs() && this.tabsDocked ? AppTheme.FORUM_TAB_BG : Color.Transparent)
      .border(this.stickyTabs() && this.tabsDocked ? { width: { bottom: 0.5 }, color: AppTheme.DIVIDER } : { width: 0 })
      .height(this.forumHeaderHeight())
      // 圆角统一由外层 ListItemGroup 负责（它铺底色），此处不再单独设，避免两层圆角错位。
      .clip(true)
  }
  private async changePostOrder(sort: number): Promise<void> {
    const success: boolean = await this.vm.changeSort(this.hostContext(), sort);
    if (success) {
      this.activeScroller().scrollTo({ xOffset: 0,
        yOffset: Math.min(this.activeScroller().currentOffset().yOffset, this.contentTopOffset()), animation: false });
    } else if (this.vm.errorText.length > 0) {
      promptAction.showToast({ message: this.vm.errorText, duration: 1800 });
    }
  }

  @Builder
  PostOrderBar() {
    Row() {
      if (this.vm.isHelpTab()) {
        Row({ space: 20 }) {
          ForEach(['全部', '未回答'], (label: string, index: number) => {
            Text(label).fontSize(12).fontColor(this.vm.helpPartition === index ? AppTheme.TEXT_MAIN : AppTheme.TEXT_MUTED)
              .fontWeight(this.vm.helpPartition === index ? FontWeight.Bold : FontWeight.Normal)
              .height(FORUM_POST_ORDER_HEIGHT).accessibilityText(`互助筛选 ${label}`)
              .onClick(() => { void this.changeHelpFilter(index, this.vm.currentSort()); })
          }, (label: string) => label)
        }.layoutWeight(1)
      } else {
        Text('看帖顺序').fontSize(12).fontColor(AppTheme.TEXT_SUB).layoutWeight(1)
      }
      if (this.vm.hasPostOrder()) {
        Row() {
          ForEach(['回复', '发布'], (label: string, index: number) => {
            Text(label).fontSize(11)
              .fontColor(this.vm.currentSort() === index ? AppTheme.TEXT_MAIN : AppTheme.TEXT_MUTED)
              .padding({ left: 10, right: 10 }).height(24).borderRadius(12)
              .backgroundColor(this.vm.currentSort() === index ? AppTheme.CARD : Color.Transparent)
              .accessibilityText(`${this.vm.isHelpTab() ? '互助' : '吧内'}排序 最新${label}`)
              .onClick(() => { void this.changePostOrder(index); })
          }, (label: string) => label)
        }.borderRadius(12).backgroundColor(AppTheme.BG)
      }
    }.width('100%').height(FORUM_POST_ORDER_HEIGHT).padding({ left: 16, right: 16 })
      .backgroundColor(this.categoryPrefs.forumTabsFloating ? AppTheme.CARD : AppTheme.FORUM_TAB_BG)
      .borderRadius(this.categoryPrefs.forumTabsFloating ? 12 : 0)
      .enabled(!this.vm.loading && !this.vm.switchingTab && !this.vm.isLoadingMore)
  }

  private async changeHelpFilter(partition: number, sort: number): Promise<void> {
    const success: boolean = await this.vm.changeHelpFilter(this.hostContext(), partition, sort);
    if (success) {
      this.activeScroller().scrollTo({ xOffset: 0,
        yOffset: Math.min(this.activeScroller().currentOffset().yOffset, this.contentTopOffset()), animation: false });
    } else if (this.vm.errorText.length > 0) {
      promptAction.showToast({ message: this.vm.errorText, duration: 1800 });
    }
  }

  /**
   * 点击分类标签：与首页 `ForumListView.changeChannel` 同口径，由原生 `SwiperController.changeIndex`
   * 驱动整页平滑切换；`onAnimationStart` 即时同步标签高亮，`onChange` 再落定数据。
   */
  private selectForumTab(tab: ForumTab, index: number): void {
    if ((this.vm.loading && !this.vm.switchingTab) || tab.id === this.displaySelectedTabId()) {
      return;
    }
    this.previewTabId = tab.id;
    this.revealTopCategory();
    this.syncInactiveTabHeaders(this.activeTabId(), Math.min(this.contentScrollOffset, this.coverSpacerHeight()));
    this.tabSwiper.changeIndex(index, motionStore.isOn(MotionEffect.MOVE));
  }

  private onSwiperAnimationStart(targetIndex: number): void {
    const tab: ForumTab | undefined = this.vm.tabs[targetIndex];
    if (tab === undefined || tab.id === this.previewTabId) { return; }
    this.previewTabId = tab.id;
    this.revealTopCategory();
  }

  private async commitForumTab(index: number): Promise<void> {
    const tab: ForumTab | undefined = this.vm.tabs[index];
    if (tab === undefined) { return; }
    if (tab.id === this.vm.selectedTabId) {
      this.previewTabId = 0;
      this.syncTabsSticky(tab.id);
      return;
    }
    const revision: number = ++this.tabSwitchRevision;
    const success: boolean = await this.vm.switchTab(this.hostContext(), tab.id);
    if (!this.active || revision !== this.tabSwitchRevision) { return; }
    this.previewTabId = 0;
    if (success) {
      this.syncTabsSticky(tab.id);
      this.revealTopCategory();
    } else {
      if (this.vm.errorText.length > 0) {
        promptAction.showToast({ message: this.vm.errorText, duration: 1800 });
      }
      const fallbackIndex: number = this.vm.tabs.findIndex((item: ForumTab): boolean => item.id === this.vm.selectedTabId);
      if (fallbackIndex >= 0 && fallbackIndex !== index) {
        this.tabSwiper.changeIndex(fallbackIndex, false);
      }
    }
  }

  private toolbarBackgroundProgress(): number {
    return Math.max(0, Math.min(1, this.contentScrollOffset / this.coverSpacerHeight()));
  }

  private toolbarTitleProgress(): number {
    const start: number = this.coverSpacerHeight() + FORUM_IDENTITY_TITLE_TOP;
    return Math.max(0, Math.min(1, (this.contentScrollOffset - start) / 36));
  }

  @Builder
  TabListPage(tab: ForumTab) {
    List({ space: 0, scroller: this.scrollerForTab(tab.id) }) {
      // 占位：图下露出段（吧信息本体在 hero 层）。
      ListItem() {
        this.ForumHeaderIdentity()
      }
      .clip(false)
      .id(tab.id === this.activeTabId() ? 'forum-header-item' : `forum-header-item-${tab.id}`)
      /*
       * 分类行不再挂在 ListItemGroup 的 header 上：List 的吸顶 header
       * 会在底部留一条固定的浅色接缝，且无法控制其底色。真正的分类行由 `TabsOverlay()` 悬浮绘制，
       * 位置按滚动量自己算。
       * 它那一行的高度**垫在 ListItemGroup 里面**（见下），不要放在组外：组外是透明的，
       * 面板顶上移后会露出页面底色，贴顶停住时就是一条浅灰带。
       */
      ListItemGroup() {
        // 分类行留白：透明，吃的是面板底色；面板顶因此仍落在「封面底 −20vp」压图的位置。
        ListItem() {
          Row().width('100%').height(this.forumHeaderHeight())
        }
        .id(tab.id === this.activeTabId() ? 'forum-tabs-slot' : `forum-tabs-slot-${tab.id}`)
        if (tab.supportsPostOrder || tab.isHelp) {
          ListItem() {
            this.PostOrderBar()
          }
          .padding({ left: this.categoryPrefs.forumTabsFloating ? 8 : 0,
            right: this.categoryPrefs.forumTabsFloating ? 8 : 0 })
        }
        // 保留零高度刷新项，收起时高度可连续回弹，不因移除组件而瞬间跳回。
        ListItem() {
          Row() {
            if (tab.id === this.activeTabId() && (this.refreshing || this.pullDistance > 0)) { RefreshSpinner() }
          }
          .width('100%').height(tab.id === this.activeTabId() ? this.pullDistance : 0)
          .justifyContent(FlexAlign.Center).clip(true)
          .id(tab.id === this.activeTabId() ? 'forum-pull-refresh' : `forum-pull-refresh-${tab.id}`)
        }
        if (tab.id === this.activeTabId() && !this.refreshing && !this.vm.switchingTab && tab.supportsPostOrder && this.vm.loading) {
          ListItem() {
            Column({ space: 12 }) {
              RefreshSpinner()
              Text('正在加载分类…').fontSize(14).fontColor(AppTheme.TEXT_SUB)
            }
            .width('100%').height(Math.max(240, this.contentHeight - this.forumHeaderHeight()))
            .justifyContent(FlexAlign.Center)
            .id('forum-content-loading')
          }
        } else if (!this.vm.isTabCached(tab.id)) {
          ListItem() {
            Column({ space: 12 }) {
              RefreshSpinner()
              Text('正在加载分类…').fontSize(14).fontColor(AppTheme.TEXT_SUB)
            }
            .width('100%').height(Math.max(240, this.contentHeight - this.forumHeaderHeight()))
            .justifyContent(FlexAlign.Center)
          }
        } else if (tab.id === this.activeTabId() && this.vm.errorText.length > 0 && this.vm.threadsForTab(tab.id).length === 0) {
          ListItem() {
            Column() { this.ErrorView() }
              .width('100%').height(Math.max(240, this.contentHeight - this.forumHeaderHeight()))
          }
        } else if (tab.isVideo) {
          if (this.videoItemsForTab(tab.id).length === 0) {
            ListItem() { this.StatusView('这个分类暂无可播放视频') }
          } else {
            ListItem() {
              Row({ space: 8 }) {
                ForEach([0, 1], (side: number) => {
                  Column({ space: 8 }) {
                    ForEach(this.videoColumnForTab(tab.id, side), (item: ThreadBrief) => { this.VideoCard(item) }, (item: ThreadBrief) => `${item.tid}`)
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                }, (side: number) => `${side}`)
              }.width('100%').alignItems(VerticalAlign.Top)
            }.padding({ left: visualThemeStore.isPaper ? 0 : 8, right: visualThemeStore.isPaper ? 0 : 8,
              top: visualThemeStore.isPaper ? 0 : ThreadCardLayout.LIST_GAP })
          }
          ListItem() { this.PageFooter(tab.id) }.padding({ left: 8, right: 8 })
        } else if (this.vm.threadsForTab(tab.id).length === 0) {
          ListItem() {
            Column() { this.StatusView(tab.isHelp ?
              (this.vm.helpPartition === 1 ? '暂时没有未回答的求助' : '这个分类还没有求助帖') : '这个吧还没有帖子') }
              .width('100%').height(Math.max(240, this.contentHeight - this.forumHeaderHeight()))
          }
        } else {
          if (this.pinnedThreadsForTab(tab.id).length > 0) {
            ListItem() {
              this.PinnedSection(tab.id)
            }
            .padding({ left: visualThemeStore.isPaper ? 0 : 8, right: visualThemeStore.isPaper ? 0 : 8,
              top: visualThemeStore.isPaper ? 0 : ThreadCardLayout.LIST_GAP })
          }

          /*
           * 普通帖走 `LazyForEach` + `ThreadBriefDataSource`（虚拟化保留：按可视区 +
           * 预加载区创建、滑出回收）。**不能换回 `Repeat`**：2026-11-13 真机实测，
           * `Repeat`（含去掉 `virtualScroll` 的写法）在整批替换数据后不会重建已实例化的
           * `ListItem` —— 刷新回源成功、批次指纹变了，屏上卡片却不动（首页同一病）。
           */
          LazyForEach(this.sourceForTab(tab.id), (item: ThreadBrief) => {
            ListItem() {
              if (tab.isHelp) {
                HelpThreadCard({ item: item,
                  onOpenThread: (): void => { this.openThread(item); },
                  onOpenAnswer: (): void => {
                    this.saveScrollPosition();
                    NavigationService.openThreadDetail({ tid: item.tid, forumName: this.forumName,
                      replyCount: item.replyCount, targetPid: item.answerPid, openComments: item.answerPid <= 0 });
                  },
                  onOpenImage: (): void => { this.openImages(item.images, 0); } })
              } else {
                this.ThreadCard(item)
              }
            }
            .padding({ left: visualThemeStore.isPaper ? 0 : 8, right: visualThemeStore.isPaper ? 0 : 8,
              top: visualThemeStore.isPaper ? 0 : ThreadCardLayout.LIST_GAP })
          }, (item: ThreadBrief): string => this.cardKey(item))

          ListItem() {
            this.PageFooter(tab.id)
          }
          .padding({ left: 8, right: 8 })
        }
      }
      // 面板底色与 20vp 顶部圆角已抽到 Swiper 外的静止底板层，避免横滑切页时分类栏背后的圆角底板跟着分裂移动。
      .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
    .sticky(StickyStyle.None)
    .parallelGesture(PanGesture({ direction: PanDirection.Vertical, distance: 8 })
      .onActionStart((event: GestureEvent) => {
        if (tab.id !== this.activeTabId()) { return; }
        this.categoryScrollNotified = false;
        const offset: number = this.scrollerForTab(tab.id).currentOffset().yOffset;
        const contentTop: number = Math.max(0, this.heroHeight() - FORUM_TOOLBAR_HEIGHT - offset)
          + this.forumHeaderHeight()
          + (tab.supportsPostOrder || tab.isHelp ? FORUM_POST_ORDER_HEIGHT : 0);
        this.pullEligible = !this.refreshing && !this.vm.loading && !this.vm.switchingTab
          && !this.vm.isLoadingMore && offset <= this.heroHeight() - FORUM_TOOLBAR_HEIGHT + 1
          && event.fingerList.length > 0 && event.fingerList[0].localY - event.offsetY >= contentTop;
      })
      .onActionUpdate((event: GestureEvent) => {
        if (tab.id !== this.activeTabId()) { return; }
        if (!this.categoryScrollNotified && Math.abs(event.offsetY) > 12 && this.scrollerForTab(tab.id).currentOffset().yOffset > 8) {
          this.categoryScrollNotified = true; ++this.categoryScrollRevision;
        }
        if (this.pullEligible) { this.pullDistance = this.dampedPullDistance(event.offsetY); }
      })
      .onActionEnd(() => {
        if (!this.pullEligible) { return; }
        const refresh: boolean = this.pullEligible && this.pullDistance >= FORUM_REFRESH_OFFSET;
        this.pullEligible = false;
        if (refresh) { void this.handleRefresh(); }
        else { this.settlePullDistance(0); }
      })
      .onActionCancel(() => {
        if (!this.pullEligible) { return; }
        this.pullEligible = false; this.settlePullDistance(0);
      }))
    .hitTestBehavior(HitTestMode.Transparent)
    .onAppear(() => {
      this.alignTabScrollerOnAppear(tab.id);
    })
    .onDidScroll(() => {
      this.syncTabsSticky(tab.id);
    })
    .onReachEnd(() => {
      if (tab.id === this.activeTabId()) {
        this.vm.loadMore(this.hostContext());
      }
    })
    .onAreaChange(() => {
      if (tab.id === this.activeTabId()) {
        this.restoreScrollPosition();
      }
    })
  }

  @Builder
  ThreadList() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.ForumHeroBackdrop()
      if (!this.categoryPrefs.forumTabsFloating) {
        Column()
          .width('100%')
          .height(LayoutPolicy.matchParent)
          .backgroundColor(AppTheme.FORUM_TAB_BG)
          .borderRadius({ topLeft: 20, topRight: 20 })
          .position({ x: 0, y: this.tabsOverlayY() })
          .hitTestBehavior(HitTestMode.None)
      }
      Column() {
        Row().height(this.statusBarH + FORUM_TOOLBAR_HEIGHT).width('100%').hitTestBehavior(HitTestMode.None)
        Column() {
          Swiper(this.tabSwiper) {
            ForEach(this.displayTabs(), (tab: ForumTab) => {
              this.TabListPage(tab)
            }, (tab: ForumTab) => String(tab.id))
          }
          .width('100%')
          .layoutWeight(1)
          .indicator(false)
          .loop(false)
          .cachedCount(1)
          .duration(motionDuration(400))
          .curve(motionSwiperCurve())
          .disableSwipe(this.vm.tabs.length <= 1 || (this.vm.loading && !this.vm.switchingTab))
          .onAppear(() => {
            this.swiperReady = true;
            const index: number = this.selectedTabIndex();
            if (index >= 0) { this.tabSwiper.changeIndex(index, false); }
          })
          .onGestureSwipe(() => {
            this.syncInactiveTabHeaders(this.activeTabId(), Math.min(this.contentScrollOffset, this.coverSpacerHeight()));
          })
          .onAnimationStart((_index: number, targetIndex: number) => {
            this.onSwiperAnimationStart(targetIndex);
          })
          .onChange((index: number) => {
            void this.commitForumTab(index);
          })
        }
        .layoutWeight(1)
        .onAreaChange((_old: Area, area: Area) => { this.contentHeight = Number(area.height); })
        .hitTestBehavior(HitTestMode.Transparent)
      }
      .width('100%').height(LayoutPolicy.matchParent).hitTestBehavior(HitTestMode.Transparent)
      // 分类行悬浮层：跟着内容上滑，到工具栏下沿停住（等价原来的吸顶，但底色/接缝完全可控）。
      if (!this.categoryPrefs.forumTabsFloating) {
        Column() {
          this.ForumTabs()
        }
        .width('100%')
        .position({ x: 0, y: this.tabsOverlayY() })
        /*
         * 触摸处理：原来是 `HitTestMode.Transparent`（空白处放行纵向手势），
         * 但 Transparent 的语义是"自身不拦截、允许下层节点一起响应"——于是拖分类胶囊时列表也收到同一串事件，
         * 页面跟着滚。这里改回默认的 `Default`（自身与子节点响应、阻断下层兄弟）：在分类行上起手的拖拽
         * 只归这一行（横滑滚分类），不再带页面。代价：从这 56vp 带内起手不能纵向滚列表 / 触发下拉刷新。
         */
        .hitTestBehavior(HitTestMode.Default)
        .accessibilityGroup(true)
        .accessibilityText('吧分类栏')
      }
      this.ForumToolbar()
    }
    .width('100%').height(LayoutPolicy.matchParent)
  }

  /** 收起时保留首条置顶及总数；按钮独立于标题入口，避免误进帖子。 */
  @Builder
  PinnedSection(tabId: number) {
    Column() {
      ForEach(this.visiblePinnedThreads(this.pinnedThreadsForTab(tabId)), (item: ThreadBrief, index: number) => {
        Row({ space: 8 }) {
          Row({ space: 8 }) {
            TaggedThreadText({ text: item.title.length > 0 ? item.title : '（无标题）', labels: ['置顶'],
              textSize: 14, lineSize: 20, weight: FontWeight.Normal, textColor: AppTheme.TEXT_MAIN,
              lines: 1, fillPinned: false }).layoutWeight(1)
          }.layoutWeight(1).height('100%').alignItems(VerticalAlign.Center).onClick(() => { this.openThread(item); })
          if (index === 0 && this.pinnedThreadsForTab(tabId).length > 1) {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 5 }) {
                Text(this.pinnedExpanded ? '收起' : `共${this.pinnedThreadsForTab(tabId).length}条`)
                  .fontSize(11).fontColor(AppTheme.TEXT_SUB)
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(10).fontColor([AppTheme.TEXT_SUB])
                  .rotate({ angle: this.pinnedExpanded ? -90 : 90 })
              }.height(24).padding({ left: 8, right: 8 }).borderRadius(12)
                .border({ width: 0.5, color: AppTheme.TEXT_MUTED })
            }
              .backgroundColor(Color.Transparent).stateEffect(false).height(36).padding({ left: 0, right: 0 })
              .accessibilityText(this.pinnedExpanded ? '收起置顶帖' : `展开全部${this.pinnedThreadsForTab(tabId).length}条置顶帖`)
              .onClick(() => { this.pinnedExpanded = !this.pinnedExpanded; })
          }
        }
        .width('100%').height(36).padding({ left: 10, right: 10 }).alignItems(VerticalAlign.Center)
        .border({ width: { bottom: index < this.visiblePinnedThreads(this.pinnedThreadsForTab(tabId)).length - 1 ? 1 : 0 },
          color: AppTheme.DIVIDER })
      }, (item: ThreadBrief) => `${item.tid}`)
    }
    .width('100%').borderRadius(12).backgroundColor(AppTheme.CARD).padding({ top: 2, bottom: 2 })
    .id(tabId === this.activeTabId() ? 'forum-pinned-section' : `forum-pinned-section-${tabId}`)
  }

  /** 与首页共用完整卡片；吧内省略来源吧名，没有可用菜单时不预留菜单按钮。 */
  private videoItemsForTab(tabId: number): ThreadBrief[] {
    void this.vm.tabSnapshotRevision;
    return visibleThreads(this.vm.threadsForTab(tabId), threadBlockStore.rules(), false)
      .filter((item: ThreadBrief): boolean => item.isVideo && item.video !== undefined);
  }
  private videoRatio(item: ThreadBrief): number {
    return item.video !== undefined && item.video.width > 0 && item.video.height > 0
      ? Math.max(0.6, Math.min(1.8, item.video.width / item.video.height)) : 1;
  }
  private videoColumnForTab(tabId: number, side: number): ThreadBrief[] {
    const columns: ThreadBrief[][] = [[], []];
    const heights: number[] = [0, 0];
    const width: number = Math.max(120, (this.viewportWidth - 24) / 2);
    for (const item of this.videoItemsForTab(tabId)) {
      const target: number = heights[0] <= heights[1] ? 0 : 1;
      columns[target].push(item); heights[target] += width / this.videoRatio(item) + 94;
    }
    return columns[side];
  }
  @Builder
  VideoCard(item: ThreadBrief) {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        if (!imageLoadStore.isAutoLoadOff() && item.video !== undefined && item.video.cover.length > 0) {
          Image(item.video.cover).width('100%').aspectRatio(this.videoRatio(item)).objectFit(ImageFit.Cover)
        } else {
          Text(imageLoadStore.isAutoLoadOff() ? '未自动加载封面' : '视频').width('100%').aspectRatio(this.videoRatio(item))
            .textAlign(TextAlign.Center).fontColor(AppTheme.TEXT_SUB).backgroundColor(AppTheme.SURFACE_MUTED)
        }
        SymbolGlyph($r('sys.symbol.play_fill')).fontSize(18).fontColor([Color.White])
          .padding(8).backgroundColor('#66000000').borderRadius(20).margin(8)
      }.width('100%').clip(true)
      Text(item.title || item.summary || '视频帖').fontSize(14).fontColor(AppTheme.TEXT_MAIN).maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').padding({ left: 10, right: 10 })
      Row({ space: 5 }) {
        AvatarComponent({ url: item.authorAvatar, fallbackName: item.authorName, avatarSize: 20 })
        Text(item.authorName).fontSize(11).fontColor(AppTheme.TEXT_SUB).maxLines(1).layoutWeight(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph($r('sys.symbol.message')).fontSize(13).fontColor([AppTheme.TEXT_SUB])
        Text(`${item.replyCount}`).fontSize(11).fontColor(AppTheme.TEXT_SUB)
      }.width('100%').padding({ left: 10, right: 10, bottom: 10 })
    }.width('100%').backgroundColor(AppTheme.CARD).borderRadius(12).clip(true)
      .onClick(() => { this.saveScrollPosition(); NavigationService.openThreadDetail({ tid: item.tid, forumName: this.forumName,
        replyCount: item.replyCount, videoMode: true }); })
  }
  @Builder
  ThreadCard(item: ThreadBrief) {
    ThreadPreviewCard({
      useImageLayoutPreference: true,
      // 与首页帖子卡片同口径受光：用 BORDER（细边）而非羽化，羽化近光侧会过曝外溢。
      // 光源仍是各页面的发帖按钮；本页判断发光由按钮自己按可见性决定。
      litType: hdsEffect.PointLightIlluminatedType.BORDER,
      authorName: item.authorName, authorAvatar: item.authorAvatar,
      postedTime: formatTimeText(item.postedMs, Date.now()), title: item.title, summary: item.summary,
      images: item.images.length > 0 ? item.images : (item.coverImage.length > 0 ? [item.coverImage] : []),
      isTop: item.isTop, isGood: item.isGood, isHelp: item.isHelp,
      agreeCount: item.agreeCount, replyCount: item.replyCount,
      shareCount: item.shareCount,
      onToggleLike: (state: ThreadCardActionState): void => {
        void this.cardActions.toggleLike(state, this.getUIContext().getHostContext() as common.UIAbilityContext,
          item.tid, this.forumName).then((reason: string): void => {
            if (reason.length > 0) { this.getUIContext().getPromptAction().showToast({ message: reason }); }
          });
      },
      onOpenComments: (): void => { this.saveScrollPosition(); NavigationService.openThreadDetail({ tid: item.tid, forumName: this.forumName, replyCount: item.replyCount, openComments: true }); },
      onShare: (): void => {
        void this.cardActions.share(this.getUIContext().getHostContext() as common.UIAbilityContext,
          item.tid, item.title).then((reason: string): void => {
            if (reason.length > 0) { this.getUIContext().getPromptAction().showToast({ message: reason }); }
          });
      },
      menu: buildThreadCardMenu(this.getUIContext(), item),
      imageScroller: this.imageScroller(item.tid),
      canOpenAuthor: item.authorId > 0 || item.authorAvatar.length > 0,
      onOpenAuthor: (): void => {
        openUserByIdentity(item.authorId, item.authorAvatar, item.authorName, this.getUIContext());
      },
      onOpenThread: (): void => { this.openThread(item); },
      onOpenImage: (index: number): void => {
        this.openImages(item.images.length > 0 ? item.images : [item.coverImage], index);
      }
    })
  }
  /** 列表底部分别展示加载中、失败重试与到底状态。 */
  @Builder
  PageFooter(tabId: number) {
    ListFooter({
      loading: tabId === this.activeTabId() && this.vm.isLoadingMore,
      error: tabId === this.activeTabId() ? this.vm.loadMoreError : '',
      hasMore: this.vm.pageForTab(tabId).hasMore,
      onRetry: (): void => { void this.vm.loadMore(this.hostContext(), true); }
    })
  }

  @Builder
  StatusView(text: string) {
    PageState({ fillRemaining: true, message: text, loading: this.vm.loading && !this.vm.loadedOnce }).layoutWeight(1)
  }

  @Builder
  FullPageLoading() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 头图和帖子并行加载，遮罩下也开始解码/判断，不等正文显示后再下载。
      if (this.vm.heroHeadline.length > 0) { this.ForumHeadlineImage(this.vm.heroHeadline) }
      Column() {
        RefreshSpinner()
      }
      .width('100%').height(LayoutPolicy.matchParent)
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor(AppTheme.BG)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  ErrorView() {
    PageState({ fillRemaining: true, title: '加载失败', message: this.vm.errorText, actionLabel: '重试',
      onAction: (): void => { void this.handleRefresh(); } }).layoutWeight(1)
  }
}
