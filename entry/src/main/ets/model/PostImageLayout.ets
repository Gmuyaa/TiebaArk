import { BODY_FALLBACK_ASPECT, BODY_MIN_BOX_W, FeedImageBox, FeedImageInfo,
  PREVIEW_LONG_RATIO } from './HomeFeedPresentation';
import { ContentKind, ContentPiece } from './ThreadDetail';

/** 新版正文的长图预览高度；展开后按完整比例阅读。 */
export const POST_LONG_PREVIEW_HEIGHT: number = 240;
/** 普通正文图片完整等比预览的高度上限；长图展开阅读不受此限制。 */
export const POST_IMAGE_PREVIEW_MAX_HEIGHT: number = 280;
/** 评论图片完整等比预览的高度上限；帖子正文仍按原规则展开阅读。 */
export const COMMENT_IMAGE_PREVIEW_MAX_HEIGHT: number = 200;
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

export function readingImageBox(info: FeedImageInfo, contentWidth: number,
  density: number, expanded: boolean): FeedImageBox {
  const box: FeedImageBox = new FeedImageBox();
  const usable: number = Number.isFinite(contentWidth) && contentWidth > 0 ? contentWidth : BODY_MIN_BOX_W;
  box.width = usable;
  box.height = Math.min(POST_IMAGE_PREVIEW_MAX_HEIGHT, usable / BODY_FALLBACK_ASPECT);
  box.long = info.long;
  if (!hasReadingImageSize(info)) { return box; }
  const ratio: number = info.width / info.height;
  box.long = info.long || ratio < PREVIEW_LONG_RATIO;
  const scale: number = Number.isFinite(density) && density > 0 ? density : 1;
  // 普通图同时适配宽高上限并保留小图限制；长图按正文宽度预览或展开阅读。
  box.width = box.long ? usable : Math.max(1,
    Math.min(usable, info.width / scale * 1.5, POST_IMAGE_PREVIEW_MAX_HEIGHT * ratio));
  const fullHeight: number = box.width / ratio;
  if (!Number.isFinite(fullHeight) || fullHeight <= 0) {
    box.width = usable;
    return box;
  }
  box.height = box.long && !expanded ? Math.min(POST_LONG_PREVIEW_HEIGHT, fullHeight) : fullHeight;
  box.known = true;
  return box;
}

/** 评论只缩小整张预览，不裁切或额外撑宽；实际图片与圆角、共享源框保持一致。 */
export function commentImageBox(info: FeedImageInfo, contentWidth: number,
  density: number, placeholder: boolean = false): FeedImageBox {
  const box: FeedImageBox = readingImageBox(info, contentWidth, density, true);
  if (placeholder) {
    // 低流量模式只显示提示文字，不把文字挤进长图缩小后的窄框。
    box.width = Number.isFinite(contentWidth) && contentWidth > 0 ? contentWidth : BODY_MIN_BOX_W;
    box.height = Math.min(COMMENT_IMAGE_PREVIEW_MAX_HEIGHT, box.width / BODY_FALLBACK_ASPECT);
    return box;
  }
  const scale: number = Math.min(1, COMMENT_IMAGE_PREVIEW_MAX_HEIGHT / box.height);
  box.width *= scale;
  box.height *= scale;
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
