/** 首页滚动时三处导航的独立显隐偏好。默认沿用原有的全部隐藏行为。 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const STORE: string = 'tieba_home_navigation_prefs';
const STATUS_KEY: string = 'hide_status_bar';
const TOP_KEY: string = 'hide_top_navigation';
const BOTTOM_KEY: string = 'hide_bottom_navigation';

export enum HomeNavigationPart {
  STATUS = 0,
  TOP = 1,
  BOTTOM = 2
}

@ObservedV2
export class HomeNavigationHideStore {
  @Trace hideStatusBar: boolean = false;
  @Trace hideTopNavigation: boolean = true;
  @Trace hideBottomNavigation: boolean = true;
  @Trace saveError: string = '';
  private loaded: boolean = false;
  private writes: Promise<void> = Promise.resolve();
  private revisions: Map<string, number> = new Map<string, number>();
  private failedKeys: Set<string> = new Set<string>();

  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    const statusRevision: number = this.revisions.get(STATUS_KEY) ?? 0;
    const topRevision: number = this.revisions.get(TOP_KEY) ?? 0;
    const bottomRevision: number = this.revisions.get(BOTTOM_KEY) ?? 0;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      const status: boolean = (await store.get(STATUS_KEY, false)) === true;
      const top: boolean = (await store.get(TOP_KEY, true)) === true;
      const bottom: boolean = (await store.get(BOTTOM_KEY, true)) === true;
      if (statusRevision === (this.revisions.get(STATUS_KEY) ?? 0)) { this.hideStatusBar = status; }
      if (topRevision === (this.revisions.get(TOP_KEY) ?? 0)) { this.hideTopNavigation = top; }
      if (bottomRevision === (this.revisions.get(BOTTOM_KEY) ?? 0)) { this.hideBottomNavigation = bottom; }
    } catch (e) {
      hilog.warn(0x0, 'TiebaNav', 'navigation preferences load failed: %{public}s', String(e));
    }
  }

  async set(part: HomeNavigationPart, enabled: boolean, context: common.UIAbilityContext): Promise<void> {
    let key: string;
    switch (part) {
      case HomeNavigationPart.STATUS:
        this.hideStatusBar = enabled;
        key = STATUS_KEY;
        break;
      case HomeNavigationPart.TOP:
        this.hideTopNavigation = enabled;
        key = TOP_KEY;
        break;
      case HomeNavigationPart.BOTTOM:
        this.hideBottomNavigation = enabled;
        key = BOTTOM_KEY;
        break;
      default:
        return;
    }
    await this.saveValue(key, enabled, context);
  }

  /** 各导航项独立记错；保存另一项成功不能掩盖尚未保存的选择。 */
  private async saveValue(key: string, enabled: boolean, context: common.UIAbilityContext): Promise<void> {
    const revision: number = (this.revisions.get(key) ?? 0) + 1;
    this.revisions.set(key, revision);
    const operation: Promise<void> = this.writes.then(async (): Promise<void> => {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      await store.put(key, enabled);
      await store.flush();
    });
    this.writes = operation.catch(() => {});
    try {
      await operation;
      if (revision === this.revisions.get(key)) { this.failedKeys.delete(key); }
    } catch (e) {
      if (revision === this.revisions.get(key)) { this.failedKeys.add(key); }
      hilog.warn(0x0, 'TiebaNav', 'navigation preference save failed: %{public}s', String(e));
    }
    this.saveError = this.failedKeys.size > 0
      ? '导航隐藏设置本次已生效，保存失败，重启后可能恢复旧值' : '';
  }

  async retrySave(context: common.UIAbilityContext): Promise<void> {
    const retryStatus: boolean = this.failedKeys.has(STATUS_KEY);
    const retryTop: boolean = this.failedKeys.has(TOP_KEY);
    const retryBottom: boolean = this.failedKeys.has(BOTTOM_KEY);
    const operations: Promise<void>[] = [];
    if (retryStatus) { operations.push(this.saveValue(STATUS_KEY, this.hideStatusBar, context)); }
    if (retryTop) { operations.push(this.saveValue(TOP_KEY, this.hideTopNavigation, context)); }
    if (retryBottom) { operations.push(this.saveValue(BOTTOM_KEY, this.hideBottomNavigation, context)); }
    await Promise.all(operations);
  }
}

export const homeNavigationHideStore: HomeNavigationHideStore = new HomeNavigationHideStore();
