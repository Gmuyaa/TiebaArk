

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'tieba_search_history';
const KEY_HISTORY: string = 'words';

export const SEARCH_HISTORY_MAX: number = 50;

function sanitize(word: string): string {
  return word.trim();
}

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

  }
  return updated;
}

export async function clearSearchHistory(context: common.UIAbilityContext): Promise<void> {
  try {
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
    await store.put(KEY_HISTORY, '');
    await store.flush();
  } catch {

  }
}
