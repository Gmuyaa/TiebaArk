/** 低流量模式偏好。关闭自动加载图片时，卡片保留占位，用户可按需加载原图。 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const STORE: string = 'tieba_low_flow_prefs';
const ENABLED_KEY: string = 'low_flow_enabled';

@ObservedV2
export class LowFlowStore {
  /** 打开后：列表里的图片不自动加载（默认关闭，不改变现有观感） */
  @Trace enabled: boolean = false;
  @Trace saveError: string = '';
  private loaded: boolean = false;
  private writes: Promise<void> = Promise.resolve();
  private saveRevision: number = 0;

  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    const revision: number = this.saveRevision;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      const enabled: boolean = (await store.get(ENABLED_KEY, false)) === true;
      if (revision === this.saveRevision) { this.enabled = enabled; }
    } catch (e) {
      hilog.warn(0x0, 'TiebaLowFlow', 'low flow preference load failed: %{public}s', String(e));
    }
  }

  async setEnabled(enabled: boolean, context: common.UIAbilityContext): Promise<void> {
    this.enabled = enabled;
    await this.retrySave(context);
  }

  /** 写入当前快照并串行落盘；旧操作不得清除新操作的错误。 */
  async retrySave(context: common.UIAbilityContext): Promise<void> {
    const enabled: boolean = this.enabled;
    const revision: number = ++this.saveRevision;
    const operation: Promise<void> = this.writes.then(async (): Promise<void> => {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      await store.put(ENABLED_KEY, enabled);
      await store.flush();
    });
    this.writes = operation.catch(() => {});
    try {
      await operation;
      if (revision === this.saveRevision) { this.saveError = ''; }
    } catch (e) {
      if (revision === this.saveRevision) {
        this.saveError = '低流量模式本次已生效，保存失败，重启后可能恢复旧值';
      }
      hilog.warn(0x0, 'TiebaLowFlow', 'low flow preference save failed: %{public}s', String(e));
    }
  }
}

export const lowFlowStore: LowFlowStore = new LowFlowStore();
