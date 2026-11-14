import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { PreferenceGate } from './PreferenceGate';

const STORE: string = 'tieba_sign_strategy_prefs';
const STRATEGY_KEY: string = 'strategy';

/** 本机一键签到方案：0逐个、1官方、2混合；默认逐个，官方每批最多50个吧。 */
@ObservedV2
export class SignStrategyStore {
  @Trace strategy: number = 0;
  private gate: PreferenceGate = new PreferenceGate();

  async load(context: common.UIAbilityContext): Promise<void> {
    await this.gate.loadOnce(async (revision: number): Promise<void> => {
      try {
        const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
        const value = await store.get(STRATEGY_KEY, 0);
        if (revision === this.gate.revision()) {
          this.strategy = value === 1 || value === 2 ? value : 0;
        }
      } catch (_) {
        // 本次会话保留当前选择。
      } finally {
        this.gate.markLoaded();
      }
    });
  }

  async setStrategy(strategy: number, context: common.UIAbilityContext): Promise<void> {
    const value: number = strategy === 1 || strategy === 2 ? strategy : 0;
    this.gate.bump();
    this.strategy = value;
    try {
      await this.gate.enqueue(async (): Promise<void> => {
        const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
        await store.put(STRATEGY_KEY, value);
        await store.flush();
      });
    } catch (_) {
      throw new Error('签到方案保存失败，本次生效，重启后可能恢复旧值');
    }
  }
}

export const signStrategyStore: SignStrategyStore = new SignStrategyStore();
