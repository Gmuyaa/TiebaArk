
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CacheMeasure } from '../model/CacheClean';

const DOMAIN: number = 0x0;
const TAG: string = 'CacheClean';

const EXPORT_DIR_NAME: string = 'export';

export class ClearResult {

  cleared: number = 0;

  failed: number = 0;

  freedBytes: number = 0;
}

function exportDir(context: common.Context): string {
  return `${context.cacheDir}/${EXPORT_DIR_NAME}`;
}

class ListResult {

  ok: boolean = false;

  missing: boolean = false;
  names: string[] = [];
}

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

      measure.skipped += 1;
    }
  }
  return measure;
}

export function clearExportCache(context: common.Context): ClearResult {
  const result: ClearResult = new ClearResult();
  const dir: string = exportDir(context);
  const listed: ListResult = listEntries(dir);
  if (!listed.ok) {

    return result;
  }
  const names: string[] = listed.names;
  for (let i = 0; i < names.length; i++) {
    const path: string = `${dir}/${names[i]}`;
    const size: number = entrySize(path);
    try {
      fileIo.unlinkSync(path);
      result.cleared += 1;

      result.freedBytes += size > 0 ? size : 0;
    } catch (e) {
      result.failed += 1;
      hilog.warn(DOMAIN, TAG, 'unlink failed: %{public}s', String(e));
    }
  }
  return result;
}
