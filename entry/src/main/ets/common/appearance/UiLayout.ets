/** 普通页面的共同层级；设置专用尺寸继续由 SettingsLayout 管理。 */
export class UiLayout {
  static readonly PAGE_GUTTER: number = 16;
  /** 沉浸顶栏材质下沿到首屏内容的外部间距，不计入材质高度。 */
  static readonly SEARCH_CONTENT_GAP: number = 12;
  static readonly HEADER_HEIGHT: number = 56;
  static readonly HEADER_TITLE: number = 22;
  static readonly ROOT_TITLE: number = 26;
  static readonly STATE_TITLE: number = 17;
  static readonly STATE_BODY: number = 14;
  static readonly META: number = 12;
}

/** 只计算容器高度；fp 文字由应用统一缩放，不再手动放大文字。 */
export function searchFieldHeight(scale: number): number {
  const actual: number = Number.isFinite(scale) && scale > 0 ? scale : 1;
  return Math.max(32, Math.ceil(16 * actual * 1.4 + 8));
}

export function homeChannelHeight(scale: number): number {
  const actual: number = Number.isFinite(scale) && scale > 0 ? scale : 1;
  return Math.max(30, Math.ceil(17 * actual * 1.4 + 4));
}
