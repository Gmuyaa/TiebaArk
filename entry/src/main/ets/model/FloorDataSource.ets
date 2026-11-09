import { PostItem } from './ThreadDetail';

/**
 * 楼层列表的增量数据源。
 *
 * 为什么不用 `@Trace` 数组整体替换：那样每次追加一页都要重建整段列表，List 需要
 * 重新测量所有子项的高度，滚动位置会跟着动（表现为"新内容加载后当前页被顶走"）。
 * `LazyForEach` + `onDataAdd` 只告诉列表"末尾多了 N 项"，已有项保持原位，
 * 这是 ArkUI 维护滚动位置的标准做法。
 */
export class FloorDataSource implements IDataSource {
  private items: PostItem[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): PostItem {
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

  /** 整表替换：首屏、刷新、切换排序、定位回复。 */
  reset(items: PostItem[]): void {
    this.items = items.slice();
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  /** 尾部追加：逐项通知新增，已有项不动。 */
  append(items: PostItem[]): void {
    if (items.length === 0) {
      return;
    }
    const start: number = this.items.length;
    this.items = this.items.concat(items);
    for (let i = 0; i < items.length; i++) {
      for (let j = 0; j < this.listeners.length; j++) {
        this.listeners[j].onDataAdd(start + i);
      }
    }
  }
}
