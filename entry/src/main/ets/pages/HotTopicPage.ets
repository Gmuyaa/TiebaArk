/** 热榜话题详情：原生话题介绍与帖子列表，共用应用内导航和帖子交互。 */

import { common } from '@kit.AbilityKit';
import { LengthMetrics } from '@kit.ArkUI';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { TiebaApi } from '../api/TiebaApi';
import { authSession, AuthSession } from '../auth/AuthSession';
import { HotTopicCardInfo } from '../model/HotTopicCard';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { HotTopicCardsVM } from '../viewmodel/HotTopicCardsVM';
import { motionEdgeEffect } from '../common/appearance/MotionPolicy';
import { homeChannelHeight } from '../common/appearance/UiLayout';
import { fontScaleStore } from '../common/appearance/FontSizeScaleStore';
import { fontSizeScaleOf } from '../common/appearance/FontSizeScale';
import { lowFlowStore } from '../common/appearance/LowFlowStore';
import { PageHeader } from '../components/PageHeader';
import { GlassCircleButton } from '../components/GlassCircleButton';
import { PageState, ListFooter } from '../components/PageState';
import { PullRefreshHeader, PULL_REFRESH_OFFSET } from '../components/RefreshSpinner';
import { TopLabelItem } from '../components/TopLabelItem';
import { ThreadPreviewCard } from '../components/ThreadPreviewCard';
import { buildThreadCardMenu } from '../components/ThreadCardMenu';
import { ImageViewer } from '../components/ImageViewer';
import { animateImageTransition } from '../components/ImageTransition';
import { ThreadBrief } from '../model/ThreadList';
import { visibleThreads } from '../model/ThreadBlock';
import { ContentPiece } from '../model/ThreadDetail';
import { feedImageInfo, formatPostTime } from '../model/HomeFeedPresentation';
import { formatCount } from '../model/UserProfile';
import { NavigationService, HotTopicParams } from '../navigation/AppNavigation';
import { openContentPiece } from '../navigation/ContentNavigation';
import { openUserByIdentity } from '../navigation/UserNavigation';
import { HotTopicDetailVM } from '../viewmodel/HotTopicDetailVM';
import { ThreadCardActionsVM, ThreadCardActionState } from '../viewmodel/ThreadCardActionsVM';
import { AppTheme } from '../theme/Theme';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { ThreadBlockStore, threadBlockStore } from '../utils/ThreadBlockStore';

@ComponentV2
export struct HotTopicPage {
  @Param routeParams: HotTopicParams | undefined = undefined;
  @Local vm: HotTopicDetailVM = new HotTopicDetailVM();
  @Local cards: HotTopicCardsVM = new HotTopicCardsVM();
  @Local auth: AuthSession = authSession;
  @Local blocks: ThreadBlockStore = threadBlockStore;
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;
  @Local refreshing: boolean = false;
  @Local pullRefreshDragging: boolean = false;
  @Local viewerImages: string[] = [];
  @Local viewerIndex: number = 0;
  private cardActions: ThreadCardActionsVM = new ThreadCardActionsVM();
  private imageScrollers: Map<number, ListScroller> = new Map<number, ListScroller>();
  /** 续页复用旧对象；刷新产生的新对象即使同 tid 也重新绑定卡片内容。 */
  private cardKeys: WeakMap<ThreadBrief, string> = new WeakMap<ThreadBrief, string>();
  private nextCardKey: number = 0;
  private listScroller: ListScroller = new ListScroller();
  private alive: boolean = false;
  private refreshPending: boolean = false;
  private cardApi: TiebaApi = new TiebaApi();

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    this.alive = true;
    this.configureCards();
    void this.blocks.load(this.hostContext());
    readStatusBarVp(this.hostContext()).then((vp: number): void => {
      if (this.alive) { this.statusBarH = vp; }
    }).catch(() => {});
    void this.vm.load(this.routeParams?.topicId ?? 0, this.routeParams?.topicName ?? '');
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.cards.reset();
    this.vm.dispose();
    this.imageScrollers.clear();
  }

  private configureCards(): void {
    const account: string = authSession.sessionKey();
    const context: common.UIAbilityContext = this.hostContext();
    this.cards.reset(async (tid: number): Promise<HotTopicCardInfo | undefined> => {
      const device = await DeviceIdentity.ensure(context);
      if (!this.alive || account !== authSession.sessionKey()) { return undefined; }
      const response = await this.cardApi.fetchHotTopicCard(device, authSession.session(), tid);
      return this.alive && account === authSession.sessionKey() && response.ok ? response.data : undefined;
    });
  }

  @Monitor('vm.items')
  onItemsChanged(): void {
    if (!this.alive) { return; }
    this.cards.sync(this.vm.items);
    this.trimImageScrollers();
  }

  @Monitor('auth.snapshot')
  onAccountChanged(): void {
    if (!this.alive) { return; }
    this.configureCards();
    this.cards.sync(this.vm.items);
    void this.blocks.load(this.hostContext());
  }

  /** 修订值建立标量依赖；补充字段更新同一对象，不重建正文图片和点赞状态。 */
  private cardInfo(item: ThreadBrief, _revision: number): ThreadBrief { return item; }

  /** 作者身份在后台补齐后也重算过滤，原始分页列表与 hasMore 不受屏蔽规则影响。 */
  @Computed
  get visibleTopicThreads(): ThreadBrief[] {
    return visibleThreads(this.itemsAtRevision(this.cards.revision), this.blocks.rules());
  }

  private itemsAtRevision(_revision: number): ThreadBrief[] { return this.vm.items; }

  private topicTitle(): string {
    return this.vm.data.title || this.routeParams?.topicName?.trim() || '热议话题';
  }

  private cardKey(item: ThreadBrief): string {
    let key: string | undefined = this.cardKeys.get(item);
    if (key === undefined) {
      key = `${item.tid}-${++this.nextCardKey}`;
      this.cardKeys.set(item, key);
    }
    return key;
  }

  private imageScroller(tid: number): ListScroller {
    let scroller: ListScroller | undefined = this.imageScrollers.get(tid);
    if (scroller === undefined) {
      scroller = new ListScroller();
      this.imageScrollers.set(tid, scroller);
    }
    return scroller;
  }

  private trimImageScrollers(): void {
    const retained: Set<number> = new Set<number>();
    for (const item of this.vm.items) { retained.add(item.tid); }
    this.imageScrollers.forEach((_scroller: ListScroller, tid: number): void => {
      if (!retained.has(tid)) { this.imageScrollers.delete(tid); }
    });
  }

  private async refresh(retry: boolean = false): Promise<void> {
    if (this.refreshPending) { return; }
    this.refreshPending = true;
    try {
      if (retry) { await this.vm.retry(); }
      else { await this.vm.refresh(); }
    }
    finally {
      this.refreshPending = false;
      if (this.alive) {
        this.refreshing = false;
        this.trimImageScrollers();
      }
    }
  }

  private async selectSort(sort: number): Promise<void> {
    if (this.vm.sort === sort || this.vm.loading) { return; }
    await this.vm.selectSort(sort);
    if (!this.alive) { return; }
    this.trimImageScrollers();
    if (this.vm.error.length === 0) { this.listScroller.scrollEdge(Edge.Top); }
  }

  private showActionResult(message: string): void {
    if (this.alive && message.length > 0) { this.getUIContext().getPromptAction().showToast({ message }); }
  }

  private threadImages(item: ThreadBrief): string[] {
    return item.images.length > 0 ? item.images : (item.coverImage.length > 0 ? [item.coverImage] : []);
  }

  private openThread(item: ThreadBrief, comments: boolean = false): void {
    NavigationService.openThreadDetail({ tid: item.tid, forumName: item.sourceForum,
      replyCount: item.replyCount >= 0 ? item.replyCount : undefined, openComments: comments });
  }

  private sortHeight(): number {
    return Math.max(44, homeChannelHeight(fontSizeScaleOf(
      fontScaleStore.pref, fontScaleStore.systemScale, fontScaleStore.customSize)));
  }

  private sortWidth(): number {
    return Math.max(60, Math.ceil(48 * fontSizeScaleOf(
      fontScaleStore.pref, fontScaleStore.systemScale, fontScaleStore.customSize)));
  }

  @Builder
  HeaderActions() {
    GlassCircleButton({ symbol: $r('sys.symbol.arrow_clockwise'), iconWeight: FontWeight.Regular,
      accessibilityLabel: '刷新话题', onTap: (): void => { void this.refresh(); } })
      .enabled(!this.vm.loading && !this.vm.loadingMore)
      .opacity(this.vm.loading || this.vm.loadingMore ? 0.45 : 1)
  }

  @Builder
  PullHeader() { PullRefreshHeader({ active: this.refreshing || this.pullRefreshDragging }) }

  @Builder
  TopicIntro() {
    Column({ space: 12 }) {
      Text(this.topicTitle()).fontSize(24).fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.TEXT_MAIN).width('100%').id('hot-topic-title')
      if (this.vm.data.heat >= 0 || this.vm.data.discussCount >= 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          if (this.vm.data.heat >= 0) {
            Text(`热度 ${formatCount(this.vm.data.heat)}`).fontSize(13).fontColor(AppTheme.ACCENT_DARK)
              .margin({ right: 16 }).constraintSize({ minHeight: 24 })
          }
          if (this.vm.data.discussCount >= 0) {
            Text(`${formatCount(this.vm.data.discussCount)} 讨论`).fontSize(13).fontColor(AppTheme.TEXT_SUB)
              .constraintSize({ minHeight: 24 })
          }
        }.width('100%')
      }
      if (this.vm.data.description.length > 0) {
        Row({ space: 16 }) {
          Text(this.vm.data.description).fontSize(15).fontColor(AppTheme.TEXT_SUB)
            .lineSpacing(LengthMetrics.vp(5)).layoutWeight(1).id('hot-topic-description')
          if (this.vm.data.imageUrl.length > 0 && !lowFlowStore.enabled) {
            Image(this.vm.data.imageUrl).width(72).height(72).borderRadius(12)
              .objectFit(ImageFit.Cover).flexShrink(0).accessibilityLevel('no')
          }
        }.width('100%').alignItems(VerticalAlign.Top)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
      .padding({ left: 4, right: 4, top: 12, bottom: 8 })
  }

  @Builder
  SortBar() {
    Row({ space: 8 }) {
      Text('话题讨论').fontSize(17).fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_MAIN).layoutWeight(1)
      Row() {
        TopLabelItem({ label: '热门', selected: this.vm.sort === 1,
          onTap: (): void => { void this.selectSort(1); } })
          .width(this.sortWidth()).height(this.sortHeight())
          .enabled(!this.vm.loading).id('hot-topic-sort-hot')
        TopLabelItem({ label: '最新', selected: this.vm.sort === 2,
          onTap: (): void => { void this.selectSort(2); } })
          .width(this.sortWidth()).height(this.sortHeight())
          .enabled(!this.vm.loading).id('hot-topic-sort-new')
      }.flexShrink(0)
    }.width('100%').padding({ left: 4 })
  }

  @Builder
  ThreadCard(item: ThreadBrief) {
    ThreadPreviewCard({
      authorName: this.cardInfo(item, this.cards.revision).authorName,
      authorAvatar: this.cardInfo(item, this.cards.revision).authorAvatar,
      forumName: item.sourceForum, forumAvatar: this.cardInfo(item, this.cards.revision).sourceForumAvatar,
      forumAvatarRevision: this.cardInfo(item, this.cards.revision).avatarStamp,
      postedTime: formatPostTime(this.cardInfo(item, this.cards.revision).postedMs, Date.now()),
      title: item.title, summary: item.summary, images: this.threadImages(item),
      isTop: item.isTop, isGood: item.isGood, isHelp: item.isHelp,
      agreeCount: this.cardInfo(item, this.cards.revision).agreeCount, replyCount: item.replyCount,
      shareCount: this.cardInfo(item, this.cards.revision).shareCount,
      menu: buildThreadCardMenu(this.getUIContext(), this.cardInfo(item, this.cards.revision)),
      imageScroller: this.imageScroller(item.tid),
      canOpenAuthor: this.cardInfo(item, this.cards.revision).authorId > 0 ||
        this.cardInfo(item, this.cards.revision).authorAvatar.length > 0,
      canOpenForum: item.sourceForum.length > 0,
      onActivateContent: (piece: ContentPiece): void => { openContentPiece(piece, this.getUIContext()); },
      onOpenAuthor: (): void => {
        openUserByIdentity(item.authorId, item.authorAvatar, item.authorName, this.getUIContext());
      },
      onOpenForum: (): void => { NavigationService.openForum({ forumName: item.sourceForum }); },
      onOpenThread: (): void => { this.openThread(item); },
      onOpenComments: (): void => { this.openThread(item, true); },
      onToggleLike: (state: ThreadCardActionState): void => {
        void this.cardActions.toggleLike(state, this.hostContext(), item.tid, item.sourceForum)
          .then((message: string): void => { this.showActionResult(message); });
      },
      onShare: (): void => {
        void this.cardActions.share(this.hostContext(), item.tid, item.title)
          .then((message: string): void => { this.showActionResult(message); });
      },
      onOpenImage: (index: number): void => {
        this.viewerIndex = index;
        this.viewerImages = this.threadImages(item).map((url: string): string => feedImageInfo(url).origin || url);
      }
    })
  }

  @Builder
  TopicList() {
    Refresh({ refreshing: $$this.refreshing, builder: (): void => { this.PullHeader(); } }) {
      List({ space: 10, scroller: this.listScroller }) {
        ListItem() { this.TopicIntro() }
        ListItem() { this.SortBar() }
        if (this.vm.error.length > 0) {
          ListItem() {
            PageState({ compact: true, message: this.vm.error, actionLabel: '重试',
              onAction: (): void => { void this.refresh(true); } })
          }
        }
        if (this.vm.loading && !this.refreshing) {
          ListItem() { PageState({ compact: true, loading: true, message: '正在更新讨论…' }) }
        }
        ForEach(this.visibleTopicThreads, (item: ThreadBrief) => {
          ListItem() { this.ThreadCard(item) }
        }, (item: ThreadBrief) => this.cardKey(item))
        if (this.vm.items.length === 0 && !this.vm.loading && this.vm.error.length === 0) {
          ListItem() { PageState({ message: '这个话题暂时没有可展示的帖子' }) }
        }
        if (this.vm.items.length > 0 && this.visibleTopicThreads.length === 0 &&
          !this.vm.loading && this.vm.error.length === 0) {
          ListItem() {
            PageState({ message: '当前已加载的帖子均被屏蔽或隐藏',
              actionLabel: this.vm.hasMore && !this.vm.loadingMore && this.vm.moreError.length === 0 ? '继续加载' : '',
              onAction: (): void => { void this.vm.loadMore(); } })
          }
        }
        if (this.vm.items.length > 0) {
          ListItem() {
            ListFooter({ loading: this.vm.loadingMore, error: this.vm.moreError, hasMore: this.vm.hasMore,
              endText: '暂时没有更多讨论', onRetry: (): void => { void this.vm.loadMore(); } })
          }
        }
      }.width('100%').height('100%').padding({ left: 12, right: 12 })
        .edgeEffect(motionEdgeEffect()).scrollBar(BarState.Off)
        .onReachEnd((): void => {
          if (this.visibleTopicThreads.length > 0 && this.vm.moreError.length === 0) { void this.vm.loadMore(); }
        })
    }.width('100%').layoutWeight(1).refreshOffset(PULL_REFRESH_OFFSET)
      .onStateChange((state: RefreshStatus): void => {
        this.pullRefreshDragging = state === RefreshStatus.Drag || state === RefreshStatus.OverDrag;
      })
      .onRefreshing((): void => { void this.refresh(); })
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Column() {
          PageHeader({ title: '热议话题', onBack: (): void => { NavigationService.back(); },
            actions: (): void => { this.HeaderActions(); } })
          if (!this.vm.loaded) {
            PageState({ fillRemaining: true, loading: this.vm.loading,
              title: this.vm.error.length > 0 ? '话题加载失败' : '',
              message: this.vm.error || '正在加载话题…', actionLabel: this.vm.error.length > 0 ? '重试' : '',
              onAction: (): void => { void this.refresh(true); } }).layoutWeight(1)
          } else {
            this.TopicList()
          }
        }.width('100%').height('100%').padding({ top: this.statusBarH }).backgroundColor(AppTheme.BG)
        if (this.viewerImages.length > 0) {
          ImageViewer({ imageUrls: this.viewerImages, initialIndex: this.viewerIndex,
            onClose: (): void => { this.viewerImages = []; } })
        }
      }.width('100%').height('100%')
    }.hideTitleBar(true)
      .onBackPressed((): boolean => {
        if (this.viewerImages.length === 0) { return false; }
        animateImageTransition(this.getUIContext(), (): void => { this.viewerImages = []; });
        return true;
      })
  }
}
