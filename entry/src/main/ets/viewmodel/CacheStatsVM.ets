import { storageStatistics } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { CacheMeasure, CachePhase, cachePhaseOf, formatSystemCacheBytes } from '../model/CacheClean';
import { measureApplicationCache } from '../utils/ApplicationCache';

/** 系统应用缓存总量与导出目录的可清理量属于不同统计范围。 */
@ObservedV2
export class CacheStatsVM {
  @Trace loading: boolean = true;
  @Trace failed: boolean = false;
  @Trace bytes: number = 0;
  @Trace measure: CacheMeasure = new CacheMeasure();
  @Trace phase: CachePhase = CachePhase.STATTING;
  private requestSeq: number = 0;

  label(): string {
    if (this.loading) {
      return '正在统计…';
    }
    return this.failed ? '读取失败' : formatSystemCacheBytes(this.bytes);
  }

  async refresh(context: common.Context): Promise<void> {
    const seq: number = ++this.requestSeq;
    this.loading = true;
    this.failed = false;
    this.phase = CachePhase.STATTING;
    const files: Promise<void> = this.readFiles(context, seq);
    try {
      const stats: storageStatistics.BundleStats = await storageStatistics.getCurrentBundleStats();
      if (seq !== this.requestSeq) {
        return;
      }
      if (!Number.isFinite(stats.cacheSize) || stats.cacheSize < 0) {
        this.failed = true;
      } else {
        this.bytes = stats.cacheSize;
      }
    } catch (_) {
      if (seq === this.requestSeq) {
        this.failed = true;
      }
    } finally {
      if (seq === this.requestSeq) {
        this.loading = false;
      }
      await files;
    }
  }

  private async readFiles(context: common.Context, seq: number): Promise<void> {
    const measure: CacheMeasure = await measureApplicationCache(context);
    if (seq === this.requestSeq) {
      this.measure = measure;
      this.phase = cachePhaseOf(measure);
    }
  }

  beginClear(): void {
    this.requestSeq += 1;
    this.loading = false;
    this.phase = CachePhase.CLEARING;
  }

  dispose(): void {
    this.requestSeq += 1;
  }
}
