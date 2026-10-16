import { PullRefreshHeader, PULL_REFRESH_OFFSET } from '../components/RefreshSpinner';
import { common } from '@kit.AbilityKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { GlassBackButton } from '../components/GlassBackButton';
import { lowFlowStore } from '../common/appearance/LowFlowStore';
import { VideoFeedItem } from '../model/VideoFeed';
import { NavigationService } from '../navigation/AppNavigation';
import { AppTheme } from '../theme/Theme';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { VideoFeedVM } from '../viewmodel/VideoFeedVM';

@ComponentV2
export struct VideoFeedPage {
  @Local pullRefreshDragging: boolean = false;
  @Local vm: VideoFeedVM = new VideoFeedVM();
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;
  @Local refreshing: boolean = false;
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  aboutToAppear(): void {
    readStatusBarVp(this.context()).then((vp: number) => { this.statusBarH = vp; }).catch(() => {});
    void this.vm.refresh(this.context());
  }
  aboutToDisappear(): void { this.vm.dispose(); }
  private async reload(): Promise<void> { await this.vm.refresh(this.context()); this.refreshing = false; }
  private open(item: VideoFeedItem): void {
    const tid: number = Number(item.id);
    if (!Number.isSafeInteger(tid) || tid <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '帖子标识超出当前导航支持范围' }); return;
    }
    NavigationService.openThreadDetail({ tid: tid, forumName: item.forumName });
  }
  @Builder
  Card(item: VideoFeedItem) {
    Column({ space: 10 }) {
      if (item.clip.cover.length > 0) {
        if (lowFlowStore.enabled) {
          Text('低流量模式').width('100%').height(190).textAlign(TextAlign.Center)
            .fontSize(12).fontColor(AppTheme.TEXT_SUB).backgroundColor(AppTheme.SURFACE_MUTED).borderRadius(12)
        } else {
          Image(item.clip.cover).width('100%').height(190).objectFit(ImageFit.Cover).borderRadius(12)
        }
      }
      Text(item.title.length > 0 ? item.title : '视频帖').fontSize(16).fontColor(AppTheme.TEXT_MAIN)
        .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      if (item.authorName.length > 0 || item.forumName.length > 0) {
        Text([item.authorName, item.forumName.length > 0 ? (item.forumName.endsWith('吧') ? item.forumName : `${item.forumName}吧`) : ''].filter((value: string) => value.length > 0).join(' · '))
          .fontSize(12).fontColor(AppTheme.TEXT_SUB).width('100%')
      }
    }.width('100%').padding(14).backgroundColor(AppTheme.CARD).borderRadius(16)
      .onClick(() => { this.open(item); })
  }
  @Builder
  Footer() {
    if (this.vm.loadingMore) { Text('正在加载…').fontSize(14).fontColor(AppTheme.TEXT_SUB).padding(18) }
    else if (this.vm.moreError.length > 0) {
      Text(`${this.vm.moreError} · 点击重试`).fontSize(14).fontColor(AppTheme.ACCENT_DARK).padding(18)
        .onClick(() => { void this.vm.loadMore(this.context()); })
    } else {
      Text(this.vm.canContinue ? '上滑加载更多' : '本次没有新视频，可下拉刷新')
        .fontSize(14).fontColor(AppTheme.TEXT_SUB).padding(18)
    }
  }
  @Builder
  PullHeader() { PullRefreshHeader({ active: this.refreshing || this.pullRefreshDragging }) }

  build() {
    HdsNavDestination() {
      Column() {
        Row({ space: 14 }) {
          GlassBackButton({ onTap: (): void => { NavigationService.back(); } })
          Text('视频').fontSize(19).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT_MAIN)
        }.height(60).width('100%').padding({ left: 16, right: 16 })
        Refresh({ refreshing: $$this.refreshing, builder: (): void => { this.PullHeader(); } }) {
          List({ space: 10 }) {
            if (this.vm.error.length > 0) {
              ListItem() { Text(`${this.vm.error} · 点击重试`).fontColor(AppTheme.ACCENT_DARK).fontSize(14)
                .padding(20).onClick(() => { void this.reload(); }) }
            }
            if (this.vm.loading && !this.vm.loaded) { ListItem() { Text('正在加载…').fontColor(AppTheme.TEXT_SUB).padding(24) } }
            ForEach(this.vm.items, (item: VideoFeedItem) => { ListItem() { this.Card(item) } }, (item: VideoFeedItem) => item.id)
            if (this.vm.loaded && this.vm.items.length === 0 && this.vm.error.length === 0) {
              ListItem() { Text('暂无视频').fontColor(AppTheme.TEXT_SUB).padding(24) }
            }
            if (this.vm.loaded) { ListItem() { this.Footer() } }
          }.width('100%').height('100%').padding({ left: 12, right: 12, top: 8 }).scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring).onReachEnd(() => {
              if (this.vm.moreError.length === 0) { void this.vm.loadMore(this.context()); }
            })
        }.refreshOffset(PULL_REFRESH_OFFSET)
        .onStateChange((state: RefreshStatus) => {
          this.pullRefreshDragging = state === RefreshStatus.Drag || state === RefreshStatus.OverDrag;
        }).layoutWeight(1).onRefreshing(() => { void this.reload(); })
      }.width('100%').height('100%').padding({ top: this.statusBarH }).backgroundColor(AppTheme.BG)
    }.hideTitleBar(true)
  }
}
