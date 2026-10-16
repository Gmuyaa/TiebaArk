import { PullRefreshHeader, PULL_REFRESH_OFFSET } from '../components/RefreshSpinner';

import { common } from '@kit.AbilityKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { AvatarComponent } from '../components/AvatarComponent';
import { GlassBackButton } from '../components/GlassBackButton';
import { NotifyItem, NotifyKind } from '../model/Notify';
import { NavigationService, NotifyListParams } from '../navigation/AppNavigation';
import { AppTheme } from '../theme/Theme';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { NotifyVM } from '../viewmodel/NotifyVM';

export function notifyPageTitle(kind: NotifyKind): string {
  if (kind === 'at') { return '@我的'; }
  return kind === 'reply' ? '回复我的' : '赞我的';
}

@ComponentV2
export struct NotifyListPage {
  @Local pullRefreshDragging: boolean = false;
  @Param routeParams: NotifyListParams | undefined = undefined;

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

    this.vm = new NotifyVM(this.kind);
    readStatusBarVp(this.context()).then((vp: number) => { this.statusBarH = vp; }).catch(() => {});
    void this.vm.refresh(this.context());
  }

  aboutToDisappear(): void { this.vm.dispose(); }

  private async reload(): Promise<void> {
    await this.vm.refresh(this.context());
    this.refreshing = false;
  }

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
        Row({ space: 14 }) {
          GlassBackButton({ onTap: (): void => { NavigationService.back(); } })
          Text(notifyPageTitle(this.kind))
            .fontSize(19).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT_MAIN)
            .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.height(60).width('100%').padding({ left: 16, right: 16 })

        Refresh({ refreshing: $$this.refreshing, builder: (): void => { this.PullHeader(); } }) {
          List({ space: 10, scroller: this.scroller }) {
            if (this.vm.error.length > 0) {
              ListItem() {
                Text(`${this.vm.error} · 点击重试`).fontColor(AppTheme.ACCENT_DARK).fontSize(14)
                  .padding(20).width('100%').onClick(() => { void this.reload(); })
              }
            }
            if (!this.vm.loadedOnce && this.vm.loading) {
              ListItem() { Text('正在加载…').fontColor(AppTheme.TEXT_SUB).padding(24) }
            } else {
              ForEach(this.vm.items, (item: NotifyItem) => {
                ListItem() { this.NotifyRow(item) }
              }, (item: NotifyItem) => `${item.kind}-${item.threadIdText || item.threadId}-${item.postIdText || item.postId}-${item.userIdText || item.userId}-${item.timeMs}`)
              if (!this.vm.hasItems() && this.vm.error.length === 0) {
                ListItem() { Text('还没有通知').fontColor(AppTheme.TEXT_SUB).padding(24) }
              }
              ListItem() { this.PageFooter() }
            }

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

  @Builder
  PageFooter() {
    Column({ space: 7 }) {
      if (this.vm.loadingMore) {
        Text('正在加载更多…').fontSize(12).fontColor(AppTheme.TEXT_SUB)
      } else if (this.vm.loadMoreError.length > 0) {
        Text(`${this.vm.loadMoreError} · 点击重试`).fontSize(12).fontColor(AppTheme.ACCENT_DARK)
          .onClick(() => { void this.vm.loadMore(this.context()); })
      } else if (!this.vm.hasMore && this.vm.loadedOnce && this.vm.hasItems()) {
        Text('已经到底了').fontSize(12).fontColor(AppTheme.TEXT_MUTED)
      }
    }
    .width('100%')
    .padding({ top: 14 })
    .justifyContent(FlexAlign.Center)
  }

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
