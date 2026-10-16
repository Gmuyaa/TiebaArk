

export function formatPostTime(milliseconds: number, nowMs: number): string {
  if (milliseconds <= 0) { return ''; }
  const at: Date = new Date(milliseconds);
  const now: Date = new Date(nowMs);
  if (at.getFullYear() !== now.getFullYear()) {
    return `${at.getFullYear()}-${two(at.getMonth() + 1)}-${two(at.getDate())}`;
  }
  return `${two(at.getMonth() + 1)}-${two(at.getDate())} ${two(at.getHours())}:${two(at.getMinutes())}`;
}

function two(value: number): string {
  return value < 10 ? `0${value}` : String(value);
}

export class FeedImageInfo {
  width: number = 0;
  height: number = 0;
  long: boolean = false;
  origin: string = '';
}

const imageInfo: Map<string, FeedImageInfo> = new Map();
const measuredInfo: Map<string, FeedImageInfo> = new Map();

export function rememberFeedImage(url: string, width: number, height: number,
  long: boolean, origin: string): void {
  if (url.length === 0) { return; }
  const info: FeedImageInfo = new FeedImageInfo();
  info.width = width > 0 ? width : 0;
  info.height = height > 0 ? height : 0;
  info.long = long;
  info.origin = origin;
  if (imageInfo.size >= 1200 && !imageInfo.has(url)) { imageInfo.clear(); }
  imageInfo.set(url, info);
}

export function rememberMeasuredImage(url: string, width: number, height: number,
  long: boolean, origin: string): void {
  if (url.length === 0 || !(width > 0) || !(height > 0)) { return; }
  const info: FeedImageInfo = new FeedImageInfo();
  info.width = width;
  info.height = height;
  info.long = long;
  info.origin = origin;
  if (measuredInfo.size >= 1200 && !measuredInfo.has(url)) { measuredInfo.clear(); }
  measuredInfo.set(url, info);
}

export function feedImageInfo(url: string): FeedImageInfo {
  const measured: FeedImageInfo | undefined = measuredInfo.get(url);
  if (measured !== undefined) { return measured; }
  return imageInfo.get(url) ?? new FeedImageInfo();
}

export function feedPreviewInfo(url: string): FeedImageInfo {
  const declared: FeedImageInfo | undefined = imageInfo.get(url);
  if (declared !== undefined && declared.width > 0 && declared.height > 0) { return declared; }
  return feedImageInfo(url);
}

export function previewRowHeight(boxHeights: number[]): number {
  let max: number = 0;
  for (let i = 0; i < boxHeights.length; i++) {
    const h: number = boxHeights[i];
    if (h > max) { max = h; }
  }
  if (!(max > 0)) { return PREVIEW_ROW_H; }
  return Math.min(PREVIEW_ROW_H, max);
}

export const PREVIEW_ROW_H: number = 200;
export const PREVIEW_SINGLE_MAX_H: number = 280;
export const PREVIEW_MULTI_MAX_W: number = 240;
export const PREVIEW_GAP: number = 8;
export const PREVIEW_RADIUS: number = 11;

export const PREVIEW_LONG_RATIO: number = 0.4;

export const BODY_SINGLE_MAX_H: number = 460;
export const BODY_RADIUS: number = 12;

export const BODY_MIN_BOX_W: number = 240;

export const BODY_FALLBACK_ASPECT: number = 1.5;

export class FeedImageBox {
  width: number = 0;
  height: number = PREVIEW_ROW_H;
  long: boolean = false;

  known: boolean = false;
}

export class ImageBoxSpec {

  maxWidth: number = PREVIEW_MULTI_MAX_W;

  maxHeight: number = PREVIEW_SINGLE_MAX_H;

  rowHeight: number = PREVIEW_ROW_H;

  placeholderWidth: number = PREVIEW_MULTI_MAX_W;
  placeholderHeight: number = PREVIEW_ROW_H;

  multiple: boolean = false;

  cropLong: boolean = true;

  maxNativeScale: number = 1.5;
}

export function imageBox(info: FeedImageInfo, density: number, spec: ImageBoxSpec): FeedImageBox {
  const box: FeedImageBox = new FeedImageBox();
  box.width = spec.placeholderWidth;
  box.height = spec.placeholderHeight;

  if (!(info.width > 0) || !(info.height > 0)) { return box; }
  const ratio: number = info.width / info.height;
  box.long = info.long || ratio < PREVIEW_LONG_RATIO;
  const nativeWidth: number = info.width / Math.max(1, density) * spec.maxNativeScale;
  if (box.long && spec.cropLong) {

    box.width = Math.max(1, Math.min(spec.maxWidth, nativeWidth, spec.rowHeight * ratio));
    box.height = Math.max(1, spec.rowHeight);
  } else {

    box.width = Math.max(1, Math.min(spec.maxWidth, nativeWidth, spec.maxHeight * ratio));
    box.height = Math.max(1, Math.min(spec.maxHeight, box.width / ratio));
  }
  box.known = true;
  return box;
}

export function feedImageBox(info: FeedImageInfo, contentWidth: number,
  multiple: boolean, density: number): FeedImageBox {
  const usableWidth: number = contentWidth > 0 ? contentWidth : PREVIEW_MULTI_MAX_W;
  const maxWidth: number = multiple ? Math.max(1, usableWidth - 24) : usableWidth;
  const spec: ImageBoxSpec = new ImageBoxSpec();
  spec.maxWidth = maxWidth;
  spec.maxHeight = multiple ? PREVIEW_ROW_H : PREVIEW_SINGLE_MAX_H;
  spec.rowHeight = PREVIEW_ROW_H;
  spec.placeholderWidth = multiple ? Math.min(maxWidth, PREVIEW_MULTI_MAX_W) : maxWidth;
  spec.placeholderHeight = PREVIEW_ROW_H;
  spec.multiple = multiple;
  spec.cropLong = true;
  spec.maxNativeScale = 1.5;
  return imageBox(info, density, spec);
}

export function bodySingleImageBox(info: FeedImageInfo, contentWidth: number,
  density: number): FeedImageBox {
  const usableWidth: number = contentWidth > 0 ? contentWidth : BODY_MIN_BOX_W;
  const spec: ImageBoxSpec = new ImageBoxSpec();
  spec.maxWidth = usableWidth;
  spec.maxHeight = BODY_SINGLE_MAX_H;
  spec.rowHeight = BODY_SINGLE_MAX_H;
  spec.placeholderWidth = usableWidth;
  spec.placeholderHeight = Math.max(1, usableWidth / BODY_FALLBACK_ASPECT);
  spec.multiple = false;
  spec.cropLong = false;
  spec.maxNativeScale = 1.5;
  return imageBox(info, density, spec);
}
