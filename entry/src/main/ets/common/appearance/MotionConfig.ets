/** 动效目录。偏好属于设备设置，不属于缓存或账号数据。 */
export enum MotionGroup { ARKUI = 0, HDS = 1 }

export enum MotionEffect {
  DEFORMATION = 0,
  TOUCH_LIGHT = 1,
  SYSTEM_POPUP = 2,
  SLIDER_PARTICLES = 3,
  FADE = 4,
  MOVE = 5,
  SCALE = 6,
  ROTATE = 7,
  SPRING = 8,
  SHARED_ELEMENT = 9,
  HDS_SCROLL_BLUR = 10,
  HDS_POINT_LIGHT = 11,
  HDS_EDGE_FLOW = 12,
  HDS_BACKGROUND_FLOW = 13,
  HDS_PRESS_LIGHT = 14
}

export interface MotionOption {
  effect: MotionEffect;
  label: string;
}

export const ARKUI_MOTIONS: MotionOption[] = [
  { effect: MotionEffect.DEFORMATION, label: '按压形变' },
  { effect: MotionEffect.TOUCH_LIGHT, label: '光随指动' },
  { effect: MotionEffect.SYSTEM_POPUP, label: '系统弹出动效' },
  { effect: MotionEffect.SLIDER_PARTICLES, label: '滑动粒子' },
  { effect: MotionEffect.FADE, label: '淡入淡出' },
  { effect: MotionEffect.MOVE, label: '位移动画' },
  { effect: MotionEffect.SCALE, label: '缩放动画' },
  { effect: MotionEffect.ROTATE, label: '旋转动画' },
  { effect: MotionEffect.SPRING, label: '弹簧回弹' },
  { effect: MotionEffect.SHARED_ELEMENT, label: '共享元素转场' }
];

export const HDS_MOTIONS: MotionOption[] = [
  { effect: MotionEffect.HDS_SCROLL_BLUR, label: '滚动联动模糊' },
  { effect: MotionEffect.HDS_POINT_LIGHT, label: '点光源与受光' },
  { effect: MotionEffect.HDS_EDGE_FLOW, label: '双边边缘流光' },
  { effect: MotionEffect.HDS_BACKGROUND_FLOW, label: '背景流光' },
  { effect: MotionEffect.HDS_PRESS_LIGHT, label: '按压光效' }
];

export const DEFAULT_MOTION_MASK: number = (1 << 15) - 1;
export const MOTION_STORE: string = 'tieba_motion_prefs';

export function motionGroupOf(effect: MotionEffect): MotionGroup {
  return effect >= MotionEffect.HDS_SCROLL_BLUR ? MotionGroup.HDS : MotionGroup.ARKUI;
}

export function validMotion(effect: number): boolean {
  return Number.isInteger(effect) && effect >= 0 && effect <= MotionEffect.HDS_PRESS_LIGHT;
}

export function normalizeMotionMask(raw: number): number {
  return Number.isInteger(raw) && raw >= 0 && raw <= DEFAULT_MOTION_MASK ? raw : DEFAULT_MOTION_MASK;
}
