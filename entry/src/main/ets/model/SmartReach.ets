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
