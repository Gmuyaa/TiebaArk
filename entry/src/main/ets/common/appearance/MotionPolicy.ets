import { uiMaterial, curves } from '@kit.ArkUI';
import { hdsEffect } from '@kit.UIDesignKit';
import { MotionEffect } from './MotionConfig';
import { motionStore } from './MotionStore';
import { AppTheme } from '../../theme/Theme';

export function motionDuration(duration: number, effect: MotionEffect = MotionEffect.MOVE): number {
  return motionStore.isOn(effect) ? duration : 0;
}

export function motionSpringCurve(effect: MotionEffect = MotionEffect.MOVE): ICurve {
  // 物理弹簧不受 duration 限制，关闭对应效果时必须连同曲线一起降级。
  return motionStore.isOn(effect) && motionStore.isOn(MotionEffect.SPRING)
    ? curves.interpolatingSpring(0, 1, 170, 17) : curves.initCurve(Curve.EaseOut);
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

/** 全屏模态沿用系统过渡，位移关闭后可独立保留淡化。 */
export function motionContentCover(): ModalTransition {
  if (!motionStore.isOn(MotionEffect.SYSTEM_POPUP)) { return ModalTransition.NONE; }
  if (motionStore.isOn(MotionEffect.MOVE)) { return ModalTransition.DEFAULT; }
  return motionStore.isOn(MotionEffect.FADE) ? ModalTransition.ALPHA : ModalTransition.NONE;
}

export function motionTransition(effect: TransitionEffect, kind: MotionEffect = MotionEffect.MOVE): TransitionEffect {
  return motionStore.isOn(kind) ? effect : TransitionEffect.IDENTITY;
}

export function motionGeometryId(id: string): string {
  return motionStore.isOn(MotionEffect.SHARED_ELEMENT) ? id : '';
}

/** 官方未提供粒子独立开关；媒体滑块保留中性材质，普通滑块使用配套主题色。 */
export function sliderMaterial(media: boolean = false): uiMaterial.Material | undefined {
  if (!motionStore.isOn(MotionEffect.SLIDER_PARTICLES)) { return uiMaterial.Material.empty; }
  return new uiMaterial.ImmersiveMaterial({
    materialColor: media ? undefined : AppTheme.MATERIAL_TINT,
    lightEffect: motionStore.isOn(MotionEffect.TOUCH_LIGHT)
      ? { color: media ? Color.White : AppTheme.TOUCH_LIGHT } : null
  });
}

export function pressLight(pressed: boolean): VisualEffect {
  return new hdsEffect.HdsEffectBuilder().pressShadow(pressed && motionStore.isOn(MotionEffect.HDS_PRESS_LIGHT)
    ? hdsEffect.PressShadowType.BLEND_WHITE : hdsEffect.PressShadowType.NONE).buildEffect();
}
