import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { ForumDefaultTab } from '../../model/ForumDefaultTab';
import { PreferenceGate } from './PreferenceGate';

const STORE: string = 'tieba_forum_default_tab_prefs';
const TAB_KEY: string = 'default_tab';

/** 本机偏好：新打开吧页时默认进入热门或最新。 */
@ObservedV2
export class ForumDefaultTabStore {
  @Trace value: ForumDefaultTab = ForumDefaultTab.HOT;
  private gate: PreferenceGate = new PreferenceGate();

  async load(context: common.UIAbilityContext): Promise<void> {
    await this.gate.loadOnce(async (revision: number): Promise<void> => {
      try {
        const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
        const stored = await store.get(TAB_KEY, ForumDefaultTab.HOT);
        if (revision === this.gate.revision()) {
          this.value = stored === ForumDefaultTab.LATEST ? ForumDefaultTab.LATEST : ForumDefaultTab.HOT;
        }
      } catch (_) {
        // 读取失败保留本次会话的当前选择。
      } finally {
        this.gate.markLoaded();
      }
    });
  }

  async setValue(value: ForumDefaultTab, context: common.UIAbilityContext): Promise<void> {
    const next: ForumDefaultTab = value === ForumDefaultTab.LATEST ? ForumDefaultTab.LATEST : ForumDefaultTab.HOT;
    this.gate.bump();
    this.value = next;
    try {
      await this.gate.enqueue(async (): Promise<void> => {
        const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
        await store.put(TAB_KEY, next);
        await store.flush();
      });
    } catch (_) {
      throw new Error('吧内默认分区保存失败，本次生效，重启后可能恢复旧值');
    }
  }
}

export const forumDefaultTabStore: ForumDefaultTabStore = new ForumDefaultTabStore();
