/**
 * 进吧页关注列表的增量数据源（`LazyForEach` 用）。
 * 身份序列不变时就地写入 `@ObservedV2` 字段，不触发 `onDataChange` / `onDataReloaded`，
 * 避免每行内置的材质按钮与头像在签到或补齐连签天数时整行销毁重建。
 */
import { FollowForumItem } from './FollowForum';

export function followForumRowId(item: FollowForumItem): string {
  return `${item.fid}-${item.fname}`;
}

export class FollowForumDataSource implements IDataSource {
  private items: FollowForumItem[] = [];
  private ids: string[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): FollowForumItem {
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

  snapshot(): FollowForumItem[] {
    return this.items.slice();
  }

  /** 返回序列结构是否变化；仅原地写入字段时返回 false，避免胶囊列表整组重建。 */
  sync(next: FollowForumItem[]): boolean {
    const nextIds: string[] = [];
    for (let i: number = 0; i < next.length; i++) {
      nextIds.push(followForumRowId(next[i]));
    }
    const shorter: number = Math.min(this.ids.length, nextIds.length);
    let prefixSame: boolean = true;
    for (let i: number = 0; i < shorter; i++) {
      if (this.ids[i] !== nextIds[i]) {
        prefixSame = false;
        break;
      }
    }
    if (prefixSame && this.ids.length === nextIds.length) {
      for (let i: number = 0; i < next.length; i++) {
        this.items[i].applyFrom(next[i]);
      }
      return false;
    }
    if (prefixSame && next.length > this.ids.length) {
      for (let i: number = 0; i < shorter; i++) {
        this.items[i].applyFrom(next[i]);
      }
      this.appendFrom(this.ids.length, next, nextIds);
      return true;
    }
    this.reset(next, nextIds);
    return true;
  }

  private reset(next: FollowForumItem[], nextIds: string[]): void {
    const copied: FollowForumItem[] = [];
    for (let i: number = 0; i < next.length; i++) {
      copied.push(FollowForumItem.copy(next[i]));
    }
    this.items = copied;
    this.ids = nextIds;
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  private appendFrom(start: number, next: FollowForumItem[], nextIds: string[]): void {
    const added: number = next.length - start;
    for (let i: number = start; i < next.length; i++) {
      this.items.push(FollowForumItem.copy(next[i]));
      this.ids.push(nextIds[i]);
    }
    for (let i: number = 0; i < added; i++) {
      for (let j: number = 0; j < this.listeners.length; j++) {
        this.listeners[j].onDataAdd(start + i);
      }
    }
  }
}
