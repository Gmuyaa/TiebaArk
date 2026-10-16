/** 图片超分的尺寸校验、内存预算、淘汰策略与任务有效性。输出边长按输入的四倍估算，RGBA 内存按宽×高×4计算；实际占用以 PixelMap 返回值为准。 */

/** 官方下限：文档写"须严格大于"，本机实测 16 也成功；取保守值（16 判为过小） */
export const SR_MIN_SIDE: number = 16;
/** 官方上限：文档写"须严格小于"，本机实测 2048 成功、2049 回 401；取保守值 */
export const SR_MAX_SIDE: number = 2048;
/** 官方"建议"上限：超过它仍可尝试，但要受内存预算与超时约束 */
export const SR_RECOMMENDED_SIDE: number = 1024;
/** 实测：输出边长是输入的 4 倍（1024→4096） */
export const SR_UPSCALE_FACTOR: number = 4;
/** 实测：输出是 RGBA_8888，行距 = 宽×4 */
export const SR_BYTES_PER_PIXEL: number = 4;

/** 解码后一张图的字节数（RGBA_8888 口径） */
export function srDecodedBytes(width: number, height: number): number {
  if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width <= 0 || height <= 0) {
    return 0;
  }
  return width * height * SR_BYTES_PER_PIXEL;
}

/**
 * 预测的**增强图**字节数。实测输出边长×4，所以是输入解码字节的 **16 倍**
 * （1024×1024 输入 4MB → 输出 64MB，与真机 `getPixelBytesNumber()` 一致）。
 * 这只是预算用的预估；实际结果落地时以 `getPixelBytesNumber()` 的实测值为准。
 */
export function srPredictedOutputBytes(width: number, height: number): number {
  const side: number = SR_UPSCALE_FACTOR;
  return srDecodedBytes(width * side, height * side);
}

/**
 * 单张增强图允许占用的内存上限。这不是"设备做不到"（真机实测 8192×8192 = 256MB 也能分配），
 * 而是**看图场景的预算**：超分结果要和原图、ArkUI 的纹理、导出缓冲同时活着，
 * 超过这条线就如实报不可用，不拿进程稳定性去换一张更大的图。
 * 64MB 对应输入约 100 万像素（1024×1024、720×1280 这一档）。
 */
export const SR_MAX_OUTPUT_BYTES: number = 64 * 1024 * 1024;

/**
 * 会话内增强图结果缓存预算（按**实测字节**计量，不按张数）。
 * 当前图永不淘汰；这条线约束的是"回看别的图还能不能命中缓存"。
 */
export const SR_CACHE_BUDGET_BYTES: number = 64 * 1024 * 1024;

/** 超分单次处理的超时上限（ms）。实测 100 万像素约 1.3s，这条线只用来兜住异常长尾 */
export const SR_TIMEOUT_MS: number = 30000;

/** 每张图在查看器会话里的超分状态 */
export enum SrStatus {
  /** 设备或这张图本身不满足条件，按钮灰显，点击只解释原因 */
  UNAVAILABLE = 0,
  /** 关闭：显示原图 */
  OFF = 1,
  /** 处理中：显示原图 + 进度动画，期间不接受重复提交 */
  PROCESSING = 2,
  /** 开启：显示已生成的增强图 */
  ON = 3,
  /** 失败：保留原图，允许重试 */
  ERROR = 4
}

/** 判定结果：`ok=false` 时 `reason` 是原话，直接展示给用户，不吞成"不可用" */
export class SrEligibility {
  ok: boolean = false;
  reason: string = '';
}

function srFail(reason: string): SrEligibility {
  const result: SrEligibility = new SrEligibility();
  result.ok = false;
  result.reason = reason;
  return result;
}

function srPass(): SrEligibility {
  const result: SrEligibility = new SrEligibility();
  result.ok = true;
  return result;
}

/**
 * **只看尺寸与内存**的判定：图片解码尺寸一报出来（`Image.onComplete`）就能用，
 * 因此"超大的长截图"在点击之前就会灰显，而不是点了才说不行。
 */
export function srSizeEligibility(width: number, height: number): SrEligibility {
  if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width <= 0 || height <= 0) {
    return srFail('图片尺寸未知，暂不支持超分');
  }
  if (width <= SR_MIN_SIDE || height <= SR_MIN_SIDE) {
    return srFail(`图片过小（宽高需大于 ${SR_MIN_SIDE}px，当前 ${width}×${height}）`);
  }
  if (width >= SR_MAX_SIDE || height >= SR_MAX_SIDE) {
    return srFail(`图片过大（宽高需小于 ${SR_MAX_SIDE}px，当前 ${width}×${height}）`);
  }
  const outputBytes: number = srPredictedOutputBytes(width, height);
  if (outputBytes > SR_MAX_OUTPUT_BYTES) {
    return srFail(`图片过大（增强结果约 ${Math.round(outputBytes / (1024 * 1024))}MB，超出内存预算）`);
  }
  return srPass();
}

/**
 * 这张图能不能超分。先判"帧数"（只有真去读文件才知道），再判尺寸与内存。
 *
 * `frames` 由 `ImageSource.getFrameCount()` 给；**读不到就不要猜**（非正数视为不可用），
 * 因为"动图截首帧冒充处理结果"是被明确禁止的。
 */
export function srEligibility(width: number, height: number, frames: number): SrEligibility {
  if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width <= 0 || height <= 0) {
    return srFail('图片尺寸未知，暂不支持超分');
  }
  if (frames <= 0) {
    return srFail('无法确认图片帧数，暂不支持超分');
  }
  if (frames > 1) {
    return srFail('动图暂不支持超分');
  }
  return srSizeEligibility(width, height);
}

// ─────────────────────────────── 缓存与淘汰 ───────────────────────────────

/** 参与缓存预算计量的条目（只带"身份 + 实际解码字节"，不持有 PixelMap 本身） */
export class SrCacheEntry {
  key: string = '';
  bytes: number = 0;
}

/**
 * 淘汰计划：返回**应当释放**的 key（按传入顺序 = 由旧到新，越靠前越先淘汰）。
 *
 * 三条硬规则：
 *   1. **绝不淘汰当前图**（`currentKey`），否则用户正看着的结果会自己消失；
 *   2. **绝不淘汰正在导出的那一张**（`pinnedKey`）—— 导出是异步编码，
 *      这时候把它脚下的 PixelMap 释放掉会编出坏文件甚至崩；
 *   3. 淘汰只为把总字节压回预算内，够用就停，不"顺手多清几张"。
 */
export function srEvictionPlan(entries: SrCacheEntry[], currentKey: string,
  budgetBytes: number, pinnedKey: string): string[] {
  const doomed: string[] = [];
  if (budgetBytes <= 0) {
    return doomed;
  }
  let total: number = 0;
  for (let i: number = 0; i < entries.length; i++) {
    total += entries[i].bytes;
  }
  if (total <= budgetBytes) {
    return doomed;
  }
  for (let i: number = 0; i < entries.length; i++) {
    if (total <= budgetBytes) {
      break;
    }
    const entry: SrCacheEntry = entries[i];
    if (entry.key === currentKey || entry.key === pinnedKey) {
      continue;
    }
    doomed.push(entry.key);
    total -= entry.bytes;
  }
  return doomed;
}

// ─────────────────────────────── 任务有效性 ───────────────────────────────

/**
 * 迟到的超分结果能不能落地。
 *
 * 判据是**图片身份 + 会话纪元**，不是页码：翻页、退出查看器、图片来源改变（列表重建）
 * 都会让旧任务失效。失效结果**只释放、不自动开启效果、不覆盖当前页**。
 */
export function srResultAcceptable(taskKey: string, taskEpoch: number,
  currentKey: string, currentEpoch: number): boolean {
  return taskKey.length > 0 && taskKey === currentKey && taskEpoch === currentEpoch;
}

// ─────────────────────────────── 悬浮按钮几何 ───────────────────────────────

/** 圆形底座的视觉直径（vp） */
export const SR_BUTTON_BASE: number = 40;
/** 图标尺寸（vp） */
export const SR_BUTTON_ICON: number = 20;
/** 触控区域边长（vp）：至少 44，视觉底座居中放进这个方框 */
export const SR_BUTTON_TOUCH: number = 44;
/** 距图片显示区域右上角的内缩（vp） */
export const SR_BUTTON_INSET: number = 12;
/** 距容器边缘的安全边距（vp），保证按钮完整落在可操作区域内 */
export const SR_BUTTON_MARGIN: number = 6;

export class SrButtonBox {
  x: number = 0;
  y: number = 0;
  size: number = SR_BUTTON_TOUCH;
}

function clamp(value: number, low: number, high: number): number {
  if (high < low) {
    return low;
  }
  return Math.max(low, Math.min(high, value));
}

/**
 * 按钮落点：**以图片实际显示区域的右上角为锚**，内缩 `inset`，再夹进容器可操作区域。
 *
 * 输入都是 vp：`fitWidth/fitHeight` 是 `ImageFit.Contain` 下的基准显示尺寸（缩放前），
 * `scale/panX/panY` 是当前缩放与位移。锚点取**图片与容器的可见交集**的右上角，于是：
 *   - 满屏图 / 放大铺满：交集 = 整个容器 → 按钮落在屏幕右上角；
 *   - 小图、长图：交集是图片本身 → 按钮贴着图片右上角，而不是飘在黑色留白里；
 *   - 拖动到图片边缘出屏：交集跟着裁掉出屏部分 → 按钮**始终留在屏幕内**。
 * `minY` 用来避开状态栏（由调用方按避让区传入），`containerWidth/Height` 为 0 时退回左上角安全值。
 */
export function srButtonPosition(containerWidth: number, containerHeight: number,
  fitWidth: number, fitHeight: number, scale: number, panX: number, panY: number,
  inset: number, minY: number): SrButtonBox {
  const box: SrButtonBox = new SrButtonBox();
  const size: number = SR_BUTTON_TOUCH;
  if (!(containerWidth > 0) || !(containerHeight > 0)) {
    box.x = inset;
    box.y = Math.max(inset, minY);
    return box;
  }
  const safeScale: number = scale > 0 ? scale : 1;
  const drawWidth: number = fitWidth > 0 ? fitWidth * safeScale : 0;
  const drawHeight: number = fitHeight > 0 ? fitHeight * safeScale : 0;
  const left: number = (containerWidth - drawWidth) / 2 + panX;
  const top: number = (containerHeight - drawHeight) / 2 + panY;
  // 图片与容器的可见交集（图片完全在屏幕外时交集为空，锚点退回容器边）
  const visLeft: number = Math.max(0, left);
  const visTop: number = Math.max(0, top);
  const visRight: number = Math.min(containerWidth, left + drawWidth);
  const visBottom: number = Math.min(containerHeight, top + drawHeight);
  const anchorRight: number = visRight > visLeft ? visRight : containerWidth;
  // 图片被拖到上边缘之外时可见交集为空 —— 锚点退回容器上沿，保证按钮仍在屏幕内
  const anchorTop: number = visBottom > visTop ? visTop : 0;

  box.size = size;
  box.x = clamp(anchorRight - inset - size, SR_BUTTON_MARGIN, containerWidth - size - SR_BUTTON_MARGIN);
  box.y = clamp(anchorTop + inset, Math.max(SR_BUTTON_MARGIN, minY),
    containerHeight - size - SR_BUTTON_MARGIN);
  return box;
}

// ─────────────────────────────── 增强图导出 ───────────────────────────────

/** 增强图的编码格式：原图带透明通道就用 PNG，否则用 JPEG（相册里体积更友好） */
export function srExportFormat(hasAlpha: boolean): string {
  return hasAlpha ? 'image/png' : 'image/jpeg';
}

/**
 * 增强图的缓存文件名。**必须与原图文件名区分**：原图走 `imageFileName()`
 * （`tieba_<时间戳>_<序号>.<扩展>`），这里加 `_sr` 段，两条路互不覆盖。
 */
export function srExportFileName(index: number, stamp: number, extension: string): string {
  return `tieba_sr_${stamp}_${index}.${extension}`;
}

/** `image/jpeg` → `jpg`、`image/png` → `png`；未知按 jpg */
export function srFormatExtension(format: string): string {
  if (format === 'image/png') {
    return 'png';
  }
  return 'jpg';
}

// ─────────────────────────────── 失败归因文案 ───────────────────────────────

/** 失败归类：区分"设备不支持 / 服务不可用 / 输入不合法 / 处理失败 / 超时"，不混成一句"失败" */
export enum SrFailure {
  DEVICE_UNSUPPORTED = 0,
  SERVICE_EXCEPTION = 1,
  INPUT_INVALID = 2,
  DECODE_FAILED = 3,
  NETWORK_FAILED = 4,
  TIMEOUT = 5,
  UNKNOWN = 6
}

/** Core Vision Kit 的服务异常码（`@hms.ai.vision.imageSuperResolution.d.ts` 唯一公开的 throws） */
export const SR_SERVICE_ERROR_CODE: number = 1018700001;

export function srClassifyError(code: number, message: string): SrFailure {
  if (code === SR_SERVICE_ERROR_CODE) {
    return SrFailure.SERVICE_EXCEPTION;
  }
  if (code === 401) {
    return SrFailure.INPUT_INVALID;
  }
  if (message.length === 0 && code === 0) {
    return SrFailure.UNKNOWN;
  }
  return SrFailure.UNKNOWN;
}

/** 失败原话（用户可见）；设备不支持与服务不可用必须能分辨 */
export function srFailureText(kind: SrFailure, detail: string): string {
  if (kind === SrFailure.DEVICE_UNSUPPORTED) {
    return '本机不支持图像超分';
  }
  if (kind === SrFailure.SERVICE_EXCEPTION) {
    return '超分服务不可用，请稍后重试';
  }
  if (kind === SrFailure.INPUT_INVALID) {
    return '这张图不满足超分输入要求';
  }
  if (kind === SrFailure.DECODE_FAILED) {
    return '图片解码失败，无法超分';
  }
  if (kind === SrFailure.NETWORK_FAILED) {
    return detail.length > 0 ? `下载原图失败：${detail}` : '下载原图失败';
  }
  if (kind === SrFailure.TIMEOUT) {
    return '图像超分超时，已恢复原图';
  }
  return detail.length > 0 ? detail : '图像超分失败';
}
