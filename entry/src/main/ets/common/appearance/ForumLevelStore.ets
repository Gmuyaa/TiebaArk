import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

@ObservedV2
export class ForumLevelStore {
  @Trace style: number = 0;
  private loaded: boolean = false;
  private revision: number = 0;
  private writes: Promise<void> = Promise.resolve();

  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) { return; }
    this.loaded = true;
    const revision: number = this.revision;
    try {
      const store = await preferences.getPreferences(context, 'tieba_forum_level_prefs');
      const value = await store.get('style', 0);
      if (revision === this.revision) { this.style = value === 1 ? 1 : 0; }
    } catch (_) {  }
  }

  async setStyle(style: number, context: common.UIAbilityContext): Promise<void> {
    const value: number = style === 1 ? 1 : 0;
    this.revision++;
    this.style = value;
    const operation: Promise<void> = this.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, 'tieba_forum_level_prefs');
      await store.put('style', value);
      await store.flush();
    });
    this.writes = operation.catch(() => {});
    try { await operation; } catch (_) {
      throw new Error('等级标签偏好保存失败，本次生效，重启后可能恢复旧值');
    }
  }
}

export const forumLevelStore: ForumLevelStore = new ForumLevelStore();
