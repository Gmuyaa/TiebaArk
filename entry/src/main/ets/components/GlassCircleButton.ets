/** 圆面优先使用 ArkUI 官方材质，设备不支持时回退 HDS；图标和触控沿用原尺寸。 */

import { MaterialTabs } from './MaterialTabs';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { materialManager } from '../common/material/MaterialManager';
import { AppTheme } from '../theme/Theme';
import { CloseIcon } from './CloseIcon';
import { MotionEffect } from '../common/appearance/MotionConfig';
import { motionStore } from '../common/appearance/MotionStore';
import { motionDuration, motionSpringCurve } from '../common/appearance/MotionPolicy';

/** 圆直径默认值（vp）。全站统一 40，顶栏高度 52~60 都能容纳 */
const DIAMETER: number = 40;
/** 图标字号默认值（vp）。参考图里图形相对圆偏大，24 比 20 更接近 */
const ICON_SIZE: number = 24;

/**
 * 必须是 **V2**（`@ComponentV2`）：`MaterialManager.mode` 是 `@Trace` 的，
 * 只有 V2 组件会订阅它 —— 在设置页把强度档位改掉，已经渲染出来的圆按钮要**立刻**跟着变
 * （V1 的 `@Component` 读 `@ObservedV2` 属性不会触发重绘，只能等页面重建）。
 */
@ComponentV2
export struct GlassCircleButton {
  @Local pressed: boolean = false;
  /** 圆内 Symbol 资源。名字必须查 SDK 原始表，写错不报错、只渲染空白 */
  @Param symbol: Resource = $r('sys.symbol.chevron_left');
  /** 非空时在同一沉浸光感圆面内显示文字。 */
  @Param label: string = '';
  @Param accessibilityLabel: string = '';
  @Param labelOffsetY: number = 0;
  /** 点击行为，由调用方传入 */
  @Param onTap: () => void = (): void => {};
  /** 圆直径（vp），默认 40 */
  @Param diameter: number = DIAMETER;
  /** 图标字号（vp），默认 24 */
  @Param iconSize: number = ICON_SIZE;
  @Param iconWeight: FontWeight = FontWeight.Bold;
  /** 按页面需要关闭官方材质阴影。 */
  @Param shadowEnabled: boolean = true;
  /** 材质槽位。小型圆形悬浮控件统一用 BACK_BUTTON 档，厚度随全站设置 */
  @Param slot: MaterialSlot = MaterialSlot.BACK_BUTTON;

  @Param iconOffsetX: number = 0;
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

  @Builder
  SymbolContent() {
    Row() {
      if (this.useCustomIcon) {
        // Builder 外包一层容器承接光学偏移，始终由圆面尺寸的前景居中。
        Column() {
          this.customIcon();
        }
        .offset({ x: this.iconOffsetX })
      } else if (this.label.length > 0) {
        Text(this.label)
          .fontSize(this.iconSize).maxFontScale(1)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT_MAIN)
          .textAlign(TextAlign.Center)
          .offset({ x: this.iconOffsetX, y: this.labelOffsetY })
          .accessibilityText(this.accessibilityLabel.length > 0 ? this.accessibilityLabel : this.label)
      } else if (this.symbol.id === $r('sys.symbol.xmark').id) {
        CloseIcon({ iconSize: this.iconSize, iconWeight: this.iconWeight, color: AppTheme.TEXT_MAIN })
          .width(this.iconSize).height(this.iconSize).offset({ x: this.iconOffsetX })
      } else {
        SymbolGlyph(this.symbol)
          .fontSize(this.iconSize).maxFontScale(1)
          .fontWeight(this.iconWeight)
          .fontColor([AppTheme.TEXT_MAIN])
          .offset({ x: this.iconOffsetX })
      }
    }
    .height(this.diameter)
    .width(this.diameter)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .accessibilityGroup(true)
    .accessibilityText(this.accessibilityLabel.length > 0 ? this.accessibilityLabel :
      (!this.useCustomIcon && this.label.length === 0 && this.symbol.id === $r('sys.symbol.xmark').id ? '关闭' : this.label))
    .opacity(this.pressed && motionStore.isOn(MotionEffect.FADE) ? 0.8 : 1)
    .animation({ duration: motionDuration(160, MotionEffect.FADE), curve: motionSpringCurve(MotionEffect.FADE) })
    .translate({ y: this.pressed && motionStore.isOn(MotionEffect.MOVE) ? 1 : 0 })
    .animation({ duration: motionDuration(160, MotionEffect.MOVE), curve: motionSpringCurve(MotionEffect.MOVE) })
    .scale({ x: this.pressed && motionStore.isOn(MotionEffect.SCALE) ? 0.95 : 1,
      y: this.pressed && motionStore.isOn(MotionEffect.SCALE) ? 0.95 : 1 })
    .animation({ duration: motionDuration(160, MotionEffect.SCALE), curve: motionSpringCurve(MotionEffect.SCALE) })
    .rotate({ angle: this.pressed && motionStore.isOn(MotionEffect.ROTATE) ? 4 : 0 })
    .animation({ duration: motionDuration(160, MotionEffect.ROTATE), curve: motionSpringCurve(MotionEffect.ROTATE) })
    .hitTestBehavior(HitTestMode.None).zIndex(1)
    // 触屏点击由宿主手势接收；前景保留无障碍激活动作。
    .onClick((): void => { this.onTap(); })
  }

  @Builder
  MaterialTab() {
    if (materialManager.useArkUI) {
      // 官方组件材质必须位于合法区域；这里使用真实圆形 Button，不给普通内容区空挂材质。
      Button({ type: ButtonType.Circle }) {
        Row().width('100%').height('100%')
      }
      .width(this.diameter).height(this.diameter).margin(0).padding(0)
      .backgroundColor(Color.Transparent)
      .systemMaterial(materialManager.officialOf(this.slot, this.shadowEnabled))
      .accessibilityLevel('no')
      // 原生按钮接收触摸反馈，业务动作仍由外层手势统一分发。
      .onClick((): void => {})
    } else {
      Row().width('100%').height('100%').hitTestBehavior(HitTestMode.None)
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
      // 图标保持独立，保留现有位移、缩放、旋转与淡入淡出。
      this.SymbolContent()
    }
    .width(this.diameter)
    .height(this.diameter)
    .borderRadius(this.diameter / 2)
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) { this.pressed = true; }
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.pressed = false; }
    })
    // 与原生 TabBar 的材质手势并行，点击只从宿主分发一次。
    .parallelGesture(TapGesture().onAction((): void => { this.onTap(); }))

  }
}
