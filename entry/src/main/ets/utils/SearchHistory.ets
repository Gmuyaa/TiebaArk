

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'tieba_search_history';
const KEY_HISTORY: string = 'words';

/** 历史上限。超出后从最旧的（尾部）开始淘汰 */
export const SEARCH_HISTORY_MAX: number = 50;

function sanitize(word: string): string {
  return word.trim();
}

/** 读取全部历史（最近在前）。读不到/解析失败一律返回空数组，不让界面崩 */
export async function loadSearchHistory(context: common.UIAbilityContext): Promise<string[]> {
  try {
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
    const raw: string = (await store.get(KEY_HISTORY, '')) as string;
    if (raw.length === 0) {
      return [];
    }

    const parsed: string[] = JSON.parse(raw) as string[];
    const words: string[] = [];
    for (const item of parsed) {
      if (typeof item === 'string' && item.trim().length > 0) {
        words.push(item.trim());
      }
    }
    return words;
  } catch {
    return [];
  }
}

/**
 * 记录一次搜索：去重置顶 + 上限淘汰，返回**更新后的完整历史**。
 * 界面拿返回值直接刷新，不用再 load 一次。
 */
export async function addSearchHistory(context: common.UIAbilityContext, word: string): Promise<string[]> {
  const clean: string = sanitize(word);
  const history: string[] = await loadSearchHistory(context);
  const updated: string[] = history.filter((item: string): boolean => item !== clean);
  updated.unshift(clean);
  while (updated.length > SEARCH_HISTORY_MAX) {
    updated.pop();
  }
  try {
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
    await store.put(KEY_HISTORY, JSON.stringify(updated));
    await store.flush();
  } catch {
    // 写失败不影响搜索本身：本次会话内界面仍有 updated，下次启动历史可能少一条
  }
  return updated;
}

/** 清空全部历史 */
export async function clearSearchHistory(context: common.UIAbilityContext): Promise<void> {
  try {
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
    await store.put(KEY_HISTORY, '');
    await store.flush();
  } catch {
    // 同上：存储失败不抛给界面
  }
}
