

export enum CacheKind {

  EXPORT = 0
}

export const CACHE_ACTION_EXPORT: string = 'cache_export';

export interface CacheItemSpec {
  kind: CacheKind;

  key: string;

  title: string;

  subtitle: string;

  userData: boolean;

  order: number;
}

export const CACHE_ITEM_SPECS: CacheItemSpec[] = [
  {
    kind: CacheKind.EXPORT,
    key: CACHE_ACTION_EXPORT,
    title: '图片与导出缓存',
    subtitle: '清理图片导出产生的临时文件，不影响已保存的图片',
    userData: false,
    order: 0
  }
];

export function cacheSpecOfAction(action: string): CacheItemSpec | undefined {
  for (let i = 0; i < CACHE_ITEM_SPECS.length; i++) {
    if (CACHE_ITEM_SPECS[i].key === action) {
      return CACHE_ITEM_SPECS[i];
    }
  }
  return undefined;
}

export function formatBytes(bytes: number): string {
  const value: number = Number.isFinite(bytes) ? Math.max(0, Math.floor(bytes)) : 0;
  const kb: number = 1024;
  const mb: number = kb * 1024;
  const gb: number = mb * 1024;
  if (value < kb) {
    return `${value} B`;
  }
  if (value < mb) {
    return `${(value / kb).toFixed(1)} KB`;
  }
  if (value < gb) {
    return `${(value / mb).toFixed(1)} MB`;
  }
  return `${(value / gb).toFixed(2)} GB`;
}

export class CacheMeasure {

  ok: boolean = false;

  missing: boolean = false;

  bytes: number = 0;

  entries: number = 0;

  skipped: number = 0;
}

export enum CachePhase {

  STATTING = 0,

  OK = 1,

  EMPTY = 2,

  READ_FAIL = 3,

  PARTIAL = 4,

  CLEARING = 5,

  PARTIAL_DONE = 6
}

export function cachePhaseOf(measure: CacheMeasure | undefined): CachePhase {
  if (measure === undefined || !measure.ok) {
    return CachePhase.READ_FAIL;
  }
  if (measure.missing) {
    return CachePhase.EMPTY;
  }
  if (measure.skipped > 0) {
    return CachePhase.PARTIAL;
  }
  return measure.bytes > 0 ? CachePhase.OK : CachePhase.EMPTY;
}

export function cachePhaseAmountLabel(phase: CachePhase, measure: CacheMeasure | undefined): string {
  switch (phase) {
    case CachePhase.STATTING:
      return '正在统计…';
    case CachePhase.READ_FAIL:
      return '读取失败';
    case CachePhase.EMPTY:
      return '暂无缓存文件';
    case CachePhase.CLEARING:
      return '清理中…';
    case CachePhase.PARTIAL_DONE:

      return '部分完成';
    case CachePhase.PARTIAL:
      return `已统计 ${measure !== undefined ? measure.entries : 0} 项，另有 ${measure !== undefined ? measure.skipped : 0} 项无法读取`;
    case CachePhase.OK:
    default:
      return formatBytes(measure !== undefined ? measure.bytes : 0);
  }
}

export function cachePhaseCanClear(phase: CachePhase): boolean {
  return phase === CachePhase.OK || phase === CachePhase.PARTIAL;
}

export function cacheResultLines(phase: CachePhase, cleared: number, failed: number,
  freedBytes: number): string[] {
  const lines: string[] = [];
  if (phase === CachePhase.PARTIAL_DONE) {
    lines.push(`已删除 ${cleared} 个文件，${failed} 个未能删除。`);
    if (Number.isFinite(freedBytes) && freedBytes > 0) {
      lines.push(`已释放 ${formatBytes(freedBytes)}。`);
    }
    lines.push('剩余占用暂未确认，请刷新重试。');
    return lines;
  }
  if (cleared <= 0 && failed <= 0) {
    return lines;
  }
  if (cleared <= 0) {
    lines.push(`清理失败：${failed} 个文件未能删除。`);
    return lines;
  }
  lines.push(`已删除 ${cleared} 个文件，已释放 ${formatBytes(freedBytes)}。`);
  return lines;
}
