

export function formatPostTime(milliseconds: number, nowMs: number): string {
  if (milliseconds <= 0) { return ''; }
  const at: Date = new Date(milliseconds);
  const now: Date = new Date(nowMs);
  if (at.getFullYear() !== now.getFullYear()) {
    return `${at.getFullYear()}-${two(at.getMonth() + 1)}-${two(at.getDate())}`;
  }
  return `${two(at.getMonth() + 1)}-${two(at.getDate())} ${two(at.getHours())}:${two(at.getMinutes())}`;
}

/** 两位补零（月/日/时/分） */
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

/** 记下一次 `Image.onComplete` 确认过的实际加载尺寸（无效值直接丢弃）。 */
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

/** 已确认的实际尺寸 > 服务端声明尺寸 > 空（空 = 只能先按占位框渲染）。 */
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

/** 预览尺寸口径（vp）。两个帖子列表入口共用，不各自发明一套。 */
export const PREVIEW_ROW_H: number = 200;
export const PREVIEW_SINGLE_MAX_H: number = 280;
export const PREVIEW_MULTI_MAX_W: number = 240;
export const PREVIEW_GAP: number = 8;
export const PREVIEW_RADIUS: number = 11;
/** 长图判定：显式标记，或宽高比小于该值（沿用既有口径） */
export const PREVIEW_LONG_RATIO: number = 0.4;

export const BODY_SINGLE_MAX_H: number = 460;
export const BODY_RADIUS: number = 12;
/** 内容区宽度拿不到时的兜底（vp） */
export const BODY_MIN_BOX_W: number = 240;
/**
 * 正文单图在服务端与实测**都没给尺寸**时的兜底比例（宽/高）。
 * 与 `ThreadDetail.FALLBACK_IMAGE_ASPECT` 同值：图集整体比例一直用 1.5，
 * 这里保持同口径，免得同一张图在"没有尺寸"时两个模块给出两个占位高度。
 */
export const BODY_FALLBACK_ASPECT: number = 1.5;

export class FeedImageBox {
  width: number = 0;
  height: number = PREVIEW_ROW_H;
  long: boolean = false;
  /** false = 还没有尺寸，当前是占位框，加载成功后要按真实尺寸校正一次 */
  known: boolean = false;
}

export class ImageBoxSpec {
  /** 最终宽度硬上限 */
  maxWidth: number = PREVIEW_MULTI_MAX_W;
  /** 最终高度硬上限（长图走 `cropLong` 分支时由 `rowHeight` 决定） */
  maxHeight: number = PREVIEW_SINGLE_MAX_H;
  /** 长图 / 固定行高多图使用的高度 */
  rowHeight: number = PREVIEW_ROW_H;
  /** 还没拿到尺寸时的占位宽、占位高（必须成对：外框就是它） */
  placeholderWidth: number = PREVIEW_MULTI_MAX_W;
  placeholderHeight: number = PREVIEW_ROW_H;

  multiple: boolean = false;
  /** true = 长图裁进 `rowHeight`（列表预览）；false = 长图也等比完整显示（正文） */
  cropLong: boolean = true;
  /** 小图最多按原像素的多少倍呈现，避免小图被铺满容器 */
  maxNativeScale: number = 1.5;
}

export function imageBox(info: FeedImageInfo, density: number, spec: ImageBoxSpec): FeedImageBox {
  const box: FeedImageBox = new FeedImageBox();
  box.width = spec.placeholderWidth;
  box.height = spec.placeholderHeight;
  // 0 / 负数 / NaN 一律走占位框（`>` 对 NaN 恒为 false，这里顺带挡住 NaN）
  if (!(info.width > 0) || !(info.height > 0)) { return box; }
  const ratio: number = info.width / info.height;
  box.long = info.long || ratio < PREVIEW_LONG_RATIO;
  const nativeWidth: number = info.width / Math.max(1, density) * spec.maxNativeScale;
  if (box.long && spec.cropLong) {
    // 长图：宽度按行高等比收，高度固定为行高，超出部分交给 `Cover` 裁
    box.width = Math.max(1, Math.min(spec.maxWidth, nativeWidth, spec.rowHeight * ratio));
    box.height = Math.max(1, spec.rowHeight);
  } else {
    // 常规：高度上限换算成宽度上限，宽高成对，图片完整显示
    box.width = Math.max(1, Math.min(spec.maxWidth, nativeWidth, spec.maxHeight * ratio));
    box.height = Math.max(1, Math.min(spec.maxHeight, box.width / ratio));
  }
  box.known = true;
  return box;
}

/**
 * 帖子列表图片预览框。两个列表入口共用，算法见 `imageBox`。
 *
 * 无尺寸时先占位（宽满、高 `PREVIEW_ROW_H`）；有尺寸后按比例等比收缩，
 * 多图整行高度由外层固定为 `PREVIEW_ROW_H`，不跟着单张图片的比例变。
 */
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

/**
 * 正文**单图**的容器（vp）：容器本身就是图片的最终显示框 ——
 * 不再用同一张图模糊铺底去撑满一个偏大的框。
 *
 * 与列表预览的差别只有两点：高度上限放宽到 `BODY_SINGLE_MAX_H`；长图不裁切。
 * 容器贴合图片后，比例差不再需要背景补位，正文里也就没有那圈"模糊边"。
 */
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
