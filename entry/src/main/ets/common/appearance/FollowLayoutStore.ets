import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { PreferenceGate } from './PreferenceGate';

const STORE: string = 'tieba_follow_layout_prefs';
const LAYOUT_KEY: string = 'layout';

export const FOLLOW_LAYOUT_LIST: number = 0;
export const FOLLOW_LAYOUT_CAPSULE: number = 1;

/** 进吧页「我的关注」布局偏好：0 为列表，1 为小胶囊。 */
@ObservedV2
export class FollowLayoutStore {
  @Trace layout: number = FOLLOW_LAYOUT_LIST;
  private gate: PreferenceGate = new PreferenceGate();

  get isCapsule(): boolean {
    return this.layout === FOLLOW_LAYOUT_CAPSULE;
  }

  async load(context: common.UIAbilityContext): Promise<void> {
    await this.gate.loadOnce(async (revision: number): Promise<void> => {
      try {
        const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
        const value = await store.get(LAYOUT_KEY, FOLLOW_LAYOUT_LIST);
        if (revision === this.gate.revision()) {
          this.layout = value === FOLLOW_LAYOUT_CAPSULE ? FOLLOW_LAYOUT_CAPSULE : FOLLOW_LAYOUT_LIST;
        }
      } catch (_) {
        // 本次会话保留当前偏好。
      } finally {
        this.gate.markLoaded();
      }
    });
  }

  async setLayout(layout: number, context: common.UIAbilityContext): Promise<void> {
    const value: number = layout === FOLLOW_LAYOUT_CAPSULE ? FOLLOW_LAYOUT_CAPSULE : FOLLOW_LAYOUT_LIST;
    this.gate.bump();
    this.layout = value;
    try {
      await this.gate.enqueue(async (): Promise<void> => {
        const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
        await store.put(LAYOUT_KEY, value);
        await store.flush();
      });
    } catch (_) {
      // 写盘失败时保留本次会话内存态，不阻断页面切换。
    }
  }

  async toggle(context: common.UIAbilityContext): Promise<void> {
    const next: number = this.isCapsule ? FOLLOW_LAYOUT_LIST : FOLLOW_LAYOUT_CAPSULE;
    await this.setLayout(next, context);
  }
}

export const followLayoutStore: FollowLayoutStore = new FollowLayoutStore();
