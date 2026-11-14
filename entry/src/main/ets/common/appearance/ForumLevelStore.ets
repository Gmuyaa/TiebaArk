import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { PreferenceGate } from './PreferenceGate';

const STORE: string = 'tieba_forum_level_prefs';
const STYLE_KEY: string = 'style';

/** 本机等级标签偏好：0 为已有简洁样式，1 为官方等级标签与服务端称号。 */
@ObservedV2
export class ForumLevelStore {
  @Trace style: number = 0;
  private gate: PreferenceGate = new PreferenceGate();

  async load(context: common.UIAbilityContext): Promise<void> {
    await this.gate.loadOnce(async (revision: number): Promise<void> => {
      try {
        const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
        const value = await store.get(STYLE_KEY, 0);
        if (revision === this.gate.revision()) { this.style = value === 1 ? 1 : 0; }
      } catch (_) {
        // 本次会话保留当前偏好。
      } finally {
        // 读失败也不重试：与原实现一致（原实现在 await 之前就置 loaded）。
        this.gate.markLoaded();
      }
    });
  }

  async setStyle(style: number, context: common.UIAbilityContext): Promise<void> {
    const value: number = style === 1 ? 1 : 0;
    const revision: number = this.gate.bump();
    this.style = value;
    try {
      await this.gate.enqueue(async (): Promise<void> => {
        const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
        await store.put(STYLE_KEY, value);
        await store.flush();
      });
    } catch (_) {
      throw new Error('等级标签偏好保存失败，本次生效，重启后可能恢复旧值');
    }
  }
}

export const forumLevelStore: ForumLevelStore = new ForumLevelStore();
