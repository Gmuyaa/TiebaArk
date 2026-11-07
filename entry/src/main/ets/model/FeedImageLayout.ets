import {
  FeedImageBox, FeedImageInfo, PREVIEW_GAP, PREVIEW_LONG_RATIO, PREVIEW_MULTI_MAX_W, PREVIEW_ROW_H,
  PREVIEW_SINGLE_MAX_H
} from './HomeFeedPresentation';
import { ReadingDecodeSize, readingDecodeSize } from './PostImageLayout';

/** 单个信息流缩略图的目标解码上限，不代表整个页面的实际内存上限。 */
export const FEED_IMAGE_DECODE_PIXELS: number = 2 * 1024 * 1024;
export const FEED_IMAGE_DECODE_EDGE: number = 4096;

/** 新版信息流最多展示前三张；这里仅产出预览下标，原图序列仍由页面持有。 */
export function modernFeedPreviewIndices(total: number): number[] {
  const result: number[] = [];
  const count: number = Number.isFinite(total) ? Math.min(3, Math.max(0, Math.floor(total))) : 0;
  for (let index: number = 0; index < count; index++) { result.push(index); }
  return result;
}

/** 总数只附在最后一张可见预览上，且取完整序列的数量。 */
export function modernFeedTotalLabel(total: number, index: number): string {
  return Number.isFinite(total) && total >= 3 && index === 2 ? `共 ${Math.floor(total)} 张` : '';
}

function usableWidth(contentWidth: number): number {
  return Number.isFinite(contentWidth) && contentWidth > 0 ? contentWidth : PREVIEW_MULTI_MAX_W;
}

function validInfo(info: FeedImageInfo): boolean {
  return Number.isFinite(info.width) && Number.isFinite(info.height) && info.width > 0 && info.height > 0 &&
    Number.isFinite(info.width / info.height) && info.width / info.height > 0;
}

function nativeScale(density: number): number {
  const safeDensity: number = Number.isFinite(density) && density > 0 ? Math.max(1, density) : 1;
  // 单图保留小图上限：换算为 vp 后最多放大 1.5 倍；多图以铺满方格为准。
  return 1.5 / safeDensity;
}

export function modernFeedImageGap(contentWidth: number, total: number): number {
  const columns: number = modernFeedPreviewIndices(total).length;
  if (columns < 2) { return 0; }
  return Math.min(PREVIEW_GAP, usableWidth(contentWidth) / (columns * 2));
}

/** 单图（含长图）完整等比适配宽高上限；多图固定为等宽正方形。 */
export function modernFeedImageBox(info: FeedImageInfo, contentWidth: number,
  total: number, density: number): FeedImageBox {
  const box: FeedImageBox = new FeedImageBox();
  const width: number = usableWidth(contentWidth);
  const columns: number = modernFeedPreviewIndices(total).length;
  box.width = columns > 1 ? (width - modernFeedImageGap(width, total) * (columns - 1)) / columns : width;
  box.height = columns > 1 ? box.width : Math.min(PREVIEW_ROW_H, width / 1.5);
  if (!validInfo(info)) { return box; }
  const ratio: number = info.width / info.height;
  box.known = true;
  box.long = info.long || ratio < PREVIEW_LONG_RATIO;
  if (columns < 2) {
    // 长图标记只描述内容，不再让单图转入顶部裁切；卡片与完整图片保持同一比例。
    box.width = Math.min(width, info.width * nativeScale(density), PREVIEW_SINGLE_MAX_H * ratio);
    box.height = box.width / ratio;
  }
  return box;
}

/** 绘制区与裁切框分离，图片等比铺满外框；超出部分由外框统一裁切和圆角。 */
export class FeedImagePlacement {
  width: number = 0;
  height: number = 0;
  x: number = 0;
  y: number = 0;
}

export function modernFeedImagePlacement(info: FeedImageInfo, box: FeedImageBox,
  _density: number): FeedImagePlacement {
  const result: FeedImagePlacement = new FeedImagePlacement();
  result.width = box.width;
  result.height = box.height;
  if (!validInfo(info)) { return result; }
  // 单图宽高与放大上限已由 modernFeedImageBox 决定；多图即使源图较小也要填满等大方格。
  const scale: number = Math.max(box.width / info.width, box.height / info.height);
  result.width = info.width * scale;
  result.height = info.height * scale;
  result.x = (box.width - result.width) / 2;
  result.y = box.long ? 0 : (box.height - result.height) / 2;
  return result;
}

/** 以最终绘制宽度解码，避免先按 Contain 的细条解码、再放大裁切造成模糊。 */
export function modernFeedDecodeSize(info: FeedImageInfo, box: FeedImageBox,
  density: number): ReadingDecodeSize | undefined {
  const placement: FeedImagePlacement = modernFeedImagePlacement(info, box, density);
  const size: ReadingDecodeSize | undefined = readingDecodeSize(info, placement.width, density);
  if (size === undefined) { return undefined; }
  const factor: number = Math.min(1, FEED_IMAGE_DECODE_EDGE / Math.max(size.width, size.height),
    Math.sqrt(FEED_IMAGE_DECODE_PIXELS / size.width / size.height));
  size.width = Math.max(1, Math.floor(size.width * factor));
  size.height = Math.max(1, Math.floor(size.height * factor));
  return size;
}

/** 在正常大小的 Image 节点上做等比绘制变换；不用超高节点向父布局申请高度。 */
export class FeedImageTransform {
  scale: number = 1;
  xPercent: number = 0;
  yPercent: number = 0;
}

export function modernFeedImageTransform(info: FeedImageInfo, box: FeedImageBox,
  density: number): FeedImageTransform {
  const result: FeedImageTransform = new FeedImageTransform();
  if (!validInfo(info)) { return result; }
  const containedScale: number = Math.min(box.width / info.width, box.height / info.height);
  const containedWidth: number = info.width * containedScale;
  const containedHeight: number = info.height * containedScale;
  const drawn: FeedImagePlacement = modernFeedImagePlacement(info, box, density);
  result.scale = drawn.width / containedWidth;
  result.xPercent = (drawn.x - (box.width - containedWidth) * result.scale / 2) / box.width * 100;
  result.yPercent = (drawn.y - (box.height - containedHeight) * result.scale / 2) / box.height * 100;
  // 方格分配可能产生浮点尾差；近零位移必须精确归零，避免单位缩放被误判为纯平移。
  if (Math.abs(result.xPercent) < 0.0000000001) { result.xPercent = 0; }
  if (Math.abs(result.yPercent) < 0.0000000001) { result.yPercent = 0; }
  return result;
}
