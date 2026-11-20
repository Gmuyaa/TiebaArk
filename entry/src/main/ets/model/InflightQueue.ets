/**
 * 「同时最多 N 个在飞 + 完成后继续」的调度队列。
 *
 * 只做调度，不含业务判断：取哪一项、取出来要不要跳过、完成后做什么，全由调用方的
 * `next` / `run` 决定。纯逻辑、不引 `@kit.*`，可在 Node 用例里直接构造。
 */
export class InflightQueue<T> {
  private queue: T[] = [];
  private inflight: number = 0;
  private readonly limit: number;

  constructor(limit: number) {
    this.limit = limit;
  }

  pending(): T[] { return this.queue; }
  size(): number { return this.queue.length; }
  inflightCount(): number { return this.inflight; }

  enqueue(item: T): void { this.queue.push(item); }

  /** 丢弃未派发的任务（在飞的不受影响） */
  retain(keep: (item: T) => boolean): void { this.queue = this.queue.filter(keep); }

  clear(): void { this.queue = []; }

  takeWhere(match: (item: T) => boolean): T | undefined {
    const index: number = this.queue.findIndex(match);
    if (index < 0) { return undefined; }
    return this.queue.splice(index, 1)[0];
  }

  takeFirst(): T | undefined { return this.queue.shift(); }

  /**
   * `run` 的异常由本方法吞掉：失败怎么记（冷却、计数、保留兜底）是调用方的事，
   * 但无论如何都要把在飞计数还回来并继续派发，否则队列会永久卡死。
   */
  pump(active: () => boolean, next: () => T | undefined, run: (item: T) => Promise<void>): void {
    while (this.inflight < this.limit && active()) {
      const item: T | undefined = next();
      if (item === undefined) { return; }
      this.inflight++;
      const task: Promise<void> = (async (): Promise<void> => {
        try {
          await run(item);
        } catch (_) {
          // 由 run 自己记录失败原因；这里只保证队列不被一次异常卡死。
        } finally {
          this.inflight--;
        }
      })();
      void task.then((): void => { this.pump(active, next, run); });
    }
  }
}
