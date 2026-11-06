import { hdsEffect } from '@kit.UIDesignKit';
import { MotionEffect } from '../common/appearance/MotionConfig';
import { motionStore } from '../common/appearance/MotionStore';
import { AppTheme } from '../theme/Theme';

/** 官方光场只承载背景；文字图标由宿主在整个材质控件上方绘制。 */
@ComponentV2
export struct MaterialMotionLayer {
  @Param radius: number = 24;
  @Param pressed: boolean = false;

  private pointLight(): VisualEffect {
    const enabled: boolean = motionStore.isOn(MotionEffect.HDS_POINT_LIGHT);
    return new hdsEffect.HdsEffectBuilder().pointLight({
      sourceType: enabled && this.pressed ? hdsEffect.PointLightSourceType.SOFT : hdsEffect.PointLightSourceType.NONE,
      illuminatedType: enabled ? hdsEffect.PointLightIlluminatedType.BORDER_CONTENT : hdsEffect.PointLightIlluminatedType.NONE,
      options: { color: AppTheme.TOUCH_LIGHT }
    }).buildEffect();
  }

  private edgeLight(): VisualEffect {
    return new hdsEffect.HdsEffectBuilder().shaderEffect({
      effectType: hdsEffect.EffectType.DUAL_EDGE_FLOW_LIGHT,
      animation: { duration: 1200, iterations: -1 },
      params: { firstEdgeFlowLight: { startPos: 0, endPos: 1, color: AppTheme.FLOW_EDGE_PRIMARY },
        secondEdgeFlowLight: { startPos: 0.5, endPos: 1.5, color: AppTheme.FLOW_EDGE_SECONDARY } }
    }).buildEffect();
  }

  private backgroundLight(): VisualEffect {
    return new hdsEffect.HdsEffectBuilder().shaderEffect({
      effectType: hdsEffect.EffectType.UV_BACKGROUND_FLOW_LIGHT,
      animation: { duration: 1600, iterations: -1 },
      params: { colorSource: [AppTheme.FLOW_BACKGROUND_START, AppTheme.FLOW_BACKGROUND_MIDDLE, AppTheme.FLOW_BACKGROUND_END],
        colorTarget: [AppTheme.FLOW_BACKGROUND_MIDDLE, AppTheme.FLOW_BACKGROUND_END, AppTheme.FLOW_BACKGROUND_START] }
    }).buildEffect();
  }

  build() {
    Stack() {
      Row().width('100%').height('100%').visualEffect(this.pointLight()).hitTestBehavior(HitTestMode.None)
      if (this.pressed && motionStore.isOn(MotionEffect.HDS_BACKGROUND_FLOW)) {
        Row().width('100%').height('100%').visualEffect(this.backgroundLight())
          .opacity(0.18).hitTestBehavior(HitTestMode.None)
      }
      if (this.pressed && motionStore.isOn(MotionEffect.HDS_EDGE_FLOW)) {
        Row().width('100%').height('100%').visualEffect(this.edgeLight()).hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%').height('100%').borderRadius(this.radius).clip(true)
    .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }
}
