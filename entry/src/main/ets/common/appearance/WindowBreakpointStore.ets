/** 窗口响应式断点（sm < 600vp / md 600~839vp / lg >= 840vp），供平板与折叠屏限宽居中与列数适配。 */

import { window } from '@kit.ArkUI';

export enum WindowBreakpoint {
  SM = 'sm',
  MD = 'md',
  LG = 'lg'
}

export function breakpointForWidthVp(widthVp: number): WindowBreakpoint {
  if (widthVp >= 840) { return WindowBreakpoint.LG; }
  if (widthVp >= 600) { return WindowBreakpoint.MD; }
  return WindowBreakpoint.SM;
}

export function readingMaxWidthFor(bp: WindowBreakpoint): number {
  if (bp === WindowBreakpoint.LG) { return 720; }
  if (bp === WindowBreakpoint.MD) { return 640; }
  return 0;
}

export function wideMaxWidthFor(bp: WindowBreakpoint): number {
  if (bp === WindowBreakpoint.LG) { return 840; }
  if (bp === WindowBreakpoint.MD) { return 680; }
  return 0;
}

export function videoColumnsFor(bp: WindowBreakpoint): number {
  if (bp === WindowBreakpoint.LG) { return 4; }
  if (bp === WindowBreakpoint.MD) { return 3; }
  return 2;
}

@ObservedV2
export class WindowBreakpointStore {
  @Trace widthVp: number = 0;
  @Trace heightVp: number = 0;
  @Trace breakpoint: WindowBreakpoint = WindowBreakpoint.SM;

  private boundWin: window.Window | undefined = undefined;
  private resizeCb: ((size: window.Size) => void) | undefined = undefined;

  get isWide(): boolean {
    return this.breakpoint !== WindowBreakpoint.SM;
  }

  /** 正文/列表/设置页在大屏下的居中最大宽度；手机竖屏（SM）返回 '100%'。 */
  readingMaxWidth(): Length {
    const limit: number = readingMaxWidthFor(this.breakpoint);
    return limit > 0 ? limit : '100%';
  }

  /** 发帖/宽容器在大屏下的居中最大宽度；手机竖屏（SM）返回 '100%'。 */
  wideMaxWidth(): Length {
    const limit: number = wideMaxWidthFor(this.breakpoint);
    return limit > 0 ? limit : '100%';
  }

  /** 弹窗/回复卡片宽度：手机按屏宽减两侧边距，大屏封顶。 */
  dialogWidth(sideMargin: number, maxCap: number = 560, fallback: number = 336): number {
    if (this.widthVp <= 0) { return fallback; }
    const avail: number = Math.max(240, this.widthVp - sideMargin * 2);
    return this.isWide ? Math.min(avail, maxCap) : avail;
  }

  videoColumns(): number {
    return videoColumnsFor(this.breakpoint);
  }

  updateFromPx(widthPx: number, heightPx: number, converter?: (px: number) => number): void {
    if (widthPx <= 0 || heightPx <= 0) { return; }
    const wVp: number = converter !== undefined ? converter(widthPx) : widthPx;
    const hVp: number = converter !== undefined ? converter(heightPx) : heightPx;
    this.widthVp = wVp;
    this.heightVp = hVp;
    this.breakpoint = breakpointForWidthVp(wVp);
  }

  attachWindow(win: window.Window): void {
    this.detachWindow();
    this.boundWin = win;
    const toVp = (px: number): number => {
      try { return win.getUIContext().px2vp(px); } catch (_) { return px; }
    };
    try {
      const rect: window.Rect = win.getWindowProperties().windowRect;
      this.updateFromPx(rect.width, rect.height, toVp);
    } catch {
      // 取不到窗口尺寸时维持 SM 兜底
    }
    this.resizeCb = (size: window.Size): void => {
      this.updateFromPx(size.width, size.height, toVp);
    };
    try {
      win.on('windowSizeChange', this.resizeCb);
    } catch {
      this.resizeCb = undefined;
    }
  }

  detachWindow(): void {
    if (this.boundWin !== undefined && this.resizeCb !== undefined) {
      try {
        this.boundWin.off('windowSizeChange', this.resizeCb);
      } catch {
        // 窗口已销毁时静默忽略
      }
    }
    this.boundWin = undefined;
    this.resizeCb = undefined;
  }
}

export const windowBreakpoint: WindowBreakpointStore = new WindowBreakpointStore();
