
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CacheMeasure } from '../model/CacheClean';

const DOMAIN: number = 0x0;
const TAG: string = 'CacheClean';
/** 导出缓存目录（与 `utils/ImageExport.ets` 的 `writeImageToCache` 同一路径） */
const EXPORT_DIR_NAME: string = 'export';

/** 一次清理的结果 */
export class ClearResult {
  /** 成功删除的文件数 */
  cleared: number = 0;
  /** 删除失败的文件数（如实上报，不合并进成功数） */
  failed: number = 0;
  /** 删除成功文件的逻辑字节数，不能当作系统实际回收块空间的精确差值。 */
  freedBytes: number = 0;
}

function exportDir(context: common.Context): string {
  return `${context.cacheDir}/${EXPORT_DIR_NAME}`;
}

class ListResult {
  /** 是否成功列举（`false` = 权限/IO 失败，**不是**"目录是空的"） */
  ok: boolean = false;
  /** 目录不存在（第一次导出之前）= 确实为空，不是失败 */
  missing: boolean = false;
  names: string[] = [];
}

/** 列出目录里的条目名；失败**不抛给界面**，但把失败事实带出去。 */
function listEntries(dir: string): ListResult {
  const result: ListResult = new ListResult();
  try {
    if (!fileIo.accessSync(dir)) {
      result.ok = true;
      result.missing = true;
      return result;
    }
    result.names = fileIo.listFileSync(dir);
    result.ok = true;
    return result;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'list failed: %{public}s', String(e));
    return result;
  }
}

/** 单条目的逻辑大小；取不到（并发删除/权限）时返回 -1，由调用方决定怎么处理 */
function entrySize(path: string): number {
  try {
    return fileIo.statSync(path).size;
  } catch (e) {
    return -1;
  }
}

export function measureExportCache(context: common.Context): CacheMeasure {
  const dir: string = exportDir(context);
  const listed: ListResult = listEntries(dir);
  const measure: CacheMeasure = new CacheMeasure();
  if (!listed.ok) {
    // 读取失败：`ok` 保持 false，页面据此走"读取失败"分支而不是"为空"
    return measure;
  }
  measure.ok = true;
  measure.missing = listed.missing;
  for (let i = 0; i < listed.names.length; i++) {
    const path: string = `${dir}/${listed.names[i]}`;
    try {
      const stat: fileIo.Stat = fileIo.statSync(path);
      if (stat.isDirectory()) {
        continue;
      }
      measure.bytes += stat.size;
      measure.entries += 1;
    } catch (e) {
      // 单个条目 stat 失败（并发/已删）不再静默吞掉：记进 skipped，页面如实展示"部分统计失败"
      measure.skipped += 1;
    }
  }
  return measure;
}

/**
 * 清掉 `cacheDir/export` 里的文件（**目录本身保留**，下次导出还要用）。
 *
 * 逐个删而不是整目录删：整目录删在部分场景下会连带清掉系统对缓存目录的索引，
 * 且失败时无法定位到具体文件。
 *
 * 子目录（正常情况下不存在）也会尝试删，删不掉就计进 `failed` —— 如实上报，
 * 不为了"看起来全清干净"而跳过它们。
 */
export function clearExportCache(context: common.Context): ClearResult {
  const result: ClearResult = new ClearResult();
  const dir: string = exportDir(context);
  const listed: ListResult = listEntries(dir);
  if (!listed.ok) {
    // 列举就失败：什么都没删（页面会在重新统计时看到"读取失败"，不会假装清空）
    return result;
  }
  const names: string[] = listed.names;
  for (let i = 0; i < names.length; i++) {
    const path: string = `${dir}/${names[i]}`;
    const size: number = entrySize(path);
    try {
      fileIo.unlinkSync(path);
      result.cleared += 1;
      // size < 0 表示删之前就量不到：释放量记 0（不虚报）
      result.freedBytes += size > 0 ? size : 0;
    } catch (e) {
      result.failed += 1;
      hilog.warn(DOMAIN, TAG, 'unlink failed: %{public}s', String(e));
    }
  }
  return result;
}
