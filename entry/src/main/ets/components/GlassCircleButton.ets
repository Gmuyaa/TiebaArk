/** 使用等宽高 HdsTabs 承载圆形系统玻璃面。内层裁剪圆角，外层 Stack 绘制阴影；透明渐变遮罩避免矩形暗底。组件使用 V2 状态以响应材质配置变化。 */

import { HdsTabs } from '@kit.UIDesignKit';
import { materialManager } from '../common/material/MaterialManager';
import { MaterialSlot, SPLIT_PILL_GRADIENT_MASK } from '../common/material/MaterialConfig';
import { AppTheme } from '../theme/Theme';

/** 圆直径默认值（vp）。全站统一 40，顶栏高度 52~60 都能容纳 */
const DIAMETER: number = 40;
/** 图标字号默认值（vp）。参考图里图形相对圆偏大，24 比 20 更接近 */
const ICON_SIZE: number = 24;

const ICON_COLOR: ResourceColor = AppTheme.TEXT_MAIN;

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
  @Param labelOffsetY: number = 0;
  /** 点击行为，由调用方传入 */
  @Param onTap: () => void = (): void => {};
  /** 圆直径（vp），默认 40 */
  @Param diameter: number = DIAMETER;
  /** 图标字号（vp），默认 24 */
  @Param iconSize: number = ICON_SIZE;
  /** 材质槽位。小型圆形悬浮控件统一用 BACK_BUTTON 档（HDS 通道下各槽位同参数） */
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
  SymbolTab() {
    Row() {
      if (this.useCustomIcon) {
        // 自绘图标同样吃 `iconOffsetX`：对称路径一般不需要（实测确实不偏），但这是
        // 自绘图形唯一能微调的入口，留着与字形分支行为一致（见 `iconOffsetX` 注释）。
        // `@BuilderParam` 不能链属性，外面套一层零尺寸 Column 承接 offset。
        Column() {
          this.customIcon();
        }
        .offset({ x: this.iconOffsetX })
      } else if (this.label.length > 0) {
        Text(this.label)
          .fontSize(this.iconSize).maxFontScale(1)
          .fontWeight(FontWeight.Bold)
          .fontColor(ICON_COLOR)
          .textAlign(TextAlign.Center)
          .offset({ x: this.iconOffsetX, y: this.labelOffsetY })
          .accessibilityText(this.accessibilityLabel.length > 0 ? this.accessibilityLabel : this.label)
      } else {
        SymbolGlyph(this.symbol)
          .fontSize(this.iconSize).maxFontScale(1)
          // 参考图里的图形笔画偏粗，`Bold` 更接近（`Medium` 实测几乎看不出差别）
          .fontWeight(FontWeight.Bold)
          .fontColor([ICON_COLOR])
          .offset({ x: this.iconOffsetX })
      }
    }
    .height('100%')
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .accessibilityGroup(true)
    .accessibilityText(this.accessibilityLabel.length > 0 ? this.accessibilityLabel : this.label)
    .onClick(() => {
      this.onTap();
    })
  }

  build() {

    Stack() {
      HdsTabs({ barPosition: BarPosition.End }) {
        TabContent() {
        }
        .tabBar(this.SymbolTab())
      }
      .barHeight(this.diameter)
      .barMode(BarMode.Fixed)
      .scrollable(false)
      .animationDuration(0)
      .barOverlap(true)
      // 让出系统自带的整块底衬（与首页底栏 / 分离式胶囊同一处理）
      .barBackgroundColor(Color.Transparent)
      .barBackgroundBlurStyle(BlurStyle.NONE)

      .barFloatingStyle({
        barWidth: { smallWidth: this.diameter, mediumWidth: this.diameter, largeWidth: this.diameter },
        barSideMargin: 0,
        barBottomMargin: 0,

        gradientMask: SPLIT_PILL_GRADIENT_MASK,
        thermoCtrl: true,
        systemMaterialEffect: materialManager.hdsEffectOf(this.slot)
      })

      .borderRadius(this.diameter / 2)
      .clip(true)
      .width(this.diameter)
      .height(this.diameter)
    }
    .width(this.diameter)
    .height(this.diameter)
    .borderRadius(this.diameter / 2)

    .shadow({ radius: 18, color: '#28000000', offsetX: 0, offsetY: 6 })
  }
}

/*
 * 备查：
 * - 官方悬浮面自带 1px 白描边（TD-18，无公开开关），白底详情页上不可见、
 *   深色内容经过时与胶囊一样显形 —— 与底部胶囊同一视觉语言，不另画描边。
 * - 旧「自绘 backgroundEffect」实现见 git 历史前的注释存档：
 *   Stack + `.backgroundEffect(materialManager.glassOf(slot))` +
 *   `.systemMaterial(materialManager.officialOf(slot))` + 1vp `rgba(0,0,0,0.10)` 暗边。
 *   若官方 HdsTabs 通道在小尺寸上有硬伤（如 barWidth 被钳到 84vp），按此回退。
 */
