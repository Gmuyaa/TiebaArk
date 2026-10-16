import { RefreshSpinner, FORUM_REFRESH_OFFSET } from '../components/RefreshSpinner';
import { ForumIdentity } from '../components/ForumIdentity';
import { ForumAvatarImage, forumAvatarRadius } from '../components/ForumAvatarImage';

import { openUserByIdentity } from '../navigation/UserNavigation';
import { common } from '@kit.AbilityKit';
import { DirectoryKind } from '../model/PageDirectory';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction, curves } from '@kit.ArkUI';
import { effectKit } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { ForumTab, ThreadBrief } from '../model/ThreadList';
import { feedImageInfo, formatPostTime } from '../model/HomeFeedPresentation';
import { ThreadListVM } from '../viewmodel/ThreadListVM';
import { AppTheme } from '../theme/Theme';
import { ImageViewer } from '../components/ImageViewer';
import { ThreadPreviewCard } from '../components/ThreadPreviewCard';
import { buildThreadCardMenu } from '../components/ThreadCardMenu';
import { visibleThreads } from '../model/ThreadBlock';
import { threadBlockStore } from '../utils/ThreadBlockStore';
import {
  FORUM_HERO_PATTERN_COLOR_FILTER, FORUM_HERO_PATTERN_OPACITY, FORUM_HERO_HEADLINE_SCRIM_BOTTOM,
  FORUM_HERO_HEADLINE_SCRIM_TOP, ForumHeroPalette, forumHeroPalette
} from '../common/appearance/ForumHeroStyle';
import { GlassBackButton } from '../components/GlassBackButton';
import { GlassCircleButton } from '../components/GlassCircleButton';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { ForumPageParams, NavigationService, SearchResultParams } from '../navigation/AppNavigation';
import { forumDefaultTabStore } from '../common/appearance/ForumDefaultTabStore';
import { ForumDefaultTab } from '../model/ForumDefaultTab';

class ForumPageState {
  vm: ThreadListVM = new ThreadListVM();
  scrollOffset: number = 0;
  defaultTab: ForumDefaultTab = ForumDefaultTab.HOT;
}

const FORUM_PAGE_STATES: Map<string, ForumPageState> = new Map<string, ForumPageState>();
const FORUM_HERO_HEIGHT: number = 160;

const FORUM_HERO_BACKGROUND_HEIGHT: number = 280;

const FORUM_TOOLBAR_HEIGHT: number = 56;
const FORUM_TAB_HEIGHT: number = 46;
const FORUM_TAB_HANDLE_HEIGHT: number = 12;
let forumTintSerial: number = 0;

@ComponentV2
export struct ForumPage {
  @Local vm: ThreadListVM = new ThreadListVM();

  @Param routeParams: ForumPageParams | undefined = undefined;

  @Local forumName: string = '';
  @Local refreshing: boolean = false;
  @Local pullDistance: number = 0;
  private pullEligible: boolean = false;
  @Local headerRefreshRevision: number = 0;
  @Local introductionVisible: boolean = false;
  @Local moreShown: boolean = false;
  @Local restorePending: boolean = false;
  @Local pinnedExpanded: boolean = false;

  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;

  @Local tabsNavProgress: number = 0;
  @Local sampledHeroColor: string = '';
  @Local contentHeight: number = 500;
  @Local contentShift: number = 0;
  @Local contentOpacity: number = 1;
  private colorImage: string = '';
  private tintId: string = `forum-head-color-${++forumTintSerial}`;
  private active: boolean = true;
  private tabAnimation: number = 0;

  aboutToDisappear(): void { this.active = false; ++this.tabAnimation; }

  private async sampleHeroColor(): Promise<void> {
    const source: string = this.vm.heroHeadline;
    if (source.length === 0 || source === this.colorImage) { return; }
    this.colorImage = source;
    let pixels: image.PixelMap | undefined = undefined;
    try {
      pixels = await this.getUIContext().getComponentSnapshot().get(this.tintId, { scale: 0.15, waitUntilRenderFinished: true });
      const info = await pixels.getImageInfo();

      await pixels.crop({ x: 0, y: 0, size: { width: info.size.width,
        height: Math.max(1, Math.round(info.size.height * (this.statusBarH + FORUM_TOOLBAR_HEIGHT)
          / (FORUM_HERO_BACKGROUND_HEIGHT + this.statusBarH))) } });
      const picker = await effectKit.createColorPicker(pixels);
      const color = await picker.getMainColor();
      if (!this.active || source !== this.vm.heroHeadline || color.alpha <= 0) { return; }

      const channel = (value: number): string => Math.round(Math.max(0, Math.min(255, value)) * 0.65)
        .toString(16).padStart(2, '0');
      this.sampledHeroColor = `#${channel(color.red)}${channel(color.green)}${channel(color.blue)}`;
    } catch (err) {  }
    finally { if (pixels !== undefined) { try { await pixels.release(); } catch (err) {  } } }
  }
  private scroller: ListScroller = new ListScroller();

  private tabsScroller: Scroller = new Scroller();

  private imageScrollers: Map<number, ListScroller> = new Map<number, ListScroller>();

  @Local viewerUrls: string[] = [];
  @Local viewerIndex: number = 0;

  private pageState: ForumPageState | undefined = undefined;

  aboutToAppear(): void {
    this.active = true;

    let name: string = '';
    if (this.routeParams !== undefined && this.routeParams.forumName !== undefined) {
      name = this.routeParams.forumName.trim();
    }
    hilog.info(0x0, 'ForumPageNav', 'aboutToAppear forumName=%{public}s', name);
    this.forumName = name;
    readStatusBarVp(this.hostContext()).then((vp: number) => {
      this.statusBarH = vp;
    }).catch(() => {

    });

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
    this.restorePending = pageState.scrollOffset > 0;

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

  private openForumMember(): void {
    if (this.vm.forum.id <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '吧成员尚未加载，请稍后重试' });
      return;
    }
    this.saveScrollPosition();
    NavigationService.openForumMember({ forumId: this.vm.forum.id, forumName: this.titleText() });
  }

  private titleText(): string {
    if (this.forumName.length > 0) {
      return this.forumName;
    }
    return this.vm.forum.name.length > 0 ? this.vm.forum.name : '吧';
  }

  private openForumSearch(): void {
    const name: string = this.forumName.trim();
    if (name.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '吧名尚未加载，请稍后重试' });
      return;
    }
    this.saveScrollPosition();
    NavigationService.openSearchResult({ forumName: name } as SearchResultParams);
  }

  private async handleRefresh(scrollToContentTop: boolean = false): Promise<void> {
    if (this.refreshing || this.vm.loading || this.vm.isLoadingMore || this.vm.switchingTab) {
      if (!this.refreshing) { this.settlePullDistance(0); }
      return;
    }
    this.refreshing = true;
    this.settlePullDistance(FORUM_REFRESH_OFFSET);
    try {
      await this.vm.refresh(this.hostContext(), this.forumName, this.vm.loadedOnce);
      if (this.vm.errorText.length === 0) {
        if (scrollToContentTop) {
          setTimeout(() => {
            if (!this.active) { return; }
            const top: number = this.heroHeight() - FORUM_TOOLBAR_HEIGHT;
            this.scroller.scrollTo({ xOffset: 0, yOffset: top, animation: true });
            if (this.pageState !== undefined) { this.pageState.scrollOffset = top; }
          }, 16);
        }
      } else {
        promptAction.showToast({ message: this.vm.errorText, duration: 1800 });
      }
    } finally {

      this.refreshing = false;
      if (this.active) { this.settlePullDistance(0); }
    }
  }

  private dampedPullDistance(offset: number): number {
    const raw: number = Math.max(0, offset * 0.4);
    if (raw <= FORUM_REFRESH_OFFSET) { return raw; }
    const resistance: number = 64;
    return FORUM_REFRESH_OFFSET + resistance * Math.log(1 + (raw - FORUM_REFRESH_OFFSET) / resistance);
  }

  private settlePullDistance(distance: number): void {
    this.getUIContext().animateTo({ duration: 420, curve: curves.springMotion(0.38, 0.8) }, () => {
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

  private syncTabsSticky(): void {
    const distance: number = this.heroHeight() - FORUM_TOOLBAR_HEIGHT;
    const offset: number = this.scroller.currentOffset().yOffset;
    const progress: number = Math.max(0, Math.min(1, offset / distance));
    if (Math.abs(progress - this.tabsNavProgress) > 0.001) { this.tabsNavProgress = progress; }
  }

  private goBack(): void {
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

  private openImages(images: string[], index: number): void {
    this.viewerUrls = images.map((url: string): string => feedImageInfo(url).origin || url);
    this.viewerIndex = index;
  }

  private pinnedThreads(): ThreadBrief[] {
    return visibleThreads(this.vm.threads, threadBlockStore.rules(), false)
      .filter((item: ThreadBrief) => item.isTop);
  }

  private regularThreads(): ThreadBrief[] {
    return visibleThreads(this.vm.threads, threadBlockStore.rules(), false)
      .filter((item: ThreadBrief) => !item.isTop);
  }

  private visiblePinnedThreads(items: ThreadBrief[]): ThreadBrief[] {
    return this.pinnedExpanded || items.length <= 3 ? items : items.slice(0, 3);
  }

  build() {

    HdsNavDestination() {

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

        if (this.forumName.length > 0 && this.vm.loadedOnce && this.viewerUrls.length === 0) {
          GlassCircleButton({ symbol: $r('sys.symbol.arrow_clockwise'), diameter: 48, iconSize: 24,
            onTap: (): void => {
              if (!this.refreshing && !this.vm.loading && !this.vm.isLoadingMore && !this.vm.switchingTab) {
                void this.handleRefresh(true);
              }
            } })
          .align(Alignment.BottomEnd).margin({ right: 16, bottom: 32 + 48 })
          .opacity(this.refreshing || this.vm.loading || this.vm.switchingTab ? 0.6 : 1)
          .accessibilityText('刷新当前分类')
        }

        if (this.viewerUrls.length > 0) {
          ImageViewer({ imageUrls: this.viewerUrls, initialIndex: this.viewerIndex,
            onClose: (): void => { this.viewerUrls = []; this.viewerIndex = 0; } })
            .zIndex(100)
        }
      }
      .width('100%')
      .height(LayoutPolicy.matchParent)
    }

    .hideTitleBar(true)
  }

  @Builder
  TopBar() {
    Row({ space: 10 }) {

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
  ForumHero() {
    Stack({ alignContent: Alignment.TopStart }) {

      Column()
        .width('100%')
        .height(FORUM_HERO_BACKGROUND_HEIGHT + this.statusBarH)
        .linearGradient({ angle: 180, colors: this.heroGradientColors() })

      if (this.vm.heroHeadline.length > 0) {
        Image(this.vm.heroHeadline)
          .id(this.tintId)
          .onComplete(() => { setTimeout(() => { if (this.active) { void this.sampleHeroColor(); } }, 120); })
          .width('100%')
          .height(FORUM_HERO_BACKGROUND_HEIGHT + this.statusBarH)
          .objectFit(ImageFit.Cover)
          .interpolation(ImageInterpolation.High)
        Column()
          .width('100%')
          .height(FORUM_HERO_BACKGROUND_HEIGHT + this.statusBarH)
          .linearGradient({
            angle: 180,
            colors: [
              [`rgba(0,0,0,${FORUM_HERO_HEADLINE_SCRIM_TOP})`, 0.0],
              [`rgba(0,0,0,${FORUM_HERO_HEADLINE_SCRIM_BOTTOM})`, 1.0]
            ]
          })
      }

      if (this.vm.heroHeadline.length === 0 && this.vm.forum.heroImage.length > 0) {
        Image(this.vm.forum.heroImage)
          .width('100%')
          .height(FORUM_HERO_BACKGROUND_HEIGHT + this.statusBarH)
          .objectFit(ImageFit.Cover)
          .interpolation(ImageInterpolation.High)
          .colorFilter(FORUM_HERO_PATTERN_COLOR_FILTER)
          .opacity(FORUM_HERO_PATTERN_OPACITY)
      }

      Column().width('100%').height(24)
        .position({ x: 0, y: this.heroHeight() + this.statusBarH - 24 })
        .linearGradient({ angle: 180, colors: [
          [Color.Transparent, 0], [AppTheme.FORUM_TAB_BG, 1] ] })
        .hitTestBehavior(HitTestMode.None)
      Column().width('100%').height(this.statusBarH + FORUM_TOOLBAR_HEIGHT)
        .backgroundColor(this.sampledHeroColor || this.heroPalette().bottomColor)
        .opacity(this.tabsNavProgress).hitTestBehavior(HitTestMode.None)

      Column() {
        Row({ space: 10 }) {

          GlassBackButton({
            onTap: (): void => {
              this.goBack();
            }
          })
          Row({ space: 8 }) {

            ForumAvatarImage({ url: this.vm.forum.avatar, forumName: this.titleText(),
              avatarSize: 28, radius: forumAvatarRadius(28), onHero: true })
            Text(this.titleText().endsWith('吧') ? this.titleText() : `${this.titleText()}吧`)
              .fontSize(17).fontWeight(FontWeight.Medium).fontColor(Color.White)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          }
          .layoutWeight(1).opacity(this.tabsNavProgress)
          .hitTestBehavior(this.tabsNavProgress > 0 ? HitTestMode.Default : HitTestMode.None)
          .onClick(() => { this.openForumDirectory('forum'); })

          GlassCircleButton({ symbol: $r('sys.symbol.magnifyingglass'), iconSize: 22, iconOffsetX: -3,
            onTap: (): void => { this.openForumSearch(); } })

          GlassCircleButton({ symbol: $r('sys.symbol.more'), iconSize: 24, iconOffsetX: -4,
            onTap: (): void => { this.moreShown = !this.moreShown; } })
            .bindMenu(this.moreShown, [{ value: '吧资料', action: (): void => {
              this.moreShown = false;
              this.openForumDirectory('forum');
            } }, { value: '吧成员', action: (): void => {
              this.moreShown = false;
              this.openForumMember();
            } }], { onDisappear: (): void => { this.moreShown = false; } })
        }
        .width('100%')
        .height(56)
        .padding({ left: 4, right: 16 })
        .alignItems(VerticalAlign.Center)

        ForumIdentity({ forumId: this.vm.forum.id, forumName: this.titleText(), avatar: this.vm.forum.avatar,
          refreshRevision: this.headerRefreshRevision, memberCount: this.vm.forum.memberCount,
          threadCount: this.vm.forum.threadCount,
          onOpenInformation: (): void => { this.openForumDirectory('forum'); },
          onIntroductionVisible: (visible: boolean): void => { this.introductionVisible = visible; this.syncTabsSticky(); } })
          .padding({ left: 16, right: 16 })
          .margin({ top: 12 })

      }
      .width('100%')
      .height('100%')

      .padding({ top: this.statusBarH })
    }
    .width('100%')
    .height(this.heroHeight() + this.statusBarH)
    .clip(true)

    .backgroundColor(this.heroPalette().bottomColor)
  }

  private heroHeight(): number { return FORUM_HERO_HEIGHT + (this.introductionVisible ? 54 : 0); }

  private heroPalette(): ForumHeroPalette {
    return forumHeroPalette(this.vm.forum.heroColor);
  }

  private heroGradientColors(): Array<[ResourceColor, number]> {
    const palette: ForumHeroPalette = this.heroPalette();
    return [[palette.topColor, 0.0], [palette.bottomColor, 1.0]];
  }

  @Builder
  ForumTabs() {
    Column() {

      Column() {
        Row() {
          Row().width(36).height(4).borderRadius(2).backgroundColor(AppTheme.TEXT_MUTED).opacity(0.25)
        }
        .width('100%').height(FORUM_TAB_HANDLE_HEIGHT * (1 - this.tabsNavProgress))
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
        .opacity(1 - this.tabsNavProgress).clip(true)
        Scroll(this.tabsScroller) {
          Row({ space: 26 }) {
            if (this.vm.tabs.length === 0) {
              Text('帖子').fontSize(16).fontWeight(FontWeight.Bold).fontColor(AppTheme.TEXT_MAIN)
            } else {
              ForEach(this.vm.tabs, (tab: ForumTab, index: number) => {
                Column({ space: 5 }) {
                  Text(tab.name).fontSize(16)
                    .fontWeight(tab.id === this.vm.selectedTabId ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(tab.id === this.vm.selectedTabId ? AppTheme.TEXT_MAIN : AppTheme.TAB_UNDERLINE_TEXT)
                  Row().width(tab.id === this.vm.selectedTabId ? 20 : 0).height(3)
                    .borderRadius(2).backgroundColor(AppTheme.ACCENT)
                    .animation({ duration: 220, curve: Curve.EaseOut })
                }
                .height(FORUM_TAB_HEIGHT).justifyContent(FlexAlign.Center)
                .onClick(() => { this.selectForumTab(tab, index); })
              }, (tab: ForumTab) => `${tab.id}`)
            }
          }
          .padding({ left: 20, right: 20 }).height('100%').alignItems(VerticalAlign.Center)
        }
        .width('100%').height(FORUM_TAB_HEIGHT).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
      .width('100%').backgroundColor(AppTheme.FORUM_TAB_BG)
      .borderRadius({ topLeft: 24 * (1 - this.tabsNavProgress), topRight: 24 * (1 - this.tabsNavProgress) })
      .clip(true)
    }
    .width('100%')
    .height(FORUM_TAB_HEIGHT + FORUM_TAB_HANDLE_HEIGHT * (1 - this.tabsNavProgress))
  }

  private async selectForumTab(tab: ForumTab, index: number): Promise<void> {
    if (this.vm.loading || this.vm.isLoadingMore || this.vm.switchingTab || tab.id === this.vm.selectedTabId) {
      return;
    }
    const previous: number = this.vm.tabs.findIndex((value: ForumTab) => value.id === this.vm.selectedTabId);
    const direction: number = index >= previous ? 1 : -1;
    const revision: number = ++this.tabAnimation;
    const offset: number = Math.min(this.scroller.currentOffset().yOffset, this.heroHeight() - FORUM_TOOLBAR_HEIGHT);
    this.getUIContext().animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
      this.contentShift = -24 * direction; this.contentOpacity = 0.4;
    });
    const switching: Promise<boolean> = this.vm.switchTab(this.hostContext(), tab.id);
    if (this.pageState !== undefined) {
      this.pageState.scrollOffset = 0;
    }
    const success: boolean = await switching;
    if (!this.active || revision !== this.tabAnimation) { return; }
    this.contentShift = 24 * direction; this.contentOpacity = 0.4;
    setTimeout(() => {
      if (!this.active || revision !== this.tabAnimation) { return; }
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.contentShift = 0; this.contentOpacity = 1;
      });
    }, 16);
    if (success) {
      this.scroller.scrollTo({ xOffset: 0, yOffset: offset, animation: false });
      this.tabsScroller.scrollToIndex(index, true, ScrollAlign.CENTER);
    } else if (this.vm.errorText.length > 0) {
      promptAction.showToast({ message: this.vm.errorText, duration: 1800 });
    }
  }

  private swipeForumTab(offset: number): void {
    const current: number = this.vm.tabs.findIndex((tab: ForumTab) => tab.id === this.vm.selectedTabId);
    const next: number = current + (offset < 0 ? 1 : -1);
    if (current < 0 || next < 0 || next >= this.vm.tabs.length) { return; }
    void this.selectForumTab(this.vm.tabs[next], next);
  }

  @Builder
  ThreadList() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.ForumHero()
      Column() {
        Row().height(this.statusBarH + FORUM_TOOLBAR_HEIGHT).width('100%').hitTestBehavior(HitTestMode.None)
        Column() {
          List({ space: 0, scroller: this.scroller }) {
            ListItem() {
              Row().width('100%').height(this.heroHeight() - FORUM_TOOLBAR_HEIGHT)
            }
            .hitTestBehavior(HitTestMode.None)

            ListItemGroup({ header: this.ForumTabs() }) {

              ListItem() {
                Row() {
                  if (this.refreshing || this.pullDistance > 0) { RefreshSpinner() }
                }
                .width('100%').height(this.pullDistance)
                .justifyContent(FlexAlign.Center).clip(true)
              }
              if (this.vm.switchingTab) {
                ListItem() {
                  Column({ space: 12 }) {
                    RefreshSpinner()
                    Text('正在加载分类…').fontSize(14).fontColor(AppTheme.TEXT_SUB)
                  }
                  .width('100%').height(Math.max(240, this.contentHeight - FORUM_TAB_HEIGHT - FORUM_TAB_HANDLE_HEIGHT))
                  .justifyContent(FlexAlign.Center).backgroundColor(AppTheme.FORUM_TAB_BG)
                }
              } else if (this.vm.loading && !this.vm.loadedOnce) {
                ListItem() {
                  Column() { this.StatusView('正在加载…') }
                    .width('100%').height(Math.max(240, this.contentHeight - FORUM_TAB_HEIGHT - FORUM_TAB_HANDLE_HEIGHT))
                }
              } else if (this.vm.errorText.length > 0 && this.vm.threads.length === 0) {
                ListItem() {
                  Column() { this.ErrorView() }
                    .width('100%').height(Math.max(240, this.contentHeight - FORUM_TAB_HEIGHT - FORUM_TAB_HANDLE_HEIGHT))
                }
              } else if (this.vm.threads.length === 0) {
                ListItem() {
                  Column() { this.StatusView('这个吧还没有帖子') }
                    .width('100%').height(Math.max(240, this.contentHeight - FORUM_TAB_HEIGHT - FORUM_TAB_HANDLE_HEIGHT))
                }
              } else {
                if (this.pinnedThreads().length > 0) {
                  ListItem() {
                    this.PinnedSection()
                  }
                  .padding({ left: 8, right: 8, top: 8 })
                  .translate({ x: this.contentShift }).opacity(this.contentOpacity)
                }

                ForEach(this.regularThreads(), (item: ThreadBrief) => {
                  ListItem() {
                    this.ThreadCard(item)
                  }
                  .padding({ left: 8, right: 8, top: 8 })
                  .translate({ x: this.contentShift }).opacity(this.contentOpacity)
                }, (item: ThreadBrief) => `${item.tid}`)

                ListItem() {
                  this.PageFooter()
                }
                .padding({ left: 8, right: 8 })
              }
            }
            .backgroundColor(AppTheme.FORUM_TAB_BG)
            .borderRadius({ topLeft: 24, topRight: 24 })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)

          .edgeEffect(EdgeEffect.None)
          .sticky(StickyStyle.Header)
          .parallelGesture(PanGesture({ direction: PanDirection.Vertical, distance: 8 })
            .onActionStart((event: GestureEvent) => {
              const offset: number = this.scroller.currentOffset().yOffset;
              const contentTop: number = Math.max(0, this.heroHeight() - FORUM_TOOLBAR_HEIGHT - offset)
                + FORUM_TAB_HEIGHT + FORUM_TAB_HANDLE_HEIGHT * (1 - this.tabsNavProgress);
              this.pullEligible = !this.refreshing && !this.vm.loading && !this.vm.switchingTab
                && !this.vm.isLoadingMore && offset <= this.heroHeight() - FORUM_TOOLBAR_HEIGHT + 1
                && event.fingerList.length > 0 && event.fingerList[0].localY - event.offsetY >= contentTop;
            })
            .onActionUpdate((event: GestureEvent) => {
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
          .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 48 })
            .onActionEnd((event: GestureEvent) => { this.swipeForumTab(event.offsetX); }))
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
    }
    .width('100%').height(LayoutPolicy.matchParent)
  }

  @Builder
  PinnedSection() {
    Column() {
      ForEach(this.visiblePinnedThreads(this.pinnedThreads()), (item: ThreadBrief, index: number) => {
        Row({ space: 8 }) {
          this.Tag('置顶', false)
          Text(item.title.length > 0 ? item.title : '（无标题）')
            .fontSize(15).fontColor(AppTheme.TEXT_MAIN).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        }
        .width('100%').height(44).padding({ left: 12, right: 12 }).alignItems(VerticalAlign.Center)
        .border({ width: { bottom: index < this.visiblePinnedThreads(this.pinnedThreads()).length - 1 ? 1 : 0 },
          color: AppTheme.DIVIDER })
        .onClick(() => { this.openThread(item); })
      }, (item: ThreadBrief) => `${item.tid}`)
      if (this.pinnedThreads().length > 3) {
        Text(this.pinnedExpanded ? '收起' : `展开全部 (${this.pinnedThreads().length})`)
          .fontSize(12).fontColor(AppTheme.ACCENT_DARK).height(32).width('100%').textAlign(TextAlign.End)
          .padding({ right: 12 }).onClick(() => { this.pinnedExpanded = !this.pinnedExpanded; })
      }
    }
    .width('100%').borderRadius(12).backgroundColor(AppTheme.CARD).padding({ top: 4, bottom: 4 })
  }

  @Builder
  ThreadCard(item: ThreadBrief) {
    ThreadPreviewCard({
      authorName: item.authorName, authorAvatar: item.authorAvatar,
      postedTime: formatPostTime(item.postedMs, Date.now()), title: item.title, summary: item.summary,
      images: item.images.length > 0 ? item.images : (item.coverImage.length > 0 ? [item.coverImage] : []),
      isTop: item.isTop, isGood: item.isGood,
      agreeCount: item.agreeCount, replyCount: item.replyCount,
      shareCount: item.shareCount,
      menu: buildThreadCardMenu(this.getUIContext(), item),
      imageScroller: this.imageScroller(item.tid),
      onOpenAuthor: (): void => {
        openUserByIdentity(item.authorId, item.authorAvatar, item.authorName, this.getUIContext());
      },
      onOpenThread: (): void => { this.openThread(item); },
      onOpenImage: (index: number): void => {
        this.openImages(item.images.length > 0 ? item.images : [item.coverImage], index);
      }
    })
  }

  @Builder
  Tag(text: string, filled: boolean) {
    Text(text)
      .fontSize(10)
      .fontColor(filled ? Color.White : AppTheme.ACCENT_DARK)
      .backgroundColor(filled ? AppTheme.ACCENT : AppTheme.ACCENT_LIGHT)
      .borderRadius(4)
      .padding({ left: 5, right: 5, top: 2, bottom: 2 })
  }

  @Builder
  PageFooter() {
    Column({ space: 7 }) {
      if (this.vm.isLoadingMore) {
        Row({ space: 8 }) {
          RefreshSpinner({ diameter: 18 })
          Text('正在加载更多…')
            .fontSize(12)
            .fontColor(AppTheme.TEXT_SUB)
        }
      } else if (this.vm.loadMoreError.length > 0) {
        Text('加载更多失败，点击重试')
          .fontSize(12)
          .fontColor(AppTheme.ACCENT_DARK)
          .onClick(() => {
            this.vm.loadMore(this.hostContext(), true);
          })
      } else if (!this.vm.page.hasMore) {
        Text('已经到底了')
          .fontSize(12)
          .fontColor(AppTheme.TEXT_MUTED)
      } else {
        Text(`已加载 ${this.vm.threads.length} 条`)
          .fontSize(12)
          .fontColor(AppTheme.TEXT_SUB)
      }
    }
    .width('100%')

    .padding({ top: 14 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  StatusView(text: string) {
    Column() {
      Text(text)
        .fontSize(14)
        .fontColor(AppTheme.TEXT_SUB)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  FullPageLoading() {
    Column() {
      RefreshSpinner()
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  ErrorView() {
    Column({ space: 10 }) {
      Text('加载失败')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_MAIN)
      Text(this.vm.errorText)
        .fontSize(13)
        .fontColor(AppTheme.TEXT_SUB)
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
      Text('重试')
        .fontSize(14)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .width(96)
        .height(38)
        .borderRadius(19)
        .backgroundColor(AppTheme.ACCENT)
        .onClick(() => {
          this.handleRefresh();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }
}
