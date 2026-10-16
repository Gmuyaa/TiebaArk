import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/** 本机一键签到方案；官方批量写协议未验证前，默认保留逐个签到。 */
@ObservedV2
export class SignStrategyStore {
  @Trace strategy: number = 0;
  private loaded: boolean = false;
  private loading: Promise<void> | undefined = undefined;
  private revision: number = 0;
  private writes: Promise<void> = Promise.resolve();

  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) { return; }
    if (this.loading !== undefined) { return this.loading; }
    const revision: number = this.revision;
    this.loading = (async (): Promise<void> => {
      try {
        const store = await preferences.getPreferences(context, 'tieba_sign_strategy_prefs');
        const value = await store.get('strategy', 0);
        if (revision === this.revision) { this.strategy = value === 1 ? 1 : 0; }
      } catch (_) { /* 本次会话保留当前选择。 */ }
      finally { this.loaded = true; this.loading = undefined; }
    })();
    return this.loading;
  }

  async setStrategy(strategy: number, context: common.UIAbilityContext): Promise<void> {
    const value: number = strategy === 1 ? 1 : 0;
    this.revision++;
    this.strategy = value;
    const operation: Promise<void> = this.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, 'tieba_sign_strategy_prefs');
      await store.put('strategy', value);
      await store.flush();
    });
    this.writes = operation.catch(() => {});
    try { await operation; } catch (_) {
      throw new Error('签到方案保存失败，本次生效，重启后可能恢复旧值');
    }
  }
}

export const signStrategyStore: SignStrategyStore = new SignStrategyStore();
