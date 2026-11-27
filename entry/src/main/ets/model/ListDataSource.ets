/** 通用列表增量数据源，供各长列表 `LazyForEach` 复用。 */

export class ListDataSource<T> implements IDataSource {
  private items: T[] = [];
  private keys: string[] = [];
  private ids: string[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): T {
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

  sync(next: T[], keyOf: (item: T) => string, idOf?: (item: T) => string): void {
    const resolveId = idOf ?? keyOf;
    const nextKeys: string[] = [];
    const nextIds: string[] = [];
    for (let i: number = 0; i < next.length; i++) {
      nextKeys.push(keyOf(next[i]));
      nextIds.push(resolveId(next[i]));
    }
    const prevKeys: string[] = this.keys;
    const prevIds: string[] = this.ids;
    const shorter: number = Math.min(prevKeys.length, nextKeys.length);
    let prefixSame: boolean = true;
    let idsSame: boolean = prevIds.length === nextIds.length;
    const changed: number[] = [];
    for (let i: number = 0; i < shorter; i++) {
      if (prevKeys[i] !== nextKeys[i]) {
        prefixSame = false;
        changed.push(i);
      }
      if (prevIds[i] !== nextIds[i]) {
        idsSame = false;
      }
    }
    this.items = next.slice();
    this.keys = nextKeys;
    this.ids = nextIds;

    if (prefixSame && prevKeys.length === nextKeys.length) {
      return;
    }
    if (prefixSame && nextKeys.length > prevKeys.length) {
      for (let i: number = prevKeys.length; i < nextKeys.length; i++) {
        this.notifyAdd(i);
      }
      return;
    }
    if (prevKeys.length > 0 && nextKeys.length > prevKeys.length) {
      const prependCount: number = nextKeys.length - prevKeys.length;
      let suffixSame: boolean = true;
      for (let i: number = 0; i < prevKeys.length; i++) {
        if (prevKeys[i] !== nextKeys[prependCount + i]) {
          suffixSame = false;
          break;
        }
      }
      if (suffixSame) {
        for (let i: number = 0; i < prependCount; i++) {
          this.notifyAdd(i);
        }
        return;
      }
    }
    if (idsSame && changed.length > 0) {
      for (let i: number = 0; i < changed.length; i++) {
        this.notifyChange(changed[i]);
      }
      return;
    }
    this.notifyReload();
  }

  private notifyAdd(index: number): void {
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataAdd(index);
    }
  }

  private notifyChange(index: number): void {
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataChange(index);
    }
  }

  private notifyReload(): void {
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }
}
