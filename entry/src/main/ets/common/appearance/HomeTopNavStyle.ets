

export enum HomeTopNavStyle {

  UNDERLINE = 0,

  BG_HIGHLIGHT = 1,

  FLOATING_ISLANDS = 2,

  UNIFIED_GLASS = 3,

  LIGHT_LABELS = 4,

  OFFICIAL_DUAL_ROW = 5
}

export const DEFAULT_HOME_TOP_NAV_STYLE: HomeTopNavStyle = HomeTopNavStyle.UNDERLINE;

export interface HomeTopNavOption {

  value: HomeTopNavStyle;

  label: string;

  desc: string;
}

export const ALL_HOME_TOP_NAV_OPTIONS: HomeTopNavOption[] = [
  {
    value: HomeTopNavStyle.UNDERLINE,
    label: '当前样式',
    desc: '频道文字配浅蓝滑动底，背景沿用顶栏渐变模糊'
  },
  {
    value: HomeTopNavStyle.FLOATING_ISLANDS,
    label: '悬浮双岛',
    desc: '左侧频道共用一个玻璃胶囊，右侧是独立的圆形玻璃搜索按钮'
  },
  {
    value: HomeTopNavStyle.UNIFIED_GLASS,
    label: '一体玻璃',
    desc: '频道与搜索放进同一条悬浮玻璃容器，左右对齐页面边距'
  },
  {
    value: HomeTopNavStyle.LIGHT_LABELS,
    label: '轻盈标签',
    desc: '文字频道配短蓝线，背景玻璃向内容自然渐隐'
  },
  {
    value: HomeTopNavStyle.OFFICIAL_DUAL_ROW,
    label: '官方沉浸',
    desc: '上排搜索、下排频道的整片官方标题栏玻璃，内容从背后穿过'
  }
];

export const ALL_HOME_TOP_NAV_STYLES: HomeTopNavStyle[] = [
  HomeTopNavStyle.UNDERLINE,
  HomeTopNavStyle.BG_HIGHLIGHT,
  HomeTopNavStyle.FLOATING_ISLANDS,
  HomeTopNavStyle.UNIFIED_GLASS,
  HomeTopNavStyle.LIGHT_LABELS,
  HomeTopNavStyle.OFFICIAL_DUAL_ROW
];

export function normalizeHomeTopNavStyle(raw: number): HomeTopNavStyle {
  switch (raw) {
    case HomeTopNavStyle.BG_HIGHLIGHT:
      return HomeTopNavStyle.BG_HIGHLIGHT;
    case HomeTopNavStyle.FLOATING_ISLANDS:
      return HomeTopNavStyle.FLOATING_ISLANDS;
    case HomeTopNavStyle.UNIFIED_GLASS:
      return HomeTopNavStyle.UNIFIED_GLASS;
    case HomeTopNavStyle.LIGHT_LABELS:
      return HomeTopNavStyle.LIGHT_LABELS;
    case HomeTopNavStyle.OFFICIAL_DUAL_ROW:
      return HomeTopNavStyle.OFFICIAL_DUAL_ROW;
    case HomeTopNavStyle.UNDERLINE:
    default:
      return DEFAULT_HOME_TOP_NAV_STYLE;
  }
}

export function homeTopNavOptionIndexOf(style: HomeTopNavStyle): number {
  const normalized: HomeTopNavStyle = normalizeHomeTopNavStyle(style as number);
  for (let i = 0; i < ALL_HOME_TOP_NAV_OPTIONS.length; i++) {
    if (ALL_HOME_TOP_NAV_OPTIONS[i].value === normalized) {
      return i;
    }
  }

  return 0;
}

export function homeTopNavStyleLabel(style: HomeTopNavStyle): string {
  return ALL_HOME_TOP_NAV_OPTIONS[homeTopNavOptionIndexOf(style)].label;
}

export function homeTopNavStyleDesc(style: HomeTopNavStyle): string {
  return ALL_HOME_TOP_NAV_OPTIONS[homeTopNavOptionIndexOf(style)].desc;
}

export function homeTopNavStyleUsesGlassSegment(style: HomeTopNavStyle): boolean {
  const normalized: HomeTopNavStyle = normalizeHomeTopNavStyle(style as number);
  return normalized === HomeTopNavStyle.BG_HIGHLIGHT
    || normalized === HomeTopNavStyle.FLOATING_ISLANDS
    || normalized === HomeTopNavStyle.UNIFIED_GLASS;
}

export function homeTopNavRowHeight(style: HomeTopNavStyle, scale: number, textHeight: number = 0): number {
  if (style === HomeTopNavStyle.OFFICIAL_DUAL_ROW) {
    return OFFICIAL_DUAL_ROW_HEIGHT;
  }
  if (style !== HomeTopNavStyle.LIGHT_LABELS) { return 54; }
  return Math.max(54, Math.ceil(Math.max(18 * scale * 1.5, textHeight) + 18));
}

export const OFFICIAL_DUAL_ROW_HEIGHT: number = 72;

export function homeTopNavScrollTarget(start: number, width: number, content: number,
  viewport: number, current: number): number {
  if (viewport <= 0) { return current; }
  const max: number = Math.max(0, content - viewport);
  const actual: number = Math.max(0, Math.min(max, current));
  if (width > viewport) { return Math.max(0, Math.min(max, start + width / 2 - viewport / 2)); }
  if (start < actual) { return Math.max(0, Math.min(max, start)); }
  if (start + width > actual + viewport) { return Math.max(0, Math.min(max, start + width - viewport)); }
  return actual;
}
