/**
 * 设置里的官方黑名单全高列表面板：每条为独立圆角长条卡片，支持左滑红色圆形删除按钮解除，
 * 以及与「屏蔽吧」一致的多选批量解除。
 */
import { common } from '@kit.AbilityKit';
import { authSession } from '../auth/AuthSession';
import { SettingsLayout } from '../common/appearance/SettingsLayout';
import { ImBlacklistUser } from '../model/AuthorBlock';
import { portraitUrl } from '../model/ThreadDetail';
import { AppTheme } from '../theme/Theme';
import { threadBlockStore } from '../utils/ThreadBlockStore';
import { BlacklistVM } from '../viewmodel/BlacklistVM';
import { SettingsEntryRow, SettingsInfoRow, SettingsStatusKind, SettingsStatusLine } from './SettingsComponents';
import { SwipeDeleteButton } from './SwipeDeleteButton';

function resolveBlacklistAvatar(portrait: string): string {
  if (portrait.length === 0) { return ''; }
  if (portrait.startsWith('http://') || portrait.startsWith('https://')) { return portrait; }
  return portraitUrl(portrait);
}

@ComponentV2
export struct BlacklistPane {
  @Require @Param vm: BlacklistVM;
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
    void this.vm.load(this.context());
  }

  aboutToDisappear(): void {
    this.vm.dispose();
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
      const count: number = this.vm.preparedCount;
      const confirm = await this.getUIContext().getPromptAction().showDialog({
        title: '解除拉黑',
        message: count === 1
          ? '解除后对方的内容会重新出现，该操作会同步到贴吧账号。'
          : `将解除所选 ${count} 位用户的拉黑，对方的内容会重新出现，并同步到贴吧账号。`,
        buttons: [{ text: '取消', color: AppTheme.TEXT_SUB }, { text: '解除拉黑', color: AppTheme.DANGER_TEXT }]
      });
      if (confirm.index !== 1) { return; }
      if (!this.vm.ownsCurrentAccount() || owner !== authSession.sessionKey()) { return; }
      await this.vm.executePrepared(context);
      if (this.vm.ownsCurrentAccount() && threadBlockStore.usersSaveError.length > 0) {
        this.vm.actionMessage += `；${threadBlockStore.usersSaveError}`;
      }
      if (this.vm.ownsCurrentAccount() && this.vm.actionMessage.length > 0) {
        this.toast(this.vm.actionMessage);
      }
    } catch (err) {
      if (this.vm.ownsCurrentAccount()) { this.toast('操作已取消'); }
    } finally {
      this.vm.cancelPrepared();
    }
  }

  build() {
    List({ space: 10, scroller: this.scroller }) {
      ListItem() { Row().height(Math.max(0, this.topInset - 10)).width('100%') }
      if (this.vm.items.length === 0 && (this.vm.loading || (this.vm.loaded && this.vm.error.length === 0))) {
        ListItem() {
          SettingsInfoRow({ label: this.vm.loading ? '正在同步…' : '黑名单为空', showDivider: false })
        }.backgroundColor(AppTheme.CARD).borderRadius(SettingsLayout.CARD_RADIUS)
      }
      ForEach(this.vm.items, (user: ImBlacklistUser) => {
        ListItem() {
          this.UserCard(user)
        }
        .swipeAction({
          end: this.vm.selecting ? undefined : (): void => { this.DeleteSwipeAction(user); },
          edgeEffect: SwipeEdgeEffect.Spring
        })
      }, (user: ImBlacklistUser) => `u${user.uidText}:${user.displayName()}:${user.portrait}`)
      ListItem() {
        Column() {
          if (this.vm.error.length > 0) {
            SettingsStatusLine({
              kind: SettingsStatusKind.ERROR,
              message: this.vm.error,
              retryLabel: '重试',
              onRetry: (): void => { void this.vm.load(this.context()); }
            })
          }
          if (threadBlockStore.usersSaveError.length > 0) {
            SettingsStatusLine({ kind: SettingsStatusKind.ERROR, message: threadBlockStore.usersSaveError })
          }
          if (this.vm.actionMessage.length > 0) {
            SettingsStatusLine({ kind: SettingsStatusKind.LOADING, message: this.vm.actionMessage })
          }
        }.width('100%').padding({ bottom: SettingsLayout.PAGE_BOTTOM_GAP + (this.vm.selecting ? 84 : 0) })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: SettingsLayout.PAGE_GUTTER, right: SettingsLayout.PAGE_GUTTER })
    .scrollBar(BarState.Off)
    .onScroll(() => { this.onScrolled(); })
  }

  @Builder
  UserCard(user: ImBlacklistUser) {
    Row() {
      SettingsEntryRow({
        label: user.displayName(),
        summary: '',
        avatarUrl: resolveBlacklistAvatar(user.portrait),
        avatarName: user.displayName(),
        showChevron: false,
        showDivider: false,
        onTap: (): void => {
          if (this.vm.selecting) { this.vm.toggleItem(user.uidText); }
        }
      }).layoutWeight(1)
      if (this.vm.selecting) {
        Checkbox()
          .select(this.vm.isSelected(user.uidText))
          .width(20)
          .height(20)
          .selectedColor(AppTheme.ACCENT)
          .unselectedColor(AppTheme.TEXT_MUTED)
          .mark({ strokeColor: AppTheme.ON_ACCENT })
          .margin({ right: 16 })
          .enabled(!this.vm.actionBusy)
          .accessibilityText(`选择${user.displayName()}`)
          .onChange((selected: boolean) => {
            if (selected !== this.vm.isSelected(user.uidText)) { this.vm.toggleItem(user.uidText); }
          })
      }
    }
    .width('100%')
    .backgroundColor(AppTheme.CARD)
    .borderRadius(SettingsLayout.CARD_RADIUS)
    .clip(true)
    .enabled(!this.vm.actionBusy)
  }

  @Builder
  DeleteSwipeAction(user: ImBlacklistUser) {
    SwipeDeleteButton({
      accessibilityLabel: `解除拉黑${user.displayName()}`,
      buttonEnabled: !this.vm.actionBusy && !this.vm.loading,
      onTap: (): void => { void this.confirmUnblock([user.uidText]); }
    })
  }
}
