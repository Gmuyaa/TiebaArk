
export enum ForumDefaultTab { HOT = 0, LATEST = 1 }

export function forumDefaultTabLabel(value: ForumDefaultTab): string {
  return value === ForumDefaultTab.LATEST ? '最新' : '热门';
}

export interface NamedForumTab { id: number; name: string; }

export function preferredForumTabId(tabs: NamedForumTab[], value: ForumDefaultTab): number {
  const name: string = forumDefaultTabLabel(value);
  for (const tab of tabs) {
    if (tab.id > 0 && tab.name.trim() === name) { return tab.id; }
  }
  return 0;
}
