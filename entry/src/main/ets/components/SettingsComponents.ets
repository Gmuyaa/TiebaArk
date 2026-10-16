
import { AppTheme } from '../theme/Theme';
import { SettingsLayout, summaryGoesBelow } from '../common/appearance/SettingsLayout';
import { fontScaleStore } from '../common/appearance/FontSizeScaleStore';
import { fontSizeScaleOf } from '../common/appearance/FontSizeScale';
import { SettingsOptionItem } from '../model/SettingsModel';
import { materialManager } from '../common/material/MaterialManager';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { ForumAvatarImage, forumAvatarRadius } from './ForumAvatarImage';

export function settingsFontScale(): number {
  return fontSizeScaleOf(fontScaleStore.pref, fontScaleStore.systemScale, fontScaleStore.customSize);
}

export function summaryBelow(label: string, summary: string): boolean {
  const scale: number = settingsFontScale();
  return summaryGoesBelow(label, summary, SettingsLayout.LABEL_SIZE * scale, SettingsLayout.VALUE_SIZE * scale);
}

@ComponentV2
export struct SettingsCard {

  @Param marginTop: number = 0;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .backgroundColor(AppTheme.CARD)
    .borderRadius(SettingsLayout.CARD_RADIUS)
    .margin({ top: this.marginTop })
    .clip(true)
  }
}

@ComponentV2
export struct SettingsGroupTitle {
  @Param title: string = '';

  build() {
    Text(this.title)
      .fontSize(SettingsLayout.SUB_SIZE)

      .fontColor(AppTheme.NOTE_TEXT)
      .width('100%')
      .padding({ left: 4, right: 4 })
      .margin({ top: SettingsLayout.GROUP_GAP, bottom: SettingsLayout.GROUP_TITLE_GAP })
  }
}

@ComponentV2
struct RowShell {
  @Param tall: boolean = false;
  @Param showDivider: boolean = true;
  @Param dividerInset: number = SettingsLayout.ROW_PAD_L;
  @Param onTap: () => void = (): void => {};
  @Param clickable: boolean = true;

  @Param popupOpen: boolean = false;
  @Param popupItems: SettingsOptionItem[] = [];
  @Event onPopupPick: (index: number) => void = (_index: number): void => {};
  @Event onPopupClosed: () => void = (): void => {};
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  build() {
    Column() {
      Row() {
        this.content()
      }
      .width('100%')
      .constraintSize({ minHeight: this.tall ? SettingsLayout.ROW_MIN_H_TALL : SettingsLayout.ROW_MIN_H })
      .padding({
        left: SettingsLayout.ROW_PAD_L, right: SettingsLayout.ROW_PAD_R,
        top: SettingsLayout.ROW_PAD_V, bottom: SettingsLayout.ROW_PAD_V
      })
      .onClick(() => {
        if (this.clickable) {
          this.onTap();
        }
      })

      if (this.showDivider) {
        Divider()
          .color(AppTheme.DIVIDER)
          .strokeWidth(0.5)
          .margin({ left: this.dividerInset })
      }
    }
    .width('100%')

    .bindPopup(this.popupOpen && this.popupItems.length > 0, {
      builder: (): void => {
        this.menu()
      },
      placement: Placement.BottomRight,
      enableArrow: false,
      mask: true,
      autoCancel: true,
      width: SettingsLayout.POPUP_W,
      radius: SettingsLayout.POPUP_RADIUS,
      targetSpace: SettingsLayout.POPUP_TARGET_SPACE,
      backgroundEffect: materialManager.glassOf(MaterialSlot.SHEET),
      systemMaterial: materialManager.officialOf(MaterialSlot.SHEET),
      onStateChange: (event: PopupStateChangeParam): void => {
        if (!event.isVisible) {
          this.onPopupClosed();
        }
      }
    })
  }

  @Builder
  menu() {
    Column() {
      ForEach(this.popupItems, (item: SettingsOptionItem, index: number) => {
        if (index > 0) {
          this.menuLine()
        }
        this.menuRow(item, index)
      }, (item: SettingsOptionItem) => item.key)
    }
    .width('100%')
  }

  @Builder
  menuLine() {
    Column() {
      Row()
        .width('100%')
        .height(SettingsLayout.POPUP_LINE_H)
        .backgroundColor(AppTheme.POPUP_LINE)
    }
    .width('100%')
    .padding({ left: SettingsLayout.POPUP_LINE_INSET, right: SettingsLayout.POPUP_LINE_INSET })
  }

  @Builder
  menuRow(item: SettingsOptionItem, index: number) {
    Row() {
      Text(item.label)
        .fontSize(SettingsLayout.POPUP_LABEL_SIZE)
        .fontColor(AppTheme.TEXT_MAIN)
        .maxLines(1)
        .layoutWeight(1)
      if (item.selected) {

        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(SettingsLayout.POPUP_LABEL_SIZE + 4)
          .fontColor([AppTheme.ACCENT])
      }
    }
    .width('100%')
    .constraintSize({ minHeight: SettingsLayout.POPUP_ROW_H })
    .padding({
      left: SettingsLayout.POPUP_PAD_L, right: SettingsLayout.POPUP_PAD_R,
      top: 8, bottom: 8
    })
    .onClick(() => {
      this.onPopupPick(index);
    })
  }
}

@Component
struct RowChevron {
  build() {
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(SettingsLayout.CHEVRON_SIZE)
      .fontColor([AppTheme.CHEVRON_TINT])
      .margin({ right: SettingsLayout.CHEVRON_INSET })
  }
}

@ComponentV2
export struct SettingsEntryRow {
  @Param label: string = '';
  @Param summary: string = '';
  @Param icon: Resource | undefined = undefined;

  @Param avatarUrl: string = '';
  @Param avatarName: string = '';
  @Param showDivider: boolean = true;
  @Event onTap: () => void = (): void => {};

  private hasAvatar(): boolean {
    return this.avatarUrl.length > 0 || this.avatarName.length > 0;
  }

  build() {
    RowShell({
      showDivider: this.showDivider,
      dividerInset: this.icon !== undefined || this.hasAvatar() ? 52 : SettingsLayout.ROW_PAD_L,
      onTap: this.onTap,
      content: (): void => {
        this.entryContent();
      }
    })
  }

  @Builder
  entryContent() {
    if (this.hasAvatar()) {
      ForumAvatarImage({
        url: this.avatarUrl, forumName: this.avatarName,
        avatarSize: SettingsLayout.ICON_BOX, radius: forumAvatarRadius(SettingsLayout.ICON_BOX)
      })
        .margin({ right: 12 })
    } else if (this.icon !== undefined) {
      SymbolGlyph(this.icon)
        .fontSize(SettingsLayout.ICON_BOX)
        .fontColor([AppTheme.ICON])
        .margin({ right: 12 })
    }
    Column({ space: 3 }) {
      Text(this.label)
        .fontSize(SettingsLayout.LABEL_SIZE)
        .fontColor(AppTheme.TEXT_MAIN)
        .width('100%')
      if (summaryBelow(this.label, this.summary)) {
        Text(this.summary)
          .fontSize(SettingsLayout.SUB_SIZE)
          .fontColor(AppTheme.NOTE_TEXT)
          .width('100%')
      }
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)

    if (this.summary.length > 0 && !summaryBelow(this.label, this.summary)) {
      Text(this.summary)
        .fontSize(SettingsLayout.VALUE_SIZE)
        .fontColor(AppTheme.VALUE_TEXT)
        .margin({ left: 12, right: SettingsLayout.CHEVRON_INSET })
    }
    RowChevron()
  }
}

@ComponentV2
export struct SettingsOptionRow {
  @Param label: string = '';
  @Param value: string = '';
  @Param showDivider: boolean = true;

  @Param popupOpen: boolean = false;
  @Param items: SettingsOptionItem[] = [];
  @Event onTap: () => void = (): void => {};
  @Event onPick: (index: number) => void = (_index: number): void => {};
  @Event onPopupClosed: () => void = (): void => {};

  build() {
    RowShell({
      showDivider: this.showDivider,
      onTap: this.onTap,
      popupOpen: this.popupOpen,
      popupItems: this.items,
      onPopupPick: this.onPick,
      onPopupClosed: this.onPopupClosed,
      content: (): void => {
        this.optionContent();
      }
    })
  }

  @Builder
  optionContent() {
    Text(this.label)
      .fontSize(SettingsLayout.LABEL_SIZE)
      .fontColor(AppTheme.TEXT_MAIN)
      .layoutWeight(1)
    Text(this.value)
      .fontSize(SettingsLayout.VALUE_SIZE)
      .fontColor(AppTheme.VALUE_TEXT)
      .margin({ left: 12, right: SettingsLayout.CHEVRON_INSET })
    RowChevron()
  }
}

@ComponentV2
export struct SettingsSwitchRow {
  @Param label: string = '';
  @Param sub: string = '';
  @Param checked: boolean = false;
  @Param showDivider: boolean = true;
  @Event onToggle: (next: boolean) => void = (_next: boolean): void => {};

  build() {
    RowShell({
      tall: this.sub.length > 0,
      showDivider: this.showDivider,
      onTap: (): void => {
        this.onToggle(!this.checked);
      },
      content: (): void => {
        this.switchContent();
      }
    })
  }

  @Builder
  switchContent() {
    Column({ space: 3 }) {
      Text(this.label)
        .fontSize(SettingsLayout.LABEL_SIZE)
        .fontColor(AppTheme.TEXT_MAIN)
        .width('100%')
      if (this.sub.length > 0) {
        Text(this.sub)
          .fontSize(SettingsLayout.SUB_SIZE)
          .fontColor(AppTheme.NOTE_TEXT)
          .width('100%')
      }
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)

    Toggle({ type: ToggleType.Switch, isOn: this.checked })
      .selectedColor(AppTheme.ACCENT)

      .hitTestBehavior(HitTestMode.None)
  }
}

@ComponentV2
export struct SettingsInfoRow {
  @Param label: string = '';
  @Param value: string = '';
  @Param sub: string = '';
  @Param showDivider: boolean = true;

  @Param labelColor: string = '';

  build() {
    RowShell({
      tall: this.sub.length > 0,
      showDivider: this.showDivider,
      clickable: false,
      content: (): void => {
        this.infoContent();
      }
    })
  }

  @Builder
  infoContent() {
    Column({ space: 3 }) {
      Text(this.label)
        .fontSize(SettingsLayout.LABEL_SIZE)
        .fontColor(this.labelColor.length > 0 ? this.labelColor : AppTheme.TEXT_MAIN)
        .width('100%')
      if (this.sub.length > 0) {
        Text(this.sub)
          .fontSize(SettingsLayout.SUB_SIZE)
          .fontColor(AppTheme.NOTE_TEXT)
          .width('100%')
      }
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)

    if (this.value.length > 0) {
      Text(this.value)
        .fontSize(SettingsLayout.VALUE_SIZE)
        .fontColor(AppTheme.VALUE_TEXT)
        .margin({ left: 12 })
    }
  }
}

export enum SettingsActionTone {
  ACCENT = 0,
  DANGER = 1
}

@ComponentV2
export struct SettingsActionRow {
  @Param label: string = '';
  @Param busyLabel: string = '';
  @Param busy: boolean = false;
  @Param tone: SettingsActionTone = SettingsActionTone.ACCENT;
  @Param showDivider: boolean = false;
  @Event onTap: () => void = (): void => {};

  build() {
    RowShell({
      showDivider: this.showDivider,
      clickable: !this.busy,
      onTap: this.onTap,
      content: (): void => {
        this.actionContent();
      }
    })
  }

  @Builder
  actionContent() {
    Text(this.busy && this.busyLabel.length > 0 ? this.busyLabel : this.label)
      .fontSize(SettingsLayout.LABEL_SIZE)
      .fontColor(this.tone === SettingsActionTone.DANGER ? AppTheme.DANGER_TEXT : AppTheme.ACCENT)
      .textAlign(TextAlign.Center)
      .width('100%')
      .opacity(this.busy ? 0.6 : 1)
  }
}

export enum SettingsStatusKind {
  LOADING = 0,
  EMPTY = 1,
  ERROR = 2,
  LOGIN = 3
}

@ComponentV2
export struct SettingsStatusLine {
  @Param kind: SettingsStatusKind = SettingsStatusKind.LOADING;
  @Param message: string = '';
  @Param retryLabel: string = '';
  @Event onRetry: () => void = (): void => {};

  build() {
    Row() {
      Text(this.text())
        .fontSize(SettingsLayout.VALUE_SIZE)
        .fontColor(this.kind === SettingsStatusKind.ERROR ? AppTheme.DANGER_TEXT : AppTheme.NOTE_TEXT)
        .layoutWeight(1)
      if (this.retryLabel.length > 0) {
        Button(this.retryLabel)
          .fontSize(SettingsLayout.VALUE_SIZE)
          .fontColor(AppTheme.ACCENT)
          .backgroundColor(AppTheme.CARD)
          .borderRadius(12)
          .onClick(() => {
            this.onRetry();
          })
      }
    }
    .width('100%')
    .padding({
      left: SettingsLayout.ROW_PAD_L, right: SettingsLayout.ROW_PAD_R,
      top: 12, bottom: 12
    })
  }

  private text(): string {
    if (this.message.length > 0) {
      return this.message;
    }
    switch (this.kind) {
      case SettingsStatusKind.EMPTY:
        return '暂无内容';
      case SettingsStatusKind.ERROR:
        return '读取失败';
      case SettingsStatusKind.LOGIN:
        return '登录后查看';
      case SettingsStatusKind.LOADING:
      default:
        return '正在读取…';
    }
  }
}

@ComponentV2
export struct SettingsNote {
  @Param text: string = '';

  build() {
    Text(this.text)
      .fontSize(SettingsLayout.SUB_SIZE)
      .fontColor(AppTheme.NOTE_TEXT)
      .lineHeight(20)
      .width('100%')
      .padding({ left: 4, right: 4 })
      .margin({ top: 12 })
  }
}
