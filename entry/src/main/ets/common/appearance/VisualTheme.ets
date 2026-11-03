/** 整套视觉方案与深浅色、字号、材质偏好正交；持久化编号不可重排。 */
export enum VisualTheme {
  CLASSIC = 0,
  PAPER = 1
}

export function normalizeVisualTheme(raw: number): VisualTheme {
  return raw === VisualTheme.PAPER ? VisualTheme.PAPER : VisualTheme.CLASSIC;
}

export function visualThemeLabel(theme: VisualTheme): string {
  return theme === VisualTheme.PAPER ? '敦煌纸境' : '经典鸿蒙';
}

/** 纸境只改变视觉组合，不改写用户的独立布局偏好。 */
export class PaperLayout {
  static readonly BRAND_HEIGHT: number = 36;
  static readonly CHANNEL_LABEL_SIZE: number = 16;
  static readonly CARD_TITLE_SIZE: number = 19;
  static readonly CARD_TITLE_LINE: number = 28;
  static readonly CARD_CONTENT_GAP: number = 12;
  static readonly CARD_TEXT_GAP: number = 6;
  static readonly READING_TITLE: number = 23;
  static readonly READING_BODY: number = 16;
  static readonly READING_LINE: number = 26;
  static readonly READING_BLOCK_GAP: number = 12;
}
