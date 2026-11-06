

import { homeChannelHeight, UiLayout } from '../common/appearance/UiLayout';
import { fontSizeScaleOf } from '../common/appearance/FontSizeScale';
import { fontScaleStore } from '../common/appearance/FontSizeScaleStore';
import { PageState, ListFooter } from '../components/PageState';
import { common } from '@kit.AbilityKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { SearchPostItem, searchEmptyHint, searchNoResultText, searchPlaceholder, searchScopeForum,
  searchScopeLabel } from '../model/SearchPost';
import { ForumSearchItem } from '../model/ForumSearch';
import { UserSearchItem } from '../model/UserSearch';
import { SearchResultVM } from '../viewmodel/SearchResultVM';
import { AvatarComponent } from '../components/AvatarComponent';
import { TopLabelItem } from '../components/TopLabelItem';
import { openUserByIdentity } from '../navigation/UserNavigation';
import { formatPostTime } from '../model/HomeFeedPresentation';
import { AppTheme } from '../theme/Theme';
import { SearchPageHeader } from '../components/SearchPageHeader';
import { ForumAvatarImage, forumAvatarRadius } from '../components/ForumAvatarImage';
import { ThreadPreviewCard } from '../components/ThreadPreviewCard';
import { ThreadCardActionState, ThreadCardActionsVM } from '../viewmodel/ThreadCardActionsVM';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { NavigationService, SearchResultParams } from '../navigation/AppNavigation';

/** 全站结果分类；吧内搜索固定为帖子。 */
const TAB_FORUM: number = 0;
const TAB_POST: number = 1;
const TAB_USER: number = 2;

@ComponentV2
export struct SearchResultPage {
  @Local cardActions: ThreadCardActionsVM = new ThreadCardActionsVM();
  /** PageMap 注入的路由参数，唯一定义见 navigation/AppNavigation.ets 的 SearchResultParams */
  @Param routeParams: SearchResultParams | undefined = undefined;
  @Local vm: SearchResultVM = new SearchResultVM();
  /** 状态栏高度（vp），见 SafeArea.ets */
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;
  @Local headerHeight: number = STATUS_BAR_FALLBACK_VP + 96;

  private cardScroller: ListScroller = new ListScroller();
  /** 搜索框内容与 word 分开存，避免打字过程触发刷新 */
  @Local input: string = '';
  /** 当前结果分类；默认搜吧。 */
  @Local resultTab: number = TAB_FORUM;
  /**
   * 吧内搜索范围（A-02）：非空时本页只显示「搜帖子」结果、请求多带 `kw` = 本值。
   * 缺省空串 = 全站搜索。
   */
  @Local scopeForum: string = '';

  aboutToDisappear(): void { this.vm.dispose(); }

  aboutToAppear(): void {

    let keyword: string = '';
    if (this.routeParams !== undefined && this.routeParams.word !== undefined) {
      keyword = this.routeParams.word.trim();
    }
    this.scopeForum = searchScopeForum(this.routeParams === undefined
      ? undefined : this.routeParams.forumName);
    // 吧内搜索只有一个结果面（帖子），直接落在「搜帖子」上，不留一个点了也没用的「搜吧」tab
    if (this.scopeForum.length > 0) {
      this.resultTab = TAB_POST;
    }
    this.vm.word = keyword;
    this.input = this.vm.word;
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    readStatusBarVp(context).then((vp: number) => {
      this.statusBarH = vp;
    }).catch(() => {
      // 拿不到就保持兜底值
    });
    if (this.vm.word.length > 0) {
      this.reload();
    }
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  /** 首屏加载（改词重搜与进入页面共用） */
  private async reload(): Promise<void> {
    await this.vm.reload(this.hostContext(), this.input, this.scopeForum, this.resultTab === TAB_USER);
  }

  /** 是否处于吧内搜索形态（只看帖子、请求带 kw） */
  private scoped(): boolean {
    return this.scopeForum.length > 0;
  }

  private resultTimeText(item: SearchPostItem): string {
    // 全站统一格式（今年 `MM-DD HH:mm` / 往年 `YYYY-MM-DD`），与首页同一函数
    return formatPostTime(item.timeMs, Date.now());
  }

  private goBack(): void {
    NavigationService.back();
  }

  /** 进吧：复用现有 ForumPage（frs/page 链路）。吧名来自搜索结果的 forum_name */
  private openForumPage(name: string): void {
    const target: string = name.trim();
    if (target.length === 0) {
      return;
    }
    NavigationService.openForum({ forumName: target });
  }

  private openThread(item: SearchPostItem): void {
    if (item.tid <= 0) {
      return;
    }

    NavigationService.openThreadDetail({ tid: item.tid, forumName: item.forumName });
  }

  private selectResultTab(tab: number): void {
    this.resultTab = tab;
    if (tab === TAB_USER) { void this.vm.users.load(); }
  }

  /** 列表自己含顶部透明占位；状态页则在顶栏以下占满剩余空间。 */
  private showingList(): boolean {
    if (this.vm.word.length === 0) { return false; }
    if (!this.scoped() && this.resultTab === TAB_USER) {
      return !this.vm.users.loading && this.vm.users.error.length === 0 && this.vm.users.items.length > 0;
    }
    if (!this.scoped() && this.resultTab === TAB_FORUM) {
      return !this.vm.forumLoading && this.vm.forumErrorText.length === 0 && this.vm.forumItems.length > 0;
    }
    return !this.vm.loading && this.vm.errorText.length === 0 && this.vm.items.length > 0;
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Top }) {
        Column() {
          if (this.vm.word.length === 0 && this.scoped()) {
            // 从吧页搜索入口进来时还没输入关键词：给一句明确的提示，不发必然为空的请求
            this.StatusView(searchEmptyHint(this.scopeForum))
          } else if (!this.scoped() && this.resultTab === TAB_USER) {
            if (this.vm.users.loading) {
              PageState({ fillRemaining: true, message: '正在搜索…', loading: true }).layoutWeight(1)
            } else if (this.vm.users.error.length > 0) {
              PageState({ fillRemaining: true, title: '搜索失败', message: this.vm.users.error, actionLabel: '重试',
                onAction: (): void => { void this.vm.users.load(true); } }).layoutWeight(1)
            } else if (this.vm.users.items.length === 0) {
              PageState({ fillRemaining: true, message: `没有找到与「${this.vm.word}」相关的用户` }).layoutWeight(1)
            } else {
              this.UserListTab()
            }
          } else if (!this.scoped() && this.resultTab === TAB_FORUM) {
            // 搜吧 tab：关键词相关的吧列表（模糊搜索，精确匹配排最前）
            if (this.vm.forumLoading) {
              this.StatusView('正在搜索…')
            } else if (this.vm.forumErrorText.length > 0) {
              this.ForumErrorView()
            } else if (this.vm.forumItems.length === 0) {
              this.StatusView(`没有找到与「${this.vm.word}」相关的吧`)
            } else {
              this.ForumListTab()
            }
          } else if (this.vm.loading) {
            this.StatusView('正在搜索…')
          } else if (this.vm.errorText.length > 0) {
            this.ErrorView()
          } else if (this.vm.items.length === 0) {
            this.StatusView(searchNoResultText(this.scopeForum, this.vm.word))
          } else {
            this.ResultList()
          }
        }
        .width('100%').height('100%')
        .padding({ left: UiLayout.PAGE_GUTTER, right: UiLayout.PAGE_GUTTER,
          top: this.showingList() ? 0 : this.headerHeight + UiLayout.SEARCH_CONTENT_GAP })
        .alignItems(HorizontalAlign.Start)
        .id('search-results-body')
        this.TopBar()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppTheme.BG)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    }
    // 顶栏固定，列表从整片 HDS 材质后方经过。
    .hideTitleBar(true)
    .systemTransition(NavigationSystemTransitionType.NONE)
    .onBackPressed((): boolean => { this.goBack(); return true; })
  }

  /**
   * 吧内搜索的范围标签（A-02）。取代「搜吧／搜帖子」分段控件的位置 ——
   * 吧内搜索只有一个结果面，留一个点了也没用的 tab 反而误导。
   * 文案来自 `model/SearchPost.ets#searchScopeLabel`（与请求参数同一处真值源）。
   */
  @Builder
  ScopeLabel() {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(14)
        .fontColor([AppTheme.ACCENT_DARK])
      Text(searchScopeLabel(this.scopeForum))
        .fontSize(13)
        .fontColor(AppTheme.ACCENT_DARK)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(36)
    .padding({ left: 12, right: 12 })
    .borderRadius(18)
    .backgroundColor(AppTheme.ACCENT_LIGHT)
    .margin({ bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 结果分类放在连续材质内，保持切换即时、字号和点击高度一致。
   */
  @Builder
  ResultTabs() {
    Row({ space: 0 }) {
      this.ResultTabItem('搜吧', TAB_FORUM)
      this.ResultTabItem('搜帖子', TAB_POST)
      this.ResultTabItem('搜人', TAB_USER)
    }
    .width('100%')
    .height(homeChannelHeight(fontSizeScaleOf(
      fontScaleStore.pref, fontScaleStore.systemScale, fontScaleStore.customSize)))
    .margin({ bottom: 8 })
    .id('search-result-tabs')
  }

  @Builder
  ResultTabItem(label: string, tabIndex: number) {
    TopLabelItem({ label, selected: this.resultTab === tabIndex,
      onTap: (): void => { this.selectResultTab(tabIndex); } })
      .layoutWeight(1).height('100%')
  }

  @Builder
  ForumListTab() {
    List({ space: 10 }) {
      // List 自带10vp项间距；其余占位保证材质下沿之外还有统一内容间距。
      ListItem() { Row().width('100%').height(Math.max(0, this.headerHeight + UiLayout.SEARCH_CONTENT_GAP - 10)) }
      ForEach(this.vm.forumItems, (item: ForumSearchItem) => {
        ListItem() {
          Row({ space: 12 }) {

            ForumAvatarImage({ url: item.avatar, forumName: item.displayName(),
              avatarSize: 44, radius: forumAvatarRadius(44) })

            Column({ space: 3 }) {
              Row({ space: 6 }) {
                Text(item.displayName().endsWith('吧') ? item.displayName() : `${item.displayName()}吧`)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(AppTheme.TEXT_MAIN)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                if (item.isOfficial) {
                  Text('官方')
                    .fontSize(10)
                    .fontColor(AppTheme.ACCENT_DARK)
                    .backgroundColor(AppTheme.ACCENT_LIGHT)
                    .borderRadius(4)
                    .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                    .flexShrink(0)
                }
              }
              .width('100%')

              if (item.slogan.length > 0) {
                Text(item.slogan)
                  .fontSize(12)
                  .fontColor(AppTheme.TEXT_SUB)
                  .lineHeight(17)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }

              Text(`关注 ${item.concernNum} · 帖子 ${item.postNum}`)
                .fontSize(11)
                .fontColor(AppTheme.TEXT_MUTED)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(14)
              .fontColor([AppTheme.ICON])
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .borderRadius(AppTheme.CARD_RADIUS)
          .backgroundColor(AppTheme.CARD)
          .onClick(() => {
            this.openForumPage(item.forumName);
          })
        }
      }, (item: ForumSearchItem) => `${item.forumId}-${item.forumName}`)

    }
    .width('100%')
    // 占满容器可滚到底；不加底部手势区留白。
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  /** 搜吧 tab 的失败视图：与帖子 tab 的 ErrorView 同构，重试只重发吧搜索 */
  @Builder
  ForumErrorView() {
    PageState({ fillRemaining: true, title: '搜索失败', message: this.vm.forumErrorText, actionLabel: '重试',
      onAction: (): void => { void this.vm.retryForums(); } }).layoutWeight(1)
  }

  /** 顶部：返回 + 搜索框（可改词重搜） */
  @Builder
  TopBar() {
    SearchPageHeader({ text: this.input, placeholder: searchPlaceholder(this.scopeForum),
      statusBarHeight: this.statusBarH,
      secondaryHeight: this.scoped() ? 48 : 38,
      secondary: (): void => { this.ResultHeader(); },
      onHeightChange: (height: number): void => { this.headerHeight = height; },
      onChange: (value: string): void => { this.input = value; },
      onSubmit: (): void => { this.reload(); },
      onBack: (): void => { this.goBack(); } })
  }

  @Builder
  ResultHeader() {
    Column() {
      if (this.scoped()) { this.ScopeLabel() } else { this.ResultTabs() }
    }
    .width('100%')
    .padding({ left: UiLayout.PAGE_GUTTER, right: UiLayout.PAGE_GUTTER })
  }

  @Builder
  UserListTab() {
    List({ space: 10 }) {
      ListItem() { Row().width('100%').height(Math.max(0, this.headerHeight + UiLayout.SEARCH_CONTENT_GAP - 10)) }
      ForEach(this.vm.users.items, (item: UserSearchItem) => {
        ListItem() {
          Row({ space: 12 }) {
            AvatarComponent({ url: item.avatar, avatarSize: 44, fallbackName: item.name })
            Column({ space: 4 }) {
              Text(item.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT_MAIN)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              if (item.intro.length > 0) {
                Text(item.intro).fontSize(12).fontColor(AppTheme.TEXT_SUB)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              }
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([AppTheme.ICON])
          }
          .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 12 })
          .alignItems(VerticalAlign.Center).borderRadius(AppTheme.CARD_RADIUS).backgroundColor(AppTheme.CARD)
          .id('search-user-row')
          .onClick(() => { openUserByIdentity(item.uid, item.portrait, item.name, this.getUIContext()); })
        }
      }, (item: UserSearchItem) => item.key())
      ListItem() {
        ListFooter({ loading: this.vm.users.loadingMore, error: this.vm.users.pagingError.length > 0 ? '加载失败' : '',
          hasMore: this.vm.users.hasMore, onRetry: (): void => { void this.vm.users.loadMore(true); } })
      }
    }
    .width('100%').layoutWeight(1).scrollBar(BarState.Off)
    .id('search-user-list')
    .onReachEnd(() => { void this.vm.users.loadMore(); })
  }

  @Builder
  ResultList() {
    List({ space: 10 }) {
      ListItem() { Row().width('100%').height(Math.max(0, this.headerHeight + UiLayout.SEARCH_CONTENT_GAP - 10)) }
      ForEach(this.vm.items, (item: SearchPostItem) => {
        ListItem() {
          ThreadPreviewCard({
            authorName: item.authorName,
            authorAvatar: this.vm.postAvatars.urls.get(`author:${item.tid}:${item.pid}`) ?? '',
            forumName: item.forumName,
            forumAvatar: this.vm.postAvatars.urls.get(`forum:${item.forumName}`) ?? '',
            postedTime: this.resultTimeText(item),
            title: item.displayTitle(),
            summary: item.snippet === item.displayTitle() ? '' : item.snippet,
            images: [],
            menu: [],
            canOpenForum: item.forumName.length > 0,
            onOpenForum: (): void => { this.openForumPage(item.forumName); },
            imageScroller: this.cardScroller,
            onToggleLike: (state: ThreadCardActionState): void => {
              void this.cardActions.toggleLike(state, this.getUIContext().getHostContext() as common.UIAbilityContext,
                item.tid, item.forumName).then((reason: string): void => {
                  if (reason.length > 0) { this.getUIContext().getPromptAction().showToast({ message: reason }); }
                });
            },
            onOpenComments: (): void => { NavigationService.openThreadDetail({ tid: item.tid, forumName: item.forumName, openComments: true }); },
            onShare: (): void => {
              void this.cardActions.share(this.getUIContext().getHostContext() as common.UIAbilityContext,
                item.tid, item.title).then((reason: string): void => {
                  if (reason.length > 0) { this.getUIContext().getPromptAction().showToast({ message: reason }); }
                });
            },
            onOpenThread: (): void => { this.openThread(item); }
          })
        }
        .onAppear(() => {
          this.vm.requestAvatar(item);
        })
      }, (item: SearchPostItem) => `${item.tid}-${item.pid}`)

      ListItem() {
        this.PageFooter()
      }
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .onReachEnd(() => {
      void this.vm.loadMore(this.hostContext());
    })
  }

  @Builder
  PageFooter() {
    ListFooter({ loading: this.vm.loadingMore, error: this.vm.pagingError.length > 0 ? '加载失败' : '',
      hasMore: this.vm.hasMore, onRetry: (): void => { void this.vm.loadMore(this.hostContext(), true); } })
  }

  @Builder
  StatusView(text: string) {
    PageState({ fillRemaining: true, message: text, loading: this.vm.loading || this.vm.forumLoading }).layoutWeight(1)
  }

  @Builder
  ErrorView() {
    PageState({ fillRemaining: true, title: '搜索失败', message: this.vm.errorText, actionLabel: '重试',
      onAction: (): void => { this.reload(); } }).layoutWeight(1)
  }
}
