/** “我的”页多账号快捷切换居中弹窗，复用 AuthSession 名册与官方沉浸材质。 */

import { promptAction } from '@kit.ArkUI';
import { authSession } from '../auth/AuthSession';
import { AuthSnapshot } from '../auth/AuthModel';
import { SavedAccount } from '../auth/AccountRosterStore';
import { motionEdgeEffect, popupMotion } from '../common/appearance/MotionPolicy';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { materialManager } from '../common/material/MaterialManager';
import { portraitUrl } from '../model/ThreadDetail';
import { AppTheme } from '../theme/Theme';
import { AvatarComponent } from './AvatarComponent';

const DIALOG_RADIUS: number = 24;
const DIALOG_MIN_WIDTH: number = 280;
const DIALOG_MAX_WIDTH: number = 360;
const DIALOG_FALLBACK_WIDTH: number = 320;
const DIALOG_SIDE_INSET: number = 24;
const LIST_MIN_HEIGHT: number = 200;
const LIST_MAX_HEIGHT: number = 360;
const LIST_FALLBACK_HEIGHT: number = 300;
const ROW_PADDING_H: number = 20;
const AVATAR_SIZE: number = 36;
const ROW_ICON_GAP: number = 12;

export class AccountSwitcherEntry {
  uid: number = 0;
  displayName: string = '';
  subtitle: string = '';
  portrait: string = '';
  isCurrent: boolean = false;
}

function buildEntry(uid: number, nickname: string, userName: string, portrait: string,
  isCurrent: boolean): AccountSwitcherEntry {
  const entry: AccountSwitcherEntry = new AccountSwitcherEntry();
  entry.uid = uid;
  if (nickname.length > 0) {
    entry.displayName = nickname;
  } else if (userName.length > 0) {
    entry.displayName = userName;
  } else if (uid > 0) {
    entry.displayName = `UID ${uid}`;
  } else {
    entry.displayName = '贴吧用户';
  }
  if (userName.length > 0) {
    entry.subtitle = `@${userName}`;
  } else if (uid > 0) {
    entry.subtitle = `UID ${uid}`;
  } else {
    entry.subtitle = isCurrent ? '当前登录' : '';
  }
  entry.portrait = portrait;
  entry.isCurrent = isCurrent;
  return entry;
}

/** 合并名册与当前会话快照：当前登录账号置顶去重，未归档时补入兜底项。 */
export function resolveAccountSwitcherEntries(savedAccounts: SavedAccount[],
  snapshot: AuthSnapshot): AccountSwitcherEntry[] {
  const result: AccountSwitcherEntry[] = [];
  const seen: Set<number> = new Set<number>();

  if (snapshot.isLoggedIn()) {
    const currentUid: number = Number.isSafeInteger(snapshot.uid) && snapshot.uid > 0 ? snapshot.uid : 0;
    const matched: SavedAccount | undefined = currentUid > 0
      ? savedAccounts.find((a: SavedAccount): boolean => a.uid === currentUid) : undefined;
    const nickname: string = snapshot.nickname.length > 0
      ? snapshot.nickname : (matched !== undefined ? matched.nickname : '');
    const userName: string = snapshot.userName.length > 0
      ? snapshot.userName : (matched !== undefined ? matched.userName : '');
    const portrait: string = snapshot.portrait.length > 0
      ? snapshot.portrait : (matched !== undefined ? matched.portrait : '');
    result.push(buildEntry(currentUid, nickname, userName, portrait, true));
    if (currentUid > 0) {
      seen.add(currentUid);
    }
  }

  for (let i: number = 0; i < savedAccounts.length; i++) {
    const account: SavedAccount = savedAccounts[i];
    if (!Number.isSafeInteger(account.uid) || account.uid <= 0 || seen.has(account.uid)) {
      continue;
    }
    seen.add(account.uid);
    result.push(buildEntry(account.uid, account.nickname, account.userName, account.portrait, false));
  }

  return result;
}

export function accountSwitcherDialogWidth(viewportWidthVp: number): number {
  if (!Number.isFinite(viewportWidthVp) || viewportWidthVp <= 0) {
    return DIALOG_FALLBACK_WIDTH;
  }
  return Math.min(Math.max(viewportWidthVp - DIALOG_SIDE_INSET * 2, DIALOG_MIN_WIDTH), DIALOG_MAX_WIDTH);
}

export function accountSwitcherListMaxHeight(viewportHeightVp: number): number {
  if (!Number.isFinite(viewportHeightVp) || viewportHeightVp <= 0) {
    return LIST_FALLBACK_HEIGHT;
  }
  return Math.max(LIST_MIN_HEIGHT, Math.min(Math.round(viewportHeightVp * 0.45), LIST_MAX_HEIGHT));
}

export function accountSwitcherDialogOptions(builder: CustomBuilder, viewportWidthVp: number,
  canDismiss: () => boolean, onDisappear: () => void): promptAction.CustomDialogOptions {
  return {
    builder: builder,
    alignment: DialogAlignment.Center,
    width: accountSwitcherDialogWidth(viewportWidthVp),
    cornerRadius: DIALOG_RADIUS,
    isModal: true,
    autoCancel: true,
    dialogTransition: popupMotion(),
    maskTransition: popupMotion(),
    systemMaterial: materialManager.officialOf(MaterialSlot.SHEET, true, true),
    backgroundColor: materialManager.useArkUI ? undefined : AppTheme.CARD,
    onWillDismiss: (action: DismissDialogAction): void => {
      if (canDismiss()) {
        action.dismiss();
      }
    },
    onDidDisappear: onDisappear
  };
}

@ComponentV2
export struct AccountSwitcherDialogContent {
  @Param maxListHeight: number = LIST_FALLBACK_HEIGHT;
  @Param switchingUid: number = 0;
  @Event onSelectAccount: (entry: AccountSwitcherEntry) => void = (_entry: AccountSwitcherEntry): void => {};
  @Event onAddAccount: () => void = (): void => {};

  private isBusy(): boolean {
    return this.switchingUid > 0 || authSession.switchingAccount;
  }

  private avatarUrlOf(entry: AccountSwitcherEntry): string {
    if (entry.portrait.length === 0) {
      return '';
    }
    return entry.isCurrent
      ? portraitUrl(entry.portrait, authSession.avatarRevision)
      : portraitUrl(entry.portrait);
  }

  private entries(): AccountSwitcherEntry[] {
    return resolveAccountSwitcherEntries(authSession.savedAccounts, authSession.snapshot);
  }

  @Builder
  AccountRow(entry: AccountSwitcherEntry) {
    Row({ space: ROW_ICON_GAP }) {
      AvatarComponent({
        url: this.avatarUrlOf(entry),
        avatarSize: AVATAR_SIZE,
        fallbackName: entry.displayName,
        traceTag: 'account-switcher-dialog'
      })
      Column({ space: 2 }) {
        Text(entry.displayName)
          .fontSize(15)
          .fontWeight(entry.isCurrent ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(AppTheme.TEXT_MAIN)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (entry.subtitle.length > 0) {
          Text(entry.subtitle)
            .fontSize(12)
            .fontColor(AppTheme.TEXT_MUTED)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (entry.isCurrent) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .maxFontScale(1)
          .fontColor([AppTheme.ACCENT])
      } else if (this.switchingUid === entry.uid) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(AppTheme.ACCENT)
      } else {
        SymbolGlyph($r('sys.symbol.reverse_order'))
          .fontSize(18)
          .maxFontScale(1)
          .fontColor([AppTheme.ICON])
          .opacity(this.isBusy() ? 0.4 : 1)
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 60 })
    .padding({ left: ROW_PADDING_H, right: ROW_PADDING_H, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .enabled(!this.isBusy() || entry.isCurrent)
    .accessibilityGroup(true)
    .accessibilityText(entry.isCurrent ? `${entry.displayName}，当前登录` : `切换到 ${entry.displayName}`)
    .accessibilitySelected(entry.isCurrent)
    .onClick((): void => {
      if (entry.isCurrent || entry.uid <= 0 || this.isBusy()) {
        return;
      }
      this.onSelectAccount(entry);
    })
  }

  @Builder
  AccountList() {
    if (this.entries().length === 0) {
      Text('暂无已登录账号')
        .fontSize(14)
        .fontColor(AppTheme.TEXT_SUB)
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ left: ROW_PADDING_H, right: ROW_PADDING_H, top: 28, bottom: 28 })
    } else {
      Scroll() {
        Column() {
          ForEach(this.entries(), (entry: AccountSwitcherEntry, index: number) => {
            if (index > 0) {
              Divider()
                .color(AppTheme.DIVIDER)
                .strokeWidth(0.5)
                .margin({ left: ROW_PADDING_H + AVATAR_SIZE + ROW_ICON_GAP, right: ROW_PADDING_H })
            }
            this.AccountRow(entry)
          }, (entry: AccountSwitcherEntry): string =>
            `${entry.uid}_${entry.isCurrent ? 1 : 0}_${entry.displayName}_${entry.subtitle}_${entry.portrait}`)
        }
        .width('100%')
      }
      .width('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(motionEdgeEffect())
      .constraintSize({ maxHeight: this.maxListHeight })
    }
  }

  build() {
    Column() {
      Text('切换账号')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.TEXT_MAIN)
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ left: ROW_PADDING_H, right: ROW_PADDING_H, top: 20, bottom: 14 })

      Divider()
        .color(AppTheme.DIVIDER)
        .strokeWidth(0.5)

      this.AccountList()

      Divider()
        .color(AppTheme.DIVIDER)
        .strokeWidth(0.5)

      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.person_badge_plus'))
          .fontSize(18)
          .maxFontScale(1)
          .fontColor([AppTheme.ACCENT])
        Text('添加账号')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.ACCENT)
      }
      .width('100%')
      .constraintSize({ minHeight: 54 })
      .padding({ left: ROW_PADDING_H, right: ROW_PADDING_H, top: 14, bottom: 16 })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .opacity(this.isBusy() ? 0.45 : 1)
      .enabled(!this.isBusy())
      .accessibilityGroup(true)
      .accessibilityText('添加账号')
      .id('account-switcher-add-account')
      .onClick((): void => {
        if (this.isBusy()) {
          return;
        }
        this.onAddAccount();
      })
    }
    .width('100%')
    .id('account-switcher-dialog')
  }
}
