import { followChanges } from '../viewmodel/FollowActionVM';

import { openUserByIdentity } from '../navigation/UserNavigation';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { curves, promptAction, router } from '@kit.ArkUI';
import { ThreadPreviewCard } from './ThreadPreviewCard';
import { buildThreadCardMenu } from './ThreadCardMenu';
import { visibleThreads } from '../model/ThreadBlock';
import { threadBlockStore } from '../utils/ThreadBlockStore';
import { feedImageInfo, formatPostTime } from '../model/HomeFeedPresentation';
import { ThreadBrief } from '../model/ThreadList';
import { RecommendVM } from '../viewmodel/RecommendVM';
import { FollowFeedVM } from '../viewmodel/FollowFeedVM';
import { HotTopicVM } from '../viewmodel/HotTopicVM';
import { HotTopicItem, hotDiscussLabel } from '../model/HotTopic';
import { AppTheme } from '../theme/Theme';
import { NavigationService } from '../navigation/AppNavigation';
import { LoginEmptyView } from './LoginEmptyView';
import { RefreshSpinner, HOME_REFRESH_OFFSET } from './RefreshSpinner';
import { AuthSession, authSession } from '../auth/AuthSession';
import { isForumAvatarFetched, putForumAvatar } from '../model/ForumAvatarStore';
import { ForumAvatarQueue } from '../model/ForumAvatarQueue';
import { TiebaApi, ThreadListResponse } from '../api/TiebaApi';
import { TiebaDevice, TiebaSession } from '../net/TiebaParams';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { BrowseItem, loadBrowseHistory } from '../utils/BrowseHistory';
import { readStatusBarVp } from '../utils/SafeArea';

interface FeedChannel {
  label: string;
  forum: string;
}

const CHANNELS: FeedChannel[] = [
  { label: '关注', forum: '' },
  { label: '推荐', forum: '' },
  { label: '热榜', forum: '' }
];

const PREFETCH_ITEMS: number = 5;

const REFRESH_ECHO_MS: number = 300;

const REFRESH_OFFSET_VP: number = HOME_REFRESH_OFFSET;

@ComponentV2
export struct ForumListView {
  private changes = followChanges;
  private relationshipRefreshPending: boolean = false;
  @Monitor('changes.forums')
  refreshRelationships(): void {
    this.relationshipRefreshPending = true;
    this.applyRelationshipRefresh();
  }
  @Monitor('followVm.loading', 'followVm.loadingMore')
  applyRelationshipRefresh(): void {
    if (!this.relationshipRefreshPending || this.followVm.loading || this.followVm.loadingMore) { return; }
    this.relationshipRefreshPending = false;
    this.followVm.loadedOnce = false;
    if (this.selectedChannel === '关注') { this.followVm.load(this.hostContext()); }
  }
  @Param topNavigationRowHeight: number = 54;
  @Param topNavigationHidden: boolean = false;
  @Param scrollNavigationHidden: boolean = false;

  @Param recommendScroller: ListScroller = new ListScroller();
  @Param followScroller: ListScroller = new ListScroller();
  @Param hotScroller: ListScroller = new ListScroller();
  @Event onScrollNavigationHiddenChange: (hidden: boolean) => void = (_hidden: boolean): void => {};

  @Event onHomeActionsReady: (scrollTop: () => void, refresh: () => void) => void =
    (_scrollTop: () => void, _refresh: () => void): void => {};
  @Event onChannelActionsReady: (change: (label: string) => void) => void =
    (_change: (label: string) => void): void => {};
  @Event onChannelChanged: (label: string) => void = (_label: string): void => {};
  @Local auth: AuthSession = authSession;
  @Monitor('auth.sessionRevision')
  onAccountChanged(): void {
    this.vm.resetAccount(); this.followVm.resetAccount();
    void threadBlockStore.load(this.hostContext());
    if (authSession.isLoggedIn()) {
      void this.vm.refreshRecommend(this.hostContext());
      if (this.selectedChannel === '关注') { void this.followVm.load(this.hostContext()); }
    }
  }
  @Local vm: RecommendVM = new RecommendVM();

  @Local followVm: FollowFeedVM = new FollowFeedVM();
  @Local hotVm: HotTopicVM = new HotTopicVM();
  @Local inputName: string = '';
  @Local refreshing: boolean = false;

  @Local followRefreshing: boolean = false;
  @Local hotRefreshing: boolean = false;

  @Local selectedChannel: string = '推荐';
  private imageScrollers: Map<number, ListScroller> = new Map();
  @Event onOpenImages: (urls: string[], index: number) => void =
    (_urls: string[], _index: number): void => {};

  private imageScroller(tid: number): ListScroller {
    let scroller: ListScroller | undefined = this.imageScrollers.get(tid);
    if (!scroller) { scroller = new ListScroller(); this.imageScrollers.set(tid, scroller); }
    return scroller;
  }

  private openFeedImages(images: string[], index: number): void {
    this.onOpenImages(images.map((url: string): string => feedImageInfo(url).origin || url), index);
  }

  private channelSwiper: SwiperController = new SwiperController();

  private scrollDirection: number = 0;
  private scrollDistance: number = 0;
  private suppressScrollUntil: number = 0;

  @Local statusBarH: number = 39;

  @Local headerH: number = 0;

  @Local avatarEpoch: number = 0;

  private avatarQueue: ForumAvatarQueue | undefined = undefined;

  aboutToAppear(): void {
    this.onHomeActionsReady(
      (): void => { this.scrollCurrentToTop(); },
      (): void => { this.retryCurrent(); }
    );
    this.onChannelActionsReady((label: string): void => { this.changeChannelByLabel(label); });
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;

    loadBrowseHistory(context).then((items: BrowseItem[]): void => {
      for (const it of items) {
        putForumAvatar(it.forumName, it.forumAvatar);
      }
    });

    const avatarApi: TiebaApi = new TiebaApi();

    void threadBlockStore.load(context);
    this.avatarQueue = new ForumAvatarQueue(
      async (name: string): Promise<string> => {
        const device: TiebaDevice = await DeviceIdentity.ensure(context);
        const session: TiebaSession = authSession.session();
        const res: ThreadListResponse =
          await avatarApi.fetchThreadList(device, session, name, 1, 1);
        hilog.info(0x0, 'TiebaTop', 'AVQ fetch %{public}s: ok=%{public}s', name, String(res.ok));
        if (!res.ok) {
          return '';
        }
        return res.data.forum.avatar;
      });
    this.vm.refreshRecommend(context);

    readStatusBarVp(context).then((vp: number) => {
      this.statusBarH = vp;
      hilog.info(0x0, 'TiebaTop', 'statusBarH_vp=%{public}s', String(vp));
    }).catch(() => {

    });
  }

  private listSpacerH(): number {
    if (this.headerH > 0) {
      return this.headerH;
    }
    const extra: number =
      this.topNavigationRowHeight + 8;
    return this.statusBarH + extra;
  }

  private trackStatusBarScroll(channel: string, offset: number, state: ScrollState): void {
    if (channel !== this.selectedChannel || state === ScrollState.Idle ||
      Date.now() < this.suppressScrollUntil || Math.abs(offset) < 1) {
      return;
    }
    const direction: number = offset > 0 ? 1 : -1;
    if (direction !== this.scrollDirection) {
      this.scrollDirection = direction;
      this.scrollDistance = 0;
    }
    this.scrollDistance += Math.abs(offset);
    if (this.scrollDistance < (direction > 0 ? 24 : 16)) {
      return;
    }
    this.scrollDistance = 0;
    if (this.scrollNavigationHidden !== (direction > 0)) {
      this.suppressScrollUntil = Date.now() + 240;
      this.onScrollNavigationHiddenChange(direction > 0);
    }
  }

  private restoreStatusBar(): void {
    this.scrollDirection = 0;
    this.scrollDistance = 0;
    if (this.scrollNavigationHidden) {
      this.suppressScrollUntil = Date.now() + 240;
      this.onScrollNavigationHiddenChange(false);
    }
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private openForum(name: string): void {
    const target: string = name.trim();
    if (target.length === 0) {
      promptAction.showToast({ message: '请输入吧名', duration: 1600 });
      return;
    }
    this.selectedChannel = '';
    this.onChannelChanged('');

    this.channelSwiper.changeIndex(1, false);
    this.vm.openForum(this.hostContext(), target);
  }

  private selectChannel(channel: FeedChannel): void {
    this.restoreStatusBar();
    this.inputName = '';
    this.selectedChannel = channel.label;
    this.onChannelChanged(channel.label);
    if (channel.label === '关注') {

      if (authSession.snapshot.isLoggedIn() && !this.followVm.loadedOnce &&
        this.followVm.errorText.length === 0) {
        this.followVm.load(this.hostContext());
      }
      return;
    }
    if (channel.label === '热榜') {
      this.hotVm.load();
      return;
    }
    if (channel.label === '推荐') {

      if (this.vm.mode.length > 0) {
        this.vm.backToRecommend(this.hostContext());
      }
    }
  }

  private syncChannelLabel(index: number): void {
    const channel: FeedChannel | undefined = CHANNELS[index];
    if (channel === undefined || channel.label === this.selectedChannel) {
      return;
    }
    this.restoreStatusBar();
    this.inputName = '';
    this.selectedChannel = channel.label;
    this.onChannelChanged(channel.label);
  }

  private changeChannel(channel: FeedChannel): void {
    const index: number = CHANNELS.indexOf(channel);
    if (index >= 0) {
      this.channelSwiper.changeIndex(index, true);
    }
  }

  private changeChannelByLabel(label: string): void {
    const channel: FeedChannel | undefined = CHANNELS.find((item: FeedChannel) => item.label === label);
    if (channel) {
      this.changeChannel(channel);
    }
  }

  private channelIndex(): number {
    const index: number = CHANNELS.findIndex((channel: FeedChannel) =>
      channel.label === this.selectedChannel);
    return index < 0 ? 1 : index;
  }

  @Builder
  private RecommendChannelView() {
    if (this.vm.mode.length === 0 && !authSession.snapshot.isLoggedIn()) {
      this.RecommendLoginView()
    } else if (this.vm.mode.length === 0 && !this.vm.loadedOnce
      && this.vm.errorText.length === 0) {
      this.RecommendPendingView()
    } else if (this.vm.loading && !this.vm.loadedOnce) {
      this.StatusView('正在加载内容…')
    } else if (this.vm.errorText.length > 0 && this.vm.threads.length === 0) {
      this.ErrorView(this.vm.errorText)
    } else if (this.vm.threads.length === 0) {
      this.StatusView('这里还没有内容')
    } else {
      this.RecommendFeed()
    }
  }

  private sawDragSinceIdle: boolean = false;
  private touchDownAtMs: number = 0;
  private lastRecommendDoneMs: number = 0;
  private lastFollowDoneMs: number = 0;
  private lastHotDoneMs: number = 0;

  private isFreshGesture(doneMs: number): boolean {
    const sawDrag: boolean = this.sawDragSinceIdle;
    const downAfterDone: boolean = this.touchDownAtMs > doneMs;
    const pass: boolean = sawDrag && downAfterDone;
    hilog.info(0x0000, 'ForumListView',
      'gesture check sawDrag=%{public}s down>done=%{public}s',
      String(sawDrag), String(downAfterDone));
    return pass;
  }

  private handleRefreshState(state: RefreshStatus): void {
    if (state === RefreshStatus.Drag || state === RefreshStatus.OverDrag) {
      this.sawDragSinceIdle = true;
      hilog.info(0x0000, 'ForumListView', 'refresh state Drag/OverDrag -> sawDrag=true');
    } else if (state === RefreshStatus.Inactive) {
      this.sawDragSinceIdle = false;
    }
  }

  private async handleRefresh(fromGesture: boolean): Promise<void> {
    hilog.info(0x0000, 'ForumListView', 'pull fired refreshing=%{public}s fromGesture=%{public}s',
      String(this.refreshing), String(fromGesture));
    if (this.refreshing) {
      return;
    }
    if (fromGesture && !this.isFreshGesture(this.lastRecommendDoneMs)) {

      hilog.info(0x0000, 'ForumListView', 'refresh swallow (replayed trigger, not fresh gesture)');
      this.refreshing = true;
      setTimeout((): void => {
        this.refreshing = false;
      }, REFRESH_ECHO_MS);
      return;
    }
    this.refreshing = true;
    try {

      const before: number[] = this.vm.threads.map((t: ThreadBrief) => t.tid);
      await this.vm.refresh(this.hostContext());
      if (this.vm.errorText.length === 0 && this.vm.mode.length === 0 && this.vm.threads.length > 0) {
        const after: number[] = this.vm.threads.map((t: ThreadBrief) => t.tid);
        let same: boolean = before.length === after.length;
        for (let i = 0; same && i < after.length; i++) {
          if (!before.includes(after[i])) {
            same = false;
          }
        }
        if (same) {
          hilog.info(0x0000, 'ForumListView', 'refresh done, content unchanged -> toast');
          promptAction.showToast({ message: '推荐内容暂无更新', duration: 1600 });
        }
      }
    } finally {

      this.lastRecommendDoneMs = Date.now();
      this.refreshing = false;
    }
  }

  private async handleFollowRefresh(fromGesture: boolean): Promise<void> {
    if (this.followRefreshing) {
      return;
    }

    if (fromGesture && !this.isFreshGesture(this.lastFollowDoneMs)) {
      hilog.info(0x0000, 'ForumListView', 'follow refresh swallow (replayed trigger, not fresh gesture)');
      this.followRefreshing = true;
      setTimeout((): void => {
        this.followRefreshing = false;
      }, REFRESH_ECHO_MS);
      return;
    }
    this.followRefreshing = true;
    try {
      await this.followVm.load(this.hostContext());
    } finally {

      this.lastFollowDoneMs = Date.now();
      this.followRefreshing = false;
    }
  }

  private async handleHotRefresh(fromGesture: boolean): Promise<void> {
    if (this.hotRefreshing || this.hotVm.loading) {
      return;
    }
    if (fromGesture && !this.isFreshGesture(this.lastHotDoneMs)) {
      this.hotRefreshing = true;
      setTimeout((): void => { this.hotRefreshing = false; }, REFRESH_ECHO_MS);
      return;
    }
    this.hotRefreshing = true;
    try {
      await this.hotVm.load(true);
      if (this.hotVm.errorText.length > 0 && this.hotVm.items.length > 0) {
        promptAction.showToast({ message: this.hotVm.errorText, duration: 2000 });
      }
    } finally {
      this.lastHotDoneMs = Date.now();
      this.hotRefreshing = false;
    }
  }

  private retryCurrent(): void {
    if (this.selectedChannel === '关注') {
      this.handleFollowRefresh(false);
      return;
    }
    if (this.selectedChannel === '热榜') {
      this.handleHotRefresh(false);
      return;
    }
    this.handleRefresh(false);
  }

  private scrollCurrentToTop(): void {
    if (this.selectedChannel === '关注') {
      this.followScroller.scrollToIndex(0, true, ScrollAlign.START);
    } else if (this.selectedChannel === '热榜') {
      this.hotScroller.scrollToIndex(0, true, ScrollAlign.START);
    } else {
      this.recommendScroller.scrollToIndex(0, true, ScrollAlign.START);
    }
  }

  private forumOf(item: ThreadBrief): string {
    return item.sourceForum.length > 0 ? item.sourceForum : this.vm.mode;
  }

  private maybeQueueAvatar(item: ThreadBrief): void {
    if (this.avatarQueue === undefined) {
      return;
    }
    const name: string = this.forumOf(item).trim();
    if (name.length === 0) {
      return;
    }
    const fetched: boolean = isForumAvatarFetched(name);
    if (item.sourceForumAvatar.length > 0 && fetched) {
      return;
    }
    this.avatarQueue.enqueue(name, (url: string): void => {
      if (url.length > 0) {
        item.sourceForumAvatar = url;

        item.avatarStamp++;
        this.avatarEpoch++;
        hilog.info(0x0, 'TiebaTop', 'AVQ backfilled forum=%{public}s', name);
      }
    }, !fetched);
  }

  private openForumPage(name: string): void {
    const target: string = name.trim();
    if (target.length === 0) {
      return;
    }

    NavigationService.openForum({ forumName: target });
  }

  build() {

    Stack({ alignContent: Alignment.TopStart }) {

      Swiper(this.channelSwiper) {
        Column() {
          this.FollowChannelView()
        }
        .width('100%')
        .height('100%')

        Column() {
          this.RecommendChannelView()
        }
        .width('100%')
        .height('100%')

        Column() {
          this.HotChannelView()
        }
        .width('100%')
        .height('100%')
      }
      .indicator(false)
      .loop(false)

      .onAppear(() => {
        const index: number = this.channelIndex();
        if (index >= 0) {
          this.channelSwiper.changeIndex(index, false);
        }
      })

      .disableSwipe(this.selectedChannel.length === 0)

      .onAnimationStart((_index: number, targetIndex: number) => {
        this.syncChannelLabel(targetIndex);
      })
      .onChange((index: number) => {
        this.selectChannel(CHANNELS[index]);
      })
      .width('100%')
      .height('100%')

      this.Header()
    }
    .width('100%')
    .height(LayoutPolicy.matchParent)

    .clip(false)
    .backgroundColor(AppTheme.BG)
  }

  @Builder
  Header() {

    Column({ space: 8 }) {

      Blank().height(this.topNavigationRowHeight)

      if (this.vm.mode.length > 0 && this.selectedChannel.length === 0) {
        Row({ space: 6 }) {
          Text(`正在浏览 ${this.vm.mode} 吧`)
            .fontSize(12)
            .fontColor(AppTheme.ACCENT_DARK)
          Text('返回推荐')
            .fontSize(12)
            .fontColor(AppTheme.LINK_HINT)
            .onClick(() => {
              this.vm.backToRecommend(this.hostContext());
            })
          Blank()
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 6 })
      }
    }
    .width('100%')
    .padding({ top: this.statusBarH + 8, left: 14, right: 14 })
    .scale({ x: this.topNavigationHidden ? 0.04 : 1, y: this.topNavigationHidden ? 0.04 : 1,
      centerX: '50%', centerY: 0 })
    .translate({ y: this.topNavigationHidden ? -this.statusBarH - 8 : 0 })
    .opacity(this.topNavigationHidden ? 0 : 1)
    .animation({ duration: this.topNavigationHidden ? 300 : 440,
      curve: this.topNavigationHidden ? Curve.EaseIn : curves.springMotion(0.38, 0.64) })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.headerH = Number(newArea.height);
      hilog.info(0x0, 'TiebaTop', 'headerH=%{public}s gY=%{public}s gX=%{public}s',
        String(this.headerH), String(Number(newArea.globalPosition.y)),
        String(Number(newArea.globalPosition.x)));
    })
  }

  private threadsOf(channel: string): ThreadBrief[] {
    const items: ThreadBrief[] = channel === '关注' ? this.followVm.threads : this.vm.threads;
    return visibleThreads(items, threadBlockStore.rules());
  }

  @Builder
  FeedList(channel: string) {
    List({ space: 8, scroller: channel === '关注' ? this.followScroller : this.recommendScroller }) {

      ListItem() {
        Row()
          .width('100%')
          .height(this.listSpacerH())
      }

      ForEach(this.threadsOf(channel), (item: ThreadBrief) => {
        ListItem() {
          this.ThreadCard(item)
        }
        .padding({ left: 8, right: 8 })

        .onAppear(() => {
          this.maybeQueueAvatar(item);
        })
      }, (item: ThreadBrief) => {

        const epoch: number = this.avatarEpoch;

        return `${item.tid}-${item.avatarStamp + epoch * 0}`;
      })

      ListItem() {
        this.FeedFooter(channel)
      }
    }
    .width('100%')
    .scrollBar(BarState.Off)

    .onReachEnd(() => {
      this.loadMoreFor(channel);
    })

    .onScrollIndex((_first: number, last: number) => {
      if (last >= this.threadsOf(channel).length + 1 - PREFETCH_ITEMS) {
        this.loadMoreFor(channel);
      }
    })
    .onDidScroll((offset: number, state: ScrollState) => {
      this.trackStatusBarScroll(channel, offset, state);
    })
    .onReachStart(() => {
      if (channel === this.selectedChannel) {
        this.restoreStatusBar();
      }
    })

  }

  @Builder
  FeedFooter(channel: string) {
    Column() {
      if (this.isLoadingMoreOf(channel)) {
        Row({ space: 8 }) {
          RefreshSpinner({ diameter: 18 })
          Text('正在加载更多…')
            .fontSize(12)
            .fontColor(AppTheme.TEXT_SUB)
        }
      } else if (this.loadMoreErrorOf(channel).length > 0) {
        Text('加载更多失败，点击重试')
          .fontSize(12)
          .fontColor(AppTheme.ACCENT_DARK)
          .onClick(() => {
            this.retryLoadMore(channel);
          })
      } else if (this.hasMoreOf(channel)) {

        Text('上滑加载更多')
          .fontSize(12)
          .fontColor(AppTheme.TEXT_MUTED)
      } else {
        Text('没有更多了')
          .fontSize(12)
          .fontColor(AppTheme.TEXT_MUTED)
      }
    }
    .width('100%')
    .height(AppTheme.BAR_TOTAL_H)
    .justifyContent(FlexAlign.Center)
  }

  private isLoadingMoreOf(channel: string): boolean {
    return channel === '关注' ? this.followVm.loadingMore : this.vm.loadingMore;
  }

  private hasMoreOf(channel: string): boolean {
    return channel === '关注' ? this.followVm.hasMore : this.vm.hasMore;
  }

  private loadMoreErrorOf(channel: string): string {
    return channel === '关注' ? this.followVm.loadMoreError : this.vm.loadMoreError;
  }

  private loadMoreFor(channel: string, retry: boolean = false): void {
    if (channel === '关注') {
      this.followVm.loadMore(this.hostContext(), retry);
      return;
    }
    this.vm.loadMore(this.hostContext(), retry);
  }

  private retryLoadMore(channel: string): void {
    this.loadMoreFor(channel, true);
  }

  @Builder
  FeedRefreshHeader() {
    Column()
      .width('100%')
      .height(1)
  }

  @Builder
  FeedRefreshOverlay(channel: string) {
    if (this.refreshingOf(channel)) {
      Row() {
        RefreshSpinner()
      }
      .width('100%')

      .height(REFRESH_OFFSET_VP)
      .justifyContent(FlexAlign.Center)
      .hitTestBehavior(HitTestMode.None)
      .margin({ top: this.listSpacerH() })
    }
  }

  private refreshingOf(channel: string): boolean {
    if (channel === '关注') {
      return this.followRefreshing;
    }
    return channel === '热榜' ? this.hotRefreshing : this.refreshing;
  }

  @Builder
  RecommendFeed() {
    Stack({ alignContent: Alignment.TopStart }) {
      Refresh({
        refreshing: this.refreshing,
        builder: (): void => {
          this.FeedRefreshHeader();
        }
      }) {
        this.FeedList('推荐')
      }
      .onRefreshing(() => {
        this.handleRefresh(true);
      })

      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.touchDownAtMs = Date.now();
        }
      })

      .onStateChange((state: RefreshStatus) => {
        this.handleRefreshState(state);
      })

      .refreshOffset(REFRESH_OFFSET_VP)
      this.FeedRefreshOverlay('推荐')
    }
    .layoutWeight(1)
  }

  @Builder
  RecommendPendingView() {
    Column({ space: 12 }) {
      RefreshSpinner()
      Text('正在加载推荐内容…')
        .fontSize(14)
        .fontColor(AppTheme.TEXT_SUB)
    }
    .width('100%')

    .padding({ top: this.listSpacerH() - this.statusBarH })
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .onAppear(() => {
      this.vm.refreshRecommend(this.hostContext());
    })
  }

  @Builder
  RecommendLoginView() {
    Column() {
      LoginEmptyView({
        icon: $r('app.media.icon_home'),
        title: '登录后查看推荐内容',
        subtitle: '推荐流来自贴吧的个性化推荐，需要登录后使用',
        onLogin: (): void => {
          router.pushUrl({ url: 'pages/Login' });
        }
      })
    }
    .width('100%')
    .padding({ top: this.listSpacerH() - this.statusBarH })
    .layoutWeight(1)
  }

  @Builder
  FollowFeed() {
    Stack({ alignContent: Alignment.TopStart }) {
      Refresh({
        refreshing: this.followRefreshing,
        builder: (): void => {
          this.FeedRefreshHeader();
        }
      }) {
        this.FeedList('关注')
      }
      .onRefreshing(() => {
        this.handleFollowRefresh(true);
      })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.touchDownAtMs = Date.now();
        }
      })

      .onStateChange((state: RefreshStatus) => {
        this.handleRefreshState(state);
      })
      .refreshOffset(REFRESH_OFFSET_VP)
      this.FeedRefreshOverlay('关注')
    }
    .layoutWeight(1)
  }

  @Builder
  FollowChannelView() {
    if (!authSession.snapshot.isLoggedIn()) {
      this.FollowLoginView()
    } else if (!this.followVm.loadedOnce && this.followVm.errorText.length === 0) {
      this.FollowPendingView()
    } else if (this.followVm.errorText.length > 0 && this.followVm.threads.length === 0) {
      this.ErrorView(this.followVm.errorText)
    } else if (this.followVm.threads.length === 0) {
      this.FollowEmptyView()
    } else {
      this.FollowFeed()
    }
  }

  @Builder
  FollowPendingView() {
    Column({ space: 12 }) {
      RefreshSpinner()
      Text('正在加载关注内容…')
        .fontSize(14)
        .fontColor(AppTheme.TEXT_SUB)
    }
    .width('100%')

    .padding({ top: this.listSpacerH() - this.statusBarH })
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .onAppear(() => {
      if (this.selectedChannel === '关注') {
        this.followVm.load(this.hostContext());
      }
    })
  }

  @Builder
  FollowLoginView() {
    Column() {
      LoginEmptyView({
        icon: $r('app.media.icon_follow'),
        title: '登录后查看关注内容',
        subtitle: '这里只显示你关注的吧的帖子',
        onLogin: (): void => {
          router.pushUrl({ url: 'pages/Login' });
        }
      })
    }
    .width('100%')
    .padding({ top: this.listSpacerH() - this.statusBarH })
    .layoutWeight(1)
  }

  @Builder
  FollowEmptyView() {
    Column({ space: 8 }) {
      Text(this.followVm.followedCount === 0 ? '还没有关注的吧' : '关注的吧暂时没有新内容')
        .fontSize(16)
        .fontColor(AppTheme.TEXT_MAIN)
      if (this.followVm.followedCount === 0) {
        Text('在贴吧客户端里关注几个吧，这里就会显示它们的帖子')
          .fontSize(13)
          .fontColor(AppTheme.TEXT_SUB)
          .textAlign(TextAlign.Center)
          .padding({ left: 32, right: 32 })
      }
    }
    .width('100%')

    .padding({ top: this.listSpacerH() - this.statusBarH })
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  HotChannelView() {
    if (this.hotVm.items.length > 0) {
      this.HotFeed()
    } else if (this.hotVm.errorText.length > 0) {
      Column({ space: 12 }) {
        Text(this.hotVm.errorText)
          .fontSize(14)
          .fontColor(AppTheme.TEXT_SUB)
          .textAlign(TextAlign.Center)
        Text('点击重试')
          .fontSize(14)
          .fontColor(AppTheme.ACCENT_DARK)
          .onClick(() => { this.hotVm.load(true); })
      }
      .width('100%')
      .padding({ top: this.listSpacerH() - this.statusBarH, left: 28, right: 28 })
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (this.hotVm.loadedOnce) {
      this.StatusView('暂时没有热议话题')
    } else {
      Column({ space: 12 }) {
        RefreshSpinner()
        Text('正在加载热榜…').fontSize(14).fontColor(AppTheme.TEXT_SUB)
      }
      .width('100%')
      .padding({ top: this.listSpacerH() - this.statusBarH })
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .onAppear(() => {
        if (this.selectedChannel === '热榜') {
          this.hotVm.load();
        }
      })
    }
  }

  @Builder
  HotFeed() {
    Stack({ alignContent: Alignment.TopStart }) {
      Refresh({
        refreshing: this.hotRefreshing,
        builder: (): void => { this.FeedRefreshHeader(); }
      }) {
        this.HotTopicList()
      }
      .onRefreshing(() => { this.handleHotRefresh(true); })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.touchDownAtMs = Date.now();
        }
      })
      .onStateChange((state: RefreshStatus) => { this.handleRefreshState(state); })
      .refreshOffset(REFRESH_OFFSET_VP)
      this.FeedRefreshOverlay('热榜')
    }
    .layoutWeight(1)
  }

  @Builder
  HotTopicList() {
    List({ space: 10, scroller: this.hotScroller }) {
      ListItem() {
        Column().height(this.listSpacerH())
      }
      ListItem() {
        Row() {
          Text('热议话题')
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.TEXT_MAIN)
            .layoutWeight(1)
          Text(`共 ${this.hotVm.items.length} 条`)
            .fontSize(12)
            .fontColor(AppTheme.TEXT_MUTED)
        }
        .width('100%')
        .padding({ left: 4, right: 4, top: 2, bottom: 4 })
      }
      ForEach(this.hotVm.items, (item: HotTopicItem, index: number) => {
        ListItem() {
          this.HotTopicCard(item, index)
        }
      }, (item: HotTopicItem) => `${item.id}`)
      ListItem() {
        Text('已显示全部话题')
          .fontSize(12)
          .fontColor(AppTheme.TEXT_MUTED)
          .width('100%')
          .height(AppTheme.BAR_TOTAL_H)
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 14, right: 14 })
    .scrollBar(BarState.Off)
    .onDidScroll((offset: number, state: ScrollState) => {
      this.trackStatusBarScroll('热榜', offset, state);
    })
    .onReachStart(() => {
      if (this.selectedChannel === '热榜') {
        this.restoreStatusBar();
      }
    })
  }

  @Builder
  HotTopicCard(item: HotTopicItem, index: number) {
    Row({ space: 12 }) {
      Text(`${index + 1}`)
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor(index < 3 ? AppTheme.ACCENT : AppTheme.TEXT_MUTED)
        .width(28)
        .textAlign(TextAlign.Center)
      Column({ space: 8 }) {
        Text(item.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_MAIN)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(hotDiscussLabel(item.discussCount))
          .fontSize(12)
          .fontColor(AppTheme.TEXT_SUB)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (item.imageUrl.length > 0) {
        Image(item.imageUrl)
          .width(72)
          .height(62)
          .borderRadius(9)
          .objectFit(ImageFit.Cover)
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 13, bottom: 13 })
    .borderRadius(AppTheme.CARD_RADIUS)
    .backgroundColor(AppTheme.CARD)
    .onClick(() => {
      NavigationService.openHotTopic({ topicId: item.id, topicName: item.name });
    })
  }

  @Builder
  ThreadCard(item: ThreadBrief) {
    ThreadPreviewCard({
      authorName: item.authorName, authorAvatar: item.authorAvatar,
      forumName: this.forumOf(item), forumAvatar: item.sourceForumAvatar,
      postedTime: formatPostTime(item.postedMs, Date.now()),
      title: item.title, summary: item.summary,
      images: item.images.length > 0 ? item.images : (item.coverImage.length > 0 ? [item.coverImage] : []),
      isTop: this.vm.mode.length > 0 && item.isTop,
      isGood: this.vm.mode.length > 0 && item.isGood,
      agreeCount: item.agreeCount, replyCount: item.replyCount,
      shareCount: item.shareCount,
      menu: buildThreadCardMenu(this.getUIContext(), item), imageScroller: this.imageScroller(item.tid),
      onOpenAuthor: (): void => {
        openUserByIdentity(item.authorId, item.authorAvatar, item.authorName, this.getUIContext());
      },
      onOpenForum: (): void => { this.openForumPage(this.forumOf(item)); },
      onOpenThread: (): void => {

        NavigationService.openThreadDetail({ tid: item.tid, replyCount: item.replyCount,
          forumName: this.forumOf(item) });
      },
      onOpenImage: (index: number): void => {
        this.openFeedImages(item.images.length > 0 ? item.images : [item.coverImage], index);
      }
    })
  }

  @Builder
  StatusView(text: string) {
    Column() {
      Text(text).fontSize(14).fontColor(AppTheme.TEXT_SUB)
    }
    .width('100%')

    .padding({ top: this.listSpacerH() - this.statusBarH })
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  ErrorView(text: string) {
    Column({ space: 10 }) {
      Text('加载失败')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_MAIN)
      Text(text)
        .fontSize(13)
        .fontColor(AppTheme.TEXT_SUB)
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
      Button('重新加载')
        .fontSize(14)
        .fontColor(Color.White)
        .height(38)
        .borderRadius(19)
        .backgroundColor(AppTheme.ACCENT)
        .onClick(() => {
          this.retryCurrent();
        })
    }
    .width('100%')

    .padding({ top: this.listSpacerH() - this.statusBarH })
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }
}
