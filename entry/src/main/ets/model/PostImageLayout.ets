import { BODY_FALLBACK_ASPECT, BODY_MIN_BOX_W, FeedImageBox, FeedImageInfo,
  PREVIEW_LONG_RATIO } from './HomeFeedPresentation';
import { ContentKind, ContentPiece } from './ThreadDetail';

/** 正文单图的高度上限（× 内容宽，约一屏）；超过就顶部裁切。 */
export const POST_IMAGE_MAX_H_RATIO: number = 2;
/** 正文长图的显示宽度占内容宽的比例；整块按这个比例同比缩小。 */
export const POST_LONG_WIDTH_RATIO: number = 0.8;
/** 正文图片未测到尺寸时的占位高度上限。 */
export const POST_IMAGE_PREVIEW_MAX_HEIGHT: number = 280;
/** 评论单图预览的高度上限；常规比例等比缩进此上限，长图按 3:5 竖框顶部裁切。 */
export const COMMENT_IMAGE_PREVIEW_MAX_HEIGHT: number = 200;
/** 评论单张长图顶部裁切框的宽高比（3:5 竖长预览窗，与信息流卡片一致）。 */
export const COMMENT_SINGLE_LONG_RATIO: number = 0.6;
/** 只限制单个解码目标，不把它当成整个页面的实际内存上限。 */
export const POST_IMAGE_DECODE_PIXELS: number = 8 * 1024 * 1024;
export const POST_IMAGE_DECODE_EDGE: number = 16384;

export class ReadingDecodeSize {
  width: number = 0;
  height: number = 0;
}

export function hasReadingImageSize(info: FeedImageInfo): boolean {
  return Number.isFinite(info.width) && Number.isFinite(info.height) && info.width > 0 && info.height > 0 &&
    Number.isFinite(info.width / info.height) && info.width / info.height > 0;
}

/** 图片实际比例决定绘制；原图的长图语义不能被裁成方形的缩略图抹掉。 */
export function readingImageInfo(declared: FeedImageInfo, actual: FeedImageInfo): FeedImageInfo {
  const source: FeedImageInfo = hasReadingImageSize(actual) ? actual : declared;
  const info: FeedImageInfo = new FeedImageInfo();
  info.width = source.width;
  info.height = source.height;
  info.origin = declared.origin || actual.origin;
  info.long = declared.long || actual.long ||
    (hasReadingImageSize(declared) && declared.width / declared.height < PREVIEW_LONG_RATIO) ||
    (hasReadingImageSize(actual) && actual.width / actual.height < PREVIEW_LONG_RATIO);
  return info;
}

/**
 * 正文（含评论）单图的几何。
 *
 * `expanded = true`：按完整比例给高度，不裁切（评论、旧图集用）。
 * `expanded = false`：高度超过 `POST_IMAGE_MAX_H_RATIO × 宽度` 就裁。
 * 会被裁的图（按比例判定的长图，或被高度上限截掉的截图）宽度收窄到
 * `POST_LONG_WIDTH_RATIO`：正文里它只是附图，不该和正文抢满宽。
 * 普通图仍然满宽、只限制小图放大。
 */
export function readingImageBox(info: FeedImageInfo, contentWidth: number,
  density: number, expanded: boolean): FeedImageBox {
  const box: FeedImageBox = new FeedImageBox();
  const usable: number = Number.isFinite(contentWidth) && contentWidth > 0 ? contentWidth : BODY_MIN_BOX_W;
  box.width = usable;
  box.height = Math.min(POST_IMAGE_PREVIEW_MAX_HEIGHT, usable / BODY_FALLBACK_ASPECT);
  box.long = info.long;
  if (!hasReadingImageSize(info)) { return box; }
  const ratio: number = info.width / info.height;
  const scale: number = Number.isFinite(density) && density > 0 ? density : 1;
  const longByRatio: boolean = info.long || ratio < PREVIEW_LONG_RATIO;
  // 先按满宽估一次：满宽下就已经超上限的图，和长图同样处理。
  const clipsAtFullWidth: boolean = !expanded && usable / ratio > usable * POST_IMAGE_MAX_H_RATIO;
  const isLong: boolean = longByRatio || clipsAtFullWidth;
  // 长图/长截图不能被 1.5 倍放大限制压成细线，改为收窄到 80% 内容宽；
  // 评论、旧图集的展开态仍按满宽算，尺寸由调用方再缩。
  box.width = isLong
    ? (expanded ? usable : usable * POST_LONG_WIDTH_RATIO)
    : Math.max(1, Math.min(usable, info.width / scale * 1.5));
  const fullHeight: number = box.width / ratio;
  if (!Number.isFinite(fullHeight) || fullHeight <= 0) {
    box.width = usable;
    return box;
  }
  // 高度上限跟着实际宽度走：长图整块同比缩小，不是只收窄不改高。
  const maxHeight: number = expanded ? fullHeight : box.width * POST_IMAGE_MAX_H_RATIO;
  box.height = Math.min(fullHeight, maxHeight);
  // 被裁过的图一律按长图处理：顶部对齐绘制，并挂「长图」角标。
  box.long = isLong || box.height < fullHeight;
  box.known = true;
  return box;
}

/** 外框是否比整张图矮；比图矮就必须顶部对齐裁切，不能 Contain 留白。 */
export function readingImageClipped(info: FeedImageInfo, frame: FeedImageBox): boolean {
  if (!hasReadingImageSize(info) || !Number.isFinite(frame.width) || !Number.isFinite(frame.height) ||
    frame.width <= 0 || frame.height <= 0) { return false; }
  const ratio: number = info.width / info.height;
  if (!Number.isFinite(ratio) || ratio <= 0) { return false; }
  const fullHeight: number = frame.width / ratio;
  return Number.isFinite(fullHeight) && fullHeight > frame.height + 0.5;
}

/** 评论单图常规比例等比缩进高度上限；长图按 3:5 竖框顶部裁切，避免缩成极窄细条。 */
export function commentImageBox(info: FeedImageInfo, contentWidth: number,
  density: number, placeholder: boolean = false): FeedImageBox {
  const usable: number = Number.isFinite(contentWidth) && contentWidth > 0 ? contentWidth : BODY_MIN_BOX_W;
  const box: FeedImageBox = new FeedImageBox();
  box.width = usable;
  box.height = Math.min(COMMENT_IMAGE_PREVIEW_MAX_HEIGHT, usable / BODY_FALLBACK_ASPECT);
  box.long = info.long;
  if (placeholder || !hasReadingImageSize(info)) {
    return box;
  }
  const ratio: number = info.width / info.height;
  const scale: number = Number.isFinite(density) && density > 0 ? Math.max(1, density) : 1;
  const nativeWidth: number = info.width / scale * 1.5;
  box.known = true;
  box.long = info.long || ratio < PREVIEW_LONG_RATIO;
  if (box.long && ratio < COMMENT_SINGLE_LONG_RATIO && nativeWidth / ratio > COMMENT_IMAGE_PREVIEW_MAX_HEIGHT) {
    box.width = Math.min(usable, COMMENT_IMAGE_PREVIEW_MAX_HEIGHT * COMMENT_SINGLE_LONG_RATIO);
    box.height = Math.min(COMMENT_IMAGE_PREVIEW_MAX_HEIGHT, box.width / COMMENT_SINGLE_LONG_RATIO);
    return box;
  }
  box.width = Math.max(1, Math.min(usable, nativeWidth, COMMENT_IMAGE_PREVIEW_MAX_HEIGHT * ratio));
  box.height = Math.max(1, Math.min(COMMENT_IMAGE_PREVIEW_MAX_HEIGHT, box.width / ratio));
  return box;
}

/** 收起时仍按实际源的比例绘制完整图，只让外框裁掉下部，不拉伸缩略图。 */
export function readingDrawHeight(info: FeedImageInfo, frame: FeedImageBox, expanded: boolean): number {
  if (!frame.long || expanded || !hasReadingImageSize(info)) { return frame.height; }
  const height: number = frame.width * (info.height / info.width);
  return Number.isFinite(height) && height > 0 ? height : frame.height;
}

/**
 * 收起长图时 Image 节点仍等于裁切框；先 Contain，再以顶部中心做等比绘制缩放。
 * Contain 的完整图片贴满框高，乘此比例后恰好贴满框宽，源图顶部保持在 y = 0。
 * 只改变绘制，不改变外框、展开高度或 sourceSize 的解码预算。
 */
export function readingImageDrawScale(info: FeedImageInfo, frame: FeedImageBox, expanded: boolean): number {
  if (!frame.long || expanded || !hasReadingImageSize(info) || !Number.isFinite(frame.width) ||
    !Number.isFinite(frame.height) || frame.width <= 0 || frame.height <= 0) { return 1; }
  const scale: number = readingDrawHeight(info, frame, false) / frame.height;
  return Number.isFinite(scale) && scale > 1 ? scale : 1;
}

/** 按实际显示宽度降采样，等比限制长边与像素总量；未知尺寸交给 autoResize。 */
export function readingDecodeSize(info: FeedImageInfo, contentWidth: number,
  density: number): ReadingDecodeSize | undefined {
  if (!hasReadingImageSize(info)) { return undefined; }
  const scale: number = Number.isFinite(density) && density > 0 ? density : 1;
  const usable: number = Number.isFinite(contentWidth) && contentWidth > 0 ? contentWidth : BODY_MIN_BOX_W;
  const width: number = Math.min(info.width, usable * scale);
  const height: number = width * (info.height / info.width);
  if (!Number.isFinite(width) || !Number.isFinite(height) || !(width > 0) || !(height > 0)) { return undefined; }
  const factor: number = Math.min(1, POST_IMAGE_DECODE_EDGE / Math.max(width, height),
    Math.sqrt(POST_IMAGE_DECODE_PIXELS / width / height));
  const size: ReadingDecodeSize = new ReadingDecodeSize();
  size.width = Math.max(1, Math.floor(width * factor));
  size.height = Math.max(1, Math.floor(height * factor));
  return size;
}

/** 全篇原始图片序号 → 查看器有效地址序号；重复 URL 仍按出现位置区分。 */
export function readingViewerIndex(pieces: ContentPiece[], imageIndex: number): number {
  if (!Number.isInteger(imageIndex) || imageIndex < 0) { return -1; }
  let rawIndex: number = 0;
  let previewIndex: number = 0;
  for (const piece of pieces) {
    if (piece.kind !== ContentKind.IMAGE) { continue; }
    const valid: boolean = piece.originImageUrl.length > 0 || piece.imageUrl.length > 0;
    if (rawIndex === imageIndex) { return valid ? previewIndex : -1; }
    rawIndex++;
    if (valid) { previewIndex++; }
  }
  return -1;
}
