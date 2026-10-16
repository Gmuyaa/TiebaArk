import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { EXPORT_CACHE_BYTES, EXPORT_CACHE_FILES, EXPORT_CACHE_MAX_AGE_MS, isCacheEntryName } from '../model/CachePolicy';

class ExportFile {
  path: string = '';
  size: number = 0;
  modified: number = 0;
}

/** 保留近期可能仍被分享接收方使用的文件，超预算时拒绝继续堆积。 */
const SHARE_GRACE_MS: number = 10 * 60 * 1000;

/** 新导出之前及启动时收敛：24小时过期，最多32项/32MiB；不遍历其他目录。 */
export function trimExportCache(context: common.Context, incomingBytes: number = 0, replacingName: string = ''): void {
  if (incomingBytes < 0 || incomingBytes > EXPORT_CACHE_BYTES) {
    throw new Error('图片超过临时缓存容量限制');
  }
  const dir: string = `${context.cacheDir}/export`;
  if (!fileIo.accessSync(dir)) { return; }
  const rootStat: fileIo.Stat = fileIo.lstatSync(dir);
  if (rootStat.isSymbolicLink() || !rootStat.isDirectory()) { throw new Error('导出缓存目录异常'); }
  const files: ExportFile[] = [];
  const now: number = Date.now();
  let bytes: number = 0;
  for (const name of fileIo.listFileSync(dir)) {
    if (!isCacheEntryName(name)) { throw new Error('导出缓存文件名异常'); }
    const path: string = `${dir}/${name}`;
    const stat: fileIo.Stat = fileIo.lstatSync(path);
    if (!stat.isFile() || stat.isSymbolicLink()) { continue; }
    if (incomingBytes > 0 && name === replacingName) { continue; }
    const item: ExportFile = new ExportFile();
    item.path = path; item.size = stat.size; item.modified = stat.mtime * 1000;
    files.push(item); bytes += item.size;
  }
  files.sort((a: ExportFile, b: ExportFile): number => a.modified - b.modified);
  let count: number = files.length;
  const incomingCount: number = incomingBytes > 0 ? 1 : 0;
  for (const item of files) {
    const expired: boolean = now - item.modified > EXPORT_CACHE_MAX_AGE_MS;
    const overBudget: boolean = bytes + incomingBytes > EXPORT_CACHE_BYTES || count + incomingCount > EXPORT_CACHE_FILES;
    if ((expired || overBudget) && now - item.modified > SHARE_GRACE_MS) {
      fileIo.unlinkSync(item.path);
      bytes -= item.size; count -= 1;
    }
  }
  if (incomingBytes > 0 && (bytes + incomingBytes > EXPORT_CACHE_BYTES || count + 1 > EXPORT_CACHE_FILES)) {
    throw new Error('近期导出文件正在保留，请稍后重试或先清理缓存');
  }
}
