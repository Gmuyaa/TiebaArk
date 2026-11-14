/**
 * 「同时最多 N 个在飞 + 完成后继续」的调度队列。
 *
 * 只做调度，不含业务判断：取哪一项、取出来要不要跳过、完成后做什么，全由调用方的
 * `next` / `run` 决定。两个使用点（话题卡片补取、搜帖补图）原本各写一份同样的
 * `while (inflight < 2 …)` 循环与「完成后自己减计数再 pump」的收尾，容易改一处漏一处。
 *
 * 纯逻辑、不引 `@kit.*`，可在 Node 用例里直接构造。
 */
export class InflightQueue<T> {
  private queue: T[] = [];
  private inflight: number = 0;
  private readonly limit: number;

  constructor(limit: number) {
    this.limit = limit;
  }

  /** 未派发的任务，保持入队顺序 */
  pending(): T[] { return this.queue; }
  /** 未派发任务数 */
  size(): number { return this.queue.length; }
  /** 正在执行的任务数 */
  inflightCount(): number { return this.inflight; }

  enqueue(item: T): void { this.queue.push(item); }

  /** 丢弃未派发的任务（在飞的不受影响） */
  retain(keep: (item: T) => boolean): void { this.queue = this.queue.filter(keep); }

  clear(): void { this.queue = []; }

  /** 取出并删除第一个满足条件的任务；找不到返回 undefined */
  takeWhere(match: (item: T) => boolean): T | undefined {
    const index: number = this.queue.findIndex(match);
    if (index < 0) { return undefined; }
    return this.queue.splice(index, 1)[0];
  }

  /** 取出并删除队首任务 */
  takeFirst(): T | undefined { return this.queue.shift(); }

  /**
   * 派发到限额。`active()` 为 false 时停止派发（例如执行体已被撤销）；
   * `next()` 返回 undefined 表示这一轮没有可派发的项。
   *
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
