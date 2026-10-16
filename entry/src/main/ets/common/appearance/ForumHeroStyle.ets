/** 吧页头图区的主题色与渐变派生。服务端颜色来自嵌套的 theme_color；图案层放在深色渐变之上，避免被遮盖。 */

export const FORUM_HERO_FALLBACK_TOP: string = '#0D3A6B';
export const FORUM_HERO_FALLBACK_BOTTOM: string = '#0A2044';

export const FORUM_HERO_PATTERN_OPACITY: number = 0.45;

/** 底图的 4×5 RGBA 对比增强矩阵；放大图案灰度差，保持透明通道。 */
export const FORUM_HERO_PATTERN_COLOR_FILTER: number[] = [
  2.2, 0, 0, 0, -1.35,
  0, 2.2, 0, 0, -1.35,
  0, 0, 2.2, 0, -1.35,
  0, 0, 0, 1, 0
];

/**
 * **真实吧头图**（pb 通道 `forum_headline_img_info.img_url`）层上的暗化 scrim。
 *
 * 头图与底纹不同：它是照片/插画，直接铺满时白字、统计数字与玻璃返回键的对比
 * 完全取决于图片内容本身 —— 不可控。官方 App 的做法就是在图上叠一层
 * 自下而上的暗渐变，这里取底部 0.55 的黑色 scrim（Hero 下半部是统计数字区，
 * 上半部状态栏区域由 0.15 的顶部 scrim 兜住浅色图片）。
 *
 * 头图层不叠主题色蒙层 —— 那会把照片染色；scrim 只负责可读性。
 */
export const FORUM_HERO_HEADLINE_SCRIM_TOP: number = 0.15;
export const FORUM_HERO_HEADLINE_SCRIM_BOTTOM: number = 0.55;

/** 浅色主题色需要压暗的亮度阈值：超过它白字压不住（实测贴吧蓝 3484D3 亮度 ≈ 0.46） */
const LIGHT_COLOR_LUMINANCE: number = 0.45;
/** 过亮主题色的压暗系数 */
const LIGHT_COLOR_DIM: number = 0.52;
/** 底部比顶部再暗一档，形成原有渐变方向感 */
const BOTTOM_DIM: number = 0.7;

const HEX_DIGITS: string = '0123456789abcdef';

/** 吧页 Hero 用到的全部色值。`hasThemeColor=false` 时就是迁移前的兜底渐变 */
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

/**
 * 规范化协议色值：服务端给的是**6 位十六进制但不带 `#`**（实测 `"3F2F0F"`），
 * 界面要 `#RRGGBB` 才能用。长度不符或含非十六进制字符一律返回空串 ——
 * 让调用方回退默认配色，绝不猜、也绝不抛异常。
 */
export function normalizeForumColor(raw: string): string {
  if (raw.length !== 6 || hexToInt(raw) < 0) {
    return '';
  }
  return `#${raw.toUpperCase()}`;
}

/** `#RRGGBB` 按系数压暗（factor=1 原样）。入参非法返回空串 */
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

/** 感知亮度（0~1）。入参非法返回 -1，调用方据此跳过压暗判断 */
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

/**
 * 由协议的吧主题色派生出 Hero 的底色渐变。
 *
 * @param rawCommonColor `forum.theme_color.day.common_color`，如 `"3F2F0F"`（**不带 `#`**）
 *
 * 行为：
 * - 取不到/非法 → `hasThemeColor=false`，界面用兜底深蓝渐变（逐像素保持迁移前观感）；
 * - 拿到 → 过亮的主色先压暗（否则白字压不住），再给出顶部/底部两档实色，
 *   底纹图（`pattern_image`）以 `FORUM_HERO_PATTERN_OPACITY` 叠在它之上。
 */
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

/** 缩写档位：k=10³，w=10⁴（万），kw=10⁷（千万）。遵循贴吧/中文社区计数习惯 */
const COUNT_UNIT_K: number = 1000;
const COUNT_UNIT_W: number = 10000;
const COUNT_UNIT_KW: number = 10000000;

/** 按 `divisor` 缩写并保留至多 1 位小数（去尾零）：4811247/10⁴ → "481.1w"、100000/10⁴ → "10w" */
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
