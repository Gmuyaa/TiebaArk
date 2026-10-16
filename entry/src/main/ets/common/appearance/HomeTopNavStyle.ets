import { searchFieldHeight, homeChannelHeight } from './UiLayout';

/** 首页只开放官方沉浸与一体玻璃；历史编号保留用于读取旧偏好。 */
export enum HomeTopNavStyle {
  /** 已退役，加载时迁移到官方沉浸。 */
  UNDERLINE = 0,
  /** 已退役，加载时迁移到官方沉浸。 */
  BG_HIGHLIGHT = 1,
  /** 已退役，加载时迁移到官方沉浸。 */
  FLOATING_ISLANDS = 2,
  UNIFIED_GLASS = 3,
  /** 已退役，加载时迁移到官方沉浸。 */
  LIGHT_LABELS = 4,
  /** 双排内容由 HomeDualRowTopBar 的 HDS 悬浮面承载。 */
  OFFICIAL_DUAL_ROW = 5
}

export const DEFAULT_HOME_TOP_NAV_STYLE: HomeTopNavStyle = HomeTopNavStyle.OFFICIAL_DUAL_ROW;

export interface HomeTopNavOption {
  value: HomeTopNavStyle;
  label: string;
  desc: string;
}

/** 默认项在前；持久化编号与显示下标分开。 */
export const ALL_HOME_TOP_NAV_OPTIONS: HomeTopNavOption[] = [
  {
    value: HomeTopNavStyle.OFFICIAL_DUAL_ROW,
    label: '官方沉浸',
    desc: '上排搜索、下排频道的整片玻璃，内容从背后穿过'
  },
  {
    value: HomeTopNavStyle.UNIFIED_GLASS,
    label: '一体玻璃',
    desc: '频道与搜索放进同一条悬浮玻璃容器，左右对齐页面边距'
  }
];

export const ALL_HOME_TOP_NAV_STYLES: HomeTopNavStyle[] = [
  HomeTopNavStyle.UNIFIED_GLASS, HomeTopNavStyle.OFFICIAL_DUAL_ROW
];

/** 保留一体玻璃存档，其余旧值、缺省和脏值统一迁移为官方沉浸。 */
export function normalizeHomeTopNavStyle(raw: number): HomeTopNavStyle {
  return raw === HomeTopNavStyle.UNIFIED_GLASS
    ? HomeTopNavStyle.UNIFIED_GLASS : DEFAULT_HOME_TOP_NAV_STYLE;
}

export function homeTopNavOptionIndexOf(style: HomeTopNavStyle): number {
  return normalizeHomeTopNavStyle(style as number) === HomeTopNavStyle.UNIFIED_GLASS ? 1 : 0;
}

export function homeTopNavStyleLabel(style: HomeTopNavStyle): string {
  return ALL_HOME_TOP_NAV_OPTIONS[homeTopNavOptionIndexOf(style)].label;
}

export function homeTopNavStyleDesc(style: HomeTopNavStyle): string {
  return ALL_HOME_TOP_NAV_OPTIONS[homeTopNavOptionIndexOf(style)].desc;
}

/** 吧页页签跟随一体玻璃使用胶囊，其余使用文字。 */
export function homeTopNavStyleUsesGlassSegment(style: HomeTopNavStyle): boolean {
  return normalizeHomeTopNavStyle(style as number) === HomeTopNavStyle.UNIFIED_GLASS;
}

/** 官方双排列表占位 = 搜索行40 + 间距2 + 频道行30（状态栏由宿主避让）。 */
export const OFFICIAL_DUAL_ROW_HEIGHT: number = 72;

export function homeDualRowHeight(scale: number): number {
  return Math.max(40, searchFieldHeight(scale) + 8) + 2 + homeChannelHeight(scale);
}

export function homeTopNavRowHeight(style: HomeTopNavStyle, scale: number,
  _textHeight: number = 0): number {
  return normalizeHomeTopNavStyle(style as number) === HomeTopNavStyle.OFFICIAL_DUAL_ROW
    ? homeDualRowHeight(scale) : 54;
}

/** 保持已可见项不动；超宽项居中；真实偏移参与计算，包含滚动内容的全部内距。 */
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
