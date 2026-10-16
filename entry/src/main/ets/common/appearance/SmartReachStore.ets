import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/** 本机统一握姿开关及吧页刷新按钮位置，与账号无关。默认开；坏值回落默认。
 * 仅存开关和归一化坐标，不保存握姿传感器数据。关闭仍可拖拽。
 * 同步读取防首屏跳位；写入排队防快速操作倒序，失败明确报告会话内生效。
 */
@ObservedV2
export class SmartReachStore {
  @Trace enabled: boolean = true;
  @Trace xRatio: number = -1;
  @Trace yRatio: number = -1;
  @Trace foreground: boolean = true;
  @Trace status: string = '等待进入吧页';
  private loaded: boolean = false;
  private writes: Promise<void> = Promise.resolve();

  load(context: common.UIAbilityContext): void {
    if (this.loaded) { return; }
    this.loaded = true;
    try {
      const store = preferences.getPreferencesSync(context, { name: 'tieba_smart_reach_prefs' });
      const enabled = store.getSync('enabled', true);
      this.enabled = typeof enabled === 'boolean' ? enabled : true;
      const x = store.getSync('refresh_x', -1);
      const y = store.getSync('refresh_y', -1);
      this.xRatio = typeof x === 'number' && Number.isFinite(x) && x >= 0 && x <= 1 ? x : -1;
      this.yRatio = typeof y === 'number' && Number.isFinite(y) && y >= 0 && y <= 1 ? y : -1;
    } catch (_) { this.status = '偏好读取失败，本次使用默认位置'; }
  }

  async setEnabled(enabled: boolean, context: common.UIAbilityContext): Promise<void> {
    this.enabled = enabled;
    await this.save(context);
  }

  async setPosition(x: number, y: number, context: common.UIAbilityContext): Promise<void> {
    this.xRatio = Math.max(0, Math.min(1, x));
    this.yRatio = Math.max(0, Math.min(1, y));
    await this.save(context);
  }

  private async save(context: common.UIAbilityContext): Promise<void> {
    const enabled = this.enabled;
    const x = this.xRatio;
    const y = this.yRatio;
    const operation = this.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, 'tieba_smart_reach_prefs');
      await store.put('enabled', enabled);
      await store.put('refresh_x', x);
      await store.put('refresh_y', y);
      await store.flush();
    });
    this.writes = operation.catch(() => {});
    try { await operation; }
    catch (_) { throw new Error('智感握姿偏好保存失败，本次生效，重启后可能恢复旧值'); }
  }
}

export const smartReachStore: SmartReachStore = new SmartReachStore();
