/**
 * 首页「关注」频道：我关注的吧列表、单吧签到与一键签到、进吧与吧广场入口。
 * 关系与签到态读 `ForumStateStore`；本视图只负责下拉刷新、前后台刷新与列表渲染。
 */
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@kit.UIDesignKit';
import { PageState } from './PageState';
import { FollowChanges, followChanges } from '../viewmodel/FollowActionVM';
import { ForumStateChanges, forumStateChanges } from '../viewmodel/ForumStateStore';

import { common } from '@kit.AbilityKit';
import { LengthMetrics, promptAction, router } from '@kit.ArkUI';
import { FollowVM } from '../viewmodel/FollowVM';
import { RecentForumsVM } from '../viewmodel/RecentForumsVM';
import { ForumActionButton } from './ForumActionButton';
import { GlassCircleButton } from './GlassCircleButton';
import { ForumLevelBadge } from './ForumLevelBadge';
import { FollowForumItem } from '../model/FollowForum';
import { FollowForumDataSource, followForumRowId } from '../model/FollowForumDataSource';
import { displayForumName, RecentForumItem, splitRecentTwoRows } from '../model/RecentForums';
import { authSession, AuthSession } from '../auth/AuthSession';
import { LoginEmptyView } from './LoginEmptyView';
import { ForumAvatarImage, forumAvatarRadius } from './ForumAvatarImage';
import { BrowseHistoryChanges, browseHistoryChanges } from '../utils/BrowseHistory';
import { AppTheme } from '../theme/Theme';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { NavigationService } from '../navigation/AppNavigation';
import { SignStrategyStore, signStrategyStore } from '../common/appearance/SignStrategyStore';
import { FollowLayoutStore, followLayoutStore } from '../common/appearance/FollowLayoutStore';
import { MotionEffect } from '../common/appearance/MotionConfig';
import { motionStore } from '../common/appearance/MotionStore';
import { themeModeStore } from '../common/appearance/ThemeModeStore';
import { ForegroundRefresh, foregroundRefresh } from '../viewmodel/ForegroundRefresh';
import { PullRefreshHeader, PULL_REFRESH_OFFSET } from './RefreshSpinner';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UiLayout } from '../common/appearance/UiLayout';

const FOLLOW_NAV_BAR_HEIGHT: number = 56;
const RECENT_AVATAR_SIZE: number = 48;
const RECENT_TILE_WIDTH: number = 68;
const CAPSULE_AVATAR_SIZE: number = 22;
const CAPSULE_LEVEL_SIZE: number = 18;

@ComponentV2
export struct FollowView {
  @Param active: boolean = true;
  @Local foreground: ForegroundRefresh = foregroundRefresh;
  private foregroundRevision: number = foregroundRefresh.revision;
  private foregroundRefreshPending: boolean = false;
  private foregroundExperiencePending: boolean = false;
  private foregroundAccount: string = '';
  @Local refreshing: boolean = false;
  @Local pullRefreshDragging: boolean = false;
  private navStack: NavPathStack = new NavPathStack();
  private listScroller: ListScroller = new ListScroller();
  private recentScroller: Scroller = new Scroller();
  private refreshGestureId: number = 0;
  private consumedRefreshGestureId: number = -1;
  private refreshSequence: number = 0;

  private headerHeight(): number {
    return this.statusBarH + FOLLOW_NAV_BAR_HEIGHT;
  }

  private resetPullRefresh(): void {
    this.refreshSequence++;
    this.refreshing = false;
    this.pullRefreshDragging = false;
    this.consumedRefreshGestureId = -1;
  }

  private handleRefreshTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) { this.refreshGestureId++; }
  }

  private releaseRefreshAnimation(): void {
    if (this.refreshing) { return; }
    // 原生组件可能在同一手势结束后重放回调；主动复位动画而不重复请求。
    const sequence: number = this.refreshSequence;
    this.refreshing = true;
    setTimeout((): void => {
      if (sequence === this.refreshSequence) { this.refreshing = false; }
    }, 0);
  }

  private async refreshForums(fromGesture: boolean = false): Promise<void> {
    if (fromGesture && this.consumedRefreshGestureId === this.refreshGestureId) {
      this.releaseRefreshAnimation();
      return;
    }
    if (fromGesture) { this.consumedRefreshGestureId = this.refreshGestureId; }
    if (!this.active || !authSession.isLoggedIn() || this.vm.loading || this.vm.signingAll ||
      this.vm.signingFname.length > 0) {
      if (fromGesture) { this.releaseRefreshAnimation(); }
      return;
    }
    const sequence: number = ++this.refreshSequence;
    this.refreshing = true;
    // 与回前台一致：列表完成后只强制核对当前可见吧的签到、等级与连签信息。
    this.foregroundExperiencePending = true;
    try {
      void this.recentVm.load(this.hostContext());
      await this.vm.load(this.hostContext(), true);
    } finally {
      if (sequence === this.refreshSequence) { this.refreshing = false; }
    }
  }

  @Monitor('foreground.revision', 'active')
  onForegroundRefresh(): void {
    if (!this.active) {
      this.wasActive = false;
      this.clearTransitionDefer();
      this.foregroundRefreshPending = false; this.foregroundExperiencePending = false;
      this.resetPullRefresh();
      return;
    }
    if (!this.wasActive) {
      this.wasActive = true;
      this.deferForTransition(550);
    }
    if (this.foregroundRevision === this.foreground.revision) { return; }
    this.foregroundRevision = this.foreground.revision;
    this.foregroundAccount = authSession.forumCacheSessionKey();
    this.foregroundRefreshPending = true;
    this.applyForegroundRefresh();
  }

  @Monitor('vm.loading', 'vm.signingAll', 'vm.signingFname')
  applyForegroundRefresh(): void {
    if (!this.foregroundRefreshPending || !this.active || this.vm.loading || this.vm.signingAll ||
      this.vm.signingFname.length > 0) { return; }
    this.foregroundRefreshPending = false;
    if (this.foregroundAccount.length === 0 || this.foregroundAccount !== authSession.forumCacheSessionKey()) { return; }
    this.foregroundExperiencePending = true;
    hilog.info(0x0000, 'ForegroundRefresh', 'follow requested revision=%{public}d', this.foregroundRevision);
    void this.vm.load(this.hostContext(), true);
  }

  @Local private changes: FollowChanges = followChanges;
  @Local private states: ForumStateChanges = forumStateChanges;
  @Local private historyChanges: BrowseHistoryChanges = browseHistoryChanges;
  private historyRevision: number = browseHistoryChanges.revision;
  /** 吧页/吧资料签到成功后无需重读列表：按身份状态就地校正今天的签到标记。 */
  @Monitor('states.signRevision')
  syncSignFromStore(): void { this.vm.syncFromStore(); }
  @Monitor('historyChanges.revision', 'active')
  syncRecentForums(): void {
    if (!this.active || this.historyRevision === this.historyChanges.revision) { return; }
    if (this.transitionDeferring) { return; }
    this.historyRevision = this.historyChanges.revision;
    void this.recentVm.load(this.hostContext());
  }
  private relationshipRefreshPending: boolean = false;
  private visibleForums: Map<number, FollowForumItem> = new Map();
  private visibleStartIndex: number = -1;
  private visibleEndIndex: number = -1;
  private forumSource: FollowForumDataSource = new FollowForumDataSource();
  @Local private capsuleForums: FollowForumItem[] = [];
  @Local private listScrolling: boolean = false;
  /** 推入/返回子页或切 Tab 转场期间暂撤行内按钮实时材质，避免双页叠加 20+ 次 TakeSnapshot 拖垮转场帧率。 */
  @Local private transitionDeferring: boolean = false;
  private wasActive: boolean = true;
  private transitionDeferTimer: number = -1;
  private deferForTransition(durationMs: number): void {
    this.transitionDeferring = true;
    if (this.transitionDeferTimer >= 0) { clearTimeout(this.transitionDeferTimer); }
    this.transitionDeferTimer = setTimeout((): void => {
      this.transitionDeferTimer = -1;
      this.transitionDeferring = false;
      if (this.active && this.historyRevision !== this.historyChanges.revision) {
        this.historyRevision = this.historyChanges.revision;
        void this.recentVm.load(this.hostContext());
      }
    }, durationMs);
  }
  private clearTransitionDefer(): void {
    if (this.transitionDeferTimer >= 0) {
      clearTimeout(this.transitionDeferTimer);
      this.transitionDeferTimer = -1;
    }
    this.transitionDeferring = false;
  }
  private readonly handleOpenForum: (fname: string) => void = (fname: string): void => {
    if (fname.length === 0) { return; }
    this.deferForTransition(800);
    NavigationService.openForum({ forumName: fname });
  };
  private readonly handleSignTapBound: (target: FollowForumItem) => void = (target: FollowForumItem): void => {
    this.handleSignTap(target);
  };
  @Monitor('vm.forums')
  private syncForumSource(): void {
    const changed: boolean = this.forumSource.sync(this.vm.forums);
    if (changed || this.capsuleForums.length !== this.vm.forums.length) {
      this.capsuleForums = this.forumSource.snapshot();
    }
  }
  @Monitor('changes.forums')
  refreshRelationships(): void {
    this.relationshipRefreshPending = true;
    this.applyRelationshipRefresh();
  }
  @Monitor('vm.loading')
  applyRelationshipRefresh(): void {
    if (this.vm.loading) { return; }
    this.recentVm.syncKnownAvatars(this.vm.forums);
    const force: boolean = this.active && this.foregroundExperiencePending;
    this.foregroundExperiencePending = false;
    if (!this.layoutStore.isCapsule) {
      if (this.visibleStartIndex >= 0) {
        this.syncVisibleForums();
      }
      for (const item of this.vm.forums) {
        if (this.active && this.visibleForums.has(item.fid)) { this.vm.ensureExperience(this.hostContext(), item, force); }
      }
    }
    if (!this.relationshipRefreshPending) { return; }
    this.relationshipRefreshPending = false;
    this.vm.load(this.hostContext(), true);
  }
  /** 悬浮底栏实际遮挡高度；尾部占位让最后一行能滚到导航上方。 */
  @Param bottomBarOcclusion: number = 0;
  @Local vm: FollowVM = new FollowVM();
  @Local recentVm: RecentForumsVM = new RecentForumsVM();
  @Local auth: AuthSession = authSession;
  @Local signStrategy: SignStrategyStore = signStrategyStore;
  @Local layoutStore: FollowLayoutStore = followLayoutStore;
  private account: string = authSession.forumCacheSessionKey();
  @Monitor('auth.snapshot')
  onAccountChanged(): void {
    const account: string = authSession.forumCacheSessionKey();
    if (account === this.account) { return; }
    this.account = account;
    this.resetPullRefresh();
    this.foregroundExperiencePending = false;
    this.listScrolling = false;
    this.visibleStartIndex = -1;
    this.visibleEndIndex = -1;
    this.visibleForums.clear();
    void this.recentVm.load(this.hostContext());
    void this.vm.load(this.hostContext());
  }
  /** 状态栏高度（vp），见 SafeArea.ets */
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;

  aboutToAppear(): void {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    readStatusBarVp(context).then((vp: number) => {
      this.statusBarH = vp;
    }).catch(() => {
      // 拿不到就保持兜底值
    });
    this.wasActive = this.active;
    this.historyRevision = this.historyChanges.revision;
    void this.layoutStore.load(context);
    void this.recentVm.load(context);
    // 切回先显示缓存，过期后台刷新；跨日不复用昨天的签到标记。
    this.vm.load(context);
    this.syncForumSource();
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }
  aboutToDisappear(): void {
    this.listScrolling = false;
    this.clearTransitionDefer();
    this.resetPullRefresh();
    this.vm.dispose();
    this.recentVm.dispose();
  }

  build() {
    HdsNavigation(this.navStack) {
      Column() {
        this.FollowContent()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppTheme.BG)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
        [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    }
    .titleBar({
      style: {
        scrollEffectOpts: {
          enableScrollEffect: motionStore.isOn(MotionEffect.HDS_SCROLL_BLUR),
          scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(8)
        },
        originalStyle: {
          backgroundStyle: {
            backgroundColor: Color.Transparent,
            maskExtraHeight: 0,
            blurRadius: 0
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            maskExtraHeight: motionStore.isOn(MotionEffect.HDS_SCROLL_BLUR) ? 32 : 0,
            blurRadius: motionStore.isOn(MotionEffect.HDS_SCROLL_BLUR) ? 80 : 0
          }
        }
      },
      content: {
        stackBuilder: (): void => { this.FollowNavBar(); }
      }
    })
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .hideTitleBar(false)
    .systemBarStyle(
      { statusBarContentColor: themeModeStore.isDark ? '#F2F3F4' : '#1B1B1B' },
      { statusBarContentColor: themeModeStore.isDark ? '#F2F3F4' : '#1B1B1B' }
    )
    .mode(NavigationMode.Stack)
    .bindToScrollable([this.listScroller])
    .width('100%')
    .height('100%')
  }

  @Builder
  FollowNavBar() {
    Column() {
      Row({ space: 12 }) {
        Text('进吧')
          .fontSize(UiLayout.ROOT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT_MAIN)
          .layoutWeight(1)
        this.HeaderActions()
      }
      .width('100%')
      .height(FOLLOW_NAV_BAR_HEIGHT)
      .margin({ top: this.statusBarH })
      .padding({ left: UiLayout.PAGE_GUTTER, right: UiLayout.PAGE_GUTTER })
      .alignItems(VerticalAlign.Center)
      .clip(false)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .clip(false)
  }

  @Builder
  PullHeader() {
    PullRefreshHeader({ inset: this.headerHeight(), active: this.refreshing || this.pullRefreshDragging })
  }

  @Builder
  ForumSquareEntry() {
    GlassCircleButton({ symbol: $r('sys.symbol.compass'), diameter: 40, iconSize: 22,
      iconWeight: FontWeight.Regular, accessibilityLabel: '吧广场',
      onTap: (): void => { this.deferForTransition(800); NavigationService.openForumSquare(); } })
      .id('follow-square-entry').margin(4)
  }

  @Builder
  FollowContent() {
    if (!authSession.snapshot.isLoggedIn()) {
      if (this.recentVm.forums.length > 0) {
        this.GuestFollowList()
      } else {
        // 未登录且无本地足迹：沿用 Index 原空态的引导组件（登录返回后切 Tab 重建自然刷新）
        LoginEmptyView({
          icon: $r('app.media.icon_follow'),
          title: '关注列表是空的',
          subtitle: '登录后可查看关注的吧；关注吧的帖子在首页关注频道查看',
          onLogin: (): void => {
            void this.getUIContext().getRouter().pushUrl({ url: 'pages/Login' });
          }
        })
        .padding({ top: this.headerHeight() })
        .layoutWeight(1)
      }
    } else {
      Refresh({ refreshing: this.refreshing, builder: (): void => { this.PullHeader(); } }) {
        this.FollowPage()
      }
      .width('100%').layoutWeight(1)
      .refreshOffset(PULL_REFRESH_OFFSET)
      .pullToRefresh(!this.vm.loading && !this.vm.signingAll && this.vm.signingFname.length === 0)
      .onStateChange((state: RefreshStatus): void => {
        this.pullRefreshDragging = state === RefreshStatus.Drag || state === RefreshStatus.OverDrag;
      })
      .onTouch((event: TouchEvent): void => { this.handleRefreshTouch(event); })
      .onRefreshing((): void => { void this.refreshForums(true); })
      .id('follow-refresh')
    }
  }

  private allSigned(): boolean {
    return this.vm.forums.length > 0 && this.vm.forums.every((item: FollowForumItem): boolean =>
      item.signKnown && item.isSigned);
  }

  private signAllDisabled(): boolean {
    return this.vm.signingAll || this.vm.loading || this.vm.signingFname.length > 0 ||
      this.vm.forums.length === 0 || this.allSigned();
  }

  private signAll(): void {
    if (this.signAllDisabled()) { return; }
    this.vm.signInAll(this.hostContext()).then((message: string) => {
      if (message.length > 0) { this.getUIContext().getPromptAction().showToast({ message, duration: 2400 }); }
    });
  }

  @Builder
  SignAllProgress() {
    LoadingProgress().width(20).height(20).color(AppTheme.TEXT_SUB)
  }

  private toggleLayout(): void {
    if (!this.layoutStore.isCapsule) {
      this.visibleStartIndex = -1;
      this.visibleEndIndex = -1;
      this.visibleForums.clear();
    }
    void this.layoutStore.toggle(this.hostContext());
  }

  @Builder
  LayoutToggleEntry() {
    GlassCircleButton({
      symbol: this.layoutStore.isCapsule ? $r('sys.symbol.list_bullet') : $r('sys.symbol.square_grid_2x2'),
      diameter: 40, iconSize: 22, iconWeight: FontWeight.Regular,
      accessibilityLabel: this.layoutStore.isCapsule ? '切换为列表布局' : '切换为胶囊布局',
      onTap: (): void => { this.toggleLayout(); }
    })
      .id('follow-layout-toggle').margin(4)
  }

  /** 顶栏圆形动作保持同尺寸；列表单吧签到仍沿用小型胶囊。 */
  @Builder
  HeaderActions() {
    Row({ space: 4 }) {
      this.ForumSquareEntry()
      if (authSession.snapshot.isLoggedIn()) {
        this.LayoutToggleEntry()
        GlassCircleButton({
          symbol: this.allSigned() ? $r('sys.symbol.checkmark') : $r('sys.symbol.calendar'),
          diameter: 40, iconSize: 22, iconWeight: FontWeight.Regular,
          useCustomIcon: this.vm.signingAll, customIcon: (): void => { this.SignAllProgress(); },
          accessibilityLabel: this.vm.signingAll ? '正在签到' :
            (this.allSigned() ? '所有关注的吧已签到' :
              (this.signStrategy.strategy === 2 ? '混合签到' : (this.signStrategy.strategy === 1 ? '官方批量签到' : '一键签到'))),
          onTap: (): void => { this.signAll(); }
        }).id('follow-sign-all').margin(4).enabled(!this.signAllDisabled())
          .opacity(this.signAllDisabled() && !this.vm.signingAll ? 0.5 : 1)
      }
    }.id('follow-header-actions')
  }

  @Builder
  SectionHeader(title: string) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_MAIN)
    }
    .width('100%')
    .padding({ left: UiLayout.PAGE_GUTTER, right: UiLayout.PAGE_GUTTER, top: 12, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  RecentForumTile(item: RecentForumItem) {
    Column({ space: 6 }) {
      ForumAvatarImage({
        url: item.avatar,
        forumName: item.forumName,
        avatarSize: RECENT_AVATAR_SIZE,
        radius: forumAvatarRadius(RECENT_AVATAR_SIZE),
        onLoadError: (): void => {
          void this.recentVm.retryAvatar(this.hostContext(), item.forumName);
        }
      })
      Text(displayForumName(item.forumName))
        .fontSize(12)
        .fontColor(AppTheme.TEXT_MAIN)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width(RECENT_TILE_WIDTH)
    .alignItems(HorizontalAlign.Center)
    .accessibilityGroup(true)
    .accessibilityText(`进入${displayForumName(item.forumName)}`)
    .onClick((): void => {
      this.handleOpenForum(item.forumName);
    })
  }

  private findFollowedForum(forumName: string): FollowForumItem | undefined {
    for (let i: number = 0; i < this.capsuleForums.length; i++) {
      if (this.capsuleForums[i].fname === forumName) {
        return this.capsuleForums[i];
      }
    }
    return undefined;
  }

  private recentCapsuleItem(recent: RecentForumItem): FollowForumItem {
    const followed: FollowForumItem | undefined = this.findFollowedForum(recent.forumName);
    if (followed !== undefined) {
      return followed;
    }
    const item: FollowForumItem = new FollowForumItem();
    item.fname = recent.forumName;
    item.avatar = recent.avatar;
    return item;
  }

  private recentCapsuleKey(recent: RecentForumItem): string {
    const followed: FollowForumItem | undefined = this.findFollowedForum(recent.forumName);
    const fid: number = followed !== undefined ? followed.fid : 0;
    return `${recent.forumName}-${recent.avatar}-${fid}`;
  }

  @Builder
  RecentCapsuleRow(items: RecentForumItem[]) {
    Row({ space: 8 }) {
      ForEach(items, (item: RecentForumItem) => {
        FollowForumCapsule({
          item: this.recentCapsuleItem(item),
          fallbackAvatar: item.avatar,
          flowMargin: false,
          maxCapsuleWidth: 220,
          onAvatarError: (): void => {
            void this.recentVm.retryAvatar(this.hostContext(), item.forumName);
          },
          onOpenForum: this.handleOpenForum
        })
      }, (item: RecentForumItem): string => this.recentCapsuleKey(item))
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  RecentForumsSection() {
    Column() {
      this.SectionHeader('我的足迹')
      Scroll(this.recentScroller) {
        if (this.layoutStore.isCapsule) {
          Column({ space: 10 }) {
            this.RecentCapsuleRow(splitRecentTwoRows(this.recentVm.forums)[0])
            if (splitRecentTwoRows(this.recentVm.forums)[1].length > 0) {
              this.RecentCapsuleRow(splitRecentTwoRows(this.recentVm.forums)[1])
            }
          }
          .padding({ left: UiLayout.PAGE_GUTTER, right: UiLayout.PAGE_GUTTER, top: 2, bottom: 6 })
          .alignItems(HorizontalAlign.Start)
        } else {
          Row({ space: 12 }) {
            ForEach(this.recentVm.forums, (item: RecentForumItem) => {
              this.RecentForumTile(item)
            }, (item: RecentForumItem): string => `${item.forumName}-${item.avatar}`)
          }
          .padding({ left: UiLayout.PAGE_GUTTER, right: UiLayout.PAGE_GUTTER, top: 4, bottom: 10 })
          .alignItems(VerticalAlign.Top)
        }
      }
      .width('100%')
      .align(Alignment.TopStart)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .id('follow-recent-list')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  GuestFollowList() {
    List({ space: 0, scroller: this.listScroller }) {
      ListItem() {
        Row().width('100%').height(this.headerHeight())
      }
      .accessibilityLevel('no')
      .hitTestBehavior(HitTestMode.None)
      if (this.recentVm.forums.length > 0) {
        ListItem() {
          this.RecentForumsSection()
        }.id('follow-guest-recent-section')
      }
      ListItem() {
        this.SectionHeader('我的关注')
      }.id('follow-guest-section-title')
      ListItem() {
        LoginEmptyView({
          icon: $r('app.media.icon_follow'),
          title: '关注列表是空的',
          subtitle: '登录后可查看关注的吧；关注吧的帖子在首页关注频道查看',
          onLogin: (): void => {
            void this.getUIContext().getRouter().pushUrl({ url: 'pages/Login' });
          }
        })
      }
      ListItem() {
        Column().width('100%').height(this.bottomBarOcclusion)
          .accessibilityLevel('no').hitTestBehavior(HitTestMode.None)
      }.id('follow-guest-bottom-occlusion')
    }
    .width('100%')
    .layoutWeight(1)
    .clip(true)
    .scrollBar(BarState.Off)
  }

  @Builder
  FollowPage() {
    Column() {
      this.FollowList()
    }
    .width('100%')
    .height('100%')
  }

  private forumStartIndex(): number {
    let idx: number = 1;
    if (this.recentVm.forums.length > 0) { idx++; }
    idx++;
    if (this.vm.errorText.length > 0) { idx++; }
    return idx;
  }

  private syncVisibleForums(): void {
    if (this.layoutStore.isCapsule || this.visibleStartIndex < 0 || this.visibleEndIndex < 0) {
      this.visibleForums.clear();
      return;
    }
    const total: number = this.vm.forums.length;
    const startIdx: number = this.forumStartIndex();
    if (total === 0 || this.visibleEndIndex < startIdx || this.visibleStartIndex >= startIdx + total) {
      this.visibleForums.clear();
      return;
    }
    const first: number = Math.max(0, this.visibleStartIndex - startIdx);
    const last: number = Math.min(total - 1, this.visibleEndIndex - startIdx);
    this.visibleForums.clear();
    for (let i: number = first; i <= last && i < total; i++) {
      const row: FollowForumItem = this.vm.forums[i];
      this.visibleForums.set(row.fid, row);
    }
  }

  private updateVisibleForums(start: VisibleListContentInfo, end: VisibleListContentInfo): void {
    if (this.layoutStore.isCapsule) {
      this.visibleStartIndex = -1;
      this.visibleEndIndex = -1;
      this.visibleForums.clear();
      return;
    }
    this.visibleStartIndex = start.index;
    this.visibleEndIndex = end.index;
    if (this.listScrolling) { return; }
    this.syncVisibleForums();
    this.ensureVisibleExperiences(false);
  }

  private ensureVisibleExperiences(force: boolean): void {
    if (!this.active || this.vm.loading) { return; }
    this.visibleForums.forEach((row: FollowForumItem): void => {
      this.vm.ensureExperience(this.hostContext(), row, force);
    });
  }

  private handleSignTap(item: FollowForumItem): void {
    if (!item.signKnown) { void this.refreshForums(); return; }
    // 写操作防连点在 VM 内部（signingFname 占位）；结果用 toast 反馈
    this.vm.signIn(this.hostContext(), item).then((message: string) => {
      if (message.length > 0) {
        this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
      }
    });
  }

  @Builder
  FollowCapsuleFlow() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.capsuleForums, (item: FollowForumItem) => {
        FollowForumCapsule({
          item: item,
          onOpenForum: this.handleOpenForum
        })
      }, (item: FollowForumItem): string => followForumRowId(item))
    }
    .width('100%')
    .padding({ left: UiLayout.PAGE_GUTTER, right: UiLayout.PAGE_GUTTER, top: 2 })
  }

  @Builder
  FollowList() {
    List({ space: 0, scroller: this.listScroller }) {
      ListItem() {
        Row().width('100%').height(this.headerHeight())
      }
      .accessibilityLevel('no')
      .hitTestBehavior(HitTestMode.None)
      if (this.recentVm.forums.length > 0) {
        ListItem() {
          this.RecentForumsSection()
        }.id('follow-recent-section')
      }
      ListItem() {
        this.SectionHeader('我的关注')
      }.id('follow-section-title')
      if (this.vm.loading && !this.vm.loadedOnce) {
        ListItem() {
          PageState({ loading: true, message: '正在加载关注的吧…' })
        }
      } else if (this.vm.forums.length === 0 && this.vm.errorText.length > 0) {
        ListItem() {
          PageState({ title: '加载失败', message: this.vm.errorText, actionLabel: '重试',
            onAction: (): void => { void this.refreshForums(); } })
        }
      } else if (this.vm.forums.length === 0) {
        ListItem() {
          PageState({ message: '还没有关注任何吧' })
        }
      } else {
        if (this.vm.errorText.length > 0) {
          ListItem() {
            PageState({ compact: true, message: '更新失败，正在显示上次数据', actionLabel: '重试',
              onAction: (): void => { void this.refreshForums(); } })
          }
        }
        if (this.layoutStore.isCapsule) {
          ListItem() {
            this.FollowCapsuleFlow()
          }.id('follow-capsule-flow')
        } else {
          LazyForEach(this.forumSource, (item: FollowForumItem, index: number) => {
            ListItem() {
              FollowForumRow({
                item: item,
                showTopDivider: index > 0,
                scrolling: this.listScrolling || !this.active || this.transitionDeferring,
                signingFname: this.vm.signingFname,
                vmLoading: this.vm.loading,
                signingAll: this.vm.signingAll,
                onOpenForum: this.handleOpenForum,
                onSignTap: this.handleSignTapBound
              })
            }
          }, (item: FollowForumItem): string => followForumRowId(item))
        }
      }
      ListItem() {
        Column().width('100%').height(this.bottomBarOcclusion)
          .accessibilityLevel('no').hitTestBehavior(HitTestMode.None)
      }.id('follow-bottom-occlusion')
    }
    .width('100%')
    .layoutWeight(1)
    .clip(true)
    .scrollBar(BarState.Off)
    .cachedCount(6)
    .onScrollStart((): void => { this.listScrolling = true; })
    .onScrollStop((): void => {
      this.listScrolling = false;
      this.syncVisibleForums();
      this.ensureVisibleExperiences(false);
    })
    .onScrollVisibleContentChange((start: VisibleListContentInfo, end: VisibleListContentInfo): void => {
      this.updateVisibleForums(start, end);
    })
  }

}

@ReusableV2
@ComponentV2
export struct FollowForumRow {
  @Param @Require item: FollowForumItem;
  @Param showTopDivider: boolean = false;
  @Param scrolling: boolean = false;
  @Param signingFname: string = '';
  @Param vmLoading: boolean = false;
  @Param signingAll: boolean = false;
  @Event onOpenForum: (fname: string) => void = (_fname: string): void => {};
  @Event onSignTap: (item: FollowForumItem) => void = (_item: FollowForumItem): void => {};
  private readonly handleSignButtonTap: () => void = (): void => { this.onSignTap(this.item); };
  private readonly handleRowClick: () => void = (): void => { this.onOpenForum(this.item.fname); };

  /** 进行中只用按钮内的转圈表示，文案保持稳定状态，不加「…中…」字样。 */
  private signLabel(): string {
    if (this.signingFname === this.item.fname) { return '签到'; }
    if (!this.item.signKnown) { return '重试'; }
    return this.item.isSigned ? '已签到' : '签到';
  }

  build() {
    Column() {
      if (this.showTopDivider) {
        Divider()
          .strokeWidth(0.5)
          .color(AppTheme.DIVIDER)
          .margin({ left: 66, right: 16 })
      }
      Row({ space: 10 }) {
        ForumAvatarImage({ url: this.item.avatar, forumName: this.item.fname,
          avatarSize: 40, radius: 40 * 14 / 64 })

        Column({ space: 3 }) {
          Text(displayForumName(this.item.fname))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT_MAIN)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row({ space: 6 }) {
            ForumLevelBadge({ level: this.item.level, levelName: this.item.levelName }).flexShrink(0)
            if (this.item.continuousCount >= 0) {
              Text(`连签 ${this.item.continuousCount} 天`)
                .fontSize(UiLayout.META).fontColor(AppTheme.TEXT_SUB)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        ForumActionButton({
          label: this.signLabel(),
          actionSymbol: $r('sys.symbol.calendar'),
          busy: this.signingFname === this.item.fname || (!this.item.signKnown && this.vmLoading),
          completed: this.item.signKnown && this.item.isSigned,
          retry: !this.item.signKnown && !this.vmLoading,
          disabled: (this.item.signKnown && this.item.isSigned) || this.vmLoading || this.signingAll ||
            this.signingFname.length > 0,
          deferMaterial: this.scrolling,
          accessibilityLabel: `${this.item.fname}，${this.signLabel()}`,
          onTap: this.handleSignButtonTap
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .onClick(this.handleRowClick)
  }
}

@ComponentV2
export struct FollowForumCapsule {
  @Param @Require item: FollowForumItem;
  @Param fallbackAvatar: string = '';
  @Param flowMargin: boolean = true;
  @Param maxCapsuleWidth: Length = '100%';
  @Event onAvatarError: () => void = (): void => {};
  @Event onOpenForum: (fname: string) => void = (_fname: string): void => {};

  private signed(): boolean {
    return this.item.signKnown && this.item.isSigned;
  }

  private avatarUrl(): string {
    return this.item.avatar.length > 0 ? this.item.avatar : this.fallbackAvatar;
  }

  private capsuleA11yLabel(): string {
    const name: string = displayForumName(this.item.fname);
    if (this.item.level <= 0) {
      return `进入${name}`;
    }
    const signPart: string = this.signed() ? '，已签到' : '，未签到';
    return `${name}，${this.item.level}级${signPart}`;
  }

  build() {
    Row({ space: 6 }) {
      ForumAvatarImage({
        url: this.avatarUrl(),
        forumName: this.item.fname,
        avatarSize: CAPSULE_AVATAR_SIZE,
        radius: CAPSULE_AVATAR_SIZE / 2,
        onLoadError: (): void => { this.onAvatarError(); }
      })
      Text(displayForumName(this.item.fname))
        .fontSize(14)
        .fontColor(AppTheme.TEXT_MAIN)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .flexShrink(1)
      if (this.item.level > 0) {
        Text(`${this.item.level}`)
          .fontSize(10)
          .maxFontScale(1)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .width(CAPSULE_LEVEL_SIZE)
          .height(CAPSULE_LEVEL_SIZE)
          .borderRadius(CAPSULE_LEVEL_SIZE / 2)
          .backgroundColor(this.signed() ? AppTheme.FOLLOW_LEVEL_SIGNED_BG : AppTheme.FOLLOW_LEVEL_UNSIGNED_BG)
          .flexShrink(0)
      }
    }
    .constraintSize({ maxWidth: this.maxCapsuleWidth, minHeight: 32 })
    .padding({ left: 6, right: 8, top: 5, bottom: 5 })
    .borderRadius(999)
    .backgroundColor(AppTheme.CARD)
    .alignItems(VerticalAlign.Center)
    .margin(this.flowMargin ? { right: 8, bottom: 10 } : 0)
    .accessibilityGroup(true)
    .accessibilityText(this.capsuleA11yLabel())
    .onClick((): void => { this.onOpenForum(this.item.fname); })
  }
}
