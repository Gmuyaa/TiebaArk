

export const FORUM_HERO_FALLBACK_TOP: string = '#0D3A6B';
export const FORUM_HERO_FALLBACK_BOTTOM: string = '#0A2044';

export const FORUM_HERO_PATTERN_OPACITY: number = 0.45;

export const FORUM_HERO_PATTERN_COLOR_FILTER: number[] = [
  2.2, 0, 0, 0, -1.35,
  0, 2.2, 0, 0, -1.35,
  0, 0, 2.2, 0, -1.35,
  0, 0, 0, 1, 0
];

export const FORUM_HERO_HEADLINE_SCRIM_TOP: number = 0.15;
export const FORUM_HERO_HEADLINE_SCRIM_BOTTOM: number = 0.55;

const LIGHT_COLOR_LUMINANCE: number = 0.45;

const LIGHT_COLOR_DIM: number = 0.52;

const BOTTOM_DIM: number = 0.7;

const HEX_DIGITS: string = '0123456789abcdef';

export class ForumHeroPalette {
  topColor: string = FORUM_HERO_FALLBACK_TOP;
  bottomColor: string = FORUM_HERO_FALLBACK_BOTTOM;
  hasThemeColor: boolean = false;
}

function hexToInt(hex: string): number {
  let value: number = 0;
  for (let i: number = 0; i < hex.length; i++) {
    const digit: number = HEX_DIGITS.indexOf(hex.charAt(i).toLowerCase());
    if (digit < 0) {
      return -1;
    }
    value = value * 16 + digit;
  }
  return value;
}

function byteToHex(value: number): string {
  const clamped: number = value < 0 ? 0 : (value > 255 ? 255 : Math.round(value));
  const text: string = clamped.toString(16).toUpperCase();
  return text.length === 1 ? `0${text}` : text;
}

export function normalizeForumColor(raw: string): string {
  if (raw.length !== 6 || hexToInt(raw) < 0) {
    return '';
  }
  return `#${raw.toUpperCase()}`;
}

export function darkenColor(color: string, factor: number): string {
  if (color.length !== 7 || color.charAt(0) !== '#' || hexToInt(color.slice(1)) < 0) {
    return '';
  }
  const rgb: number = hexToInt(color.slice(1));
  const r: number = (rgb >> 16) & 0xFF;
  const g: number = (rgb >> 8) & 0xFF;
  const b: number = rgb & 0xFF;
  return `#${byteToHex(r * factor)}${byteToHex(g * factor)}${byteToHex(b * factor)}`;
}

export function colorLuminance(color: string): number {
  if (color.length !== 7 || color.charAt(0) !== '#' || hexToInt(color.slice(1)) < 0) {
    return -1;
  }
  const rgb: number = hexToInt(color.slice(1));
  const r: number = (rgb >> 16) & 0xFF;
  const g: number = (rgb >> 8) & 0xFF;
  const b: number = rgb & 0xFF;
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255;
}

export function forumHeroPalette(rawCommonColor: string): ForumHeroPalette {
  const palette: ForumHeroPalette = new ForumHeroPalette();
  const base: string = normalizeForumColor(rawCommonColor);
  if (base.length === 0) {
    return palette;
  }
  const luminance: number = colorLuminance(base);
  const adjusted: string = luminance > LIGHT_COLOR_LUMINANCE ? darkenColor(base, LIGHT_COLOR_DIM) : base;
  palette.hasThemeColor = true;
  palette.topColor = adjusted;
  palette.bottomColor = darkenColor(adjusted, BOTTOM_DIM);
  return palette;
}

const COUNT_UNIT_K: number = 1000;
const COUNT_UNIT_W: number = 10000;
const COUNT_UNIT_KW: number = 10000000;

function countWithTenth(count: number, divisor: number, unit: string): string {
  const tenth: number = Math.floor(count / (divisor / 10));
  const whole: number = Math.floor(tenth / 10);
  const frac: number = tenth % 10;
  return frac === 0 ? `${whole}${unit}` : `${whole}.${frac}${unit}`;
}

export function forumCountLabel(count: number): string {
  if (!(count > 0)) {
    return '0';
  }
  if (count < COUNT_UNIT_K) {
    return `${Math.floor(count)}`;
  }
  if (count < COUNT_UNIT_W) {
    return countWithTenth(count, COUNT_UNIT_K, 'k');
  }
  if (count < COUNT_UNIT_KW) {
    return countWithTenth(count, COUNT_UNIT_W, 'w');
  }
  return countWithTenth(count, COUNT_UNIT_KW, 'kw');
}
