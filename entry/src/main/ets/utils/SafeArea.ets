/** 读取顶部状态栏高度并换算为 vp；窗口不可用时使用调用方的兜底值。 */

import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

/**
 * 状态栏高度兜底值（vp）：只在首次有效测量前使用，隐藏系统栏期间沿用最近一次有效测量。
 */
export const STATUS_BAR_FALLBACK_VP: number = 39;
/** 隐藏状态栏时系统避让区会暂时报 0；保留最后一次可见时测得的高度。 */
let lastVisibleStatusBarVp: number = STATUS_BAR_FALLBACK_VP;

/** 同步读取最近一次有效测得的状态栏高度（vp），供新页面首帧直接落位避免二次重排。 */
export function cachedStatusBarVp(): number {
  return lastVisibleStatusBarVp;
}

/**
 * 读取状态栏高度（vp）。
 *
 * 每次调用都重新查询窗口，尺寸变化后更新最近一次有效高度；系统栏隐藏期间
 * 避让区可能报告 0，此时沿用上次测量值，让新页面顶栏仍留在原位。
 * 调用方负责在 `.catch()` 里静默兜底——拿不到时保持兜底值，界面只是偏差几像素。
 */
export function readStatusBarVp(context: common.UIAbilityContext): Promise<number> {
  return window.getLastWindow(context).then((win: window.Window) => {
    const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    const height: number = win.getUIContext().px2vp(area.topRect.height);
    if (height > 0) {
      lastVisibleStatusBarVp = height;
    }
    return lastVisibleStatusBarVp;
  });
}

/**
 * 读取底部手势条/导航条高度（vp）。
 *
 * 全屏页（没有底部 TabBar 的页面）要自己让开这块：贴底的输入栏、
 * 悬浮按钮如果铺到屏幕最底，会被手势条压住一截。
 * 读不到时返回 0，调用方按"不额外留白"处理。
 */
export function readBottomInsetVp(context: common.UIAbilityContext): Promise<number> {
  return window.getLastWindow(context).then((win: window.Window) => {
    const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    return win.getUIContext().px2vp(area.bottomRect.height);
  });
}
