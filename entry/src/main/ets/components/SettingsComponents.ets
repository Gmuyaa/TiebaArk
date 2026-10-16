/** 设置页共享行、分组与状态组件，尺寸来自 SettingsLayout，颜色来自 AppTheme。 */
import { AppTheme } from '../theme/Theme';
import { SettingsLayout, summaryGoesBelow } from '../common/appearance/SettingsLayout';
import { fontScaleStore } from '../common/appearance/FontSizeScaleStore';
import { fontSizeScaleOf } from '../common/appearance/FontSizeScale';
import { SettingsOptionItem } from '../model/SettingsModel';
import { materialManager } from '../common/material/MaterialManager';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { ForumAvatarImage, forumAvatarRadius } from './ForumAvatarImage';

/** 当前应用字体缩放比：摘要换行判定要按**实际渲染尺寸**算，不能按设计值算。 */
export function settingsFontScale(): number {
  return fontSizeScaleOf(fontScaleStore.pref, fontScaleStore.systemScale, fontScaleStore.customSize);
}

/** 摘要是否应放到名称下方（转调纯逻辑，Node 侧同源）。 */
export function summaryBelow(label: string, summary: string): boolean {
  const scale: number = settingsFontScale();
  return summaryGoesBelow(label, summary, SettingsLayout.LABEL_SIZE * scale, SettingsLayout.VALUE_SIZE * scale);
}

/** 卡片：圆角 + 卡底 + 裁剪，内容由调用方以 @BuilderParam 传入。 */
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

/** 分组标题：「使用体验」「贴吧账号偏好」这类**只是标题，不是页面**。 */
@ComponentV2
export struct SettingsGroupTitle {
  @Param title: string = '';

  build() {
    Text(this.title)
      .fontSize(SettingsLayout.SUB_SIZE)
      // app_note_text：实测 5.27（页面底）/ 5.74（卡片），TEXT_SUB 只有 2.62 不达标
      .fontColor(AppTheme.NOTE_TEXT)
      .width('100%')
      .padding({ left: 4, right: 4 })
      .margin({ top: SettingsLayout.GROUP_GAP, bottom: SettingsLayout.GROUP_TITLE_GAP })
  }
}

/** 行外壳：统一最小高度、内距与底部分隔线；选项行还在这里挂选项弹层。 */
@ComponentV2
struct RowShell {
  @Param tall: boolean = false;
  @Param showDivider: boolean = true;
  @Param dividerInset: number = SettingsLayout.ROW_PAD_L;
  @Param onTap: () => void = (): void => {};
  @Param clickable: boolean = true;
  /** 选项弹层是否展开（只由页面状态驱动，行自己不记住）；空数组 = 不挂弹层。 */
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
    // 弹层几何与材质集中在这里：宽度/圆角/行高读 SettingsLayout，材质走 SHEET 槽位
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

  /** 弹层内容：选项名 + 当前项勾选，分隔线左右缩进与文字对齐。 */
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
        .layoutWeight(1)
      if (item.selected) {
        // `sys.symbol.checkmark` 是真名（base 块 0xF0013）
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(SettingsLayout.POPUP_LABEL_SIZE + 4).maxFontScale(1)
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

/** 右侧箭头。`chevron_right` 是真名（base 块 0xF00D9），字形盒窄所以内缩 4vp。 */
@Component
struct RowChevron {
  build() {
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(SettingsLayout.CHEVRON_SIZE).maxFontScale(1)
      .fontColor([AppTheme.CHEVRON_TINT])
      .margin({ right: SettingsLayout.CHEVRON_INSET })
  }
}

/**
 * 入口行：图标（可选）+ 名称 + 摘要 + 箭头。
 *
 * 摘要位置由 `summaryBelow()` 决定：**过长或当前字号挤不下就移到名称下方**，
 * 不跟名称和箭头争宽度（16fp 走行右，24fp 落到名称下方）。
 */
@ComponentV2
export struct SettingsEntryRow {
  @Param label: string = '';
  @Param summary: string = '';
  @Param icon: Resource | undefined = undefined;
  @Param imageIcon: Resource | undefined = undefined;

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
      dividerInset: this.icon !== undefined || this.imageIcon !== undefined || this.hasAvatar() ? 52 : SettingsLayout.ROW_PAD_L,
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
        .fontSize(SettingsLayout.ICON_BOX).maxFontScale(1)
        .fontColor([AppTheme.ICON])
        .margin({ right: 12 })
    } else if (this.imageIcon !== undefined) {
      Image(this.imageIcon).width(SettingsLayout.ICON_BOX).height(SettingsLayout.ICON_BOX)
        .fillColor(AppTheme.ICON).margin({ right: 12 })
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
  /** 本行的弹层是否展开（页面用"当前展开的是哪一行"驱动，保证同时只有一层） */
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

/** 开关行：名称 + 可选说明 + 开关（整行可点，避免双触发）。 */
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
      // 触摸交给整行处理；开关仍随 isOn 响应式变化（防止"点开关又触发行点击"的双触发）
      .hitTestBehavior(HitTestMode.None)
  }
}

/** 信息行：名称 + 值，**无箭头、不可点**（只读项用它，不做成置灰开关）。 */
@ComponentV2
export struct SettingsInfoRow {
  @Param label: string = '';
  @Param value: string = '';
  @Param sub: string = '';
  @Param showDivider: boolean = true;
  /**
   * 名称文字色（可选）。只给**数据驱动**的行用（例：小尾巴的服务端颜色），
   * 普通行留空即用主题主文字色 —— 不要拿它做装饰性配色。
   */
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

/** 操作组件的形态；`ACCENT` 主要操作、`DANGER` 危险操作（红字）。 */
export enum SettingsActionTone {
  ACCENT = 0,
  DANGER = 1
}

/**
 * 操作行：明确动作文案 + 执行中状态 + 防重复触发。
 * `busy = true` 时显示进行态文案且**不可点**。
 */
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

/** 状态区的性质。 */
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

/** 卡片下方的辅助说明（13fp；长状态说明一律走这里，不塞进行内右侧）。 */
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
