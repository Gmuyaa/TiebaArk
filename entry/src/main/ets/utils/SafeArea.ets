

import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

export const STATUS_BAR_FALLBACK_VP: number = 39;

let lastVisibleStatusBarVp: number = STATUS_BAR_FALLBACK_VP;

export function readStatusBarVp(context: common.UIAbilityContext): Promise<number> {
  return window.getLastWindow(context).then((win: window.Window) => {
    const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    const height: number = px2vp(area.topRect.height);
    if (height > 0) {
      lastVisibleStatusBarVp = height;
    }
    return lastVisibleStatusBarVp;
  });
}
