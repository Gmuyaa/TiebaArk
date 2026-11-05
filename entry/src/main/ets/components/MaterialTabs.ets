import { HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { materialManager } from '../common/material/MaterialManager';
import { MaterialSlot } from '../common/material/MaterialConfig';

/** 原生 TabBar 内部仍会裁切子组件；留足官方阴影的衰减范围，避免出现横向灰带截口。 */
const COMPONENT_OVERFLOW: number = 64;

/** 官方悬浮材质承载：优先 ArkUI Tabs，设备不支持时才使用 HDS；不叠加自绘玻璃。 */
@ComponentV2
export struct MaterialTabs {
  @Param slot: MaterialSlot = MaterialSlot.BOTTOM_BAR;
  @Param barHeight: number = 48;
  @Param barWidth: number = 0;
  @Param barSideMargin: number = 0;
  @Param barBottomMargin: number = 0;
  @Param maskColor: ResourceColor = Color.Transparent;
  @Param maskHeight: number = 0;
  @Param barVisible: boolean = true;
  @Param applyShadow: boolean = true;
  /** ArkUI 前景组件自行设置材质；TabBar 只提供合法生效区域，不再叠加悬浮面。 */
  @Param componentMaterial: boolean = false;
  @Param controller: TabsController | undefined = undefined;
  @Param fallbackController: HdsTabsController | undefined = undefined;
  @Local contentWidth: number = 0;
  @Event onChange: (index: number) => void = (_index: number): void => {};

  @Builder
  EmptyBar() { Row().width('100%').height('100%') }
  @BuilderParam barContent: () => void = this.EmptyBar;

  @Builder
  ComponentBar() {
    if (materialManager.useArkUI && this.componentMaterial) {
      Row() {
        this.barContent()
      }
      .width(`calc(100% - ${COMPONENT_OVERFLOW * 2}vp)`).height(this.barHeight)
      .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
      .clip(false)
    } else {
      this.barContent()
    }
  }
  @Builder
  DefaultPage() { TabContent() {}.tabBar(this.ComponentBar) }
  @BuilderParam pages: () => void = this.DefaultPage;

  build() {
    if (materialManager.useArkUI) {
      Stack() {
        Tabs({ controller: this.controller, barPosition: BarPosition.End }) {
          this.pages()
        }
        .vertical(false).barMode(BarMode.Fixed).scrollable(false).animationDuration(0)
        .barHeight(this.barVisible ? this.barHeight + (this.componentMaterial ? COMPONENT_OVERFLOW * 2 : 0) : 0,
          true).barOverlap(true)
        .barBackgroundColor(Color.Transparent).barBackgroundBlurStyle(BlurStyle.NONE)
        // 首页过渡结束后才切换 barVisible，撤销浮面以保证后续布局不会重新露出缩小的底栏。
        .barFloatingStyle(this.componentMaterial || !this.barVisible ? undefined : {
          barWidth: { smallBarWidth: this.barWidth,
            mediumBarWidth: this.barWidth, largeBarWidth: this.barWidth },
          barSideMargin: this.barSideMargin,
          barBottomMargin: this.barBottomMargin,
          maskColor: this.barVisible ? this.maskColor : Color.Transparent,
          maskHeight: this.barVisible ? this.maskHeight : 0,
          systemMaterial: materialManager.officialOf(this.slot, this.applyShadow)
        })
        .onChange((index: number): void => { this.onChange(index); })
        // 官方材质按压时会越过布局边界，不能由承载 Tabs 再次裁切。
        .clip(false)
        .width(this.componentMaterial ? `calc(100% + ${COMPONENT_OVERFLOW * 2}vp)` : '100%')
        .height(this.componentMaterial ? `calc(100% + ${COMPONENT_OVERFLOW * 2}vp)` : '100%')
      }
      .width('100%').height('100%')
      .clip(false)
      .onAreaChange((_old: Area, area: Area): void => {
        const width: number = Number(area.width);
        if (width > 0 && Math.abs(width - this.contentWidth) > 0.5) { this.contentWidth = width; }
      })
      // 阴影可以越界，透明承载区不能截走相邻按钮、频道或列表的触摸。
      .onTouchIntercept((event: TouchEvent): HitTestMode => {
        if (!this.componentMaterial || !event.touches || event.touches.length === 0) {
          return HitTestMode.Default;
        }
        const touch: TouchObject = event.touches[0];
        // 事件拦截阶段 target.area.width 在真机上为 0，使用布局实测宽度。
        return touch.x < 0 || (this.contentWidth > 0 && touch.x > this.contentWidth) ||
          touch.y < 0 || touch.y > this.barHeight
          ? HitTestMode.BLOCK_DESCENDANTS : HitTestMode.Default;
      })
    } else {
      HdsTabs({ controller: this.fallbackController, barPosition: BarPosition.End }) {
        this.pages()
      }
      .vertical(false).barMode(BarMode.Fixed).scrollable(false).animationDuration(0)
      .barHeight(this.barVisible ? this.barHeight : 0).barOverlap(true)
      .barBackgroundColor(Color.Transparent).barBackgroundBlurStyle(BlurStyle.NONE)
      .barFloatingStyle({
        barWidth: { smallWidth: this.barVisible ? this.barWidth : 4,
          mediumWidth: this.barVisible ? this.barWidth : 4,
          largeWidth: this.barVisible ? this.barWidth : 4 },
        barSideMargin: this.barSideMargin,
        barBottomMargin: this.barVisible ? this.barBottomMargin : 0,
        gradientMask: { maskColor: this.barVisible ? this.maskColor : Color.Transparent,
          maskHeight: this.barVisible ? this.maskHeight : 0 },
        barOpacity: this.barVisible ? 1 : 0,
        thermoCtrl: true,
        systemMaterialEffect: materialManager.hdsEffectOf(this.slot)
      })
      .onChange((index: number): void => { this.onChange(index); })
      .clip(false)
      .width('100%').height('100%')
    }
  }
}
