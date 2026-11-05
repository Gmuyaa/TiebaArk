import { hdsEffect } from '@kit.UIDesignKit';
import { MotionEffect } from '../common/appearance/MotionConfig';
import { motionStore } from '../common/appearance/MotionStore';

/** 官方光场只承载背景；文字图标由宿主在整个材质控件上方绘制。 */
@ComponentV2
export struct MaterialMotionLayer {
  @Param radius: number = 24;
  @Param pressed: boolean = false;

  private pointLight(): VisualEffect {
    const enabled: boolean = motionStore.isOn(MotionEffect.HDS_POINT_LIGHT);
    return new hdsEffect.HdsEffectBuilder().pointLight({
      sourceType: enabled && this.pressed ? hdsEffect.PointLightSourceType.SOFT : hdsEffect.PointLightSourceType.NONE,
      illuminatedType: enabled ? hdsEffect.PointLightIlluminatedType.BORDER_CONTENT : hdsEffect.PointLightIlluminatedType.NONE
    }).buildEffect();
  }

  private edgeLight(): VisualEffect {
    return new hdsEffect.HdsEffectBuilder().shaderEffect({
      effectType: hdsEffect.EffectType.DUAL_EDGE_FLOW_LIGHT,
      animation: { duration: 1200, iterations: -1 },
      params: { firstEdgeFlowLight: { startPos: 0, endPos: 1, color: '#9985BFFF' },
        secondEdgeFlowLight: { startPos: 0.5, endPos: 1.5, color: '#9984E1D0' } }
    }).buildEffect();
  }

  private backgroundLight(): VisualEffect {
    return new hdsEffect.HdsEffectBuilder().shaderEffect({
      effectType: hdsEffect.EffectType.UV_BACKGROUND_FLOW_LIGHT,
      animation: { duration: 1600, iterations: -1 },
      params: { colorSource: ['#3385BFFF', '#2284E1D0', '#22C0A7EE'],
        colorTarget: ['#2284E1D0', '#22C0A7EE', '#3385BFFF'] }
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
