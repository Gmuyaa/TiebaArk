

export class TransferStatsSnapshot {

  elapsedMs: number = 0;

  bytes: number = 0;

  retry: number = 0;

  mode: number = 1;
}

export class TransferStats {

  private static latest: TransferStatsSnapshot | undefined = undefined;

  private static pending: TransferStatsSnapshot | undefined = undefined;

  private static errorNums: number = 0;

  static recordSuccess(elapsedMs: number, bytes: number): void {
    const snapshot: TransferStatsSnapshot = new TransferStatsSnapshot();
    snapshot.elapsedMs = elapsedMs > 0 ? elapsedMs : 0;
    snapshot.bytes = bytes > 0 ? bytes : 0;
    snapshot.retry = 0;
    snapshot.mode = 1;
    TransferStats.latest = snapshot;
    TransferStats.pending = undefined;
  }

  static recordFailure(): void {
    if (TransferStats.pending !== undefined) {
      TransferStats.latest = TransferStats.pending;
      TransferStats.pending = undefined;
    }
    TransferStats.errorNums += 1;
  }

  static take(): TransferStatsSnapshot | undefined {
    const snapshot: TransferStatsSnapshot | undefined = TransferStats.latest;
    if (snapshot === undefined) {
      return undefined;
    }
    TransferStats.latest = undefined;
    TransferStats.pending = snapshot;
    return snapshot;
  }

  static takeErrorNums(): number {
    const value: number = TransferStats.errorNums;
    TransferStats.errorNums = 0;
    return value;
  }

  static reset(): void {
    TransferStats.latest = undefined;
    TransferStats.pending = undefined;
    TransferStats.errorNums = 0;
  }
}
