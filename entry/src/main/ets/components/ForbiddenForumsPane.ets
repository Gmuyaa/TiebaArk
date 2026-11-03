
import { AppTheme } from '../theme/Theme';
import { SettingsLayout } from '../common/appearance/SettingsLayout';
import { common } from '@kit.AbilityKit';
import { authSession } from '../auth/AuthSession';
import { ForbiddenForum } from '../model/ForbiddenForums';
import { ForbiddenForumsVM } from '../viewmodel/ForbiddenForumsVM';
import { threadBlockStore } from '../utils/ThreadBlockStore';
import { SettingsEntryRow, SettingsInfoRow, SettingsStatusKind, SettingsStatusLine } from './SettingsComponents';

@ComponentV2
export struct ForbiddenForumsPane {
  /** 页面顶栏刷新序号：自增即触发重读（初值 0 不触发） */
  @Param refreshSeq: number = 0;
  /** 页面「接近底部」序号：自增即请求下一页（初值 0 不触发） */
  @Param loadMoreSeq: number = 0;
  @Event onPageStarted: () => void = (): void => {};
  @Event onPageSettled: () => void = (): void => {};
  @Require @Param vm: ForbiddenForumsVM;
  @Param unblockSeq: number = 0;
  @Param scroller: Scroller = new Scroller();
  @Param topInset: number = 0;
  @Event onScrolled: () => void = (): void => {};

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  aboutToAppear(): void {
    this.reload();
  }

  aboutToDisappear(): void {
    this.vm.dispose();
  }

  /** 读服务端列表：分页未完只合并已知项，确认全部读完才覆盖镜像 */
  private reload(): void {
    this.vm.load(this.context(), false, (): void => {}, this.onPageSettled).then((): void => {
      this.syncMirror();
    });
  }

  private syncMirror(): void {
    if (!this.vm.loaded || this.vm.error.length > 0 || !this.vm.ownsCurrentAccount()) { return; }
    const names: string[] = [];
    for (const item of this.vm.items) {
      if (item.name.length > 0) { names.push(item.name); }
    }
    void threadBlockStore.replaceBlockedForums(this.context(), names, !this.vm.hasMore && !this.vm.stalled && this.vm.pagingError.length === 0);
  }

  @Monitor('refreshSeq')
  onRefreshRequested(): void {
    if (this.refreshSeq > 0) {
      this.vm.load(this.context(), false, (): void => {}, this.onPageSettled).then((): void => {
        this.syncMirror();
      });
    }
  }

  @Monitor('loadMoreSeq')
  onLoadMoreRequested(): void {
    if (this.loadMoreSeq > 0) {
      // 实际接受的分页由 VM 通知父页，忽略重复触发不发完成事件
      void this.vm.load(this.context(), true, this.onPageStarted, this.onPageSettled).then((): void => { this.syncMirror(); });
    }
  }

  @Monitor('unblockSeq')
  onUnblockRequested(): void {
    if (this.unblockSeq > 0) { void this.confirmUnblock(this.vm.selectedIds); }
  }

  private async confirmUnblock(ids: string[]): Promise<void> {
    if (this.vm.prepareItems(ids)) { await this.confirmPrepared(); }
  }

  private async confirmPrepared(): Promise<void> {
    const owner: string = authSession.sessionKey();
    const context: common.UIAbilityContext = this.context();
    try {
      const confirm = await this.getUIContext().getPromptAction().showDialog({
        title: '取消屏蔽',
        message: `将取消所选 ${this.vm.preparedCount} 个吧的屏蔽，相关帖子会重新出现在推荐与关注列表中，并同步到贴吧账号。`,
        buttons: [{ text: '取消', color: AppTheme.TEXT_SUB }, { text: '取消屏蔽', color: AppTheme.DANGER_TEXT }]
      });
      if (confirm.index !== 1) { return; }
      if (!this.vm.ownsCurrentAccount() || owner !== authSession.sessionKey()) { return; }
      await this.vm.executePrepared(context, async (items: ForbiddenForum[]): Promise<void> => {
        await threadBlockStore.forgetBlockedForums(context, items.map((item: ForbiddenForum): string => item.name));
      });
      if (this.vm.ownsCurrentAccount()) { this.toast(this.vm.actionMessage); }
    } catch (err) {
      if (this.vm.ownsCurrentAccount()) { this.toast('操作已取消'); }
    } finally {
      this.vm.cancelPrepared();
    }
  }

  build() {
    List({ scroller: this.scroller }) {
      ListItem() { Row().height(this.topInset).width('100%') }
      if (this.vm.items.length === 0 && (this.vm.loading || (this.vm.loaded && this.vm.error.length === 0))) {
        ListItem() {
          SettingsInfoRow({ label: this.vm.loading ? '正在读取…' : '账号暂无屏蔽吧', showDivider: false })
        }.backgroundColor(AppTheme.CARD).borderRadius(SettingsLayout.CARD_RADIUS)
      }
      Repeat<ForbiddenForum>(this.vm.items)
        .each((row: RepeatItem<ForbiddenForum>) => {
          ListItem() { this.ForumRow(row.item, row.index) }
            .backgroundColor(AppTheme.CARD)
            .borderRadius({ topLeft: row.index === 0 ? SettingsLayout.CARD_RADIUS : 0,
              topRight: row.index === 0 ? SettingsLayout.CARD_RADIUS : 0,
              bottomLeft: row.index === this.vm.items.length - 1 ? SettingsLayout.CARD_RADIUS : 0,
              bottomRight: row.index === this.vm.items.length - 1 ? SettingsLayout.CARD_RADIUS : 0 })
            .clip(true)
        })
        .key((item: ForbiddenForum): string => item.id)
        .virtualScroll({ reusable: false })
      ListItem() {
        Column() {
          if (this.vm.error.length > 0) {
            SettingsStatusLine({
              kind: SettingsStatusKind.ERROR,
              message: this.vm.error,
              retryLabel: '重试',
              onRetry: (): void => { this.reload(); }
            })
          }
          this.BottomState()
          if (this.vm.actionMessage.length > 0) {
            SettingsStatusLine({ kind: SettingsStatusKind.LOADING, message: this.vm.actionMessage })
          }
        }.width('100%').padding({ bottom: SettingsLayout.PAGE_BOTTOM_GAP + (this.vm.selecting ? 84 : 0) })
      }
    }
    .width('100%').height('100%').padding({ left: SettingsLayout.PAGE_GUTTER, right: SettingsLayout.PAGE_GUTTER })
    .scrollBar(BarState.Off).cachedCount(2)
    .onScroll(() => { this.onScrolled(); })
    .onReachEnd(() => {
      void this.vm.load(this.context(), true, this.onPageStarted, this.onPageSettled).then((): void => { this.syncMirror(); });
    })
  }

  @Builder
  ForumRow(item: ForbiddenForum, index: number) {
    Row() {
      SettingsEntryRow({
        label: item.name.length > 0 ? (item.name.endsWith('吧') ? item.name : `${item.name}吧`) : '吧名未返回',
        summary: this.vm.selecting ? '' : '取消屏蔽',
        avatarUrl: item.avatar, avatarName: item.name,
        showChevron: false,
        showDivider: index < this.vm.items.length - 1,
        onTap: (): void => {
          if (this.vm.selecting) { this.vm.toggleItem(item.id); }
          else { void this.confirmUnblock([item.id]); }
        }
      }).layoutWeight(1)
      if (this.vm.selecting) {
        Checkbox().select(this.vm.isSelected(item.id)).width(20).height(20)
          .margin({ right: 16 }).enabled(!this.vm.actionBusy)
          .accessibilityText(`选择${item.name}`)
          .onChange((selected: boolean) => {
            if (selected !== this.vm.isSelected(item.id)) { this.vm.toggleItem(item.id); }
          })
      }
    }.width('100%').enabled(!this.vm.actionBusy)
  }

  @Builder
  BottomState() {
    if (this.vm.items.length > 0) {
      Row() {
        if (this.vm.loadingMore) {
          Text('正在加载…').fontSize(SettingsLayout.SUB_SIZE).fontColor(AppTheme.NOTE_TEXT)
        } else if (this.vm.pagingError.length > 0) {
          Text('加载失败，点击重试').fontSize(SettingsLayout.SUB_SIZE).fontColor(AppTheme.ACCENT)
            .onClick(() => {
              // 手动重试：清错误并请求失败的那一页（自动触底在失败期间是暂停的）
              void this.vm.retryPaging(this.context()).then((): void => { this.syncMirror(); });
            })
        } else if (this.vm.hasMore) {
          Text('点击加载更多').fontSize(SettingsLayout.SUB_SIZE).fontColor(AppTheme.ACCENT)
            .onClick(() => { void this.vm.load(this.context(), true, this.onPageStarted, this.onPageSettled).then((): void => { this.syncMirror(); }); })
        } else if (this.vm.stalled) {
          Text('暂时无法加载更多').fontSize(SettingsLayout.SUB_SIZE).fontColor(AppTheme.NOTE_TEXT)
        } else if (!this.vm.hasMore && this.vm.loaded) {
          Text('已全部加载').fontSize(SettingsLayout.SUB_SIZE).fontColor(AppTheme.NOTE_TEXT)
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 16 })
    }
  }
}
