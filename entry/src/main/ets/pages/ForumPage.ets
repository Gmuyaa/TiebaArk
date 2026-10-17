import { PageState, ListFooter } from '../components/PageState';
import { RefreshSpinner, FORUM_REFRESH_OFFSET } from '../components/RefreshSpinner';
import { ForumIdentity } from '../components/ForumIdentity';
import { ForumRefreshButton } from '../components/ForumRefreshButton';
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
import { ThreadCardActionState, ThreadCardActionsVM } from '../viewmodel/ThreadCardActionsVM';
import { AvatarComponent } from '../components/AvatarComponent';
import { lowFlowStore } from '../common/appearance/LowFlowStore';
import { buildThreadCardMenu } from '../components/ThreadCardMenu';
import { visibleThreads } from '../model/ThreadBlock';
import { threadBlockStore } from '../utils/ThreadBlockStore';
import {
  FORUM_HERO_PATTERN_COLOR_FILTER, FORUM_HERO_PATTERN_OPACITY, FORUM_HERO_HEADLINE_SCRIM_BOTTOM,
  FORUM_HERO_HEADLINE_SCRIM_TOP, ForumHeroPalette, forumHeroPalette
} from '../common/appearance/ForumHeroStyle';
import { GlassBackButton } from '../components/GlassBackButton';
import { GlassCircleButton } from '../components/GlassCircleButton';
import { SearchField } from '../components/SearchField';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { ForumPageParams, NavigationService, SearchResultParams } from '../navigation/AppNavigation';
import { forumDefaultTabStore } from '../common/appearance/ForumDefaultTabStore';
import { themeModeStore } from '../common/appearance/ThemeModeStore';
import { ForumDefaultTab } from '../model/ForumDefaultTab';

/** 仅缓存吧页返回所需的 VM 与滚动偏移，不引入全局状态框架。 */
class ForumPageState {
  vm: ThreadListVM = new ThreadListVM();
  scrollOffset: number = 0;
  defaultTab: ForumDefaultTab = ForumDefaultTab.HOT;
}

const FORUM_PAGE_STATES: Map<string, ForumPageState> = new Map<string, ForumPageState>();
const FORUM_HERO_HEIGHT: number = 160;
/** 保留原背景绘制尺寸，使顶部按钮区的头图裁切与渐变采样不变。 */
const FORUM_HERO_BACKGROUND_HEIGHT: number = 280;
/** 顶部工具栏内容行高；内容列表视口从其下沿开始。 */
const FORUM_TOOLBAR_HEIGHT: number = 56;
const FORUM_TAB_HEIGHT: number = 46;
const FORUM_TAB_HANDLE_HEIGHT: number = 12;
let forumTintSerial: number = 0;

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
  @Local introductionVisible: boolean = false;
  @Local forumSearchExpanded: boolean = false;
  @Local forumSearchProgress: number = 0;
  @Local forumSearchText: string = '';
  @Local forumSearchSlotWidth: number = 40;
  @Local restorePending: boolean = false;
  @Local pinnedExpanded: boolean = false;
  /**
   * 状态栏高度（vp）。窗口全屏布局下页面从 y=0 起排，**Hero 的内容要自己让出这一段**，
   * 否则返回键会压在状态栏上（既重叠又点不到，状态栏会吃掉那一片触摸）。
   * Hero 的**渐变底仍从 y=0 铺起**（保持沉浸感），只是内容整体下移。
   */
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;
  /** 覆盖吧信息的滚动进度 0~1，驱动内容面板提示条和圆角收拢。 */
  @Local tabsNavProgress: number = 0;
  @Local sampledHeroColor: string = '';
  @Local contentHeight: number = 500;
  @Local pageVisible: boolean = true;
  @Local viewportWidth: number = 0;
  @Local viewportHeight: number = 0;
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
      // 只采样与状态栏、工具栏对应的图片上缘，避免下方建筑主色污染天空色。
      await pixels.crop({ x: 0, y: 0, size: { width: info.size.width,
        height: Math.max(1, Math.round(info.size.height * (this.statusBarH + FORUM_TOOLBAR_HEIGHT)
          / (FORUM_HERO_BACKGROUND_HEIGHT + this.statusBarH))) } });
      const picker = await effectKit.createColorPicker(pixels);
      const color = await picker.getMainColor();
      if (!this.active || source !== this.vm.heroHeadline || color.alpha <= 0) { return; }
      // 固定白色图标的工具栏使用主色的暗化版本，保留原图色相。
      const channel = (value: number): string => Math.round(Math.max(0, Math.min(255, value)) * 0.65)
        .toString(16).padStart(2, '0');
      this.sampledHeroColor = `#${channel(color.red)}${channel(color.green)}${channel(color.blue)}`;
    } catch (err) { /* 图片快照不可用时沿用协议主题色。 */ }
    finally { if (pixels !== undefined) { try { await pixels.release(); } catch (err) { /* 不阻塞页面。 */ } } }
  }
  private scroller: ListScroller = new ListScroller();
  /** 分类页签横滚 scroller：胶囊式/下划线式共用，点击后把选中项滚到视口中间 */
  private tabsScroller: Scroller = new Scroller();
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
    this.getUIContext().animateTo({ duration: 260, curve: Curve.EaseOut }, (): void => {
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
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, (): void => {
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
      // 内容区刷新动画随请求结束收起。
      this.refreshing = false;
      if (this.active) { this.settlePullDistance(0); }
    }
  }

  /** 超过刷新带高后连续减小跟手比例，避免固定封顶形成硬挡板。 */
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

  /** 内容面板覆盖固定吧信息；分类吸顶位置是工具栏下沿。 */
  private syncTabsSticky(): void {
    const distance: number = this.heroHeight() - FORUM_TOOLBAR_HEIGHT;
    const offset: number = this.scroller.currentOffset().yOffset;
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
    return this.pinnedExpanded || items.length <= 3 ? items : items.slice(0, 3);
  }

  private lightStatusBar(): boolean {
    // 首载整页是主题底；吧头出现后始终是深色图片/渐变，包括读取失败的吧头。
    return themeModeStore.isDark || this.viewerUrls.length > 0 ||
      (this.forumName.length > 0 && !(this.vm.loading && !this.vm.loadedOnce));
  }

  build() {
    // 自绘固定工具栏与吧信息；内容列表从工具栏下沿覆盖吧信息区。
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

        if (this.forumName.length > 0 && this.vm.loadedOnce && this.viewerUrls.length === 0) {
          ForumRefreshButton({ viewportWidth: this.viewportWidth, viewportHeight: this.viewportHeight,
            topInset: this.statusBarH + FORUM_TOOLBAR_HEIGHT, active: this.pageVisible,
            busy: this.refreshing || this.vm.loading || this.vm.isLoadingMore || this.vm.switchingTab,
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
        }
      }
      .width('100%')
      .height(LayoutPolicy.matchParent)
      .onAreaChange((_old: Area, area: Area): void => {
        this.viewportWidth = Number(area.width); this.viewportHeight = Number(area.height);
      })
    }
    // 本页顶栏完全由固定 Hero 自绘，不叠加 HDS 默认标题栏
    .hideTitleBar(true)
    .systemBarStyle(
      { statusBarContentColor: this.lightStatusBar() ? '#F2F3F4' : '#1B1B1B' },
      { statusBarContentColor: this.lightStatusBar() ? '#F2F3F4' : '#1B1B1B' }
    )
    .onShown((): void => { this.pageVisible = true; })
    .onHidden((): void => { this.pageVisible = false; })
    .onBackPressed((): boolean => {
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
  ForumHero() {
    Stack({ alignContent: Alignment.TopStart }) {
      // ① 底色：吧主题色派生渐变（拿不到主题色时就是迁移前的深蓝兜底）
      Column()
        .width('100%')
        .height(FORUM_HERO_BACKGROUND_HEIGHT + this.statusBarH)
        .linearGradient({ angle: 180, colors: this.heroGradientColors() })

      /*
       * ② 吧头图：既有 PC JSON 链路取得的真实横幅，保留原背景采样尺寸。
       * 图上叠自下而上的暗化 scrim —— 照片亮部不受控，白字可读性由 scrim 兜底；
       * 不叠主题色蒙层，避免把照片染色。
       */
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

      Column().width('100%').height(this.statusBarH + FORUM_TOOLBAR_HEIGHT)
        .backgroundColor(this.sampledHeroColor || this.heroPalette().bottomColor)
        .opacity(this.tabsNavProgress).hitTestBehavior(HitTestMode.None)

      // ③ 内容层（返回键 / 吧名 / 统计），只让出状态栏。
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
                avatarSize: 28, radius: forumAvatarRadius(28), onHero: true })
              Text(this.titleText().endsWith('吧') ? this.titleText() : `${this.titleText()}吧`)
                .fontSize(17).fontWeight(FontWeight.Medium).fontColor(Color.White)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            }
            .width('100%').padding({ right: 50 })
            .opacity(this.tabsNavProgress * (1 - this.forumSearchProgress))
            .hitTestBehavior(this.tabsNavProgress > 0 && !this.forumSearchExpanded ? HitTestMode.Default : HitTestMode.None)
            .onClick(() => { this.openForumDirectory('forum'); })

            Stack({ alignContent: Alignment.End }) {
              SearchField({ inputId: 'forum-search-input', text: this.forumSearchText,
                placeholder: '搜索吧内帖子', minimumHeight: 40,
                onChange: (value: string): void => { this.forumSearchText = value; },
                onSubmit: (): void => { this.submitForumSearch(); } })
                .opacity(this.forumSearchProgress)
                .hitTestBehavior(this.forumSearchExpanded ? HitTestMode.Default : HitTestMode.None)
              GlassCircleButton({ symbol: $r('sys.symbol.magnifyingglass'), iconSize: 22, iconOffsetX: -3,
                accessibilityLabel: '搜索吧内帖子', onTap: (): void => { this.openForumSearch(); } })
                .opacity(1 - this.forumSearchProgress)
                .hitTestBehavior(this.forumSearchExpanded ? HitTestMode.None : HitTestMode.Default)
            }
            .width(40 + Math.max(0, this.forumSearchSlotWidth - 40) * this.forumSearchProgress)
            .height(40).clip(true).id('forum-search-expand')
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

        ForumIdentity({ forumId: this.vm.forum.id, forumName: this.titleText(), avatar: this.vm.forum.avatar,
          active: this.pageVisible && this.viewerUrls.length === 0,
          refreshRevision: this.headerRefreshRevision, memberCount: this.vm.forum.memberCount,
          threadCount: this.vm.forum.threadCount,
          onOpenInformation: (): void => { this.openForumDirectory('forum'); },
          onIntroductionVisible: (visible: boolean): void => { this.introductionVisible = visible; this.syncTabsSticky(); } })
          .padding({ left: 16, right: 16 })
          .margin({ top: 12 })

      }
      .width('100%')
      .height('100%')
      // 内容整体让出状态栏；底色与底纹仍从 y=0 铺（沉浸感保留）
      .padding({ top: this.statusBarH })
    }
    .width('100%')
    .height(this.heroHeight() + this.statusBarH + 24)
    .clip(true)
    // 底图未加载完 / 无主题色时的兜底底色，避免解析期闪白
    .backgroundColor(this.heroPalette().bottomColor)
  }

  private heroHeight(): number { return FORUM_HERO_HEIGHT + (this.introductionVisible ? 54 : 0); }

  /** Hero 配色：由协议吧主题色派生。无主题色时返回既有深蓝兜底（见 ForumHeroStyle） */
  private heroPalette(): ForumHeroPalette {
    return forumHeroPalette(this.vm.forum.heroColor);
  }

  /**
   * Hero 底色渐变（顶 → 底）。
   *
   * 有吧主题色时用它派生（于是每个吧的 Hero 颜色跟随该吧：李毅吧蓝紫、harmonyos 褐金、
   * 数码吧珊瑚红…），拿不到时是迁移前的深蓝兜底。底纹图不参与这里，
   * 它由 `FORUM_HERO_PATTERN_OPACITY` 单独以低不透明度叠在底色之上。
   */
  private heroGradientColors(): Array<[ResourceColor, number]> {
    const palette: ForumHeroPalette = this.heroPalette();
    return [[palette.topColor, 0.0], [palette.bottomColor, 1.0]];
  }

  /** 官方式帖子面板上缘：圆角、短提示条、真实文字分类；独立于首页导航设置。 */
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

  /**
   * 切换真实吧页分类。滚动复位与错误提示沿用旧版行为；
   * 成功后把选中签滚到视口中间（tab 多时点右侧的签不至于停在看不见的地方）。
   */
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
              // 保留零高度刷新项，收起时高度可连续回弹，不因移除组件而瞬间跳回。
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
              } else if (this.vm.isVideoTab()) {
                ListItem() { this.VideoSortBar() }.padding({ left: 12, right: 12 })
                if (this.videoItems().length === 0) {
                  ListItem() { this.StatusView('这个分类暂无可播放视频') }
                } else {
                  ListItem() {
                    Row({ space: 8 }) {
                      ForEach([0, 1], (side: number) => {
                        Column({ space: 8 }) {
                          ForEach(this.videoColumn(side), (item: ThreadBrief) => { this.VideoCard(item) }, (item: ThreadBrief) => `${item.tid}`)
                        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                      })
                    }.width('100%').alignItems(VerticalAlign.Top)
                  }.padding({ left: 8, right: 8, top: 8 })
                }
                ListItem() { this.PageFooter() }.padding({ left: 8, right: 8 })
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
            .borderRadius({ topLeft: 24 * (1 - this.tabsNavProgress), topRight: 24 * (1 - this.tabsNavProgress) })
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

  /** 置顶为紧凑标题入口，保留服务端顺序、最多三条预览与展开能力。 */
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
  VideoSortBar() {
    Row({ space: 10 }) {
      Text('看帖排序').fontSize(13).fontColor(AppTheme.TEXT_SUB).layoutWeight(1)
      ForEach([0, 1], (sort: number) => {
        Text(sort === 0 ? '回复' : '发布').fontSize(13)
          .fontColor(this.vm.videoSort === sort ? AppTheme.TEXT_MAIN : AppTheme.TEXT_SUB)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 }).borderRadius(18)
          .backgroundColor(this.vm.videoSort === sort ? AppTheme.CARD : Color.Transparent)
          .onClick(() => { void this.vm.changeVideoSort(this.hostContext(), sort); })
      })
    }.height(48).width('100%')
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
      authorName: item.authorName, authorAvatar: item.authorAvatar,
      postedTime: formatPostTime(item.postedMs, Date.now()), title: item.title, summary: item.summary,
      images: item.images.length > 0 ? item.images : (item.coverImage.length > 0 ? [item.coverImage] : []),
      isTop: item.isTop, isGood: item.isGood,
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
  /** 置顶/精品这类小标记。filled=true 用实底，false 用浅底 */
  @Builder
  Tag(text: string, filled: boolean) {
    Text(text)
      .fontSize(10)
      .fontColor(filled ? Color.White : AppTheme.ACCENT_DARK)
      .backgroundColor(filled ? AppTheme.ACCENT : AppTheme.ACCENT_LIGHT)
      .borderRadius(4)
      .padding({ left: 5, right: 5, top: 2, bottom: 2 })
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
    PageState({ fillRemaining: true, title: '加载失败', message: this.vm.errorText, actionLabel: '重试',
      onAction: (): void => { void this.handleRefresh(); } }).layoutWeight(1)
  }
}
