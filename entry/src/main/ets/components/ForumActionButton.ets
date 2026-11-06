import { AppTheme } from '../theme/Theme';
import { MaterialTabs } from './MaterialTabs';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { materialManager } from '../common/material/MaterialManager';
import { visualThemeStore } from '../common/appearance/VisualThemeStore';
import { VisualTheme } from '../common/appearance/VisualTheme';

/** 签到、关注与回关共用的小型原生玻璃按钮；视觉高度32，触控高度至少44。 */
@ComponentV2
export struct ForumActionButton {
  @Param label: string = '';
  @Param busy: boolean = false;
  @Param disabled: boolean = false;
  @Param completed: boolean = false;
  @Param retry: boolean = false;
  @Param actionSymbol: Resource = $r('sys.symbol.plus');
  @Param accessibilityLabel: string = '';
  @Local contentWidth: number = 76;
  @Local contentHeight: number = 32;
  @Event onTap: () => void = (): void => {};

  private foreground(): ResourceColor {
    if (this.completed || this.retry) { return AppTheme.TEXT_SUB; }
    return visualThemeStore.theme !== VisualTheme.CLASSIC && !visualThemeStore.isPaper
      ? AppTheme.ACCENT_DARK : AppTheme.TEXT_MAIN;
  }

  private activate(): void {
    if (!this.busy && !this.disabled) { this.onTap(); }
  }

  @Builder
  MaterialButton() {
    if (materialManager.useArkUI) {
      Button({ type: ButtonType.Capsule }) {
        Row().width('100%').height('100%')
      }
      .width(this.contentWidth).height(this.contentHeight).margin(0).padding(0)
      .backgroundColor(Color.Transparent)
      .systemMaterial(materialManager.officialOf(MaterialSlot.FORUM_ACTION_BUTTON))
      .accessibilityLevel('no').onClick((): void => {})
    } else {
      Row().width('100%').height('100%').hitTestBehavior(HitTestMode.None)
    }
  }

  build() {
    Column() {
      Stack() {
        MaterialTabs({ slot: MaterialSlot.FORUM_ACTION_BUTTON, barWidth: this.contentWidth,
          barHeight: this.contentHeight, componentMaterial: true,
          barContent: (): void => { this.MaterialButton(); } })
          .width(this.contentWidth).height(this.contentHeight)
          .position({ x: 0, y: 0 }).clip(false)
        Row({ space: 4 }) {
          if (this.busy) {
            LoadingProgress().width(12).height(12).color(this.foreground())
              .accessibilityLevel('no')
          } else {
            SymbolGlyph(this.retry ? $r('sys.symbol.arrow_clockwise') :
              (this.completed ? $r('sys.symbol.checkmark') : this.actionSymbol))
              .fontSize(12).fontWeight(FontWeight.Regular).fontColor([this.foreground()])
              .accessibilityLevel('no')
          }
          Text(this.label).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.foreground())
            .textAlign(TextAlign.Center).maxLines(1)
        }.justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
          .constraintSize({ minWidth: 76, minHeight: 32 })
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .accessibilityGroup(true).accessibilityText(this.accessibilityLabel || this.label)
          .accessibilityDescription(this.busy ? '正在处理' : (this.disabled ? '不可操作' : ''))
          .hitTestBehavior(HitTestMode.None).onClick((): void => { this.activate(); })
          .onAreaChange((_old: Area, area: Area): void => {
            this.contentWidth = Number(area.width);
            this.contentHeight = Number(area.height);
          })
      }.clip(false)
    }
      .constraintSize({ minHeight: 44 }).justifyContent(FlexAlign.Center).flexShrink(0).clip(false)
      .parallelGesture(TapGesture().onAction((): void => { this.activate(); }))
  }
}
