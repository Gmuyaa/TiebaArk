/** 帖子卡片的共用视觉参数；紧凑卡与回复卡后续迁移时复用，不改变其信息结构。 */
export class ThreadCardLayout {
  static readonly SIDE_PADDING: number = 14;
  static readonly TOP_PADDING: number = 13;
  static readonly BOTTOM_PADDING: number = 12;
  static readonly SECTION_GAP: number = 10;
  static readonly AVATAR_SIZE: number = 36;
  static readonly AUTHOR_SIZE: number = 14;
  static readonly TITLE_SIZE: number = 16;
  static readonly BODY_SIZE: number = 16;
  static readonly META_SIZE: number = 12;
  static readonly LINE_HEIGHT: number = 24;
  static readonly METRIC_ICON_SIZE: number = 14 * 1.2;
  static readonly METRIC_TEXT_SIZE: number = ThreadCardLayout.META_SIZE * 1.2;
  static readonly METRIC_ITEM_GAP: number = 4 * 1.2;
  /** 卡片外距 8vp + 内距 4vp，与首页频道行的 12vp 边界一致。 */
  static readonly METRIC_SIDE_PADDING: number = 4;
}
