import { application, common, contextConstant } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { CacheMeasure } from '../model/CacheClean';
import { isApplicationCacheRoot, isCacheEntryName } from '../model/CachePolicy';
import { ClearResult } from './CacheCleaner';

/** 与 ImageExport 共用，阻止手动清理期间产生新的导出文件。 */
class CacheMaintenance {
  busy: boolean = false;
}
export const cacheMaintenance: CacheMaintenance = new CacheMaintenance();

/** 使用独立 Context 查询路径，不改变业务共享 Context 的加密分区。 */
export async function applicationCacheRoots(context: common.Context): Promise<string[]> {
  const moduleContext: common.Context = await application.createModuleContext(context, 'entry');
  const appContext: common.ApplicationContext = context.getApplicationContext();
  const roots: string[] = [];
  const areas: contextConstant.AreaMode[] = [contextConstant.AreaMode.EL1, contextConstant.AreaMode.EL2];
  for (const area of areas) {
    moduleContext.area = area;
    const candidates: string[] = [moduleContext.cacheDir, appContext.createAreaModeContext(area).cacheDir,
      context.createAreaModeContext(area).cacheDir];
    for (const path of candidates) {
      if (!isApplicationCacheRoot(path)) {
        throw new Error('无法确认应用缓存目录');
      }
      if (roots.indexOf(path) < 0) { roots.push(path); }
    }
  }
  if (roots.length !== 4) { throw new Error('应用缓存目录不完整'); }
  return roots;
}

/** 不跟随符号链接；只逐个处理缓存根内的普通文件，根目录和子目录均保留。 */
async function walkCache(path: string, measure: CacheMeasure, result?: ClearResult): Promise<void> {
  try {
    if (!await fileIo.access(path)) { return; }
    const stat: fileIo.Stat = await fileIo.lstat(path);
    if (stat.isSymbolicLink()) {
      measure.skipped += 1;
      if (result !== undefined) { result.failed += 1; }
      return;
    }
    if (stat.isDirectory()) {
      const names: string[] = await fileIo.listFile(path);
      for (const name of names) {
        if (!isCacheEntryName(name)) {
          measure.skipped += 1;
          if (result !== undefined) { result.failed += 1; }
          continue;
        }
        await walkCache(`${path}/${name}`, measure, result);
      }
    } else if (stat.isFile()) {
      measure.bytes += stat.size;
      measure.entries += 1;
      if (result !== undefined) {
        await fileIo.unlink(path);
        result.cleared += 1;
        result.freedBytes += stat.size;
      }
    } else {
      measure.skipped += 1;
      if (result !== undefined) { result.failed += 1; }
    }
  } catch (_) {
    measure.skipped += 1;
    if (result !== undefined) { result.failed += 1; }
  }
}

export async function measureApplicationCache(context: common.Context): Promise<CacheMeasure> {
  const measure: CacheMeasure = new CacheMeasure();
  try {
    const roots: string[] = await applicationCacheRoots(context);
    for (const root of roots) { await walkCache(root, measure); }
    measure.ok = true;
  } catch (_) { /* 保持读取失败，不把未知范围当作空缓存。 */ }
  return measure;
}

export async function clearApplicationCache(context: common.Context): Promise<ClearResult> {
  const result: ClearResult = new ClearResult();
  if (cacheMaintenance.busy) { result.failed = 1; return result; }
  cacheMaintenance.busy = true;
  try {
    const roots: string[] = await applicationCacheRoots(context);
    const measure: CacheMeasure = new CacheMeasure();
    for (const root of roots) { await walkCache(root, measure, result); }
  } catch (_) { result.failed += 1; }
  finally { cacheMaintenance.busy = false; }
  return result;
}
