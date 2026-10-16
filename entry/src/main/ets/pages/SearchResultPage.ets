

import { common } from '@kit.AbilityKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { TiebaApi } from '../api/TiebaApi';
import { SearchPostItem, searchEmptyHint, searchNoResultText, searchPlaceholder, searchScopeForum,
  searchScopeLabel } from '../model/SearchPost';
import { ForumSearchItem } from '../model/ForumSearch';
import { formatPostTime } from '../model/HomeFeedPresentation';
import { TiebaDevice } from '../net/TiebaParams';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { authSession } from '../auth/AuthSession';
import { AppTheme } from '../theme/Theme';
import { GlassBackButton } from '../components/GlassBackButton';
import { ForumAvatarImage, forumAvatarRadius } from '../components/ForumAvatarImage';
import { ThreadPreviewCard } from '../components/ThreadPreviewCard';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { addSearchHistory } from '../utils/SearchHistory';
import { NavigationService, SearchResultParams } from '../navigation/AppNavigation';

const SEARCH_PAGE_SIZE: number = 30;

const TAB_FORUM: number = 0;
const TAB_POST: number = 1;

@ComponentV2
export struct SearchResultPage {

  @Param routeParams: SearchResultParams | undefined = undefined;

  @Local word: string = '';

  @Local items: SearchPostItem[] = [];

  @Local loading: boolean = false;
  @Local loadingMore: boolean = false;
  @Local hasMore: boolean = false;

  @Local errorText: string = '';
  @Local pagingError: string = '';

  private page: number = 0;

  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;

  private cardScroller: ListScroller = new ListScroller();

  @Local input: string = '';

  @Local resultTab: number = TAB_FORUM;

  @Local scopeForum: string = '';

  @Local forumItems: ForumSearchItem[] = [];
  @Local forumLoading: boolean = false;
  @Local forumErrorText: string = '';

  private requestEpoch: number = 0;
  aboutToDisappear(): void { this.requestEpoch++; }

  private api: TiebaApi = new TiebaApi();

  aboutToAppear(): void {

    let keyword: string = '';
    if (this.routeParams !== undefined && this.routeParams.word !== undefined) {
      keyword = this.routeParams.word.trim();
    }
    this.scopeForum = searchScopeForum(this.routeParams === undefined
      ? undefined : this.routeParams.forumName);

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

    });
    if (this.word.length > 0) {
      this.reload();
    }
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async reload(): Promise<void> {
    const word: string = this.input.trim();
    if (word.length === 0) {
      return;
    }
    const epoch: number = ++this.requestEpoch;
    this.loadingMore = false;
    this.forumItems = [];
    this.word = word;
    this.loading = true;
    this.errorText = ''; this.pagingError = '';
    this.page = 0;
    this.items = [];
    this.hasMore = false;

    await addSearchHistory(this.hostContext(), word).catch(() => {

    });
    if (epoch !== this.requestEpoch) { return; }

    if (this.scopeForum.length === 0) {
      this.fetchForums(word, epoch);
    }
    await this.fetchPage(word, epoch);
    if (epoch === this.requestEpoch) { this.loading = false; }
  }

  private scoped(): boolean {
    return this.scopeForum.length > 0;
  }

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

    return formatPostTime(item.timeMs, Date.now());
  }

  private goBack(): void {
    NavigationService.back();
  }

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

  build() {

    HdsNavDestination() {
      Column() {
        this.TopBar()
        if (this.scoped()) {

          this.ScopeLabel()
        } else {
          this.ResultTabs()
        }

        if (this.word.length === 0 && this.scoped()) {

          this.StatusView(searchEmptyHint(this.scopeForum))
        } else if (!this.scoped() && this.resultTab === TAB_FORUM) {

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
      .width('100%')
      .height('100%')
      .padding({ left: 24, right: 24, top: this.statusBarH + 12 })
      .backgroundColor(AppTheme.CARD)
      .alignItems(HorizontalAlign.Start)
    }

    .hideTitleBar(true)
  }

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

  @Builder
  ResultTabs() {
    Row({ space: 0 }) {
      this.ResultTabItem('搜吧', TAB_FORUM)
      this.ResultTabItem('搜帖子', TAB_POST)
    }
    .width('100%')
    .height(44)
    .borderRadius(22)
    .backgroundColor(AppTheme.BG)
    .padding(4)
    .margin({ top: 4, bottom: 12 })
  }

  @Builder
  ResultTabItem(label: string, tabIndex: number) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.resultTab === tabIndex ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.resultTab === tabIndex ? AppTheme.TEXT_MAIN : AppTheme.TEXT_SUB)
      .textAlign(TextAlign.Center)
      .height(36)
      .layoutWeight(1)
      .borderRadius(18)
      .backgroundColor(this.resultTab === tabIndex ? AppTheme.CARD : Color.Transparent)
      .onClick(() => {
        this.resultTab = tabIndex;
      })
  }

  @Builder
  ForumListTab() {
    List({ space: 10 }) {
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
                if (item.isOfficial) {
                  Text('官方')
                    .fontSize(10)
                    .fontColor(AppTheme.ACCENT_DARK)
                    .backgroundColor(AppTheme.ACCENT_LIGHT)
                    .borderRadius(4)
                    .padding({ left: 4, right: 4, top: 1, bottom: 1 })
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
          .backgroundColor(AppTheme.BG)
          .onClick(() => {
            this.openForumPage(item.forumName);
          })
        }
      }, (item: ForumSearchItem) => `${item.forumId}-${item.forumName}`)

      ListItem() {
        Column().width('100%').height(AppTheme.BAR_TOTAL_H)
      }
    }
    .width('100%')

    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  ForumErrorView() {
    Column({ space: 10 }) {
      Text('搜索失败')
        .fontSize(15)
        .fontColor(AppTheme.TEXT_MAIN)
      Text(this.forumErrorText)
        .fontSize(12)
        .fontColor(AppTheme.TEXT_SUB)
        .textAlign(TextAlign.Center)
      Text('点击重试')
        .fontSize(13)
        .fontColor(AppTheme.ACCENT_DARK)
        .onClick(() => {
          this.fetchForums(this.word);
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  TopBar() {
    Row({ space: 14 }) {

      GlassBackButton({
        onTap: (): void => {
          this.goBack();
        }
      })

      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(19)
          .fontColor([AppTheme.ICON])
        TextInput({ text: this.input, placeholder: searchPlaceholder(this.scopeForum) })
          .fontSize(16)
          .placeholderColor(AppTheme.TEXT_SUB)
          .placeholderFont({ size: 16 })
          .height(54)
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .padding(0)
          .onSubmit(() => {
            this.reload();
          })
          .onChange((value: string) => {
            this.input = value;
          })
      }
      .layoutWeight(1)
      .height(54)
      .borderRadius(27)
      .backgroundColor(AppTheme.BG)
      .padding({ left: 18, right: 18 })
      .shadow({ radius: 10, color: '#0A000000', offsetY: 2 })
    }
    .width('100%')
    .margin({ top: 10, bottom: 16 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  ResultList() {
    List({ space: 10 }) {
      ForEach(this.items, (item: SearchPostItem) => {
        ListItem() {
          ThreadPreviewCard({
            authorName: item.authorName, authorAvatar: '',

            forumName: item.forumName, forumAvatar: '',
            postedTime: this.resultTimeText(item),
            title: item.displayTitle(),
            summary: item.snippet === item.displayTitle() ? '' : item.snippet,
            images: [],
            menu: [],
            imageScroller: this.cardScroller,
            onOpenThread: (): void => { this.openThread(item); }
          })
        }
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
    Column({ space: 8 }) {
      if (this.loadingMore) {
        Text('正在加载更多…')
          .fontSize(12)
          .fontColor(AppTheme.TEXT_SUB)
      } else if (this.pagingError.length > 0) {
        Text('加载失败，点击重试').fontSize(12).fontColor(AppTheme.ACCENT)
          .onClick(() => { void this.loadMore(true); })
      } else if (!this.hasMore) {
        Text('已经到底了')
          .fontSize(12)
          .fontColor(AppTheme.TEXT_MUTED)
      }
    }
    .width('100%')

    .padding({ top: 14, bottom: AppTheme.BAR_TOTAL_H })
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
  ErrorView() {
    Column({ space: 10 }) {
      Text('搜索失败')
        .fontSize(15)
        .fontColor(AppTheme.TEXT_MAIN)
      Text(this.errorText)
        .fontSize(12)
        .fontColor(AppTheme.TEXT_SUB)
        .textAlign(TextAlign.Center)
      Text('点击重试')
        .fontSize(13)
        .fontColor(AppTheme.ACCENT_DARK)
        .onClick(() => {
          this.reload();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }
}
