
export enum FontSizePref {
  SYSTEM = 0,

  SMALL = 1,
  STANDARD = 2,
  LARGE = 3,
  XLARGE = 4,
  CUSTOM = 5
}

export const DEFAULT_FONT_SIZE_PREF: FontSizePref = FontSizePref.SYSTEM;
export const ALL_FONT_SIZE_PREFS: FontSizePref[] = [FontSizePref.SYSTEM, FontSizePref.CUSTOM];
export const FONT_SIZE_BASE: number = 16;
export const FONT_SIZE_MIN: number = 12;
export const FONT_SIZE_MAX: number = 20;

export function fontSizeLabel(pref: FontSizePref): string {
  return pref === FontSizePref.SYSTEM ? '跟随系统' : '自定义';
}

export function legacyFontSize(raw: number): number {
  switch (raw) {
    case FontSizePref.SMALL:
      return 14;
    case FontSizePref.LARGE:
      return 18;
    case FontSizePref.XLARGE:
      return 20;
    default:
      return FONT_SIZE_BASE;
  }
}

export function normalizeFontSizePref(raw: number): FontSizePref {
  return raw === FontSizePref.CUSTOM || (raw >= FontSizePref.SMALL && raw <= FontSizePref.XLARGE && Number.isInteger(raw))
    ? FontSizePref.CUSTOM : FontSizePref.SYSTEM;
}

export function normalizeCustomFontSize(raw: number): number {
  if (!Number.isFinite(raw)) {
    return FONT_SIZE_BASE;
  }
  return Math.max(FONT_SIZE_MIN, Math.min(FONT_SIZE_MAX, Math.round(raw)));
}

export function fontSizeScaleOf(pref: FontSizePref, systemScale: number, customSize: number): number {
  return pref === FontSizePref.SYSTEM ? systemScale : normalizeCustomFontSize(customSize) / FONT_SIZE_BASE;
}
