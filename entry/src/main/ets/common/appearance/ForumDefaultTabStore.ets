import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { ForumDefaultTab } from '../../model/ForumDefaultTab';

@ObservedV2
export class ForumDefaultTabStore {
  @Trace value: ForumDefaultTab = ForumDefaultTab.HOT;
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
        const store: preferences.Preferences = await preferences.getPreferences(context, 'tieba_forum_default_tab_prefs');
        const stored = await store.get('default_tab', ForumDefaultTab.HOT);
        if (revision === this.revision) {
          this.value = stored === ForumDefaultTab.LATEST ? ForumDefaultTab.LATEST : ForumDefaultTab.HOT;
        }
      } catch (_) {  }
      finally { this.loaded = true; this.loading = undefined; }
    })();
    return this.loading;
  }

  async setValue(value: ForumDefaultTab, context: common.UIAbilityContext): Promise<void> {
    const next: ForumDefaultTab = value === ForumDefaultTab.LATEST ? ForumDefaultTab.LATEST : ForumDefaultTab.HOT;
    this.revision++;
    this.value = next;
    const operation: Promise<void> = this.writes.then(async (): Promise<void> => {
      const store: preferences.Preferences = await preferences.getPreferences(context, 'tieba_forum_default_tab_prefs');
      await store.put('default_tab', next);
      await store.flush();
    });
    this.writes = operation.catch(() => {});
    try { await operation; } catch (_) {
      throw new Error('吧内默认分区保存失败，本次生效，重启后可能恢复旧值');
    }
  }
}

export const forumDefaultTabStore: ForumDefaultTabStore = new ForumDefaultTabStore();
