import { AppTheme } from '../theme/Theme';
import { MaterialTabs } from './MaterialTabs';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { materialManager } from '../common/material/MaterialManager';
import { visualThemeStore } from '../common/appearance/VisualThemeStore';
import { VisualTheme } from '../common/appearance/VisualTheme';

/** 关注/签到等按钮统一宽度。这类按钮常成对出现在同一行，等宽比贴合文字更整齐。
 *  72 是「已签到」+ 图标能完整放下的最小宽度；更长的「读取中…」等加载态由单行省略兜底。
 *  不要再加大：关注列表里吧名很长，行内空间有限，超过 72 会把按钮挤出屏幕（2026-11-09 真机）。 */
const ACTION_WIDTH: number = 72;
const ACTION_HEIGHT: number = 32;

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
  @Event onTap: () => void = (): void => {};

  private foreground(): ResourceColor {
    if (this.completed || this.retry) { return AppTheme.TEXT_SUB; }
    return visualThemeStore.theme !== VisualTheme.CLASSIC && !visualThemeStore.isPaper
      ? AppTheme.ACCENT_DARK : AppTheme.TEXT_MAIN;
  }

  private activate(): void {
    if (!this.busy && !this.disabled) { this.onTap(); }
  }

  /** 图标 + 文字。只负责画，不带触摸处理；材质按钮内部直接作为内容使用。 */
  @Builder
  LabelRow() {
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
    }.width('100%').height('100%')
      .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
      .padding({ left: 8, right: 8 })
      .accessibilityGroup(true).accessibilityText(this.accessibilityLabel || this.label)
      .accessibilityDescription(this.busy ? '正在处理' : (this.disabled ? '不可操作' : ''))
  }

  @Builder
  MaterialButton() {
    if (materialManager.useArkUI) {
      // 内容放在 Button 内部：图标/文字作为外层覆盖层会挡掉材质中心的指针位置，
      // 让按压只有边缘生效（同 GlassCircleButton 2026-11-09 真机结论）。
      Button({ type: ButtonType.Capsule }) {
        this.LabelRow()
      }
      .width(ACTION_WIDTH).height(ACTION_HEIGHT).margin(0).padding(0)
      .backgroundColor(Color.Transparent)
      .systemMaterial(materialManager.officialOf(MaterialSlot.FORUM_ACTION_BUTTON))
      .accessibilityLevel('no').onClick((): void => {})
    } else {
      Row() {
        this.LabelRow()
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.None)
    }
  }

  build() {
    Column() {
      MaterialTabs({ slot: MaterialSlot.FORUM_ACTION_BUTTON, barWidth: ACTION_WIDTH,
        barHeight: ACTION_HEIGHT, componentMaterial: true,
        barContent: (): void => { this.MaterialButton(); } })
        .width(ACTION_WIDTH).height(ACTION_HEIGHT)
        .clip(false)
    }
      .constraintSize({ minHeight: 44 }).justifyContent(FlexAlign.Center).flexShrink(0).clip(false)
      .parallelGesture(TapGesture().onAction((): void => { this.activate(); }))
  }
}
