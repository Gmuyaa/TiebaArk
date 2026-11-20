

export const BOTTOM_BAR_WIDTH_RATIO: number = 2 / 3;

/**
 * 悬浮底栏单侧外边距（vp）= 屏宽 / 6，使胶囊宽为屏宽的 2/3（HDS `barFloatingStyle.barSideMargin`）。
 *
 * 不能写死 vp：模拟器 1080px、真机 1316px、折叠屏各不相同，写死的数字只在某一块屏上恰好是 2/3。
 * 边界：屏宽拿不到（≤0 / NaN）时返回 0 把决定权交回系统，不要把负数或 NaN 传给 `barSideMargin`。
 */
export function bottomBarSideMarginVp(screenWidthVp: number): number {
  if (!(screenWidthVp > 0)) {
    return 0;
  }
  return screenWidthVp * (1 - BOTTOM_BAR_WIDTH_RATIO) / 2;
}

/**
 * 胶囊宽度（vp），供测试与文档对账：真实宽度由系统按 `barSideMargin` 摆放，本函数不参与布局。
 */
export function bottomBarWidthVp(screenWidthVp: number): number {
  if (!(screenWidthVp > 0)) {
    return 0;
  }
  return screenWidthVp * BOTTOM_BAR_WIDTH_RATIO;
}
