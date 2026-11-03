import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/** 本机统一握姿开关及各悬浮按钮的独立位置，与账号无关。默认开；坏值回落默认。
 * 仅存开关和归一化坐标，不保存握姿传感器数据。关闭仍可拖拽。
 * 同步读取防首屏跳位；写入排队防快速操作倒序，失败明确报告会话内生效。
 */
@ObservedV2
export class SmartReachStore {
  @Trace homeComposeEnabled: boolean = true;
  @Trace homeXRatio: number = -1;
  @Trace homeYRatio: number = -1;
  @Trace enabled: boolean = true;
  @Trace imageMenuEnabled: boolean = true;
  @Trace imageMenuLongPress: boolean = false;
  @Trace imageXRatio: number = -1;
  @Trace imageYRatio: number = -1;
  @Trace forumTabsEnabled: boolean = true;
  @Trace forumTabsFloating: boolean = true;
  @Trace xRatio: number = -1;
  @Trace yRatio: number = -1;
  @Trace threadXRatio: number = -1;
  @Trace threadYRatio: number = -1;
  @Trace foreground: boolean = true;
  @Trace status: string = '等待进入吧页';
  private loaded: boolean = false;
  private writes: Promise<void> = Promise.resolve();

  load(context: common.UIAbilityContext): void {
    if (this.loaded) { return; }
    this.loaded = true;
    try {
      const store = preferences.getPreferencesSync(context, { name: 'tieba_smart_reach_prefs' });
      const homeEnabled = store.getSync('home_compose_enabled', true);
      this.homeComposeEnabled = typeof homeEnabled === 'boolean' ? homeEnabled : true;
      const hx = store.getSync('home_compose_x', -1);
      const hy = store.getSync('home_compose_y', -1);
      this.homeXRatio = typeof hx === 'number' && Number.isFinite(hx) && hx >= 0 && hx <= 1 ? hx : -1;
      this.homeYRatio = typeof hy === 'number' && Number.isFinite(hy) && hy >= 0 && hy <= 1 ? hy : -1;
      const enabled = store.getSync('enabled', true);
      this.enabled = typeof enabled === 'boolean' ? enabled : true;
      const tabsEnabled = store.getSync('forum_tabs_enabled', true);
      const tabsFloating = store.getSync('forum_tabs_floating', true);
      this.forumTabsEnabled = typeof tabsEnabled === 'boolean' ? tabsEnabled : true;
      this.forumTabsFloating = typeof tabsFloating === 'boolean' ? tabsFloating : true;
      const imageEnabled = store.getSync('image_menu_enabled', true);
      const imageLongPress = store.getSync('image_menu_long_press', false);
      this.imageMenuEnabled = typeof imageEnabled === 'boolean' ? imageEnabled : true;
      this.imageMenuLongPress = typeof imageLongPress === 'boolean' ? imageLongPress : false;
      const ix = store.getSync('image_menu_x', -1);
      const iy = store.getSync('image_menu_y', -1);
      this.imageXRatio = typeof ix === 'number' && Number.isFinite(ix) && ix >= 0 && ix <= 1 ? ix : -1;
      this.imageYRatio = typeof iy === 'number' && Number.isFinite(iy) && iy >= 0 && iy <= 1 ? iy : -1;
      const x = store.getSync('refresh_x', -1);
      const y = store.getSync('refresh_y', -1);
      this.xRatio = typeof x === 'number' && Number.isFinite(x) && x >= 0 && x <= 1 ? x : -1;
      this.yRatio = typeof y === 'number' && Number.isFinite(y) && y >= 0 && y <= 1 ? y : -1;
      const threadX = store.getSync('thread_action_x', -1);
      const threadY = store.getSync('thread_action_y', -1);
      this.threadXRatio = typeof threadX === 'number' && Number.isFinite(threadX) && threadX >= 0 && threadX <= 1 ? threadX : -1;
      this.threadYRatio = typeof threadY === 'number' && Number.isFinite(threadY) && threadY >= 0 && threadY <= 1 ? threadY : -1;
    } catch (_) { this.status = '偏好读取失败，本次使用默认位置'; }
  }

  async setHomeComposeEnabled(value: boolean, context: common.UIAbilityContext): Promise<void> {
    this.homeComposeEnabled = value; await this.save(context);
  }
  async setHomePosition(x: number, y: number, context: common.UIAbilityContext): Promise<void> {
    this.homeXRatio = Math.max(0, Math.min(1, x));
    this.homeYRatio = Math.max(0, Math.min(1, y)); await this.save(context);
  }

  async setEnabled(enabled: boolean, context: common.UIAbilityContext): Promise<void> {
    this.enabled = enabled;
    await this.save(context);
  }

  async setPosition(x: number, y: number, context: common.UIAbilityContext): Promise<void> {
    this.xRatio = Math.max(0, Math.min(1, x));
    this.yRatio = Math.max(0, Math.min(1, y));
    await this.save(context);
  }

  async setForumTabsEnabled(enabled: boolean, context: common.UIAbilityContext): Promise<void> {
    if (!this.enabled) { return; }
    this.forumTabsEnabled = enabled;
    await this.save(context);
  }

  async setForumTabsFloating(floating: boolean, context: common.UIAbilityContext): Promise<void> {
    this.forumTabsFloating = floating;
    await this.save(context);
  }

  async setThreadPosition(x: number, y: number, context: common.UIAbilityContext): Promise<void> {
    this.threadXRatio = Math.max(0, Math.min(1, x));
    this.threadYRatio = Math.max(0, Math.min(1, y));
    await this.save(context);
  }

  async setImageMenuEnabled(value: boolean, context: common.UIAbilityContext): Promise<void> {
    this.imageMenuEnabled = value; await this.save(context);
  }
  async setImageMenuLongPress(value: boolean, context: common.UIAbilityContext): Promise<void> {
    this.imageMenuLongPress = value; await this.save(context);
  }
  async setImagePosition(x: number, y: number, context: common.UIAbilityContext): Promise<void> {
    this.imageXRatio = Math.max(0, Math.min(1, x));
    this.imageYRatio = Math.max(0, Math.min(1, y)); await this.save(context);
  }

  private async save(context: common.UIAbilityContext): Promise<void> {
    const homeEnabled = this.homeComposeEnabled;
    const hx = this.homeXRatio;
    const hy = this.homeYRatio;
    const imageEnabled = this.imageMenuEnabled;
    const imageLongPress = this.imageMenuLongPress;
    const ix = this.imageXRatio;
    const iy = this.imageYRatio;
    const enabled = this.enabled;
    const tabsEnabled = this.forumTabsEnabled;
    const tabsFloating = this.forumTabsFloating;
    const x = this.xRatio;
    const y = this.yRatio;
    const threadX = this.threadXRatio;
    const threadY = this.threadYRatio;
    const operation = this.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, 'tieba_smart_reach_prefs');
      await store.put('home_compose_enabled', homeEnabled);
      await store.put('home_compose_x', hx);
      await store.put('home_compose_y', hy);
      await store.put('image_menu_enabled', imageEnabled);
      await store.put('image_menu_long_press', imageLongPress);
      await store.put('image_menu_x', ix);
      await store.put('image_menu_y', iy);
      await store.put('enabled', enabled);
      await store.put('forum_tabs_enabled', tabsEnabled);
      await store.put('forum_tabs_floating', tabsFloating);
      await store.put('refresh_x', x);
      await store.put('refresh_y', y);
      await store.put('thread_action_x', threadX);
      await store.put('thread_action_y', threadY);
      await store.flush();
    });
    this.writes = operation.catch(() => {});
    try { await operation; }
    catch (_) { throw new Error('智感握姿偏好保存失败，本次生效，重启后可能恢复旧值'); }
  }
}

export const smartReachStore: SmartReachStore = new SmartReachStore();
