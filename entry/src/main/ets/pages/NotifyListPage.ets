import { PageState, ListFooter } from '../components/PageState';
import { PullRefreshHeader, PULL_REFRESH_OFFSET } from '../components/RefreshSpinner';

import { common } from '@kit.AbilityKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { AvatarComponent } from '../components/AvatarComponent';
import { PageHeader } from '../components/PageHeader';
import { NotifyItem, NotifyKind } from '../model/Notify';
import { NavigationService, NotifyListParams } from '../navigation/AppNavigation';
import { AppTheme } from '../theme/Theme';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { NotifyVM } from '../viewmodel/NotifyVM';

/** kind → 页面标题（也是唯一被消费的文案真值源） */
export function notifyPageTitle(kind: NotifyKind): string {
  if (kind === 'at') { return '@我的'; }
  return kind === 'reply' ? '回复我的' : '赞我的';
}

@ComponentV2
export struct NotifyListPage {
  @Local pullRefreshDragging: boolean = false;
  @Param routeParams: NotifyListParams | undefined = undefined;
  /** kind 只在 aboutToAppear 解析一次（同 MyListPage 的 parseKind 约定） */
  @Local kind: NotifyKind = 'reply';
  @Local vm: NotifyVM = new NotifyVM('reply');
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;
  @Local refreshing: boolean = false;
  private scroller: ListScroller = new ListScroller();

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    const kind: string = this.routeParams?.kind ?? 'reply';
    this.kind = kind === 'at' ? 'at' : kind === 'agree' ? 'agree' : 'reply';
    // kind 只解析一次，VM 与之同生（运行中不切换种类）
    this.vm = new NotifyVM(this.kind);
    readStatusBarVp(this.context()).then((vp: number) => { this.statusBarH = vp; }).catch(() => {});
    void this.vm.refresh(this.context());
  }

  aboutToDisappear(): void { this.vm.dispose(); }

  private async reload(): Promise<void> {
    await this.vm.refresh(this.context());
    this.refreshing = false;
  }

  /** 点一条通知进帖子：带 targetPid（回复我=被回的那楼；赞我=被赞的楼，主题帖被赞则不带） */
  private openTarget(item: NotifyItem): void {
    if (item.kind === 'at' && (item.threadId === 0 || (item.postIdText.length > 0 && item.postId === 0))) {
      this.getUIContext().getPromptAction().showToast({ message: '帖子标识超出当前导航支持范围' }); return;
    }
    if (item.threadId <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '这条通知没有可跳转的帖子' });
      return;
    }
    NavigationService.openThreadDetail({
      tid: item.threadId,
      targetPid: item.postId > 0 ? item.postId : undefined,
      forumName: item.forumName
    });
  }

  /** 通知行主文案：谁、做了什么、在哪（不编造：字段缺失就少显示一段） */
  private lineOf(item: NotifyItem): string {
    const parts: string[] = [];
    if (item.excerpt.length > 0) { parts.push(item.excerpt); }
    else if (item.quoteContent.length > 0) { parts.push(item.quoteContent); }
    if (item.forumName.length > 0) { parts.push(`来自 ${item.forumName}吧`); }
    return parts.join(' · ');
  }

  @Builder
  PullHeader() { PullRefreshHeader({ active: this.refreshing || this.pullRefreshDragging }) }

  build() {
    HdsNavDestination() {
      Column() {
        PageHeader({ title: notifyPageTitle(this.kind), onBack: (): void => { NavigationService.back(); } })
        Refresh({ refreshing: $$this.refreshing, builder: (): void => { this.PullHeader(); } }) {
          List({ space: 10, scroller: this.scroller }) {
            if (this.vm.error.length > 0) {
              ListItem() {
                PageState({ compact: true, title: '加载失败', message: this.vm.error, actionLabel: '重试',
                  onAction: (): void => { void this.reload(); } })
              }
            }
            if (!this.vm.loadedOnce && this.vm.loading) {
              ListItem() { PageState({ loading: true, message: '正在加载…' }) }
            } else {
              ForEach(this.vm.items, (item: NotifyItem) => {
                ListItem() { this.NotifyRow(item) }
              }, (item: NotifyItem) => `${item.kind}-${item.threadIdText || item.threadId}-${item.postIdText || item.postId}-${item.userIdText || item.userId}-${item.timeMs}`)
              if (!this.vm.hasItems() && this.vm.error.length === 0) {
                ListItem() { PageState({ message: '还没有通知' }) }
              }
              ListItem() { this.PageFooter() }
            }
          /*
           * 底部**不留**安全区留白（全站列表同口径，见 AGENTS.md）。
           */
          }.width('100%').height('100%').padding({ left: 12, right: 12, top: 8 })
          .edgeEffect(EdgeEffect.Spring)
          .scrollBar(BarState.Off)
          .onReachEnd(() => { void this.vm.loadMore(this.context()); })
        }.refreshOffset(PULL_REFRESH_OFFSET)
        .onStateChange((state: RefreshStatus) => {
          this.pullRefreshDragging = state === RefreshStatus.Drag || state === RefreshStatus.OverDrag;
        }).layoutWeight(1).onRefreshing(() => {
          void this.reload();
        })
      }.width('100%').height('100%').padding({ top: this.statusBarH }).backgroundColor(AppTheme.BG)
    }.hideTitleBar(true)
  }

  /** 尾部：加载更多 / 失败重试 / 到底了（与全站列表页同构） */
  @Builder
  PageFooter() {
    if (this.vm.hasItems()) {
      ListFooter({ loading: this.vm.loadingMore, error: this.vm.loadMoreError, hasMore: this.vm.hasMore,
        onRetry: (): void => { void this.vm.loadMore(this.context()); } })
    }
  }

  /** 一条通知：头像 + 名字 + 内容行 + 时间（右侧箭头可进帖子） */
  @Builder
  NotifyRow(item: NotifyItem) {
    Row({ space: 12 }) {
      AvatarComponent({ url: item.avatar, avatarSize: 42, fallbackName: item.displayName() })
      Column({ space: 5 }) {
        Row({ space: 6 }) {
          Text(item.displayName())
            .fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT_MAIN)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(item.headline())
            .fontSize(13).fontColor(AppTheme.TEXT_SUB)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        if (this.lineOf(item).length > 0) {
          Text(this.lineOf(item))
            .fontSize(13).fontColor(AppTheme.TEXT_MAIN).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }
        if (item.timeMs > 0) {
          Text(this.timeText(item.timeMs))
            .fontSize(11).fontColor(AppTheme.TEXT_MUTED)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([AppTheme.ARROW_ROW])
    }
    .width('100%').padding(14)
    .borderRadius(AppTheme.CARD_RADIUS).backgroundColor(AppTheme.CARD)
    .onClick(() => { this.openTarget(item); })
  }

  /** 时间文案：今天显示时分，其余显示月-日（与帖子卡片的口径一致，不引入新依赖） */
  private timeText(timeMs: number): string {
    const date: Date = new Date(timeMs);
    const now: Date = new Date();
    const sameDay: boolean = date.getFullYear() === now.getFullYear()
      && date.getMonth() === now.getMonth() && date.getDate() === now.getDate();
    const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    if (sameDay) {
      return `${pad(date.getHours())}:${pad(date.getMinutes())}`;
    }
    return `${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
  }
}
