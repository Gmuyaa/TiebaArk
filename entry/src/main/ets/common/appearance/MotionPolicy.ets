import { uiMaterial, curves } from '@kit.ArkUI';
import { hdsEffect } from '@kit.UIDesignKit';
import { MotionEffect } from './MotionConfig';
import { motionStore } from './MotionStore';

export function motionDuration(duration: number, effect: MotionEffect = MotionEffect.MOVE): number {
  return motionStore.isOn(effect) ? duration : 0;
}

export function motionSpringCurve(): ICurve {
  return motionStore.isOn(MotionEffect.SPRING) ? curves.interpolatingSpring(0, 1, 170, 17) : curves.initCurve(Curve.EaseOut);
}

/** Swiper 默认弹簧曲线不受 duration 限制；关闭位移时必须同时换成时间曲线。 */
export function motionSwiperCurve(): ICurve {
  return motionStore.isOn(MotionEffect.MOVE) ? motionSpringCurve() : curves.initCurve(Curve.EaseOut);
}

export function motionEdgeEffect(): EdgeEffect {
  return motionStore.isOn(MotionEffect.SPRING) ? EdgeEffect.Spring : EdgeEffect.None;
}

/** 显式无过渡以覆盖系统进出场，保留静态材质。 */
export function popupMotion(): TransitionEffect | undefined {
  return motionStore.isOn(MotionEffect.SYSTEM_POPUP) ? undefined : TransitionEffect.IDENTITY;
}

export function motionTransition(effect: TransitionEffect, kind: MotionEffect = MotionEffect.MOVE): TransitionEffect {
  return motionStore.isOn(kind) ? effect : TransitionEffect.IDENTITY;
}

export function motionGeometryId(id: string): string {
  return motionStore.isOn(MotionEffect.SHARED_ELEMENT) ? id : '';
}

/** 官方未提供粒子独立开关，关闭时使用常规滑块，不伪造粒子配置。 */
export function sliderMaterial(): uiMaterial.Material | undefined {
  return motionStore.isOn(MotionEffect.SLIDER_PARTICLES) ? new uiMaterial.ImmersiveMaterial() : uiMaterial.Material.empty;
}

export function pressLight(pressed: boolean): VisualEffect {
  return new hdsEffect.HdsEffectBuilder().pressShadow(pressed && motionStore.isOn(MotionEffect.HDS_PRESS_LIGHT)
    ? hdsEffect.PressShadowType.BLEND_WHITE : hdsEffect.PressShadowType.NONE).buildEffect();
}
