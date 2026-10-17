/** 握姿与悬浮按钮几何：无平台依赖，真实握姿由 motion 服务提供。 */
export interface FloatingBounds {
  minX: number;
  maxX: number;
  minY: number;
  maxY: number;
}

export function floatingBounds(width: number, height: number, top: number): FloatingBounds {
  return { minX: 16, maxX: Math.max(16, width - 64),
    minY: Math.min(Math.max(8, top + 8), Math.max(8, height - 64)),
    maxY: Math.max(8, height - 64) };
}

export const THREAD_ACTION_BUTTON_SIZE: number = 52;
export const THREAD_ACTION_HIT_INSET: number = 4;

/** 帖子按钮的拖拽范围；松手吸边由组件处理。 */
export function threadActionBounds(width: number, height: number, top: number): FloatingBounds {
  const maxX: number = Math.max(0, width - THREAD_ACTION_BUTTON_SIZE - 14);
  const maxY: number = Math.max(0, height - THREAD_ACTION_BUTTON_SIZE - 24);
  return { minX: Math.min(14, maxX), maxX,
    minY: Math.min(Math.max(8, top + 8), maxY), maxY };
}

/** 以上下半屏分界，优先朝空余较多的一侧展开。 */
export function threadActionOpensUp(y: number, height: number): boolean {
  return y + THREAD_ACTION_BUTTON_SIZE / 2 >= height / 2;
}

export interface ThreadFanPoint { x: number; y: number; }

/** 五个圆面朝屏幕内侧展开；优先贴近主按钮，边缘空间不足时再增大半径。 */
export function threadFanPoints(x: number, y: number, width: number, height: number, top: number): ThreadFanPoint[] {
  const size: number = THREAD_ACTION_BUTTON_SIZE;
  const half: number = size / 2;
  const cx: number = x + half;
  const cy: number = y + half;
  const left: boolean = cx <= width / 2;
  const maxY: number = Math.max(half, height - 8 - half);
  const minY: number = Math.min(maxY, Math.max(half, top + 8 + half));
  const up: number = Math.max(0, cy - minY);
  const down: number = Math.max(0, maxY - cy);
  const inward: number = Math.max(0, left ? width - 8 - half - cx : cx - 8 - half);
  for (let radius: number = 96; radius <= 160; radius += 8) {
    if (radius > inward) { continue; }
    const minAngle: number = -Math.asin(Math.min(1, up / radius));
    const maxAngle: number = Math.asin(Math.min(1, down / radius));
    // 相邻圆之间至少留8vp，防止触摸范围重叠。
    const minimumSweep: number = 8 * Math.asin((size + 8) / (2 * radius));
    if (maxAngle - minAngle < minimumSweep) { continue; }
    const sweep: number = Math.min(maxAngle - minAngle, Math.max(Math.PI / 2, minimumSweep));
    const start: number = clampFloating(threadActionOpensUp(y, height) ? -sweep : 0, minAngle, maxAngle - sweep);
    const points: ThreadFanPoint[] = [];
    for (let index: number = 0; index < 5; index++) {
      const angle: number = start + sweep * index / 4;
      points.push({ x: cx + (left ? 1 : -1) * radius * Math.cos(angle) - half,
        y: cy + radius * Math.sin(angle) - half });
    }
    return points;
  }
  // 正文高度不足以容纳圆弧时仍保留五个独立入口，改用紧凑的两行布局。
  const gridWidth: number = size * 3 + 16;
  const gridHeight: number = size * 2 + 8;
  const gridX: number = clampFloating(left ? x + size + 8 : x - gridWidth - 8, 8, Math.max(8, width - 8 - gridWidth));
  const gridY: number = clampFloating(y, Math.max(8, top + 8), Math.max(Math.max(8, top + 8), height - 8 - gridHeight));
  const fallback: ThreadFanPoint[] = [];
  for (let index: number = 0; index < 5; index++) {
    fallback.push({ x: gridX + (index % 3) * (size + 8), y: gridY + Math.floor(index / 3) * (size + 8) });
  }
  return fallback;
}

export function clampFloating(value: number, min: number, max: number): number {
  return Number.isFinite(value) ? Math.max(min, Math.min(max, value)) : min;
}

export function positionRatio(value: number, min: number, max: number): number {
  return max > min ? (clampFloating(value, min, max) - min) / (max - min) : 0;
}

export function dockFloatingX(value: number, bounds: FloatingBounds): number {
  return clampFloating(value, bounds.minX, bounds.maxX) < (bounds.minX + bounds.maxX) / 2 ?
    bounds.minX : bounds.maxX;
}

/** 只有明确左右单手才换边；双手、未握持和未知保持原位置。 */
export function holdingSide(status: number): number {
  return status === 1 ? -1 : status === 2 ? 1 : 0;
}

export interface HoldingSource {
  on(callback: (status: number) => void): void;
  off(callback: (status: number) => void): void;
}

/** 只取消自己的订阅；离页/关闭后即使旧回调到达，也不能再发布握姿。 */
export class HoldingSession {
  private callback: ((status: number) => void) | undefined = undefined;
  private generation: number = 0;
  private running: boolean = false;
  private source: HoldingSource;
  private publish: (status: number) => void;
  constructor(source: HoldingSource, publish: (status: number) => void) {
    this.source = source; this.publish = publish;
  }

  start(): void {
    if (this.running) { return; }
    if (this.callback !== undefined) { this.stop(); }
    const generation: number = ++this.generation;
    const callback = (status: number): void => {
      if (this.running && generation === this.generation) { this.publish(status); }
    };
    this.running = true;
    try { this.source.on(callback); this.callback = callback; }
    catch (error) { this.running = false; ++this.generation; throw error as Error; }
  }

  stop(): void {
    this.running = false;
    ++this.generation;
    if (this.callback === undefined) { return; }
    // 取消失败时保留引用，下一次start先重试清理，避免叠加监听。
    this.source.off(this.callback);
    this.callback = undefined;
  }
}
