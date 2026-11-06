/** 整套视觉方案与深浅色、字号、材质偏好正交；持久化编号不可重排。 */
export enum VisualTheme {
  CLASSIC = 0,
  PAPER = 1,
  PINE = 2,
  LILAC = 3,
  CLAY = 4,
  SKY = 5,
  BERRY = 6,
  ORANGE = 7
}

/** 顺序与已持久化编号固定，新配色追加且沿用经典布局偏好。 */
export const ALL_VISUAL_THEMES: VisualTheme[] = [
  VisualTheme.CLASSIC, VisualTheme.PAPER, VisualTheme.PINE, VisualTheme.LILAC,
  VisualTheme.CLAY, VisualTheme.SKY, VisualTheme.BERRY, VisualTheme.ORANGE
];

export function normalizeVisualTheme(raw: number): VisualTheme {
  switch (raw) {
    case VisualTheme.PAPER: return VisualTheme.PAPER;
    case VisualTheme.PINE: return VisualTheme.PINE;
    case VisualTheme.LILAC: return VisualTheme.LILAC;
    case VisualTheme.CLAY: return VisualTheme.CLAY;
    case VisualTheme.SKY: return VisualTheme.SKY;
    case VisualTheme.BERRY: return VisualTheme.BERRY;
    case VisualTheme.ORANGE: return VisualTheme.ORANGE;
    default: return VisualTheme.CLASSIC;
  }
}

export function visualThemeLabel(theme: VisualTheme): string {
  switch (theme) {
    case VisualTheme.PAPER: return '敦煌纸境';
    case VisualTheme.PINE: return '雾松';
    case VisualTheme.LILAC: return '烟紫';
    case VisualTheme.CLAY: return '砂陶';
    case VisualTheme.SKY: return '晴空';
    case VisualTheme.BERRY: return '莓果';
    case VisualTheme.ORANGE: return '橘光';
    default: return '经典鸿蒙';
  }
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
