/**
 * 圆面优先使用 ArkUI 官方材质，设备不支持时回退 HDS；图标和触控沿用原尺寸。
 *
 * 图标必须作为材质 Button 的**内容**，不能在 Stack 里另起一层盖上去：
 * 覆盖层会挡掉材质中心区域的触摸，表现为「只有圆面边缘那一圈能触发按压形变与光随指动，
 * 点图标处只有整体缩放」（2026-11-09 真机实测：中心变化像素 4118 → 搬进 Button 后 18264，
 * 与边缘的 18941 持平）。按压反馈全部交给官方材质，组件内不再自绘位移、缩放、旋转或淡化。
 */

import { MaterialTabs } from './MaterialTabs';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { materialManager } from '../common/material/MaterialManager';
import { AppTheme } from '../theme/Theme';
import { hdsEffect } from '@kit.UIDesignKit';
import { CloseIcon } from './CloseIcon';

/** 圆直径默认值（vp）。全站统一 40，顶栏高度 52~60 都能容纳 */
const DIAMETER: number = 40;
/** 图标字号默认值（vp）。参考图里图形相对圆偏大，24 比 20 更接近 */
const ICON_SIZE: number = 24;
/**
 * 点光源高度（vp）。官方 API：光源越高，照射范围越大。
 * 取按钮直径的 3 倍（48 × 3 = 144），范围随按钮尺寸走。
 */
const LIGHT_HEIGHT: number = 144;

/**
 * 必须是 **V2**（`@ComponentV2`）：`MaterialManager.mode` 是 `@Trace` 的，
 * 只有 V2 组件会订阅它 —— 在设置页把强度档位改掉，已经渲染出来的圆按钮要**立刻**跟着变
 * （V1 的 `@Component` 读 `@ObservedV2` 属性不会触发重绘，只能等页面重建）。
 */
@ComponentV2
export struct GlassCircleButton {
  /** 圆内 Symbol 资源。名字必须查 SDK 原始表，写错不报错、只渲染空白 */
  @Param symbol: Resource = $r('sys.symbol.chevron_left');
  /** 非空时在同一沉浸光感圆面内显示文字。 */
  @Param label: string = '';
  @Param accessibilityLabel: string = '';
  /** 点击行为，由调用方传入 */
  @Param onTap: () => void = (): void => {};
  /** 圆直径（vp），默认 40 */
  @Param diameter: number = DIAMETER;
  /** 图标字号（vp），默认 24 */
  @Param iconSize: number = ICON_SIZE;
  @Param iconWeight: FontWeight = FontWeight.Bold;
  /**
   * 图标颜色。默认跟随 `TEXT_MAIN`（深浅各自反转）；有固定着色的圆面（如发帖按钮的实心强调色）
   * 必须显式传入与圆面反差的颜色，否则浅色下会出现深色图标压在实心亮面上。
   */
  @Param iconColor: ResourceColor = AppTheme.TEXT_MAIN;
  /** 按页面需要关闭官方材质阴影。 */
  @Param shadowEnabled: boolean = true;
  /** 材质槽位。小型圆形悬浮控件统一用 BACK_BUTTON 档，厚度随全站设置 */
  @Param slot: MaterialSlot = MaterialSlot.BACK_BUTTON;

  /**
   * 材质承载按钮自己的触控区直径（vp）。0 = 不单独收窄，保持整面。
   *
   * 为什么需要：`interactive`（按压形变）和 `lightEffect`（光随指动）按 SDK 注释
   * 「作用于设置材质的那个组件」——触摸必须真正打到这个 Button 上才有效。
   * 悬浮按钮要把热区收到圆面中央时，不能靠宿主对整棵子树 BLOCK_DESCENDANTS，
   * 否则材质再也不会被按压；改成在这里收窄，材质仍收到自己的按下事件。
   */
  @Param hitRegion: number = 0;
  /**
   * 按压点光源强度（仅 COMPOSE_BUTTON 槽位使用），0 = 不发光。
   *
   * 角色按官方 API 定义分家：这里挂的是**光源**（`options` = 组件自定义发光参数），
   * 被照亮的是**另外标记了 `illuminatedType` 的周围组件**，不是自己。
   * 因此本组件不再设 `illuminatedType`，也不再自照边缘。
   * 其他调用方不传（默认 -1）完全不受影响。
   */
  @Param composePressLight: number = -1;
  /**
   * 按压点光源（2026-11-09 按官方 API 参考纠正）。
   *
   * - `options` 是「组件自定义发光参数」；`sourceType` 是预设发光档，优先级更高、同传会覆盖 options。
   * - 强度为 0 即不发光；关闭态仍直接返回空 `buildEffect()`，彻底不注册光源，避免常亮残留。
   * - 照射范围由 `height` 决定（越大越远），值见 `LIGHT_HEIGHT`。
   */
  private composeGlow(): VisualEffect {
    if (this.composePressLight <= 0) {
      return new hdsEffect.HdsEffectBuilder().buildEffect();
    }
    return new hdsEffect.HdsEffectBuilder().pointLight({
      // 直接拿按钮材质色当光色（现为不透明、深浅同色）：光的观感与圆面一致。
      options: { color: AppTheme.COMPOSE_TINT, intensity: this.composePressLight, height: LIGHT_HEIGHT }
    }).buildEffect();
  }
  /**
   * 是否改画调用方自绘的图标（`customIcon`），默认 false。
   *
   * 为什么要一个布尔开关：`@BuilderParam` 不能声明成可选，只能"给个空实现 + 布尔"
   * （同 `CommentActionHost.content` 的既有做法）。系统 Symbol 里没有的图形
   * （如「我的」页外观切换的三态图标）走这条路，此时 `symbol` 与 `label` 都被忽略。
   */
  @Param useCustomIcon: boolean = false;
  /**
   * 自绘图标内容。调用侧一律用箭头包一层（`customIcon: (): void => { this.X() }`）——
   * 直接传方法引用在本项目有过崩溃先例（见 `pages/ThreadDetail` 的同类注释）。
   */
  @Builder
  emptyIcon() {}
  @BuilderParam customIcon: () => void = this.emptyIcon;

  /** 圆内图标。只负责画，不带任何自绘按压动效；按压反馈由材质自身提供。 */
  @Builder
  IconContent() {
    if (this.useCustomIcon) {
      // 自绘图标同样交给 Button 居中，不再靠 offset 手调。
      Column() {
        this.customIcon();
      }
    } else if (this.label.length > 0) {
      Text(this.label)
        .fontSize(this.iconSize).maxFontScale(1)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.iconColor)
        .textAlign(TextAlign.Center)
        .accessibilityText(this.accessibilityLabel.length > 0 ? this.accessibilityLabel : this.label)
    } else if (this.symbol.id === $r('sys.symbol.xmark').id) {
      CloseIcon({ iconSize: this.iconSize, iconWeight: this.iconWeight, color: this.iconColor })
        .width(this.iconSize).height(this.iconSize)
    } else {
      SymbolGlyph(this.symbol)
        .fontSize(this.iconSize).maxFontScale(1)
        .fontWeight(this.iconWeight)
        .fontColor([this.iconColor])
    }
  }

  @Builder
  MaterialTab() {
    if (materialManager.useArkUI) {
      // 官方组件材质必须位于合法区域；这里使用真实圆形 Button，不给普通内容区空挂材质。
      // 图标放在 Button 内部当内容 —— 见文件头注释，这是中心区域能触发材质反馈的前提。
      Button({ type: ButtonType.Circle }) {
        this.IconContent()
      }
      .width(this.diameter).height(this.diameter).margin(0).padding(0)
      .backgroundColor(Color.Transparent)
      .systemMaterial(materialManager.officialOf(this.slot, this.shadowEnabled))
      // 按压点光源：本组件只当光源（options），受光在周围组件上各自挂 illuminatedType。
      .visualEffect(this.composeGlow())
      // 收窄自己的热区：材质按压效果保留，圆面边缘不截住底层列表。
      .responseRegion(this.hitRegion > 0 ? { x: (this.diameter - this.hitRegion) / 2,
        y: (this.diameter - this.hitRegion) / 2, width: this.hitRegion, height: this.hitRegion } :
        { x: 0, y: 0, width: this.diameter, height: this.diameter })
      // 原生按钮接收触摸反馈，业务动作仍由外层手势统一分发。
      .onClick((): void => {})
    } else {
      // HDS 回退：没有组件级材质，图标仍要显示，且不能挡宿主的触摸。
      Row() {
        this.IconContent()
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.None)
    }
  }

  build() {

    Stack() {
      // 保留已实测生效的官方圆面，不叠加按压增亮或彩色光场。
      MaterialTabs({ slot: this.slot, barHeight: this.diameter, barWidth: this.diameter,
        applyShadow: this.shadowEnabled, componentMaterial: true,
        barContent: (): void => { this.MaterialTab(); } })
        .borderRadius(this.diameter / 2).clip(false)
        .width(this.diameter).height(this.diameter)
    }
    .width(this.diameter)
    .height(this.diameter)
    .borderRadius(this.diameter / 2)
    .accessibilityGroup(true)
    .accessibilityText(this.accessibilityLabel.length > 0 ? this.accessibilityLabel :
      (!this.useCustomIcon && this.label.length === 0 && this.symbol.id === $r('sys.symbol.xmark').id ? '关闭' : this.label))
    // 与原生 TabBar 的材质手势并行，点击只从宿主分发一次。
    .parallelGesture(TapGesture().onAction((): void => { this.onTap(); }))

  }
}
