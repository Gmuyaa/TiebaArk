

export const BOTTOM_BAR_WIDTH_RATIO: number = 2 / 3;

export function bottomBarSideMarginVp(screenWidthVp: number): number {
  if (!(screenWidthVp > 0)) {
    return 0;
  }
  return screenWidthVp * (1 - BOTTOM_BAR_WIDTH_RATIO) / 2;
}

export function bottomBarWidthVp(screenWidthVp: number): number {
  if (!(screenWidthVp > 0)) {
    return 0;
  }
  return screenWidthVp * BOTTOM_BAR_WIDTH_RATIO;
}
