/** 吧内分区的本机默认选择；实际请求始终使用服务端返回的分区 ID。 */
export enum ForumDefaultTab { HOT = 0, LATEST = 1 }

export function forumDefaultTabLabel(value: ForumDefaultTab): string {
  return value === ForumDefaultTab.LATEST ? '最新' : '热门';
}

export interface NamedForumTab { id: number; name: string; }

/** 对应分区不存在时返回 0，调用方保留服务端实际默认分区。 */
export function preferredForumTabId(tabs: NamedForumTab[], value: ForumDefaultTab): number {
  const name: string = forumDefaultTabLabel(value);
  for (const tab of tabs) {
    if (tab.id > 0 && tab.name.trim() === name) { return tab.id; }
  }
  return 0;
}
