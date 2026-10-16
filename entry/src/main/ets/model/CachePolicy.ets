
export const IMAGE_DISK_CACHE_BYTES: number = 32 * 1024 * 1024;
export const EXPORT_CACHE_BYTES: number = 32 * 1024 * 1024;
export const EXPORT_CACHE_FILES: number = 32;
export const EXPORT_CACHE_MAX_AGE_MS: number = 24 * 60 * 60 * 1000;

/** 只接纳单 entry 模块由 Context 返回的 EL1/EL2 缓存根目录。 */
export function isApplicationCacheRoot(path: string): boolean {
  return /^\/data\/storage\/el[12]\/base(?:\/haps\/entry)?\/cache$/.test(path);
}

export function isCacheEntryName(name: string): boolean {
  return name.length > 0 && name !== '.' && name !== '..' && name.indexOf('/') < 0 &&
    name.indexOf('\\') < 0;
}
