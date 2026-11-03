/** 帖子卡片的共用视觉参数；紧凑卡与回复卡后续迁移时复用，不改变其信息结构。 */
export class ThreadCardLayout {
  static readonly RADIUS: number = 9;
  static readonly SIDE_PADDING: number = 14;
  static readonly TOP_PADDING: number = 13;
  static readonly BOTTOM_PADDING: number = 12;
  static readonly SECTION_GAP: number = 10;
  /**
   * 标题 → 摘要的行盒间距。标题与正文各自的行盒上下都留白，行盒间距按 SECTION_GAP 给会
   * 让标题与摘要的墨迹间距明显大于摘要与图片（真机 19.7vp 对 13.1vp）；收到 4vp 后两者一致。
   */
  static readonly TITLE_BODY_GAP: number = 4;
  static readonly AVATAR_SIZE: number = 36;
  static readonly AUTHOR_SIZE: number = 14;
  /** 2026-10-25 起标题比正文大一号，正文尺寸保持不变。 */
  static readonly TITLE_SIZE: number = 17;
  static readonly TITLE_LINE: number = 26;
  static readonly BODY_SIZE: number = 16;
  static readonly META_SIZE: number = 12;
  static readonly LINE_HEIGHT: number = 24;
  static readonly METRIC_ICON_SIZE: number = 14 * 1.2;
  static readonly METRIC_TEXT_SIZE: number = ThreadCardLayout.META_SIZE * 1.2;
  static readonly METRIC_ITEM_GAP: number = 4 * 1.2;
  /** 卡片外距 8vp + 内距 4vp，与首页频道行的 12vp 边界一致。 */
  static readonly METRIC_SIDE_PADDING: number = 4;
}
