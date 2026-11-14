import { AppTheme } from '../theme/Theme';
import { MaterialTabs } from './MaterialTabs';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { materialManager } from '../common/material/MaterialManager';
import { visualThemeStore } from '../common/appearance/VisualThemeStore';
import { VisualTheme } from '../common/appearance/VisualTheme';

/** 关注/签到等按钮统一宽度。这类按钮常成对出现在同一行，等宽比贴合文字更整齐。
 *  72 是「已签到」+ 图标能完整放下的最小宽度；更长的文案（如「已互关」）由单行省略兜底。
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
  /** 布局最小高度。默认 44（视觉 32 + 上下各 6 触控余量）；吧头身份行按几何约束传 32，
   *  触控则用 responseRegion 补回 44，避免牺牲可点区域。 */
  @Param minTouchHeight: number = 44;
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
      .accessibilityLevel('no')
      // 点击必须由按钮自己消费（2026-11-13 持有者要求：统一按钮全部关掉点击穿透）。
      .onClick((): void => { this.activate(); })
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
      .constraintSize({ minHeight: this.minTouchHeight }).justifyContent(FlexAlign.Center).flexShrink(0).clip(false)
      // 触控区始终按 44vp 算：布局高度被压到 32 时，上下各外扩 (44 − 32) / 2。
      .responseRegion({ x: 0, y: (this.minTouchHeight - 44) / 2, width: '100%', height: 44 })
      // 用 onClick 而不是 parallelGesture（2026-11-13 持有者要求）：并行手势不消费事件，
      // 点关注/签到会继续穿到外层的卡片/封面/行点击上（打开详情、打开大图）。这里放在外层，
      // 是为了让 44vp 触控区里超出 32vp 视觉的那圈也由按钮自己消费；官方材质分支由内部
      // Button 先接走点击，此时本回调不触发，不会重复执行。
      .onClick((): void => { if (!materialManager.useArkUI) { this.activate(); } })
      // 起始于按钮上的拖动不再带动列表滚动（2026-11-13 持有者第二次反馈：能拖按钮滑屏不合理）。
      // 距离取 3vp ≈ 10px，远小于真手指点击时的抖动容忍，所以正常点击仍走 onClick；
      // 一旦拖动超过这个距离就由按钮消费，不再落到后面列表的滚动手势上。
      .gesture(PanGesture({ fingers: 1, direction: PanDirection.All, distance: 3 })
        .onActionStart((): void => {}))
  }
}
