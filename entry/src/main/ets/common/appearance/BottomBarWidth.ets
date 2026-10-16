

export const BOTTOM_BAR_WIDTH_RATIO: number = 2 / 3;

/**
 * 悬浮底栏**单侧**外边距（vp）= (屏宽 − 屏宽 × 2/3) / 2 = **屏宽 / 6**。
 *
 * 它对应 HDS `barFloatingStyle.barSideMargin`：胶囊宽度 = 屏宽 − 2 × 侧边距。
 *
 * **为什么要按屏宽算而不是写死一个 vp**：模拟器 1080px、真机 1316px、折叠屏各不相同，
 * 写死的数字只在某一块屏上恰好等于 2/3（例如 `BAR_SIDE=24` 在 1316px 的屏上是 89% 宽，
 * 离 2/3 差得远）。比例是需求，宽度是结果 —— 只能从屏宽推。
 *
 * 边界：屏宽拿不到（≤0 / NaN）时退回 0，把决定权交回系统，
 * **不要把负数或 NaN 传给 `barSideMargin`**。
 */
export function bottomBarSideMarginVp(screenWidthVp: number): number {
  if (!(screenWidthVp > 0)) {
    return 0;
  }
  return screenWidthVp * (1 - BOTTOM_BAR_WIDTH_RATIO) / 2;
}

/**
 * 胶囊宽度（vp）—— 供测试与文档对账用。
 *
 * 真实渲染宽度由系统按 `barSideMargin` 摆放，本函数**不参与布局**；
 * 存在的意义是让"底栏确实是屏宽的 2/3"成为一条可断言的契约，而不是只能靠截图目测。
 */
export function bottomBarWidthVp(screenWidthVp: number): number {
  if (!(screenWidthVp > 0)) {
    return 0;
  }
  return screenWidthVp * BOTTOM_BAR_WIDTH_RATIO;
}
