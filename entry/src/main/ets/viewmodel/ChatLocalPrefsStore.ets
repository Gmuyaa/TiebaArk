/**
 * 会话列表的本地偏好：置顶与「删除会话」。贴吧没有私信会话的删除/置顶接口，这两项只存在本机：
 * 置顶只影响列表排序；删除会从列表移除，且**重建会话时不再自动回来**（按 key 记住）。
 * 用 `Preferences` 落盘（同 `common/appearance/*Store.ets` 的口径），失败只影响下次启动。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE: string = 'tieba_chat_local_prefs';
const PINNED_KEY: string = 'pinned_groups';
const REMOVED_KEY: string = 'removed_groups';

@ObservedV2
export class ChatLocalPrefsStore {
  @Trace pinned: string[] = [];
  @Trace removed: string[] = [];
  private loaded: boolean = false;

  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) { return; }
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      const pinned: string = String(await store.get(PINNED_KEY, ''));
      const removed: string = String(await store.get(REMOVED_KEY, ''));
      this.pinned = ChatLocalPrefsStore.split(pinned);
      this.removed = ChatLocalPrefsStore.split(removed);
      this.loaded = true;
    } catch (_) {
      // 读取失败按空处理，本次会话仍可置顶/删除（只是重启后可能恢复）
    }
  }

  private static split(raw: string): string[] {
    if (raw.length === 0) { return []; }
    return raw.split('\n').filter((one: string): boolean => one.length > 0);
  }

  isPinned(key: string): boolean {
    return this.pinned.indexOf(key) >= 0;
  }

  isRemoved(key: string): boolean {
    return this.removed.indexOf(key) >= 0;
  }

  async setPinned(context: common.UIAbilityContext, key: string, value: boolean): Promise<void> {
    const next: string[] = this.pinned.filter((one: string): boolean => one !== key);
    if (value) { next.push(key); }
    this.pinned = next;
    await this.save(context, PINNED_KEY, next);
  }

  async setRemoved(context: common.UIAbilityContext, key: string, value: boolean): Promise<void> {
    const next: string[] = this.removed.filter((one: string): boolean => one !== key);
    if (value) { next.push(key); }
    this.removed = next;
    await this.save(context, REMOVED_KEY, next);
  }

  private async save(context: common.UIAbilityContext, key: string, value: string[]): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      await store.put(key, value.join('\n'));
      await store.flush();
    } catch (_) {
      // 保存失败只影响下次启动的排序/隐藏结果
    }
  }
}

export const chatLocalPrefs: ChatLocalPrefsStore = new ChatLocalPrefsStore();
