import { motionStore } from '../common/appearance/MotionStore';
import { MotionEffect } from '../common/appearance/MotionConfig';
import { motionDuration, motionSpringCurve } from '../common/appearance/MotionPolicy';
import { visualThemeStore } from '../common/appearance/VisualThemeStore';
import { ThreadCardLayout } from '../common/appearance/ThreadCardLayout';
import { PageState, ListFooter } from '../components/PageState';
import { RefreshSpinner, FORUM_REFRESH_OFFSET } from '../components/RefreshSpinner';
import { ForumIdentity, FORUM_IDENTITY_TITLE_TOP } from '../components/ForumIdentity';
import { ForumRefreshButton } from '../components/ForumRefreshButton';
import { FloatingForumTabs } from '../components/FloatingForumTabs';
import { ForumAvatarImage, forumAvatarRadius } from '../components/ForumAvatarImage';
/**
 * 吧页面：某个吧的帖子列表。
 *
 * 入口是帖子详情页顶部的"吧头像 + 吧名"，首页信息流里的吧标签也能进。
 * 数据仍走已验证的 `/c/f/frs/page` 链路（`TiebaApi.fetchThreadList`），
 * 列表状态复用 `ThreadListVM`；吧头关注/签到由 `ForumIdentity` 与 `ForumHeaderVM` 承接。
 *
 * 配色沿用首页信息流（`AppTheme` + 标准帖子卡片），它是"帖子卡片流"，
 * 与论坛列表同一种形态；详情页那套 `DetailTheme` 留给详情页自己。
 */

import { openUserByIdentity } from '../navigation/UserNavigation';
import { common } from '@kit.AbilityKit';
import { DirectoryKind } from '../model/PageDirectory';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction, AnimatorResult } from '@kit.ArkUI';
import { HdsNavDestination, hdsEffect } from '@kit.UIDesignKit';
import { ForumTab, ThreadBrief } from '../model/ThreadList';
import { feedImageInfo, formatPostTime } from '../model/HomeFeedPresentation';
import { ThreadListVM } from '../viewmodel/ThreadListVM';
import { AppTheme } from '../theme/Theme';
import { ImageViewer } from '../components/ImageViewer';
import { closeImageTransition, imageLayerRetentionTransition } from '../components/ImageTransition';
import { ThreadPreviewCard } from '../components/ThreadPreviewCard';
import { TaggedThreadText } from '../components/TaggedThreadText';
import { HelpThreadCard } from '../components/HelpThreadCard';
import { ThreadCardActionState, ThreadCardActionsVM } from '../viewmodel/ThreadCardActionsVM';
import { AvatarComponent } from '../components/AvatarComponent';
import { lowFlowStore } from '../common/appearance/LowFlowStore';
import { buildThreadCardMenu } from '../components/ThreadCardMenu';
import { visibleThreads } from '../model/ThreadBlock';
import { threadBlockStore } from '../utils/ThreadBlockStore';
import {
  FORUM_HERO_PATTERN_COLOR_FILTER, FORUM_HERO_PATTERN_OPACITY, ForumHeroPalette, forumHeroPalette
} from '../common/appearance/ForumHeroStyle';
import { GlassBackButton } from '../components/GlassBackButton';
import { GlassCircleButton } from '../components/GlassCircleButton';
import { SearchField } from '../components/SearchField';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { ForumPageParams, NavigationService, SearchResultParams } from '../navigation/AppNavigation';
import { forumDefaultTabStore } from '../common/appearance/ForumDefaultTabStore';
import { smartReachStore, SmartReachStore } from '../common/appearance/SmartReachStore';
import { themeModeStore } from '../common/appearance/ThemeModeStore';
import { ForumDefaultTab } from '../model/ForumDefaultTab';
import { ForumCoverDetail } from '../model/ForumCoverDetail';
import { inspectForumCover } from '../utils/ForumCoverDetail';

/** 仅缓存吧页返回所需的 VM 与滚动偏移，不引入全局状态框架。 */
class ForumPageState {
  vm: ThreadListVM = new ThreadListVM();
  scrollOffset: number = 0;
  defaultTab: ForumDefaultTab = ForumDefaultTab.HOT;
  /** 跟随既有页面状态，只保存当前图片的判断，不持有图片或落盘。 */
  coverUrl: string = '';
  coverKnown: boolean = false;
  coverCompact: boolean = false;
}

interface ImageCompleteInfo {
  width: number;
  height: number;
  loadingStatus: number;
}

const FORUM_PAGE_STATES: Map<string, ForumPageState> = new Map<string, ForumPageState>();
const FORUM_IDENTITY_MIN_HEIGHT: number = 116;
const FORUM_IDENTITY_BOTTOM_GAP: number = 12;
const FORUM_IDENTITY_CARD_GAP: number = 8;
/** 封面始终维持原尺寸；只有纯色/平滑背景将身份和帖子前移。 */
const FORUM_COVER_FULL_HEIGHT: number = 184;
const FORUM_HEADER_LIFT: number = 56;
const FORUM_COVER_OVERLAP: number = 24;
const FORUM_IDENTITY_PANEL_RADIUS: number = 20;
/** 顶部工具栏内容行高；内容列表视口从其下沿开始。 */
const FORUM_TOOLBAR_HEIGHT: number = 56;
const FORUM_PANEL_RADIUS: number = 9;
const FORUM_POST_ORDER_HEIGHT: number = 28;

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
  @Local coverFlat: boolean = false;
  /** 动画每帧的实际上移量；列表几何不能只跟随布尔结果跳到终点。 */
  @Local coverLift: number = 0;
  private coverRevision: number = 0;
  private coverDecodedUrl: string = '';
  private coverProbedUrl: string = '';
  private coverLiftRevision: number = 0;
  private coverLiftAnimator: AnimatorResult | undefined = undefined;
  @Local forumSearchExpanded: boolean = false;
  @Local forumSearchProgress: number = 0;
  @Local forumSearchText: string = '';
  @Local forumSearchSlotWidth: number = 40;
  @Local restorePending: boolean = false;
  @Local pinnedExpanded: boolean = false;
  /**
   * 状态栏高度（vp）。窗口全屏布局下页面从 y=0 起排，**Hero 的内容要自己让出这一段**，
   * 否则返回键会压在状态栏上（既重叠又点不到，状态栏会吃掉那一片触摸）。
   * 封面仍从 y=0 铺起，工具栏内容整体下移。
   */
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;
  /** 吧信息滚出视口的进度 0~1，驱动顶部分类提示条和圆角收拢。 */
  @Local tabsNavProgress: number = 0;
  @Local categoryScrollRevision: number = 0;
  @Local categoriesAtTop: boolean = true;
  @Local categoryPrefs: SmartReachStore = smartReachStore;
  private topTabsScroller: Scroller = new Scroller();
  private topTabWidths: Map<number, number> = new Map<number, number>();
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
  @Local contentShift: number = 0;
  @Local contentOpacity: number = 1;
  private active: boolean = true;
  private tabAnimation: number = 0;

  aboutToDisappear(): void {
    this.active = false;
    this.cancelCoverInspection();
    this.finishCoverLift();
    this.resetTabTransition();
  }

  private resetTabTransition(): void {
    ++this.tabAnimation;
    this.contentShift = 0;
    this.contentOpacity = 1;
  }

  private scroller: ListScroller = new ListScroller();
  /**
   * 每条帖子一个横向图片列表控制器（与首页 ForumListView 同一模式）：
   * 各帖各自维护图集滚动位置，互不串位。
   */
  private imageScrollers: Map<number, ListScroller> = new Map<number, ListScroller>();
  /** 全屏看图（与本页帖子导航分离，点图片只开查看器、不进帖） */
  @Local viewerUrls: string[] = [];
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
    // 吧名为空就不发请求：空论坛名在服务端只会换来一次 110001，
    // 界面直接走"没拿到吧名"的空态更诚实
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
    this.restoreCoverDecision();
    this.restorePending = pageState.scrollOffset > 0;
    // 返回本页复用缓存；偏好变更后再次进入同一吧时重新按新默认分区加载。
    const context: common.UIAbilityContext = this.hostContext();
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
   * 打开吧成员页（A-01）。与 `openForumDirectory` 同一前置：`getMemberInfo` 只认 `forum_id`，
   * 拿不到 fid 就如实提示，不发必然失败的请求；顺手保存滚动位置。
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
    // 悬浮刷新按钮：先回顶再刷新。回顶是点击后的即时反馈，不必等网络回来——
    // 等完再滚会让"点了没反应"和"出来先蹦一下"两件事同时发生。
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

  /** 滚到帖子区顶部（头图与工具栏之下）；不带动画时直接落位，避免长列表顶着旧内容滑。 */
  private scrollToThreadsTop(): void {
    if (!this.active) { return; }
    const top: number = this.heroHeight() - FORUM_TOOLBAR_HEIGHT;
    this.scroller.scrollTo({ xOffset: 0, yOffset: top, animation: motionStore.isOn(MotionEffect.MOVE) });
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
      this.pageState.scrollOffset = this.scroller.currentOffset().yOffset;
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
      this.scroller.scrollTo({
        xOffset: 0,
        yOffset: this.pageState.scrollOffset,
        animation: false
      });
    }
  }

  /** 吧信息与帖子同列表滚动；分类吸顶位置是工具栏下沿。 */
  private syncTabsSticky(): void {
    const distance: number = this.heroHeight() - FORUM_TOOLBAR_HEIGHT;
    const offset: number = this.scroller.currentOffset().yOffset;
    this.contentScrollOffset = Math.max(0, offset);
    this.categoriesAtTop = offset <= 2;
    const progress: number = Math.max(0, Math.min(1, offset / distance));
    if (Math.abs(progress - this.tabsNavProgress) > 0.001) { this.tabsNavProgress = progress; }
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
    this.viewerIndex = index;
  }

  private pinnedThreads(): ThreadBrief[] {
    return visibleThreads(this.vm.threads, threadBlockStore.rules(), false)
      .filter((item: ThreadBrief) => item.isTop && !item.isVideo);
  }

  private regularThreads(): ThreadBrief[] {
    return visibleThreads(this.vm.threads, threadBlockStore.rules(), false)
      .filter((item: ThreadBrief) => !item.isTop && !item.isVideo);
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
          FloatingForumTabs({ tabs: this.vm.tabs, selectedId: this.vm.targetTabId(),
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
          ImageViewer({ imageUrls: this.viewerUrls, initialIndex: this.viewerIndex,
            onClose: (): void => { this.viewerUrls = []; this.viewerIndex = 0; } })
            .zIndex(100)
            .transition(imageLayerRetentionTransition())
        }
      }
      .width('100%')
      .height(LayoutPolicy.matchParent)
      .onAreaChange((_old: Area, area: Area): void => {
        this.viewportWidth = Number(area.width); this.viewportHeight = Number(area.height);
        this.tryInspectCover();
      })
    }
    // 固定工具栏独立绘制，吧信息与帖子共用列表滚动。
    .hideTitleBar(true)
    .systemBarStyle(
      { statusBarContentColor: this.lightStatusBar() ? '#F2F3F4' : '#1B1B1B' },
      { statusBarContentColor: this.lightStatusBar() ? '#F2F3F4' : '#1B1B1B' }
    )
    .onShown((): void => { this.pageVisible = true; })
    .onHidden((): void => { this.pageVisible = false; this.finishCoverLift(); this.resetTabTransition(); })
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
      .onComplete((event?: ImageCompleteInfo): void => { this.onCoverDecoded(url, event); })
  }

  @Builder
  private CoverInspectionImage(url: string, width: number, height: number) {
    Image(url).width(width).height(height).objectFit(ImageFit.Contain)
      .interpolation(ImageInterpolation.High).syncLoad(true)
  }

  private cancelCoverInspection(): void {
    ++this.coverRevision;
    this.coverDecodedUrl = '';
  }

  @Monitor('vm.heroHeadline')
  onCoverSourceChanged(): void {
    this.cancelCoverInspection();
    this.coverProbedUrl = '';
    this.restoreCoverDecision();
  }

  private restoreCoverDecision(): void {
    this.stopCoverLift();
    const state: ForumPageState | undefined = this.pageState;
    if (state !== undefined && state.coverKnown && state.coverUrl === this.vm.heroHeadline) {
      this.coverFlat = state.coverCompact;
      this.coverProbedUrl = state.coverUrl;
    } else {
      this.coverFlat = this.vm.heroHeadlineSettled && this.vm.heroHeadline.length === 0;
    }
    this.coverLift = this.coverFlat ? FORUM_HEADER_LIFT : 0;
  }

  @Monitor('vm.heroHeadlineSettled')
  onCoverMetadataSettled(): void {
    if (this.active && this.vm.heroHeadlineSettled && this.vm.heroHeadline.length === 0) { this.applyCoverLift(true); }
  }

  private applyCoverLift(compact: boolean): void {
    const target: number = compact ? FORUM_HEADER_LIFT : 0;
    if (this.coverFlat === compact && (this.coverLiftAnimator !== undefined || this.coverLift === target)) { return; }
    this.stopCoverLift();
    this.coverFlat = compact;
    // 加载遮罩内直接准备最终布局；只有已显示的页面需要连续过渡。
    if (!motionStore.isOn(MotionEffect.MOVE) || !this.active || !this.pageVisible ||
      (this.vm.loading && !this.vm.loadedOnce) || this.coverLift === target) {
      this.coverLift = target;
      return;
    }
    const revision: number = this.coverLiftRevision;
    const animation: AnimatorResult = this.getUIContext().createAnimator({ duration: 280,
      easing: 'cubic-bezier(0.2, 0, 0, 1)', delay: 0, fill: 'forwards', direction: 'normal', iterations: 1,
      begin: this.coverLift, end: target });
    this.coverLiftAnimator = animation;
    animation.onFrame = (value: number): void => {
      if (this.active && revision === this.coverLiftRevision && Number.isFinite(value)) {
        this.coverLift = Math.max(0, Math.min(FORUM_HEADER_LIFT, value));
      }
    };
    animation.onFinish = (): void => {
      if (!this.active || revision !== this.coverLiftRevision) { return; }
      this.coverLift = target;
      this.coverLiftAnimator = undefined;
    };
    animation.play();
  }

  private stopCoverLift(): void {
    ++this.coverLiftRevision;
    const animation: AnimatorResult | undefined = this.coverLiftAnimator;
    this.coverLiftAnimator = undefined;
    if (animation !== undefined) { animation.cancel(); }
  }

  private finishCoverLift(): void {
    this.stopCoverLift();
    this.coverLift = this.coverFlat ? FORUM_HEADER_LIFT : 0;
  }

  private onCoverDecoded(url: string, event: ImageCompleteInfo | undefined): void {
    if (!this.active || this.vm.heroHeadline !== url || event === undefined || event.loadingStatus !== 1) { return; }
    this.coverDecodedUrl = url;
    this.tryInspectCover();
  }

  private tryInspectCover(): void {
    const url: string = this.vm.heroHeadline;
    if (!this.active || url.length === 0 || this.coverDecodedUrl !== url || this.coverProbedUrl === url || this.viewportWidth <= 0) { return; }
    this.coverProbedUrl = url;
    const revision: number = ++this.coverRevision;
    void this.inspectCover(url, revision);
  }

  private async inspectCover(url: string, revision: number): Promise<void> {
    const current: () => boolean = (): boolean => this.active && this.coverRevision === revision && this.vm.heroHeadline === url;
    if (!current()) { return; }
    const width: number = this.viewportWidth;
    const height: number = FORUM_COVER_FULL_HEIGHT + this.statusBarH;
    const detail: ForumCoverDetail = await inspectForumCover(this.getUIContext(),
      (): void => { this.CoverInspectionImage(url, width, height); }, width, current);
    if (!current()) { return; }
    if (this.pageState !== undefined && detail.samples > 0) {
      this.pageState.coverUrl = url;
      this.pageState.coverKnown = true;
      this.pageState.coverCompact = detail.compact;
    }
    this.applyCoverLift(detail.compact);
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
              ForumAvatarImage({ url: this.vm.forum.avatar, forumName: this.titleText(),
                avatarSize: 28, radius: forumAvatarRadius(28) })
              Text(this.titleText().endsWith('吧') ? this.titleText() : `${this.titleText()}吧`)
                .fontSize(17).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT_MAIN)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            }
            .width('100%').padding({ right: 50 })
            .opacity(this.toolbarTitleProgress() * (1 - this.forumSearchProgress))
            .hitTestBehavior(this.toolbarTitleProgress() > 0 && !this.forumSearchExpanded ? HitTestMode.Default : HitTestMode.None)
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

  @Builder
  ForumHeaderIdentity() {
    Column() {
      Row().width('100%').height(this.coverSpacerHeight())
        .id('forum-cover-open').accessibilityText('查看完整封面')
        .hitTestBehavior(this.vm.heroHeadline.length > 0 ? HitTestMode.Default : HitTestMode.None)
        .onClick(() => {
          if (this.vm.heroHeadline.length > 0) { this.viewerUrls = [this.vm.heroHeadline]; this.viewerIndex = 0; }
        })
      Column() {
        ForumIdentity({ forumId: this.vm.forum.id, forumName: this.titleText(), avatar: this.vm.forum.avatar,
          active: this.pageVisible && this.viewerUrls.length === 0,
          refreshRevision: this.headerRefreshRevision, memberCount: this.vm.forum.memberCount,
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
      .width('100%').padding({ bottom: FORUM_IDENTITY_BOTTOM_GAP })
      .backgroundColor(AppTheme.CARD)
      .borderRadius(FORUM_IDENTITY_PANEL_RADIUS)
      .clip(false).id('forum-identity-panel')
    }
    .width('100%')
    .padding({ left: 8, right: 8, bottom: FORUM_IDENTITY_CARD_GAP })
    .clip(false)
    .id('forum-scroll-identity')
  }

  private coverHeight(): number {
    return FORUM_COVER_FULL_HEIGHT;
  }

  private headerLift(): number {
    return this.coverLift;
  }

  private coverSpacerHeight(): number {
    return this.coverHeight() - FORUM_TOOLBAR_HEIGHT - FORUM_COVER_OVERLAP - this.headerLift();
  }

  private heroHeight(): number {
    return this.coverHeight() - FORUM_COVER_OVERLAP - this.headerLift() + this.forumIdentityHeight + FORUM_IDENTITY_BOTTOM_GAP + FORUM_IDENTITY_CARD_GAP;
  }

  /** Hero 配色：由协议吧主题色派生。无主题色时返回既有深蓝兜底（见 ForumHeroStyle） */
  private heroPalette(): ForumHeroPalette {
    const palette: ForumHeroPalette = forumHeroPalette(this.vm.forum.heroColor);
    if (visualThemeStore.isPaper && !palette.hasThemeColor) {
      palette.topColor = '#2E6B73'; palette.bottomColor = '#193C40';
    }
    return palette;
  }

  private forumHeaderHeight(): number {
    return this.categoryPrefs.forumTabsFloating ? 0 : 46;
  }
  private revealTopCategory(): void {
    if (this.categoryPrefs.forumTabsFloating) { return; }
    setTimeout((): void => {
      if (!this.active || this.categoryPrefs.forumTabsFloating) { return; }
      let start: number = 20;
      for (const tab of this.vm.tabs) {
        const width: number = this.topTabWidths.get(tab.id) ?? tab.name.length * 16;
        if (tab.id === this.vm.targetTabId()) {
          this.topTabsScroller.scrollTo({ xOffset: Math.max(0, start + width / 2 - this.viewportWidth / 2),
            yOffset: 0, animation: { duration: motionDuration(220), curve: Curve.EaseOut } });
          return;
        }
        start += width + 26;
      }
    }, 32);
  }

  /** 两种模式共用分类数据与选择行为；顶部模式恢复原文字页签。 */
  @Builder
  ForumTabs() {
    Column() {
      if (!this.categoryPrefs.forumTabsFloating) {
        Scroll(this.topTabsScroller) {
          Row({ space: 26 }) {
            ForEach(this.vm.tabs, (tab: ForumTab, index: number) => {
              Column({ space: 5 }) {
                Text(tab.name).fontSize(16).maxFontScale(1.25)
                  .fontWeight(tab.id === this.vm.targetTabId() ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(tab.id === this.vm.targetTabId() ? AppTheme.NAV_SELECTED : AppTheme.TEXT_SUB)
                Row().width(tab.id === this.vm.targetTabId() ? 20 : 0).height(2).borderRadius(2)
                  .backgroundColor(AppTheme.NAV_SELECTED).animation({ duration: motionDuration(220, MotionEffect.MOVE), curve: Curve.EaseOut })
              }.height(46).justifyContent(FlexAlign.Center)
                .onClick((): void => { void this.selectForumTab(tab, index); })
                .onAreaChange((_old: Area, area: Area): void => {
                  const width: number = Number(area.width);
                  // 横向滚动也会改变标签位置；只在宽度变化时重新定位，避免拖动时被拉回选中项。
                  if (this.topTabWidths.get(tab.id) !== width) {
                    this.topTabWidths.set(tab.id, width);
                    if (tab.id === this.vm.targetTabId()) { this.revealTopCategory(); }
                  }
                })
            }, (tab: ForumTab) => String(tab.id))
          }.height(46).padding({ left: 20, right: 20 })
        }.width('100%').height(46).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.Start)
      }
    }.width('100%').backgroundColor(this.categoryPrefs.forumTabsFloating ? Color.Transparent : AppTheme.FORUM_TAB_BG)
      .height(this.forumHeaderHeight())
      .borderRadius({ topLeft: FORUM_PANEL_RADIUS * (1 - this.tabsNavProgress),
        topRight: FORUM_PANEL_RADIUS * (1 - this.tabsNavProgress) }).clip(true)
  }
  private async changePostOrder(sort: number): Promise<void> {
    const success: boolean = await this.vm.changeSort(this.hostContext(), sort);
    if (success) {
      this.scroller.scrollTo({ xOffset: 0,
        yOffset: Math.min(this.scroller.currentOffset().yOffset, this.heroHeight() - FORUM_TOOLBAR_HEIGHT), animation: false });
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
      this.scroller.scrollTo({ xOffset: 0,
        yOffset: Math.min(this.scroller.currentOffset().yOffset, this.heroHeight() - FORUM_TOOLBAR_HEIGHT), animation: false });
    } else if (this.vm.errorText.length > 0) {
      promptAction.showToast({ message: this.vm.errorText, duration: 1800 });
    }
  }

  private animateTabContent(shift: number, opacity: number, duration: number): void {
    this.getUIContext().animateTo({ duration: motionDuration(duration, MotionEffect.MOVE), curve: Curve.EaseOut }, (): void => {
      this.contentShift = shift;
    });
    this.getUIContext().animateTo({ duration: motionDuration(duration, MotionEffect.FADE), curve: Curve.EaseOut }, (): void => {
      this.contentOpacity = opacity;
    });
  }

  /**
   * 切换真实吧页分类。滚动复位与错误提示沿用旧版行为；
   * 成功后把选中签滚到视口中间（tab 多时点右侧的签不至于停在看不见的地方）。
   */
  private async selectForumTab(tab: ForumTab, index: number): Promise<void> {
    if ((this.vm.loading && !this.vm.switchingTab) || tab.id === this.vm.targetTabId()) {
      return;
    }
    const previous: number = this.vm.tabs.findIndex((value: ForumTab) => value.id === this.vm.targetTabId());
    const direction: number = index >= previous ? 1 : -1;
    const revision: number = ++this.tabAnimation;
    const offset: number = Math.min(this.scroller.currentOffset().yOffset, this.heroHeight() - FORUM_TOOLBAR_HEIGHT);
    this.animateTabContent(-12 * direction, 0.65, 100);
    const switching: Promise<boolean> = this.vm.switchTab(this.hostContext(), tab.id);
    this.revealTopCategory();
    const success: boolean = await switching;
    if (!this.active || revision !== this.tabAnimation) { return; }
    if (success) {
      if (this.pageState !== undefined) { this.pageState.scrollOffset = offset; }
      this.scroller.scrollTo({ xOffset: 0, yOffset: offset, animation: false });
      // 新内容从相邻方向进入；只变换列表容器，不给每张卡片创建动画。
      this.getUIContext().animateTo({ duration: 0 }, (): void => {
        this.contentShift = 12 * direction;
        this.contentOpacity = 0.65;
      });
      setTimeout((): void => {
        if (!this.active || revision !== this.tabAnimation) { return; }
        this.animateTabContent(0, 1, 260);
      }, 16);
    } else {
      this.animateTabContent(0, 1, 180);
      if (this.vm.errorText.length > 0) {
        promptAction.showToast({ message: this.vm.errorText, duration: 1800 });
      }
    }
    this.revealTopCategory();
  }

  private swipeForumTab(offset: number, verticalOffset: number): void {
    const distance: number = this.categoryPrefs.forumTabsFloating ? 24 : 48;
    if (Math.abs(offset) < distance || Math.abs(offset) < Math.abs(verticalOffset) * 1.2) { return; }
    const current: number = this.vm.tabs.findIndex((tab: ForumTab) => tab.id === this.vm.targetTabId());
    const next: number = current + (offset < 0 ? 1 : -1);
    if (current < 0 || next < 0 || next >= this.vm.tabs.length) { return; }
    void this.selectForumTab(this.vm.tabs[next], next);
  }

  private toolbarBackgroundProgress(): number {
    return Math.max(0, Math.min(1, this.contentScrollOffset / this.coverSpacerHeight()));
  }

  private toolbarTitleProgress(): number {
    const start: number = this.coverSpacerHeight() + FORUM_IDENTITY_TITLE_TOP;
    return Math.max(0, Math.min(1, (this.contentScrollOffset - start) / 36));
  }

  @Builder
  ThreadList() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.ForumHeroBackdrop()
      Column() {
        Row().height(this.statusBarH + FORUM_TOOLBAR_HEIGHT).width('100%').hitTestBehavior(HitTestMode.None)
        Column() {
          List({ space: 0, scroller: this.scroller }) {
            ListItem() {
              this.ForumHeaderIdentity()
            }
            .clip(false)
            .id('forum-header-item')

            ListItemGroup({ header: this.ForumTabs() }) {
              if (this.vm.hasPostOrder() || this.vm.isHelpTab()) {
                ListItem() {
                  this.PostOrderBar()
                }
                .padding({ left: this.categoryPrefs.forumTabsFloating ? 8 : 0,
                  right: this.categoryPrefs.forumTabsFloating ? 8 : 0 })
              }
              // 保留零高度刷新项，收起时高度可连续回弹，不因移除组件而瞬间跳回。
              ListItem() {
                Row() {
                  if (this.refreshing || this.pullDistance > 0) { RefreshSpinner() }
                }
                .width('100%').height(this.pullDistance)
                .justifyContent(FlexAlign.Center).clip(true)
                .id('forum-pull-refresh')
              }
              if (!this.refreshing && !this.vm.switchingTab && this.vm.hasPostOrder() && this.vm.loading) {
                ListItem() {
                  Column({ space: 12 }) {
                    RefreshSpinner()
                    Text('正在加载分类…').fontSize(14).fontColor(AppTheme.TEXT_SUB)
                  }
                  .width('100%').height(Math.max(240, this.contentHeight - this.forumHeaderHeight()))
                  .justifyContent(FlexAlign.Center)
                  .id('forum-content-loading')
                }
              } else if (this.vm.loading && !this.vm.loadedOnce) {
                ListItem() {
                  Column() { this.StatusView('正在加载…') }
                    .width('100%').height(Math.max(240, this.contentHeight - this.forumHeaderHeight()))
                }
              } else if (this.vm.errorText.length > 0 && this.vm.threads.length === 0) {
                ListItem() {
                  Column() { this.ErrorView() }
                    .width('100%').height(Math.max(240, this.contentHeight - this.forumHeaderHeight()))
                }
              } else if (this.vm.isVideoTab()) {
                if (this.videoItems().length === 0) {
                  ListItem() { this.StatusView('这个分类暂无可播放视频') }
                } else {
                  ListItem() {
                    Row({ space: 8 }) {
                      ForEach([0, 1], (side: number) => {
                        Column({ space: 8 }) {
                          ForEach(this.videoColumn(side), (item: ThreadBrief) => { this.VideoCard(item) }, (item: ThreadBrief) => `${item.tid}`)
                        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                      }, (side: number) => `${side}`)
                    }.width('100%').alignItems(VerticalAlign.Top)
                  }.padding({ left: visualThemeStore.isPaper ? 0 : 8, right: visualThemeStore.isPaper ? 0 : 8,
                    top: visualThemeStore.isPaper ? 0 : ThreadCardLayout.LIST_GAP })
                    .translate({ x: this.categoryPrefs.forumTabsFloating || !motionStore.isOn(MotionEffect.MOVE) ? 0 : this.contentShift })
                    .opacity(this.categoryPrefs.forumTabsFloating || !motionStore.isOn(MotionEffect.FADE) ? 1 : this.contentOpacity)
                }
                ListItem() { this.PageFooter() }.padding({ left: 8, right: 8 })
              } else if (this.vm.threads.length === 0) {
                ListItem() {
                  Column() { this.StatusView(this.vm.isHelpTab() ?
                    (this.vm.helpPartition === 1 ? '暂时没有未回答的求助' : '这个分类还没有求助帖') : '这个吧还没有帖子') }
                    .width('100%').height(Math.max(240, this.contentHeight - this.forumHeaderHeight()))
                }
              } else {
                if (this.pinnedThreads().length > 0) {
                  ListItem() {
                    this.PinnedSection()
                  }
                  .padding({ left: visualThemeStore.isPaper ? 0 : 8, right: visualThemeStore.isPaper ? 0 : 8,
                    top: visualThemeStore.isPaper ? 0 : ThreadCardLayout.LIST_GAP })
                  .translate({ x: this.categoryPrefs.forumTabsFloating || !motionStore.isOn(MotionEffect.MOVE) ? 0 : this.contentShift })
                  .opacity(this.categoryPrefs.forumTabsFloating || !motionStore.isOn(MotionEffect.FADE) ? 1 : this.contentOpacity)
                }

                ForEach(this.regularThreads(), (item: ThreadBrief) => {
                  ListItem() {
                    if (this.vm.isHelpTab()) {
                      HelpThreadCard({ item,
                        onOpenThread: (): void => { this.openThread(item); },
                        onOpenAnswer: (): void => {
                          this.saveScrollPosition();
                          NavigationService.openThreadDetail({ tid: item.tid, forumName: this.forumName,
                            replyCount: item.replyCount, targetPid: item.answerPid, openComments: item.answerPid <= 0 });
                        },
                        onOpenImage: (): void => { this.openImages(item.images, 0); } })
                    } else { this.ThreadCard(item) }
                  }
                  .padding({ left: visualThemeStore.isPaper ? 0 : 8, right: visualThemeStore.isPaper ? 0 : 8,
                    top: visualThemeStore.isPaper ? 0 : ThreadCardLayout.LIST_GAP })
                  .translate({ x: this.categoryPrefs.forumTabsFloating || !motionStore.isOn(MotionEffect.MOVE) ? 0 : this.contentShift })
                  .opacity(this.categoryPrefs.forumTabsFloating || !motionStore.isOn(MotionEffect.FADE) ? 1 : this.contentOpacity)
                }, (item: ThreadBrief) => `${item.tid}`)

                ListItem() {
                  this.PageFooter()
                }
                .padding({ left: 8, right: 8 })
              }
            }
            .backgroundColor(this.categoryPrefs.forumTabsFloating ? Color.Transparent : AppTheme.FORUM_TAB_BG)
            .borderRadius({ topLeft: this.categoryPrefs.forumTabsFloating ? 0 : FORUM_PANEL_RADIUS * (1 - this.tabsNavProgress),
              topRight: this.categoryPrefs.forumTabsFloating ? 0 : FORUM_PANEL_RADIUS * (1 - this.tabsNavProgress) })
            // 顶部模式沿用旧版逐项动画，避免把吸顶分类栏和底色一起移走。
            .translate({ x: this.categoryPrefs.forumTabsFloating && motionStore.isOn(MotionEffect.MOVE) ? this.contentShift : 0 })
            .opacity(this.categoryPrefs.forumTabsFloating && motionStore.isOn(MotionEffect.FADE) ? this.contentOpacity : 1)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)

          .edgeEffect(EdgeEffect.None)
          .sticky(this.categoryPrefs.forumTabsFloating ? StickyStyle.None : StickyStyle.Header)
          .parallelGesture(PanGesture({ direction: PanDirection.Vertical, distance: 8 })
            .onActionStart((event: GestureEvent) => {
              this.categoryScrollNotified = false;
              const offset: number = this.scroller.currentOffset().yOffset;
              const contentTop: number = Math.max(0, this.heroHeight() - FORUM_TOOLBAR_HEIGHT - offset)
                + this.forumHeaderHeight()
                + (this.vm.hasPostOrder() || this.vm.isHelpTab() ? FORUM_POST_ORDER_HEIGHT : 0);
              this.pullEligible = !this.refreshing && !this.vm.loading && !this.vm.switchingTab
                && !this.vm.isLoadingMore && offset <= this.heroHeight() - FORUM_TOOLBAR_HEIGHT + 1
                && event.fingerList.length > 0 && event.fingerList[0].localY - event.offsetY >= contentTop;
            })
            .onActionUpdate((event: GestureEvent) => {
              if (!this.categoryScrollNotified && Math.abs(event.offsetY) > 12 && this.scroller.currentOffset().yOffset > 8) {
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
          .gesture(PanGesture({ direction: PanDirection.Horizontal,
            distance: this.categoryPrefs.forumTabsFloating ? 24 : 48 })
            .onActionEnd((event: GestureEvent) => { this.swipeForumTab(event.offsetX, event.offsetY); }))
          .onDidScroll(() => {
            this.syncTabsSticky();
          })
          .onReachEnd(() => {
            this.vm.loadMore(this.hostContext());
          })
          .onAreaChange(() => {
            this.restoreScrollPosition();
          })
        }
        .layoutWeight(1)
        .onAreaChange((_old: Area, area: Area) => { this.contentHeight = Number(area.height); })
        .hitTestBehavior(HitTestMode.Transparent)
      }
      .width('100%').height(LayoutPolicy.matchParent).hitTestBehavior(HitTestMode.Transparent)
      this.ForumToolbar()
      if (this.vm.switchingTab) {
        Row({ space: 8 }) {
          RefreshSpinner()
          Text('正在加载分类…').fontSize(14).fontColor(AppTheme.TEXT_SUB)
        }
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor(AppTheme.FORUM_TAB_BG).borderRadius(16)
        .position({ x: 12, y: this.statusBarH + FORUM_TOOLBAR_HEIGHT + 8 })
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%').height(LayoutPolicy.matchParent)
  }

  /** 收起时保留首条置顶及总数；按钮独立于标题入口，避免误进帖子。 */
  @Builder
  PinnedSection() {
    Column() {
      ForEach(this.visiblePinnedThreads(this.pinnedThreads()), (item: ThreadBrief, index: number) => {
        Row({ space: 8 }) {
          Row({ space: 8 }) {
            TaggedThreadText({ text: item.title.length > 0 ? item.title : '（无标题）', labels: ['置顶'],
              textSize: 14, lineSize: 20, weight: FontWeight.Normal, textColor: AppTheme.TEXT_MAIN,
              lines: 1, fillPinned: false }).layoutWeight(1)
          }.layoutWeight(1).height('100%').alignItems(VerticalAlign.Center).onClick(() => { this.openThread(item); })
          if (index === 0 && this.pinnedThreads().length > 1) {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 5 }) {
                Text(this.pinnedExpanded ? '收起' : `共${this.pinnedThreads().length}条`)
                  .fontSize(11).fontColor(AppTheme.TEXT_SUB)
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(10).fontColor([AppTheme.TEXT_SUB])
                  .rotate({ angle: this.pinnedExpanded ? -90 : 90 })
              }.height(24).padding({ left: 8, right: 8 }).borderRadius(12)
                .border({ width: 0.5, color: AppTheme.TEXT_MUTED })
            }
              .backgroundColor(Color.Transparent).stateEffect(false).height(36).padding({ left: 0, right: 0 })
              .accessibilityText(this.pinnedExpanded ? '收起置顶帖' : `展开全部${this.pinnedThreads().length}条置顶帖`)
              .onClick(() => { this.pinnedExpanded = !this.pinnedExpanded; })
          }
        }
        .width('100%').height(36).padding({ left: 10, right: 10 }).alignItems(VerticalAlign.Center)
        .border({ width: { bottom: index < this.visiblePinnedThreads(this.pinnedThreads()).length - 1 ? 1 : 0 },
          color: AppTheme.DIVIDER })
      }, (item: ThreadBrief) => `${item.tid}`)
    }
    .width('100%').borderRadius(12).backgroundColor(AppTheme.CARD).padding({ top: 2, bottom: 2 })
    .id('forum-pinned-section')
  }

  /** 与首页共用完整卡片；吧内省略来源吧名，没有可用菜单时不预留菜单按钮。 */
  private videoItems(): ThreadBrief[] {
    return visibleThreads(this.vm.threads, threadBlockStore.rules(), false)
      .filter((item: ThreadBrief): boolean => item.isVideo && item.video !== undefined);
  }
  private videoRatio(item: ThreadBrief): number {
    return item.video !== undefined && item.video.width > 0 && item.video.height > 0
      ? Math.max(0.6, Math.min(1.8, item.video.width / item.video.height)) : 1;
  }
  private videoColumn(side: number): ThreadBrief[] {
    const columns: ThreadBrief[][] = [[], []];
    const heights: number[] = [0, 0];
    const width: number = Math.max(120, (this.viewportWidth - 24) / 2);
    for (const item of this.videoItems()) {
      const target: number = heights[0] <= heights[1] ? 0 : 1;
      columns[target].push(item); heights[target] += width / this.videoRatio(item) + 94;
    }
    return columns[side];
  }
  @Builder
  VideoCard(item: ThreadBrief) {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        if (!lowFlowStore.enabled && item.video !== undefined && item.video.cover.length > 0) {
          Image(item.video.cover).width('100%').aspectRatio(this.videoRatio(item)).objectFit(ImageFit.Cover)
        } else {
          Text(lowFlowStore.enabled ? '低流量模式' : '视频').width('100%').aspectRatio(this.videoRatio(item))
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
      postedTime: formatPostTime(item.postedMs, Date.now()), title: item.title, summary: item.summary,
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
  PageFooter() {
    ListFooter({ loading: this.vm.isLoadingMore, error: this.vm.loadMoreError, hasMore: this.vm.page.hasMore,
      onRetry: (): void => { void this.vm.loadMore(this.hostContext(), true); } })
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
