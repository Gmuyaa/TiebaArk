/**
 * 偏好读写的共享机制：并发读去重、串行落盘、代次守卫。
 *
 * 这三件事原本在 9 个设置 Store 里各写一遍，且能力不齐（6 个没有并发读去重：
 * 旧实现在 `await` 之前就置 `loaded`，第二个调用方会立刻拿到默认值）。
 *
 * 本文件**不含任何 `@Trace` 状态**，也不引 `@kit.*`：偏好语义（字段、默认值、错误文案）
 * 仍留在各 Store，这里只放机制，因此可以进 Node 镜像直接跑。
 */
export class PreferenceGate {
  private loaded: boolean = false;
  private loading: Promise<void> | undefined = undefined;
  private queue: Promise<void> = Promise.resolve();
  private stamp: number = 0;

  isLoaded(): boolean { return this.loaded; }

  /**
   * 由读取回调在「读到的值可接受」时调用。
   * 读盘失败或值非法时**不要**调用：下次进页面会再试一次（与原实现里 `loaded = valid` 的语义一致）。
   */
  markLoaded(): void { this.loaded = true; }

  /** 当前代次。读取落值前用它比对，判断期间是否有更新的写入／读取把结果变旧。 */
  revision(): number { return this.stamp; }

  /** 取一个新代次：每次写入前调用；迟到读取与旧写入不得覆盖它。 */
  bump(): number { return ++this.stamp; }

  /**
   * 只真正读一次；并发调用共享同一个 promise。
   *
   * `read` 收到开始时的代次快照：落值前应比对 `revision()`，不一致说明期间已被写入超越，丢弃本次结果。
   * 回调内部的异常由回调自己记录（各 Store 都有 catch + hilog），这里只保证不把异常漏给调用方。
   */
  async loadOnce(read: (revision: number) => Promise<void>): Promise<void> {
    if (this.loaded) { return; }
    if (this.loading !== undefined) { return this.loading; }
    const revision: number = this.stamp;
    const operation: Promise<void> = (async (): Promise<void> => {
      try {
        await read(revision);
      } catch (_) {
        // 读取失败：保持未加载，允许下次重试；错误由回调自己上报。
      }
    })();
    this.loading = operation;
    try {
      await operation;
    } finally {
      if (this.loading === operation) { this.loading = undefined; }
    }
  }

  /**
   * 串行执行一次落盘（或需要与落盘互斥的读）。
   *
   * 队列自身吞掉拒绝，避免一次失败卡死后续；本次操作的拒绝仍抛给调用方，
   * 由各 Store 决定写进 `saveError` 还是向上抛。
   */
  async enqueue(operation: () => Promise<void>): Promise<void> {
    const next: Promise<void> = this.queue.then(operation);
    this.queue = next.catch((): void => {});
    await next;
  }
}
