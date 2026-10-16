/** 写请求反爬参数所需的传输统计，不包含业务账号信息。 */

/** 一条传输统计（对应官方 `NetWorkState.StatisticsData`） */
export class TransferStatsSnapshot {
  /** 上一条请求的耗时（毫秒），对应官方 `allCostTime` → `stTime` */
  elapsedMs: number = 0;
  /** 上一条响应的响应体字节数，对应官方 `downloadSize` → `stSize` */
  bytes: number = 0;
  /** 重试次数，对应官方 `retry` → `stTimesNum`（本项目不自动重试，恒 0） */
  retry: number = 0;
  /** 网络模式，对应官方 `getMode(netType())` → `stMode`（本项目不判定网络类型，取官方缺省分支 1） */
  mode: number = 1;
}

export class TransferStats {
  /** 最近一条成功响应的统计（等下一次写请求取用） */
  private static latest: TransferStatsSnapshot | undefined = undefined;
  /** 已被写请求取走、尚未被自身响应覆盖的统计（失败时要放回） */
  private static pending: TransferStatsSnapshot | undefined = undefined;
  /** 错误计数，对应官方 `NetWorkState.mErrorNums` */
  private static errorNums: number = 0;

  /**
   * 成功拿到响应后调用：记下这一条统计，并丢弃此前被取走待确认的那条。
   *
   * 错误计数**不在这里清零**：官方只在写请求构造时 `getErrorNumsAndSet(0)` 读后清零，
   * 没有取证表明成功响应会清错误数，故本实现只由 `takeErrorNums()` 清零。
   */
  static recordSuccess(elapsedMs: number, bytes: number): void {
    const snapshot: TransferStatsSnapshot = new TransferStatsSnapshot();
    snapshot.elapsedMs = elapsedMs > 0 ? elapsedMs : 0;
    snapshot.bytes = bytes > 0 ? bytes : 0;
    snapshot.retry = 0;
    snapshot.mode = 1;
    TransferStats.latest = snapshot;
    TransferStats.pending = undefined;
  }

  /** 响应不成功时调用：把取走的统计放回，并累加错误数 */
  static recordFailure(): void {
    if (TransferStats.pending !== undefined) {
      TransferStats.latest = TransferStats.pending;
      TransferStats.pending = undefined;
    }
    TransferStats.errorNums += 1;
  }

  /** 取走最近一条统计（官方 `delStatisticsData()` 也是取走）；没有则返回 undefined */
  static take(): TransferStatsSnapshot | undefined {
    const snapshot: TransferStatsSnapshot | undefined = TransferStats.latest;
    if (snapshot === undefined) {
      return undefined;
    }
    TransferStats.latest = undefined;
    TransferStats.pending = snapshot;
    return snapshot;
  }

  /** 读出并清零错误计数（官方 `NetWorkState.getErrorNumsAndSet(0)`） */
  static takeErrorNums(): number {
    const value: number = TransferStats.errorNums;
    TransferStats.errorNums = 0;
    return value;
  }

  /** 清空进程内状态，只给用例用 */
  static reset(): void {
    TransferStats.latest = undefined;
    TransferStats.pending = undefined;
    TransferStats.errorNums = 0;
  }
}
