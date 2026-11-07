/** 长图阅读控制几何。输入统一为窗口坐标 vp；输出按钮坐标相对页面 Stack。 */
export const LONG_IMAGE_COLLAPSE_WIDTH: number = 88;
export const LONG_IMAGE_COLLAPSE_HEIGHT: number = 40;
export const LONG_IMAGE_COLLAPSE_GAP: number = 8;

export interface LongImageRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface LongImageCandidate {
  id: string;
  rect: LongImageRect;
}

export class LongImageButtonPlacement {
  visible: boolean = false;
  x: number = 0;
  y: number = 0;
  visibleArea: number = 0;
}

export class LongImageSelection extends LongImageButtonPlacement {
  id: string = '';
}

export function validLongImageRect(rect: LongImageRect): boolean {
  return Number.isFinite(rect.x) && Number.isFinite(rect.y) &&
    Number.isFinite(rect.width) && Number.isFinite(rect.height) && rect.width > 0 && rect.height > 0 &&
    Number.isFinite(rect.x + rect.width) && Number.isFinite(rect.y + rect.height);
}

function emptyRect(): LongImageRect { return { x: 0, y: 0, width: 0, height: 0 }; }

function inset(value: number, limit: number): number {
  return Number.isFinite(value) ? Math.max(0, Math.min(limit, value)) : 0;
}

/**
 * 避让量以 host 边缘为基准，再与真实 List 取交集。
 * List 自身已经位于视频/标题栏下方时，不会再把同一高度扣除第二遍。
 */
export function longImageViewport(host: LongImageRect, list: LongImageRect,
  topInset: number, bottomInset: number): LongImageRect {
  if (!validLongImageRect(host) || !validLongImageRect(list)) { return emptyRect(); }
  const left: number = Math.max(host.x, list.x);
  const right: number = Math.min(host.x + host.width, list.x + list.width);
  const top: number = Math.max(host.y + inset(topInset, host.height), list.y);
  const bottom: number = Math.min(host.y + host.height - inset(bottomInset, host.height), list.y + list.height);
  if (right <= left || bottom <= top) { return emptyRect(); }
  return { x: left, y: top, width: right - left, height: bottom - top };
}

/** 按钮完整落在图片可见片段内；放不下完整触控区时隐藏，不借用相邻回复的空间。 */
export function longImageCollapseButton(image: LongImageRect, viewport: LongImageRect,
  host: LongImageRect): LongImageButtonPlacement {
  const result: LongImageButtonPlacement = new LongImageButtonPlacement();
  if (!validLongImageRect(image) || !validLongImageRect(viewport) || !validLongImageRect(host)) { return result; }
  const left: number = Math.max(image.x, viewport.x, host.x);
  const top: number = Math.max(image.y, viewport.y, host.y);
  const right: number = Math.min(image.x + image.width, viewport.x + viewport.width, host.x + host.width);
  const bottom: number = Math.min(image.y + image.height, viewport.y + viewport.height, host.y + host.height);
  const width: number = right - left;
  const height: number = bottom - top;
  if (width < LONG_IMAGE_COLLAPSE_WIDTH || height < LONG_IMAGE_COLLAPSE_HEIGHT) { return result; }
  // 下缘常规留 8vp；仅余一个按钮的短片段允许缩小边距，但按钮本身不缩小。
  const gapY: number = Math.min(LONG_IMAGE_COLLAPSE_GAP, (height - LONG_IMAGE_COLLAPSE_HEIGHT) / 2);
  result.visible = true;
  // 水平居中，避开详情页可停靠左右两侧的主操作圆钮。
  result.x = left + (width - LONG_IMAGE_COLLAPSE_WIDTH) / 2 - host.x;
  result.y = bottom - LONG_IMAGE_COLLAPSE_HEIGHT - gapY - host.y;
  result.visibleArea = width * height;
  return result;
}

/** 同屏多张展开图只显示一个入口，优先可见面积最大者；面积相同时保持原目标。 */
export function selectLongImageButton(images: LongImageCandidate[], viewport: LongImageRect,
  host: LongImageRect, preferredId: string = ''): LongImageSelection {
  const result: LongImageSelection = new LongImageSelection();
  for (const image of images) {
    if (image.id.length === 0) { continue; }
    const candidate: LongImageButtonPlacement = longImageCollapseButton(image.rect, viewport, host);
    if (!candidate.visible) { continue; }
    if (!result.visible || candidate.visibleArea > result.visibleArea ||
      (candidate.visibleArea === result.visibleArea && image.id === preferredId)) {
      result.visible = true;
      result.id = image.id;
      result.x = candidate.x;
      result.y = candidate.y;
      result.visibleArea = candidate.visibleArea;
    }
  }
  return result;
}

/** scrollBy 的正值让内容向上移动；负值把位于视口上方的图顶带回可见区。 */
export function longImageAnchorDelta(imageTop: number, viewportTop: number): number {
  if (!Number.isFinite(imageTop) || !Number.isFinite(viewportTop)) { return 0; }
  const delta: number = imageTop - viewportTop;
  return Number.isFinite(delta) && Math.abs(delta) > 0.5 ? delta : 0;
}
