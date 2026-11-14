import { ThreadBrief } from './ThreadList';

/**
 * 首页卡片流的数据源（`LazyForEach` 用）。
 *
 * **为什么不用 `Repeat`**：2026-11-13 真机 A/B 实测 —— `Repeat`（含去掉 `virtualScroll`
 * 的写法）在数据**整批替换**（下拉刷新）后不会重建已实例化的 `ListItem`：VM 与
 * `FeedList` 的构建都拿到新数组，item builder 却一次都不执行，屏上停在旧的一批
 * （刷新前后内容区像素 diff = 0，见 `docs/开发记录/2026-11-13-首页刷新不更新.md`）。
 * `ForEach` 与 `LazyForEach` 两条路径都正常；这里选 `LazyForEach` 保留虚拟化。
 *
 * 两条更新路径分开，与楼层列表（`FloorDataSource`）同一套做法：
 * - 整批替换（刷新、切频道、屏蔽规则变化）→ `onDataReloaded`，显式重建；
 * - 尾部追加（触底翻页）→ 逐项 `onDataAdd`，已有项不动、滚动位置不跳。
 */
export class ThreadBriefDataSource implements IDataSource {
  private items: ThreadBrief[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): ThreadBrief {
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

  /** 与调用方最新的可见列表对齐：前缀没动就只追加，否则整表重建。 */
  sync(next: ThreadBrief[]): void {
    const current: ThreadBrief[] = this.items;
    const shorter: number = Math.min(current.length, next.length);
    let prefixSame: boolean = true;
    for (let i = 0; i < shorter; i++) {
      if (current[i] !== next[i]) {
        prefixSame = false;
        break;
      }
    }
    if (prefixSame && current.length === next.length) {
      return;
    }
    if (prefixSame && next.length > current.length) {
      this.appendFrom(current.length, next);
      return;
    }
    this.reset(next);
  }

  private reset(next: ThreadBrief[]): void {
    this.items = next.slice();
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  private appendFrom(start: number, next: ThreadBrief[]): void {
    const added: number = next.length - start;
    this.items = next.slice();
    for (let i = 0; i < added; i++) {
      for (let j = 0; j < this.listeners.length; j++) {
        this.listeners[j].onDataAdd(start + i);
      }
    }
  }
}
