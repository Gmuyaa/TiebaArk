

export const SR_MIN_SIDE: number = 16;

export const SR_MAX_SIDE: number = 2048;

export const SR_RECOMMENDED_SIDE: number = 1024;

export const SR_UPSCALE_FACTOR: number = 4;

export const SR_BYTES_PER_PIXEL: number = 4;

export function srDecodedBytes(width: number, height: number): number {
  if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width <= 0 || height <= 0) {
    return 0;
  }
  return width * height * SR_BYTES_PER_PIXEL;
}

export function srPredictedOutputBytes(width: number, height: number): number {
  const side: number = SR_UPSCALE_FACTOR;
  return srDecodedBytes(width * side, height * side);
}

export const SR_MAX_OUTPUT_BYTES: number = 64 * 1024 * 1024;

export const SR_CACHE_BUDGET_BYTES: number = 64 * 1024 * 1024;

export const SR_TIMEOUT_MS: number = 30000;

export enum SrStatus {

  UNAVAILABLE = 0,

  OFF = 1,

  PROCESSING = 2,

  ON = 3,

  ERROR = 4
}

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

export class SrCacheEntry {
  key: string = '';
  bytes: number = 0;
}

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

export function srResultAcceptable(taskKey: string, taskEpoch: number,
  currentKey: string, currentEpoch: number): boolean {
  return taskKey.length > 0 && taskKey === currentKey && taskEpoch === currentEpoch;
}

export const SR_BUTTON_BASE: number = 40;

export const SR_BUTTON_ICON: number = 20;

export const SR_BUTTON_TOUCH: number = 44;

export const SR_BUTTON_INSET: number = 12;

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

  const visLeft: number = Math.max(0, left);
  const visTop: number = Math.max(0, top);
  const visRight: number = Math.min(containerWidth, left + drawWidth);
  const visBottom: number = Math.min(containerHeight, top + drawHeight);
  const anchorRight: number = visRight > visLeft ? visRight : containerWidth;

  const anchorTop: number = visBottom > visTop ? visTop : 0;

  box.size = size;
  box.x = clamp(anchorRight - inset - size, SR_BUTTON_MARGIN, containerWidth - size - SR_BUTTON_MARGIN);
  box.y = clamp(anchorTop + inset, Math.max(SR_BUTTON_MARGIN, minY),
    containerHeight - size - SR_BUTTON_MARGIN);
  return box;
}

export function srExportFormat(hasAlpha: boolean): string {
  return hasAlpha ? 'image/png' : 'image/jpeg';
}

export function srExportFileName(index: number, stamp: number, extension: string): string {
  return `tieba_sr_${stamp}_${index}.${extension}`;
}

export function srFormatExtension(format: string): string {
  if (format === 'image/png') {
    return 'png';
  }
  return 'jpg';
}

export enum SrFailure {
  DEVICE_UNSUPPORTED = 0,
  SERVICE_EXCEPTION = 1,
  INPUT_INVALID = 2,
  DECODE_FAILED = 3,
  NETWORK_FAILED = 4,
  TIMEOUT = 5,
  UNKNOWN = 6
}

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
