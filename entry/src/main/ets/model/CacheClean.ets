/** 缓存清理阶段与结果的纯逻辑。系统统计与业务文件统计分别记录，读取失败与空缓存使用不同状态。 */

/** 可清理项只含可重建文件缓存，历史和账号资料不在其中。 */
export enum CacheKind {
  APPLICATION = 0
}

/** 设置行的稳定 action：页面靠它分发清除动作，**不比较中文文案** */
export const CACHE_ACTION_APPLICATION: string = 'cache_application';

/** 每项在设置页的显示信息（纯文案与顺序，页面不要再加分支） */
export interface CacheItemSpec {
  kind: CacheKind;
  /** 设置行的 `key` 与 `action` */
  key: string;
  /** 主标题 */
  title: string;
  /** 副标题（说明清的是什么、有没有风险） */
  subtitle: string;
  /** 是否是"用户数据"：true = 二次确认要提示"清理后不可恢复"（当前没有这类项） */
  userData: boolean;
  /** 展示顺序（小的在前） */
  order: number;
}

/** 各项的显示信息；顺序即设置页列表顺序 */
export const CACHE_ITEM_SPECS: CacheItemSpec[] = [
  {
    kind: CacheKind.APPLICATION,
    key: CACHE_ACTION_APPLICATION,
    title: '可清理的应用缓存',
    subtitle: '图片、导出临时文件及其他应用文件缓存，不影响已保存的图片',
    userData: false,
    order: 0
  }
];

/** 按设置行的 `action` 取规格；不是缓存项时返回 `undefined`（**不造占位项**） */
export function cacheSpecOfAction(action: string): CacheItemSpec | undefined {
  for (let i = 0; i < CACHE_ITEM_SPECS.length; i++) {
    if (CACHE_ITEM_SPECS[i].key === action) {
      return CACHE_ITEM_SPECS[i];
    }
  }
  return undefined;
}

/**
 * 字节数 → 可读文案。**只认非负有限数**：NaN/Infinity/负数一律按 0 B 处理，
 * 避免出现 "NaN MB" 这种假数字（真机上统计接口异常时真的会传回这种值）。
 */
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

/** 系统存储页采用十进制容量及三位有效数字；总量显示使用同一口径。 */
export function formatSystemCacheBytes(bytes: number): string {
  const value: number = Number.isFinite(bytes) ? Math.max(0, Math.floor(bytes)) : 0;
  if (value < 1000) {
    return `${value} B`;
  }
  if (value < 1000000) {
    return `${Number((value / 1000).toPrecision(3))} KB`;
  }
  if (value < 1000000000) {
    return `${Number((value / 1000000).toPrecision(3))} MB`;
  }
  return `${Number((value / 1000000000).toPrecision(3))} GB`;
}

/**
 * 一次占用统计的结果。
 *
 * 不再用裸 `number`：`0` 既可能是"确实为空"也可能是"读不出来"，数字本身没有这个信息。
 */
export class CacheMeasure {
  /** 统计是否正常完成（`false` = 列举目录或权限失败，**不是**网络/服务端问题） */
  ok: boolean = false;
  /** 目录不存在（= 确实为空，不是失败） */
  missing: boolean = false;
  /** 统计到的字节数 */
  bytes: number = 0;
  /** 统计到的文件数 */
  entries: number = 0;
  /** 因 `stat` 失败被跳过的文件数（>0 = 部分统计失败） */
  skipped: number = 0;
}

/** 缓存页的显示阶段。页面只按它分支，不自己拼状态。 */
export enum CachePhase {
  /** 首次统计中：**不显示确定占用、不提供清理** */
  STATTING = 0,
  /** 有可清理内容 */
  OK = 1,
  /** 统计成功且确实为空 */
  EMPTY = 2,
  /** 本机读取失败：不提供清理，可重试 */
  READ_FAIL = 3,
  /** 部分文件统计失败：如实写"已统计多少、多少无法读取" */
  PARTIAL = 4,
  /** 清理中：动作变进行态、不可点（防重复触发） */
  CLEARING = 5,
  /** 部分完成：有文件删不掉，**剩余占用未确认**，不宣称已清空 */
  PARTIAL_DONE = 6
}

/** 统计结果 → 阶段。`undefined`（还没统计）按读取失败处理，不猜成空。 */
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

/**
 * 行右的占用/状态文案。**"读取失败"与"暂无缓存文件"不许互相冒充**，
 * 统计中也不显示一个还没算出来的数字。
 */
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
      return formatSystemCacheBytes(measure !== undefined ? measure.bytes : 0);
  }
}

/** 只有"有内容"或"部分可统计"才提供清理；统计中、失败、为空、清理中都不提供。 */
export function cachePhaseCanClear(phase: CachePhase): boolean {
  return phase === CachePhase.OK || phase === CachePhase.PARTIAL;
}

export function cacheResultLines(phase: CachePhase, cleared: number, failed: number,
  freedBytes: number): string[] {
  const lines: string[] = [];
  if (phase === CachePhase.PARTIAL_DONE) {
    lines.push(`已删除 ${cleared} 个文件，${failed} 个未能删除。`);
    if (Number.isFinite(freedBytes) && freedBytes > 0) {
      lines.push(`已删除文件大小 ${formatSystemCacheBytes(freedBytes)}。`);
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
  lines.push(`已删除 ${cleared} 个文件，文件大小 ${formatSystemCacheBytes(freedBytes)}。`);
  return lines;
}
