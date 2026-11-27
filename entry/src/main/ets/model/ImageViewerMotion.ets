/** 全屏图片查看器的缩放上限、双击等宽/复原、惯性滑行与右侧长图定位条几何（纯计算，无平台依赖）。 */

export const VIEWER_MIN_SCALE: number = 1;
export const VIEWER_DEFAULT_MAX_SCALE: number = 4;
export const VIEWER_HARD_MAX_SCALE: number = 40;
export const VIEWER_DEFAULT_DOUBLE_TAP_SCALE: number = 2;
/** 1× 下拟合宽度明显小于屏宽时，双击按屏宽放大；避免仅差几像素的图被微幅缩放。 */
export const VIEWER_FIT_WIDTH_EPSILON: number = 1.05;
/** 触发右侧长图缩略图定位条的最小高宽比（高 ≥ 2 × 宽）。 */
export const VIEWER_LONG_MINIMAP_MIN_HEIGHT_RATIO: number = 2;

export const VIEWER_MIN_FLING_VELOCITY: number = 120;
export const VIEWER_STOP_FLING_VELOCITY: number = 18;
export const VIEWER_MAX_FLING_VELOCITY: number = 12000;
const FLING_DECEL: number = 3.2;
const EDGE_SPRING_OMEGA: number = 15;
const EDGE_IMPACT_DAMPING: number = 0.35;
const EDGE_RESISTANCE_FACTOR: number = 0.55;
const EDGE_MAX_OVERSCROLL: number = 120;

export const MINIMAP_DEFAULT_WIDTH: number = 44;
export const MINIMAP_MIN_WIDTH: number = 28;
export const MINIMAP_RIGHT_MARGIN: number = 10;
export const MINIMAP_MIN_WINDOW_HEIGHT: number = 16;

export class ViewerTransform {
  scale: number = VIEWER_MIN_SCALE;
  panX: number = 0;
  panY: number = 0;
}

export class FlingMotionState {
  panX: number = 0;
  panY: number = 0;
  velocityX: number = 0;
  velocityY: number = 0;
  settled: boolean = false;
}

export class LongMinimapLayout {
  visible: boolean = false;
  stripX: number = 0;
  stripY: number = 0;
  stripWidth: number = 0;
  stripHeight: number = 0;
  windowTop: number = 0;
  windowHeight: number = 0;
  topMaskHeight: number = 0;
  bottomMaskTop: number = 0;
  bottomMaskHeight: number = 0;
}

class AxisStepResult {
  pos: number = 0;
  vel: number = 0;
  settled: boolean = true;
}

function finiteOrZero(value: number): number {
  return Number.isFinite(value) ? value : 0;
}

function clamp(value: number, low: number, high: number): number {
  if (high < low) { return low; }
  return Math.max(low, Math.min(high, value));
}

/** 1× Contain 拟合图放大至与容器等宽所需的倍率；已满宽或参数无效时返回 1。 */
export function viewerFitWidthScale(containerWidth: number, fitWidth: number): number {
  if (!Number.isFinite(containerWidth) || !Number.isFinite(fitWidth) ||
    containerWidth <= 0 || fitWidth <= 0) {
    return VIEWER_MIN_SCALE;
  }
  const ratio: number = containerWidth / fitWidth;
  return Number.isFinite(ratio) && ratio > VIEWER_MIN_SCALE ? ratio : VIEWER_MIN_SCALE;
}

/** 动态缩放上限：普通图保持 4×，长图至少允许放大到 2 倍屏宽以便阅读细节。 */
export function viewerMaxScale(containerWidth: number, fitWidth: number): number {
  const fitScale: number = viewerFitWidthScale(containerWidth, fitWidth);
  return Math.min(VIEWER_HARD_MAX_SCALE, Math.max(VIEWER_DEFAULT_MAX_SCALE, fitScale * 2));
}

/** 双击目标倍率：已放大则缩回 1×；1× 下窄于屏幕则放大到精确屏宽，否则沿用 2×。 */
export function viewerDoubleTapScale(currentScale: number, containerWidth: number, fitWidth: number): number {
  const safeScale: number = Number.isFinite(currentScale) ? currentScale : VIEWER_MIN_SCALE;
  if (safeScale > VIEWER_MIN_SCALE + 0.01) {
    return VIEWER_MIN_SCALE;
  }
  const fitScale: number = viewerFitWidthScale(containerWidth, fitWidth);
  if (fitScale > VIEWER_FIT_WIDTH_EPSILON) {
    return Math.min(viewerMaxScale(containerWidth, fitWidth), fitScale);
  }
  return VIEWER_DEFAULT_DOUBLE_TAP_SCALE;
}

export function viewerOffsetLimit(containerExtent: number, fitExtent: number, scale: number): number {
  if (!Number.isFinite(containerExtent) || !Number.isFinite(fitExtent) || !Number.isFinite(scale) ||
    containerExtent <= 0 || fitExtent <= 0 || scale <= 0) {
    return 0;
  }
  return Math.max(0, (fitExtent * scale - containerExtent) / 2);
}

/** 围绕容器内焦点 `(focalX, focalY)` 缩放，并同步换算夹紧后的位移；缩回 1× 时归零。 */
export function zoomAroundPoint(
  containerWidth: number,
  containerHeight: number,
  fitWidth: number,
  fitHeight: number,
  oldScale: number,
  newScale: number,
  oldPanX: number,
  oldPanY: number,
  focalX: number,
  focalY: number
): ViewerTransform {
  const result: ViewerTransform = new ViewerTransform();
  const maxScale: number = viewerMaxScale(containerWidth, fitWidth);
  const clampedNew: number = clamp(Number.isFinite(newScale) ? newScale : VIEWER_MIN_SCALE,
    VIEWER_MIN_SCALE, maxScale);
  result.scale = clampedNew;
  if (clampedNew <= VIEWER_MIN_SCALE + 0.0001 ||
    !Number.isFinite(containerWidth) || !Number.isFinite(containerHeight) ||
    containerWidth <= 0 || containerHeight <= 0) {
    result.scale = VIEWER_MIN_SCALE;
    result.panX = 0;
    result.panY = 0;
    return result;
  }
  const safeOld: number = Number.isFinite(oldScale) && oldScale > 0 ? oldScale : VIEWER_MIN_SCALE;
  const fx: number = Number.isFinite(focalX) ? focalX : containerWidth / 2;
  const fy: number = Number.isFinite(focalY) ? focalY : containerHeight / 2;
  const dx: number = fx - containerWidth / 2;
  const dy: number = fy - containerHeight / 2;
  const ratio: number = clampedNew / safeOld;
  const rawX: number = dx - (dx - finiteOrZero(oldPanX)) * ratio;
  const rawY: number = dy - (dy - finiteOrZero(oldPanY)) * ratio;
  const limitX: number = viewerOffsetLimit(containerWidth, fitWidth, clampedNew);
  const limitY: number = viewerOffsetLimit(containerHeight, fitHeight, clampedNew);
  result.panX = clamp(rawX, -limitX, limitX);
  result.panY = clamp(rawY, -limitY, limitY);
  return result;
}

/** 边界内 1:1 跟手，拖越边界后施加渐进橡皮筋阻尼。 */
export function applyEdgeResistance(rawOffset: number, limit: number, viewportExtent: number): number {
  const offset: number = finiteOrZero(rawOffset);
  const safeLimit: number = Math.max(0, finiteOrZero(limit));
  if (Math.abs(offset) <= safeLimit) {
    return offset;
  }
  const excess: number = Math.abs(offset) - safeLimit;
  const dim: number = Math.max(200, Number.isFinite(viewportExtent) && viewportExtent > 0 ? viewportExtent : 400);
  const maxPull: number = Math.min(dim * 0.25, EDGE_MAX_OVERSCROLL);
  const resisted: number = Math.min(maxPull,
    (excess * EDGE_RESISTANCE_FACTOR * dim) / (dim + EDGE_RESISTANCE_FACTOR * excess));
  return offset >= 0 ? safeLimit + resisted : -(safeLimit + resisted);
}

function stepAxis(pos: number, vel: number, limit: number, dt: number, springEnabled: boolean): AxisStepResult {
  const out: AxisStepResult = new AxisStepResult();
  const safeLimit: number = Math.max(0, finiteOrZero(limit));
  const curPos: number = finiteOrZero(pos);
  const curVel: number = clamp(finiteOrZero(vel), -VIEWER_MAX_FLING_VELOCITY, VIEWER_MAX_FLING_VELOCITY);

  if (Math.abs(curPos) <= safeLimit) {
    if (Math.abs(curVel) <= VIEWER_STOP_FLING_VELOCITY) {
      out.pos = curPos;
      out.vel = 0;
      out.settled = true;
      return out;
    }
    const decay: number = Math.exp(-FLING_DECEL * dt);
    const nextPos: number = curPos + curVel * (1 - decay) / FLING_DECEL;
    const nextVel: number = curVel * decay;
    if (Math.abs(nextPos) <= safeLimit) {
      out.pos = nextPos;
      out.vel = Math.abs(nextVel) <= VIEWER_STOP_FLING_VELOCITY ? 0 : nextVel;
      out.settled = out.vel === 0;
      return out;
    }
    const boundary: number = nextPos > safeLimit ? safeLimit : -safeLimit;
    if (!springEnabled) {
      out.pos = boundary;
      out.vel = 0;
      out.settled = true;
      return out;
    }
    // 撞边时立即按系数吸收冲击动量，后续帧由临界阻尼弹簧平滑收回边界。
    const dampedVel: number = nextVel * EDGE_IMPACT_DAMPING;
    const overshoot: number = clamp(nextPos - boundary, -36, 36);
    out.pos = boundary + overshoot;
    out.vel = dampedVel;
    out.settled = false;
    return out;
  }

  const boundary: number = curPos > safeLimit ? safeLimit : -safeLimit;
  if (!springEnabled) {
    out.pos = boundary;
    out.vel = 0;
    out.settled = true;
    return out;
  }
  const disp: number = curPos - boundary;
  const exp: number = Math.exp(-EDGE_SPRING_OMEGA * dt);
  const coeff: number = curVel + EDGE_SPRING_OMEGA * disp;
  const nextDisp: number = (disp + coeff * dt) * exp;
  const nextVel: number = (curVel - EDGE_SPRING_OMEGA * coeff * dt) * exp;
  if (Math.abs(nextDisp) < 0.5 && Math.abs(nextVel) < VIEWER_STOP_FLING_VELOCITY) {
    out.pos = boundary;
    out.vel = 0;
    out.settled = true;
    return out;
  }
  out.pos = boundary + nextDisp;
  out.vel = nextVel;
  out.settled = false;
  return out;
}

/** 推进一帧惯性滑行或边缘弹簧回弹；`dtSec` 被夹紧在 `(0, 0.05]` 内以免疫掉帧尖刺。 */
export function stepFlingMotion(
  state: FlingMotionState,
  dtSec: number,
  limitX: number,
  limitY: number,
  springEnabled: boolean
): FlingMotionState {
  const dt: number = clamp(Number.isFinite(dtSec) && dtSec > 0 ? dtSec : 1 / 60, 0.001, 0.05);
  const x: AxisStepResult = stepAxis(state.panX, state.velocityX, limitX, dt, springEnabled);
  const y: AxisStepResult = stepAxis(state.panY, state.velocityY, limitY, dt, springEnabled);
  const next: FlingMotionState = new FlingMotionState();
  next.panX = x.pos;
  next.panY = y.pos;
  next.velocityX = x.vel;
  next.velocityY = y.vel;
  next.settled = x.settled && y.settled;
  return next;
}

/** 是否按长图口径显示右侧缩略图定位条（显式长图标记，或高宽比 ≥ 2）。 */
export function isLongImageForMinimap(sourceWidth: number, sourceHeight: number, explicitLong: boolean): boolean {
  if (explicitLong) { return true; }
  if (!Number.isFinite(sourceWidth) || !Number.isFinite(sourceHeight) ||
    sourceWidth <= 0 || sourceHeight <= 0) {
    return false;
  }
  return sourceHeight / sourceWidth >= VIEWER_LONG_MINIMAP_MIN_HEIGHT_RATIO;
}

/** 计算右侧长图缩略图定位条及当前视口高亮框的几何位置（单位 vp）。 */
export function computeLongMinimap(
  containerWidth: number,
  containerHeight: number,
  fitWidth: number,
  fitHeight: number,
  sourceWidth: number,
  sourceHeight: number,
  explicitLong: boolean,
  scale: number,
  panY: number,
  topInset: number,
  bottomInset: number
): LongMinimapLayout {
  const layout: LongMinimapLayout = new LongMinimapLayout();
  if (!Number.isFinite(containerWidth) || !Number.isFinite(containerHeight) ||
    containerWidth <= 0 || containerHeight <= 0 ||
    !Number.isFinite(fitWidth) || !Number.isFinite(fitHeight) ||
    fitWidth <= 0 || fitHeight <= 0 ||
    !Number.isFinite(scale) || scale <= VIEWER_MIN_SCALE + 0.01) {
    return layout;
  }
  if (!isLongImageForMinimap(sourceWidth, sourceHeight, explicitLong)) {
    return layout;
  }
  const drawHeight: number = fitHeight * scale;
  if (!Number.isFinite(drawHeight) || drawHeight <= containerHeight + 1) {
    return layout;
  }

  const aspect: number = Number.isFinite(sourceWidth) && Number.isFinite(sourceHeight) &&
    sourceWidth > 0 && sourceHeight > 0 ? sourceWidth / sourceHeight : fitWidth / fitHeight;
  if (!Number.isFinite(aspect) || aspect <= 0) {
    return layout;
  }

  const safeTop: number = Math.max(24, finiteOrZero(topInset) + 16);
  const safeBottom: number = Math.max(72, finiteOrZero(bottomInset) + 56);
  const maxHeight: number = Math.max(88, containerHeight - safeTop - safeBottom);
  const naturalHeight: number = MINIMAP_DEFAULT_WIDTH / aspect;

  let stripWidth: number = MINIMAP_DEFAULT_WIDTH;
  let stripHeight: number = naturalHeight;
  if (naturalHeight > maxHeight) {
    stripHeight = maxHeight;
    stripWidth = clamp(maxHeight * aspect, MINIMAP_MIN_WIDTH, MINIMAP_DEFAULT_WIDTH);
  } else if (naturalHeight < 88) {
    stripHeight = 88;
  }
  stripWidth = Math.min(stripWidth, Math.max(MINIMAP_MIN_WIDTH, containerWidth * 0.2));

  const limitY: number = Math.max(0, (drawHeight - containerHeight) / 2);
  const clampedPanY: number = clamp(finiteOrZero(panY), -limitY, limitY);
  const visibleFraction: number = clamp(containerHeight / drawHeight, 0, 1);
  const windowHeight: number = Math.min(stripHeight, Math.max(MINIMAP_MIN_WINDOW_HEIGHT, visibleFraction * stripHeight));
  const maxWindowTop: number = Math.max(0, stripHeight - windowHeight);
  const progress: number = limitY > 0 ? clamp((limitY - clampedPanY) / (2 * limitY), 0, 1) : 0;
  const windowTop: number = progress * maxWindowTop;

  layout.visible = true;
  layout.stripWidth = stripWidth;
  layout.stripHeight = stripHeight;
  layout.stripX = Math.max(MINIMAP_RIGHT_MARGIN, containerWidth - MINIMAP_RIGHT_MARGIN - stripWidth);
  layout.stripY = safeTop + Math.max(0, (maxHeight - stripHeight) / 2);
  layout.windowTop = windowTop;
  layout.windowHeight = windowHeight;
  layout.topMaskHeight = windowTop;
  layout.bottomMaskTop = windowTop + windowHeight;
  layout.bottomMaskHeight = Math.max(0, stripHeight - layout.bottomMaskTop);
  return layout;
}

/** 将定位条内的纵向触点坐标（相对条顶）映射为目标 `panY`（`+limitY` 为图顶，`-limitY` 为图底）。 */
export function minimapScrubPanY(localY: number, stripHeight: number, windowHeight: number, limitY: number): number {
  if (!Number.isFinite(localY) || !Number.isFinite(stripHeight) || !Number.isFinite(windowHeight) ||
    !Number.isFinite(limitY) || stripHeight <= 0 || limitY <= 0) {
    return 0;
  }
  const safeWindow: number = clamp(windowHeight, 0, stripHeight);
  const maxWindowTop: number = stripHeight - safeWindow;
  if (maxWindowTop <= 0) { return 0; }
  const targetTop: number = clamp(localY - safeWindow / 2, 0, maxWindowTop);
  const progress: number = targetTop / maxWindowTop;
  return limitY - progress * (2 * limitY);
}
