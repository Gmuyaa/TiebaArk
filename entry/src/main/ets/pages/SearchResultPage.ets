

import { homeChannelHeight, UiLayout } from '../common/appearance/UiLayout';
import { fontSizeScaleOf } from '../common/appearance/FontSizeScale';
import { fontScaleStore } from '../common/appearance/FontSizeScaleStore';
import { PageState, ListFooter } from '../components/PageState';
import { common } from '@kit.AbilityKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { TiebaApi } from '../api/TiebaApi';
import { SearchPostItem, searchEmptyHint, searchNoResultText, searchPlaceholder, searchScopeForum,
  searchScopeLabel } from '../model/SearchPost';
import { ForumSearchItem } from '../model/ForumSearch';
import { UserSearchItem } from '../model/UserSearch';
import { SearchUsersVM } from '../viewmodel/SearchUsersVM';
import { SearchPostAvatarsVM } from '../viewmodel/SearchPostAvatarsVM';
import { getForumAvatar, isForumAvatarFetched, markForumAvatarFetched, putForumAvatar } from '../model/ForumAvatarStore';
import { AvatarComponent } from '../components/AvatarComponent';
import { TopLabelItem } from '../components/TopLabelItem';
import { openUserByIdentity } from '../navigation/UserNavigation';
import { formatPostTime } from '../model/HomeFeedPresentation';
import { TiebaDevice } from '../net/TiebaParams';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { authSession } from '../auth/AuthSession';
import { AppTheme } from '../theme/Theme';
import { SearchPageHeader } from '../components/SearchPageHeader';
import { ForumAvatarImage, forumAvatarRadius } from '../components/ForumAvatarImage';
import { ThreadPreviewCard } from '../components/ThreadPreviewCard';
import { ThreadCardActionState, ThreadCardActionsVM } from '../viewmodel/ThreadCardActionsVM';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { addSearchHistory } from '../utils/SearchHistory';
import { NavigationService, SearchResultParams } from '../navigation/AppNavigation';

/** 每页条数。搜索结果信息密度低，30 条一页滚动观感比 10 条好 */
const SEARCH_PAGE_SIZE: number = 30;

/** 全站结果分类；吧内搜索固定为帖子。 */
const TAB_FORUM: number = 0;
const TAB_POST: number = 1;
const TAB_USER: number = 2;

@ComponentV2
export struct SearchResultPage {
  @Local cardActions: ThreadCardActionsVM = new ThreadCardActionsVM();
  /** PageMap 注入的路由参数，唯一定义见 navigation/AppNavigation.ets 的 SearchResultParams */
  @Param routeParams: SearchResultParams | undefined = undefined;
  /** 当前搜索词（可被改词重搜） */
  @Local word: string = '';
  /** 帖子结果（append 会整体触发 @Trace） */
  @Local items: SearchPostItem[] = [];
  /** 请求进行中（首屏与翻页共用，翻页由分页状态位区分） */
  @Local loading: boolean = false;
  @Local loadingMore: boolean = false;
  @Local hasMore: boolean = false;
  /** 首屏失败原因；翻页失败用 toast，不打断已有列表 */
  @Local errorText: string = '';
  @Local pagingError: string = '';
  /** 已加载到的页码 */
  private page: number = 0;
  /** 状态栏高度（vp），见 SafeArea.ets */
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;
  @Local headerHeight: number = STATUS_BAR_FALLBACK_VP + 96;
  @Local users: SearchUsersVM = new SearchUsersVM();
  @Local postAvatars: SearchPostAvatarsVM = new SearchPostAvatarsVM();

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

  @Local forumItems: ForumSearchItem[] = [];
  @Local forumLoading: boolean = false;
  @Local forumErrorText: string = '';

  private requestEpoch: number = 0;
  aboutToDisappear(): void { this.requestEpoch++; this.users.dispose(); this.postAvatars.reset(); }

  private api: TiebaApi = new TiebaApi();

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
    this.word = keyword;
    this.input = this.word;
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    readStatusBarVp(context).then((vp: number) => {
      this.statusBarH = vp;
    }).catch(() => {
      // 拿不到就保持兜底值
    });
    if (this.word.length > 0) {
      this.reload();
    }
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  /** 首屏加载（改词重搜与进入页面共用） */
  private async reload(): Promise<void> {
    const word: string = this.input.trim();
    if (word.length === 0) {
      return;
    }
    const epoch: number = ++this.requestEpoch;
    const owner: string = authSession.sessionKey();
    // 每次改词独立补图；旧查询与旧账号的结果不能回填当前卡片。
    this.postAvatars.reset(async (name: string, forum: boolean, tid: number, pid: number): Promise<string> => {
      if (epoch !== this.requestEpoch || owner !== authSession.sessionKey()) { return ''; }
      const avatarApi: TiebaApi = new TiebaApi();
      const device: TiebaDevice = await DeviceIdentity.ensure(this.hostContext());
      if (epoch !== this.requestEpoch || owner !== authSession.sessionKey()) { return ''; }
      if (!forum) {
        const url: string = await avatarApi.fetchSearchPostAuthorAvatar(device, authSession.session(), tid, pid);
        return epoch === this.requestEpoch && owner === authSession.sessionKey() ? url : '';
      }
      if (isForumAvatarFetched(name)) {
        const cached: string = getForumAvatar(name);
        if (cached.length > 0) { return cached; }
      }
      const response = await avatarApi.fetchThreadList(device, authSession.session(), name, 1, 1);
      if (epoch !== this.requestEpoch || owner !== authSession.sessionKey() || !response.ok) { return ''; }
      const url: string = response.data.forum.avatar;
      if (url.length > 0) { putForumAvatar(name, url); markForumAvatarFetched(name); }
      return url;
    });
    this.loadingMore = false;
    this.forumItems = [];
    this.word = word;
    this.loading = true;
    this.errorText = ''; this.pagingError = '';
    this.page = 0;
    this.items = [];
    this.hasMore = false;
    this.users.reset(word);
    // 改词重搜也是一次搜索，历史规则与搜索页一致（去重置顶）
    await addSearchHistory(this.hostContext(), word).catch(() => {
      // 落库失败不影响搜索
    });
    if (epoch !== this.requestEpoch) { return; }
    // 吧搜索与帖子搜索并行发，互不阻塞（各自的加载/错误状态独立）；
    // 吧内搜索不发吧搜索（在某个吧里搜"相关的吧"没有意义，见 scopeForum 注释）
    if (this.scopeForum.length === 0) {
      this.fetchForums(word, epoch);
      if (this.resultTab === TAB_USER) { void this.users.load(); }
    }
    await this.fetchPage(word, epoch);
    if (epoch === this.requestEpoch) { this.loading = false; }
  }

  /** 是否处于吧内搜索形态（只看帖子、请求带 kw） */
  private scoped(): boolean {
    return this.scopeForum.length > 0;
  }

  /** 搜吧 tab：web 端 `/mo/q/search/forum`，精确在前模糊随后。失败只影响本 tab */
  private async fetchForums(word: string, epoch: number = this.requestEpoch): Promise<void> {
    this.forumLoading = true;
    this.forumErrorText = '';
    try {
      const response = await this.api.searchForums(word, 1, 20);
      if (epoch !== this.requestEpoch) { return; }
      if (!response.ok) {
        this.forumErrorText = response.describeFailure();
        return;
      }
      this.forumItems = response.data.items;
    } catch (err) {
      const e: Error = err as Error;
      if (epoch === this.requestEpoch) { this.forumErrorText = `加载失败：${e.message}`; }
    } finally {
      if (epoch === this.requestEpoch) { this.forumLoading = false; }
    }
  }

  /** 触底加载下一页 */
  private async loadMore(retry: boolean = false): Promise<void> {
    if (this.loading || this.loadingMore || !this.hasMore || (this.pagingError.length > 0 && !retry)) {
      return;
    }
    this.loadingMore = true; this.pagingError = '';
    const epoch: number = this.requestEpoch;
    await this.fetchPage(this.word, epoch);
    if (epoch === this.requestEpoch) { this.loadingMore = false; }
  }

  private async fetchPage(word: string, epoch: number): Promise<void> {
    const requested: number = this.page + 1;
    const owner: string = authSession.sessionKey();
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(this.hostContext());
      if (epoch !== this.requestEpoch || owner !== authSession.sessionKey()) { return; }
      const response = await this.api.searchPosts(
        device, authSession.session(), word, requested, SEARCH_PAGE_SIZE, this.scopeForum);
      if (epoch !== this.requestEpoch) { return; }
      if (owner !== authSession.sessionKey()) { return; }
      if (!response.ok) { this.setPageError(requested, response.describeFailure()); return; }
      if (response.data.page !== requested) { this.setPageError(requested, '返回页码不一致，请重试'); return; }
      const seen: Set<string> = new Set<string>();
      const next: SearchPostItem[] = requested === 1 ? [] : this.items.slice();
      for (const item of next) { seen.add(`${item.tid}:${item.pid}`); }
      const before: number = next.length;
      for (const item of response.data.items) {
        const key: string = `${item.tid}:${item.pid}`;
        if (!seen.has(key)) { seen.add(key); next.push(item); }
      }
      this.items = next;
      this.page = requested;
      this.hasMore = response.data.hasMore && next.length > before;
    } catch (err) {
      const e: Error = err as Error;
      if (epoch === this.requestEpoch && owner === authSession.sessionKey()) { this.setPageError(requested, `加载失败：${e.message}`); }
    }
  }

  private setPageError(requested: number, message: string): void {
    if (requested === 1) { this.errorText = message; } else { this.pagingError = message; }
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
    if (tab === TAB_USER) { void this.users.load(); }
  }

  /** 列表自己含顶部透明占位；状态页则在顶栏以下占满剩余空间。 */
  private showingList(): boolean {
    if (this.word.length === 0) { return false; }
    if (!this.scoped() && this.resultTab === TAB_USER) {
      return !this.users.loading && this.users.error.length === 0 && this.users.items.length > 0;
    }
    if (!this.scoped() && this.resultTab === TAB_FORUM) {
      return !this.forumLoading && this.forumErrorText.length === 0 && this.forumItems.length > 0;
    }
    return !this.loading && this.errorText.length === 0 && this.items.length > 0;
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Top }) {
        Column() {
          if (this.word.length === 0 && this.scoped()) {
            // 从吧页搜索入口进来时还没输入关键词：给一句明确的提示，不发必然为空的请求
            this.StatusView(searchEmptyHint(this.scopeForum))
          } else if (!this.scoped() && this.resultTab === TAB_USER) {
            if (this.users.loading) {
              PageState({ fillRemaining: true, message: '正在搜索…', loading: true }).layoutWeight(1)
            } else if (this.users.error.length > 0) {
              PageState({ fillRemaining: true, title: '搜索失败', message: this.users.error, actionLabel: '重试',
                onAction: (): void => { void this.users.load(true); } }).layoutWeight(1)
            } else if (this.users.items.length === 0) {
              PageState({ fillRemaining: true, message: `没有找到与「${this.word}」相关的用户` }).layoutWeight(1)
            } else {
              this.UserListTab()
            }
          } else if (!this.scoped() && this.resultTab === TAB_FORUM) {
            // 搜吧 tab：关键词相关的吧列表（模糊搜索，精确匹配排最前）
            if (this.forumLoading) {
              this.StatusView('正在搜索…')
            } else if (this.forumErrorText.length > 0) {
              this.ForumErrorView()
            } else if (this.forumItems.length === 0) {
              this.StatusView(`没有找到与「${this.word}」相关的吧`)
            } else {
              this.ForumListTab()
            }
          } else if (this.loading) {
            this.StatusView('正在搜索…')
          } else if (this.errorText.length > 0) {
            this.ErrorView()
          } else if (this.items.length === 0) {
            this.StatusView(searchNoResultText(this.scopeForum, this.word))
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
      ForEach(this.forumItems, (item: ForumSearchItem) => {
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
    PageState({ fillRemaining: true, title: '搜索失败', message: this.forumErrorText, actionLabel: '重试',
      onAction: (): void => { this.fetchForums(this.word); } }).layoutWeight(1)
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
      ForEach(this.users.items, (item: UserSearchItem) => {
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
        ListFooter({ loading: this.users.loadingMore, error: this.users.pagingError.length > 0 ? '加载失败' : '',
          hasMore: this.users.hasMore, onRetry: (): void => { void this.users.loadMore(true); } })
      }
    }
    .width('100%').layoutWeight(1).scrollBar(BarState.Off)
    .id('search-user-list')
    .onReachEnd(() => { void this.users.loadMore(); })
  }

  @Builder
  ResultList() {
    List({ space: 10 }) {
      ListItem() { Row().width('100%').height(Math.max(0, this.headerHeight + UiLayout.SEARCH_CONTENT_GAP - 10)) }
      ForEach(this.items, (item: SearchPostItem) => {
        ListItem() {
          ThreadPreviewCard({
            authorName: item.authorName,
            authorAvatar: this.postAvatars.urls.get(`author:${item.tid}:${item.pid}`) ?? '',
            forumName: item.forumName,
            forumAvatar: this.postAvatars.urls.get(`forum:${item.forumName}`) ?? '',
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
        .onAppear(() => { this.postAvatars.request(item.tid, item.pid, item.forumName); })
      }, (item: SearchPostItem) => `${item.tid}-${item.pid}`)

      ListItem() {
        this.PageFooter()
      }
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .onReachEnd(() => {
      this.loadMore();
    })
  }

  @Builder
  PageFooter() {
    ListFooter({ loading: this.loadingMore, error: this.pagingError.length > 0 ? '加载失败' : '',
      hasMore: this.hasMore, onRetry: (): void => { void this.loadMore(true); } })
  }

  @Builder
  StatusView(text: string) {
    PageState({ fillRemaining: true, message: text, loading: this.loading || this.forumLoading }).layoutWeight(1)
  }

  @Builder
  ErrorView() {
    PageState({ fillRemaining: true, title: '搜索失败', message: this.errorText, actionLabel: '重试',
      onAction: (): void => { this.reload(); } }).layoutWeight(1)
  }
}
