/** 全屏看图上下拖动返回的跟手形变与松手提交判定（纯计算，无平台依赖）。 */

const MIN_SCALE: number = 0.65;
const MIN_BACKDROP_OPACITY: number = 0.15;
const PROGRESS_HEIGHT_RATIO: number = 0.45;
const MIN_PROGRESS_TRAVEL: number = 180;
const CHROME_FADE_MULTIPLIER: number = 4;
const DISMISS_DISTANCE_RATIO: number = 0.18;
const DISMISS_DISTANCE_MIN: number = 80;
const DISMISS_DISTANCE_MAX: number = 120;
const DISMISS_VELOCITY_THRESHOLD: number = 600;
const DISMISS_VELOCITY_MIN_OFFSET: number = 24;
const CANCEL_REVERSE_VELOCITY: number = 300;
const FALLBACK_CONTAINER_HEIGHT: number = 800;

export class DismissDragFrame {
  progress: number = 0;
  translateX: number = 0;
  translateY: number = 0;
  scale: number = 1;
  backdropOpacity: number = 1;
  chromeOpacity: number = 1;
}

function finiteOrZero(value: number): number {
  return Number.isFinite(value) ? value : 0;
}

function effectiveHeight(containerHeight: number): number {
  return Number.isFinite(containerHeight) && containerHeight > 0 ? containerHeight : FALLBACK_CONTAINER_HEIGHT;
}

/** 计算当前拖动偏移对应的图片位移、缩放、背景透明度与浮层透明度（上下双向对称）。 */
export function evaluateDismissDrag(offsetX: number, offsetY: number, containerHeight: number): DismissDragFrame {
  const dx: number = finiteOrZero(offsetX);
  const dy: number = finiteOrZero(offsetY);
  const travel: number = Math.max(effectiveHeight(containerHeight) * PROGRESS_HEIGHT_RATIO, MIN_PROGRESS_TRAVEL);
  const progress: number = Math.max(0, Math.min(1, Math.abs(dy) / travel));
  const frame: DismissDragFrame = new DismissDragFrame();
  frame.progress = progress;
  frame.translateX = dx;
  frame.translateY = dy;
  frame.scale = 1 - progress * (1 - MIN_SCALE);
  frame.backdropOpacity = 1 - progress * (1 - MIN_BACKDROP_OPACITY);
  frame.chromeOpacity = Math.max(0, 1 - progress * CHROME_FADE_MULTIPLIER);
  return frame;
}

/** 松手时是否提交关闭：支持上下双向位移或同向轻划速度；明显往回推则取消关闭。 */
export function shouldDismissDrag(offsetY: number, velocityY: number, containerHeight: number): boolean {
  if (!Number.isFinite(offsetY)) { return false; }
  const vy: number = finiteOrZero(velocityY);
  const absY: number = Math.abs(offsetY);
  const absV: number = Math.abs(vy);
  // 用户明显向原点回推，视为取消退出。
  if (offsetY * vy < 0 && absV >= CANCEL_REVERSE_VELOCITY) {
    return false;
  }
  const threshold: number = Math.min(
    DISMISS_DISTANCE_MAX,
    Math.max(DISMISS_DISTANCE_MIN, effectiveHeight(containerHeight) * DISMISS_DISTANCE_RATIO)
  );
  if (absY >= threshold) {
    return true;
  }
  return offsetY * vy > 0 && absV >= DISMISS_VELOCITY_THRESHOLD && absY >= DISMISS_VELOCITY_MIN_OFFSET;
}
