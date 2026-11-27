import { common } from '@kit.AbilityKit';
import { authSession } from '../auth/AuthSession';
import { SavedAccount } from '../auth/AccountRosterStore';
import { LoginResult } from '../auth/AuthModel';
import { portraitUrl } from '../model/ThreadDetail';
import { AppTheme } from '../theme/Theme';
import { SettingsLayout } from '../common/appearance/SettingsLayout';
import { AvatarComponent } from './AvatarComponent';
import { SettingsActionRow, SettingsCard } from './SettingsComponents';

@ComponentV2
export struct AccountSwitcherCard {
  @Param marginTop: number = SettingsLayout.GROUP_GAP;
  @Event onAddAccount: () => void = (): void => {};

  @Local busyUid: number = 0;

  aboutToAppear(): void {
    authSession.refreshSavedAccounts(this.hostContext());
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(message: string): void {
    try { this.getUIContext().getPromptAction().showToast({ message }); } catch (_) {}
  }

  private isCurrent(account: SavedAccount): boolean {
    return authSession.snapshot.isLoggedIn() && authSession.snapshot.uid === account.uid;
  }

  private async handleSwitch(account: SavedAccount): Promise<void> {
    if (this.busyUid > 0 || authSession.switchingAccount || this.isCurrent(account)) { return; }
    this.busyUid = account.uid;
    try {
      const result: LoginResult = await authSession.switchAccount(this.hostContext(), account.uid);
      if (!result.ok) {
        this.toast(result.message);
        return;
      }
      this.toast(`已切换到 ${account.displayName()}`);
    } finally {
      this.busyUid = 0;
    }
  }

  private async confirmRemove(account: SavedAccount): Promise<void> {
    if (this.busyUid > 0 || authSession.switchingAccount || this.isCurrent(account)) { return; }
    try {
      const res = await this.getUIContext().getPromptAction().showDialog({
        title: '移除已保存账号',
        message: `将从本机安全存储中删除「${account.displayName()}」的登录凭据，下次切换需重新登录。`,
        buttons: [
          { text: '取消', color: '#666666' },
          { text: '移除', color: '#E53935' }
        ]
      });
      if (res.index !== 1) { return; }
    } catch (_) {
      return;
    }
    const result = await authSession.removeSavedAccount(this.hostContext(), account.uid);
    this.toast(result.ok ? '已移除账号' : result.message);
  }

  @Builder
  AccountRows() {
    ForEach(authSession.savedAccounts, (account: SavedAccount, index: number) => {
      if (index > 0) {
        Divider()
          .color(AppTheme.DIVIDER)
          .strokeWidth(0.5)
          .margin({ left: SettingsLayout.ROW_PAD_L })
      }
      Row({ space: 12 }) {
        AvatarComponent({
          url: account.portrait.length > 0 ? portraitUrl(account.portrait) : '',
          avatarSize: 36,
          fallbackName: account.displayName(),
          traceTag: 'account-switcher'
        })
        Column({ space: 2 }) {
          Text(account.displayName())
            .fontSize(SettingsLayout.TITLE_SIZE)
            .fontColor(AppTheme.TEXT_MAIN)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(account.userName.length > 0 ? `@${account.userName}` : `UID ${account.uid}`)
            .fontSize(12)
            .fontColor(AppTheme.TEXT_MUTED)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.isCurrent(account)) {
          Text('当前使用')
            .fontSize(12)
            .fontColor(AppTheme.ACCENT)
        } else if (this.busyUid === account.uid) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(AppTheme.ACCENT)
        } else {
          Row({ space: 12 }) {
            Text('切换')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.ACCENT)
              .onClick((): void => { void this.handleSwitch(account); })
            Text('移除')
              .fontSize(13)
              .fontColor(AppTheme.TEXT_MUTED)
              .onClick((): void => { void this.confirmRemove(account); })
          }
        }
      }
      .width('100%')
      .padding({
        left: SettingsLayout.ROW_PAD_L,
        right: SettingsLayout.ROW_PAD_R,
        top: 11,
        bottom: 11
      })
      .alignItems(VerticalAlign.Center)
    }, (account: SavedAccount) => `${account.uid}_${account.savedAt}_${authSession.snapshot.uid}_${this.busyUid}`)

    if (authSession.savedAccounts.length > 0) {
      Divider()
        .color(AppTheme.DIVIDER)
        .strokeWidth(0.5)
        .margin({ left: SettingsLayout.ROW_PAD_L })
    }

    SettingsActionRow({
      label: '添加账号',
      onTap: (): void => { this.onAddAccount(); }
    })
  }

  build() {
    SettingsCard({
      marginTop: this.marginTop,
      content: (): void => { this.AccountRows(); }
    })
  }
}
