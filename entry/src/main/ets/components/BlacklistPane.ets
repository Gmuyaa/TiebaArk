/**
 * 设置里的官方黑名单全高列表面板：每条为独立圆角长条卡片，支持左滑红色圆形删除按钮解除，
 * 以及与「屏蔽吧」一致的多选批量解除。
 */
import { common } from '@kit.AbilityKit';
import { authSession } from '../auth/AuthSession';
import { SettingsLayout } from '../common/appearance/SettingsLayout';
import { AuthorBlockScope, ImBlacklistUser } from '../model/AuthorBlock';
import { portraitUrl } from '../model/ThreadDetail';
import { AppTheme } from '../theme/Theme';
import { threadBlockStore } from '../utils/ThreadBlockStore';
import { BlacklistVM } from '../viewmodel/BlacklistVM';
import {
  SettingsCard, SettingsEntryRow, SettingsInfoRow, SettingsStatusKind, SettingsStatusLine, SettingsSwitchRow
} from './SettingsComponents';
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
  @Local sheetOpen: boolean = false;
  @Local editingUser: ImBlacklistUser | undefined = undefined;
  @Local draftFollow: boolean = true;
  @Local draftInteract: boolean = true;
  @Local draftChat: boolean = true;
  @Local savingScope: boolean = false;

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

  private async openScopeEditor(user: ImBlacklistUser): Promise<void> {
    if (this.vm.selecting || this.vm.actionBusy || this.vm.loading || this.savingScope || user.uid <= 0) {
      return;
    }
    if (!user.scopeKnown) {
      const err: string = await this.vm.fetchUserScope(this.context(), user);
      if (err.length > 0) {
        this.toast(err);
        return;
      }
    }
    this.editingUser = user;
    this.draftFollow = user.follow;
    this.draftInteract = user.interact;
    this.draftChat = user.chat;
    this.sheetOpen = true;
  }

  private scopeChanged(): boolean {
    if (this.editingUser === undefined) { return false; }
    return this.draftFollow !== this.editingUser.follow
      || this.draftInteract !== this.editingUser.interact
      || this.draftChat !== this.editingUser.chat;
  }

  private async saveScope(): Promise<void> {
    const target: ImBlacklistUser | undefined = this.editingUser;
    if (target === undefined || this.savingScope || !this.scopeChanged()) { return; }
    const nextScope: AuthorBlockScope = AuthorBlockScope.fromFlags(
      this.draftFollow, this.draftInteract, this.draftChat);
    this.savingScope = true;
    try {
      const err: string = await this.vm.updateUserScope(this.context(), target, nextScope);
      if (err.length > 0) {
        if (target.scopeKnown) {
          this.draftFollow = target.follow;
          this.draftInteract = target.interact;
          this.draftChat = target.chat;
        }
        this.toast(err);
        return;
      }
      this.sheetOpen = false;
      this.editingUser = undefined;
      this.toast(nextScope.any() ? '已更新拉黑范围' : `已解除对 ${target.displayName()} 的拉黑`);
    } finally {
      this.savingScope = false;
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
      }, (user: ImBlacklistUser) => `u${user.uidText}:${user.displayName()}:${user.portrait}:${user.scopeKey()}`)
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
    .onDidScroll(() => { this.onScrolled(); })
    .bindSheet($$this.sheetOpen, this.ScopeSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: false,
      showClose: false,
      backgroundColor: AppTheme.BG,
      onWillDismiss: (action: DismissSheetAction): void => {
        if (!this.savingScope) { action.dismiss(); }
      },
      onDisappear: (): void => {
        if (!this.savingScope) { this.editingUser = undefined; }
      }
    })
  }

  @Builder
  ScopeSheet() {
    Column() {
      Row() {
        Text(this.editingUser !== undefined ? this.editingUser.displayName() : '拉黑范围')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_MAIN)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(20).maxFontScale(1)
          .fontColor([AppTheme.TEXT_SUB])
          .padding(6)
          .onClick((): void => {
            if (!this.savingScope) { this.sheetOpen = false; }
          })
      }
      .width('100%')
      .padding({ left: 4, right: 0, bottom: 12 })

      SettingsCard({
        content: (): void => {
          this.ScopeSwitchRows();
        }
      })

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .fontSize(SettingsLayout.LABEL_SIZE)
          .fontColor(AppTheme.TEXT_MAIN)
          .backgroundColor(AppTheme.CARD)
          .borderRadius(SettingsLayout.CARD_RADIUS)
          .enabled(!this.savingScope)
          .onClick((): void => { this.sheetOpen = false; })

        Button(this.savingScope ? '正在保存…' : (!this.draftFollow && !this.draftInteract && !this.draftChat ? '解除拉黑' : '保存'))
          .layoutWeight(1)
          .height(42)
          .fontSize(SettingsLayout.LABEL_SIZE)
          .fontColor(!this.draftFollow && !this.draftInteract && !this.draftChat ? AppTheme.DANGER_TEXT : AppTheme.ON_ACCENT)
          .backgroundColor(!this.draftFollow && !this.draftInteract && !this.draftChat ? AppTheme.CARD : AppTheme.ACCENT)
          .borderRadius(SettingsLayout.CARD_RADIUS)
          .enabled(!this.savingScope && this.scopeChanged())
          .opacity(!this.savingScope && this.scopeChanged() ? 1 : 0.45)
          .onClick((): void => { void this.saveScope(); })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
    .padding({
      left: SettingsLayout.PAGE_GUTTER, right: SettingsLayout.PAGE_GUTTER,
      top: 16, bottom: SettingsLayout.PAGE_BOTTOM_GAP
    })
  }

  @Builder
  ScopeSwitchRows() {
    SettingsSwitchRow({
      label: '禁止关注',
      checked: this.draftFollow,
      interactionEnabled: !this.savingScope,
      onToggle: (next: boolean): void => { this.draftFollow = next; }
    })
    SettingsSwitchRow({
      label: '禁止互动',
      checked: this.draftInteract,
      interactionEnabled: !this.savingScope,
      onToggle: (next: boolean): void => { this.draftInteract = next; }
    })
    SettingsSwitchRow({
      label: '禁止私信',
      checked: this.draftChat,
      interactionEnabled: !this.savingScope,
      showDivider: false,
      onToggle: (next: boolean): void => { this.draftChat = next; }
    })
  }

  @Builder
  UserCard(user: ImBlacklistUser) {
    Row() {
      SettingsEntryRow({
        label: user.displayName(),
        sub: user.scopeLabel(),
        summary: '',
        avatarUrl: resolveBlacklistAvatar(user.portrait),
        avatarName: user.displayName(),
        showChevron: false,
        showDivider: false,
        onTap: (): void => {
          if (this.vm.selecting) {
            this.vm.toggleItem(user.uidText);
          } else {
            void this.openScopeEditor(user);
          }
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
