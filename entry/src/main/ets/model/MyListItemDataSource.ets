/**
 * 「我的收藏」列表的增量数据源（`LazyForEach` 用）。
 *
 * **为什么不用 `Repeat`**：本 SDK 的 `Repeat` 在数据**整批替换**后不重建已实例化的
 * `ListItem` —— 2026-11-13 首页/吧页真机 A/B 已钉死（见 `model/ThreadBriefDataSource`
 * 文件头），收藏页 2026-11-13 18:07 又复现了一次（14 次吧头像补取全部成功，屏上 20 行
 * 一个都不更新）。`ForEach` 能重建但不虚拟化；这里用 `LazyForEach` + 本数据源兼顾两者。
 *
 * 三条通知路径分开，互不打扰：
 * 1. **同行 key 变了**（吧头像逐条上屏）→ `onDataChange(i)`，只重建那一行，
 *    滚动位置与其它行完全不动；
 * 2. **前缀不变且尾部变长**（触底翻页）→ 逐项 `onDataAdd`，已有项不重建；
 * 3. **其它**（首屏、下拉刷新、删除后重建）→ `onDataReloaded` 整表重建。
 *
 * 行类型只要求这几个字段（`MyListItem` 天然满足），这样本文件不依赖 VM，
 * Node 与真机跑同一份逻辑（见 tools/verify 镜像）。
 */

/** 本数据源需要的最小行字段（`viewmodel/MyListVM.MyListItem` 结构上满足它） */
export interface MyListRow {
  tid: number;
  forumAvatar: string;
  isDeleted: boolean;
  title: string;
  coverUrl: string;
}

/** 行 key 的单一真值来源：渲染与数据源必须用同一份，否则会出现"数据变了但列表没感觉" */
export function myListRowKey(item: MyListRow): string {
  return `${item.tid}-${item.forumAvatar}-${item.isDeleted}-${item.title}-${item.coverUrl}`;
}

/**
 * 行的**身份**（不随吧头像变化）。只用来判断"这一行还是不是原来那一行"：
 * 身份全同 = 只是内容更新（吧头像补到），可以逐行 `onDataChange`；
 * 身份有变动 = 排序/删除/整体替换，必须整表重建。
 */
export function myListRowId(item: MyListRow): string {
  return `${item.tid}`;
}

export class MyListItemDataSource implements IDataSource {
  private items: MyListRow[] = [];
  private keys: string[] = [];
  private ids: string[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): MyListRow {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const at: number = this.listeners.indexOf(listener);
    if (at >= 0) {
      this.listeners.splice(at, 1);
    }
  }

  sync(next: MyListRow[], keyOf: (item: MyListRow) => string = myListRowKey,
    idOf: (item: MyListRow) => string = myListRowId): void {
    const nextKeys: string[] = [];
    const nextIds: string[] = [];
    for (let i: number = 0; i < next.length; i++) {
      nextKeys.push(keyOf(next[i]));
      nextIds.push(idOf(next[i]));
    }
    const currentKeys: string[] = this.keys;
    const currentIds: string[] = this.ids;
    const shorter: number = Math.min(currentKeys.length, nextKeys.length);
    let prefixSame: boolean = true;
    let idsSame: boolean = currentIds.length === nextIds.length;
    const changed: number[] = [];
    for (let i: number = 0; i < shorter; i++) {
      if (currentKeys[i] !== nextKeys[i]) {
        prefixSame = false;
        changed.push(i);
      }
      if (currentIds[i] !== nextIds[i]) {
        idsSame = false;
      }
    }
    if (prefixSame && currentKeys.length === nextKeys.length) {
      return;
    }
    if (prefixSame && next.length > currentKeys.length) {
      this.appendFrom(currentKeys.length, next, nextKeys, nextIds);
      return;
    }
    if (changed.length > 0 && idsSame) {
      // 同一批行、只是内容变了（吧头像逐条上屏）：只重建那几行
      this.items = next.slice();
      this.keys = nextKeys.slice();
      this.ids = nextIds.slice();
      for (let i: number = 0; i < changed.length; i++) {
        this.notifyChange(changed[i]);
      }
      return;
    }
    this.reset(next, nextKeys, nextIds);
  }

  private reset(next: MyListRow[], nextKeys: string[], nextIds: string[]): void {
    this.items = next.slice();
    this.keys = nextKeys.slice();
    this.ids = nextIds.slice();
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  private appendFrom(start: number, next: MyListRow[], nextKeys: string[], nextIds: string[]): void {
    const added: number = next.length - start;
    this.items = next.slice();
    this.keys = nextKeys.slice();
    this.ids = nextIds.slice();
    for (let i: number = 0; i < added; i++) {
      for (let j: number = 0; j < this.listeners.length; j++) {
        this.listeners[j].onDataAdd(start + i);
      }
    }
  }

  private notifyChange(index: number): void {
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataChange(index);
    }
  }
}
