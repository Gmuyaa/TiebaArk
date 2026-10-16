import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

/** 串行应用窗口策略，退出/销毁也排队恢复，避免晚到的进入请求覆盖退出。 */
export class VideoWindowPolicy {
  private queue: Promise<void> = Promise.resolve();
  private win: window.Window | undefined = undefined;
  private orientation: window.Orientation | undefined = undefined;
  private appliedOrientation: window.Orientation | undefined = undefined;
  private keepScreenOn: boolean | undefined = undefined;
  private awakeApplied: boolean = false;
  update(context: common.UIAbilityContext, fullscreen: boolean, landscape: boolean, awake: boolean): Promise<void> {
    const operation: Promise<void> = this.queue.then(async (): Promise<void> => {
      if (this.win === undefined) {
        if (!fullscreen && !awake) { return; }
        this.win = await window.getLastWindow(context);
      }
      const win: window.Window = this.win;
      try {
        if (fullscreen) {
          if (this.orientation === undefined) { this.orientation = win.getPreferredOrientation(); }
          const target: window.Orientation = landscape ? window.Orientation.LANDSCAPE : window.Orientation.PORTRAIT;
          if (this.appliedOrientation !== target) { await win.setPreferredOrientation(target); this.appliedOrientation = target; }
        } else if (this.orientation !== undefined) {
          await win.setPreferredOrientation(this.orientation); this.orientation = undefined; this.appliedOrientation = undefined;
        }
      } finally {
        // 方向设置失败也必须尝试释放常亮，不能让屏幕一直亮着。
        if (awake) {
          if (this.keepScreenOn === undefined) { this.keepScreenOn = win.getWindowProperties().isKeepScreenOn; }
          if (!this.awakeApplied) { await win.setWindowKeepScreenOn(true); this.awakeApplied = true; }
        } else if (this.keepScreenOn !== undefined) {
          await win.setWindowKeepScreenOn(this.keepScreenOn); this.keepScreenOn = undefined; this.awakeApplied = false;
        }
      }
    });
    // 保留调用方的失败结果，同时允许后续恢复请求继续执行。
    this.queue = operation.catch((): void => {});
    return operation;
  }
}
