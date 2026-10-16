/** 设置系统统一尺寸与视觉参数。颜色由 AppTheme 提供；页面使用全宽行卡片，账号行高度独立，内容底部保留 PAGE_BOTTOM_GAP。 */

/** 行内文字区可用宽度（vp）：376 屏宽 − 2×16 页面边距 − 2×16 行内距 − 图标 24 − 箭头 16 − 各段间隙。 */
export const ROW_TEXT_WIDTH: number = 236;

/** 摘要超过这个字数就放到名称下方（即使宽度够，也不再挤在行右）。 */
export const SUMMARY_MAX_CHARS: number = 8;

/** 名称与摘要之间的最小间隙（vp）。 */
export const SUMMARY_MIN_GAP: number = 12;

/**
 * 「接近底部自动加载」触发距离（px）：距已加载内容底部小于它即请求下一页。
 * **集中配置**，页面与组件都不写魔法数。
 */
export const AUTO_LOAD_TRIGGER_PX: number = 400;

/**
 * 首屏不足一屏时的连续补页上限：达到上限且内容仍无增长就停手，
 * 保留"继续加载"的途径（继续下滑会再次触发），不无限请求。
 */
export const AUTO_FILL_MAX: number = 3;

/** 东文按 1em、西文按 0.56em 估算文字宽度。 */
const ASCII_WIDTH_RATIO: number = 0.56;

/** 东亚字符起点（CJK 统一表意文字区）。*/
const CJK_START: number = 0x2E80;

export class SettingsLayout {
  // ── 页面 ──────────────────────────────────────────────────────────────

  static readonly PAGE_GUTTER: number = 16;
  /** 设置内容到底后的底部间距；覆盖手势区并让末卡圆角完整可见。 */
  static readonly PAGE_BOTTOM_GAP: number = 32;
  /** 卡片圆角（旧值 10；关于页曾写死 16，一并统一到这里）。 */
  static readonly CARD_RADIUS: number = 20;
  /** 卡片之间的竖向间距。 */
  static readonly GROUP_GAP: number = 24;
  /** 分组标题与其下第一张卡片的间距。 */
  static readonly GROUP_TITLE_GAP: number = 8;

  static readonly ROW_GAP: number = 10;

  // ── 行 ────────────────────────────────────────────────────────────────

  static readonly ROW_MIN_H: number = 60;
  /** 带说明的设置行最小高度（与单行同为 60vp，必要时由内容顶高）。 */
  static readonly ROW_MIN_H_TALL: number = 60;

  static readonly ACCOUNT_ROW_MIN_H: number = 72;
  /** 行左右内距（与页面边距同值，保证分隔线起点与文字对齐）。 */
  static readonly ROW_PAD_L: number = 16;
  static readonly ROW_PAD_R: number = 16;
  /** 行上下内距（行高由最小高度与文字高度共同决定）。 */
  static readonly ROW_PAD_V: number = 10;

  // ── 文字（fp） ────────────────────────────────────────────────────────
  /** 顶栏标题字号。 */
  static readonly TITLE_SIZE: number = 22;
  /** 设置名称。 */
  static readonly LABEL_SIZE: number = 16;
  /** 右侧状态值。 */
  static readonly VALUE_SIZE: number = 14;
  /** 辅助说明（副标题、分组标题、影响说明、结果行）。 */
  static readonly SUB_SIZE: number = 13;

  // ── 图标 ──────────────────────────────────────────────────────────────
  static readonly ICON_BOX: number = 24;
  /** 墨迹最长边（外框的 75%）；逐个图标的视觉校正在组件层按实测值做。 */
  static readonly ICON_INK: number = 18;
  static readonly ICON_STROKE: number = 1.5;
  static readonly CHEVRON_SIZE: number = 16;
  /** 箭头内缩（`sys.symbol.chevron_right` 字形盒只有 0.5em，墨迹会偏右）。 */
  static readonly CHEVRON_INSET: number = 4;

  // ── 弹层 ──────────────────────────────────────────────────────────────
  /** 弹层宽度（旧值 156；大字号下不得截断或挤压选项）。 */
  static readonly POPUP_W: number = 200;
  static readonly POPUP_RADIUS: number = 16;
  static readonly POPUP_ROW_H: number = 48;
  static readonly POPUP_PAD_L: number = 18;
  static readonly POPUP_PAD_R: number = 20;
  static readonly POPUP_LABEL_SIZE: number = 16;
  static readonly POPUP_LINE_H: number = 1;
  static readonly POPUP_LINE_INSET: number = 18;
  /** 弹层顶边与被点行的间距（参考图实测为 0：与卡片底边齐平）。 */
  static readonly POPUP_TARGET_SPACE: number = 0;

  // ── 顶栏 ──────────────────────────────────────────────────────────────
  /** 顶栏内容高度（不含状态栏避让）。 */
  static readonly NAV_CONTENT_H: number = 56;

  static readonly NAV_GLASS_START: number = 8;
  static readonly NAV_GLASS_FULL: number = 40;

  /** 玻璃开关按钮直径（返回按钮）。 */
  static readonly NAV_BUTTON_SIZE: number = 40;
  /** 返回按钮左边距。 */
  static readonly NAV_BUTTON_MARGIN_L: number = 12;
}

/**
 * 估算一段文字在当前字号下的宽度（vp）。
 *
 * 只用于**版式决策**（摘要放行右还是名称下方），不用于精确布局；
 * 因此按"东文 1em、西文 0.56em"的近似即可，不需要字体度量。
 */
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
