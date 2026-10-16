

export const ROW_TEXT_WIDTH: number = 236;

export const SUMMARY_MAX_CHARS: number = 8;

export const SUMMARY_MIN_GAP: number = 12;

export const AUTO_LOAD_TRIGGER_PX: number = 400;

export const AUTO_FILL_MAX: number = 3;

const ASCII_WIDTH_RATIO: number = 0.56;

const CJK_START: number = 0x2E80;

export class SettingsLayout {

  static readonly PAGE_GUTTER: number = 16;

  static readonly PAGE_BOTTOM_GAP: number = 32;

  static readonly CARD_RADIUS: number = 20;

  static readonly GROUP_GAP: number = 24;

  static readonly GROUP_TITLE_GAP: number = 8;

  static readonly ROW_GAP: number = 10;

  static readonly ROW_MIN_H: number = 60;

  static readonly ROW_MIN_H_TALL: number = 60;

  static readonly ACCOUNT_ROW_MIN_H: number = 72;

  static readonly ROW_PAD_L: number = 16;
  static readonly ROW_PAD_R: number = 16;

  static readonly ROW_PAD_V: number = 10;

  static readonly TITLE_SIZE: number = 22;

  static readonly LABEL_SIZE: number = 16;

  static readonly VALUE_SIZE: number = 14;

  static readonly SUB_SIZE: number = 13;

  static readonly ICON_BOX: number = 24;

  static readonly ICON_INK: number = 18;
  static readonly ICON_STROKE: number = 1.5;
  static readonly CHEVRON_SIZE: number = 16;

  static readonly CHEVRON_INSET: number = 4;

  static readonly POPUP_W: number = 200;
  static readonly POPUP_RADIUS: number = 16;
  static readonly POPUP_ROW_H: number = 48;
  static readonly POPUP_PAD_L: number = 18;
  static readonly POPUP_PAD_R: number = 20;
  static readonly POPUP_LABEL_SIZE: number = 16;
  static readonly POPUP_LINE_H: number = 1;
  static readonly POPUP_LINE_INSET: number = 18;

  static readonly POPUP_TARGET_SPACE: number = 0;

  static readonly NAV_CONTENT_H: number = 56;

  static readonly NAV_GLASS_START: number = 8;
  static readonly NAV_GLASS_FULL: number = 40;

  static readonly NAV_BUTTON_SIZE: number = 40;

  static readonly NAV_BUTTON_MARGIN_L: number = 12;
}

export function estimateTextWidth(text: string, fontSize: number): number {
  let width: number = 0;
  for (let i = 0; i < text.length; i++) {
    const code: number = text.charCodeAt(i);
    width += (code < CJK_START ? ASCII_WIDTH_RATIO : 1) * fontSize;
  }
  return width;
}

export function summaryGoesBelow(label: string, summary: string, labelSize: number, valueSize: number): boolean {
  if (summary.length === 0) {
    return false;
  }
  if (summary.length > SUMMARY_MAX_CHARS) {
    return true;
  }
  const need: number = estimateTextWidth(label, labelSize) + estimateTextWidth(summary, valueSize) + SUMMARY_MIN_GAP;
  return need > ROW_TEXT_WIDTH;
}
