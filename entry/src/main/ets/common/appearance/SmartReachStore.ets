import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/** 本机统一握姿开关、各悬浮按钮的显示与独立位置，与账号无关。默认开；坏值回落默认。
 * 仅存开关、显隐和归一化坐标，不保存握姿传感器数据。关闭自动换边后仍可拖拽。
 * 同步读取防首屏跳位；写入排队防快速操作倒序，失败明确报告会话内生效。
 */
export enum ForumTabsStyle {
  /** 常规吸顶：分类栏固定在工具栏下，文字 + 选中下划线 */
  STICKY = 0,
  /** 胶囊：跟内容滚，滚到工具栏下沿贴住并换官方材质胶囊 */
  CAPSULE = 1,
  /** 悬浮：可拖动的分类浮层 */
  FLOATING = 2
}

@ObservedV2
export class SmartReachStore {
  /** 首页发帖按钮是否跟随握姿换边；只影响自动换边，按钮是否出现由 `homeComposeVisible` 决定。 */
  @Trace homeComposeEnabled: boolean = true;
  /** 首页发帖按钮是否渲染（设置 → 外观与布局 → 导航布局 → 悬浮按钮）。与跟随握姿独立。 */
  @Trace homeComposeVisible: boolean = true;
  @Trace homeXRatio: number = -1;
  @Trace homeYRatio: number = -1;
  @Trace enabled: boolean = true;
  @Trace imageMenuEnabled: boolean = true;
  @Trace imageMenuLongPress: boolean = false;
  @Trace imageXRatio: number = -1;
  @Trace imageYRatio: number = -1;
  @Trace forumTabsEnabled: boolean = true;
  /** 分类栏样式（2026-11-12 三种：常规吸顶 / 胶囊 / 悬浮），默认悬浮与旧行为一致。 */
  @Trace forumTabsStyle: ForumTabsStyle = ForumTabsStyle.FLOATING;
  /** 兼容旧调用点：是否悬浮样式（三选一之后 forumTabsFloating 变成派生值）。 */
  get forumTabsFloating(): boolean {
    return this.forumTabsStyle === ForumTabsStyle.FLOATING;
  }
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
      const homeVisible = store.getSync('home_compose_visible', true);
      this.homeComposeVisible = typeof homeVisible === 'boolean' ? homeVisible : true;
      const hx = store.getSync('home_compose_x', -1);
      const hy = store.getSync('home_compose_y', -1);
      this.homeXRatio = typeof hx === 'number' && Number.isFinite(hx) && hx >= 0 && hx <= 1 ? hx : -1;
      this.homeYRatio = typeof hy === 'number' && Number.isFinite(hy) && hy >= 0 && hy <= 1 ? hy : -1;
      const enabled = store.getSync('enabled', true);
      this.enabled = typeof enabled === 'boolean' ? enabled : true;
      const tabsEnabled = store.getSync('forum_tabs_enabled', true);
      this.forumTabsEnabled = typeof tabsEnabled === 'boolean' ? tabsEnabled : true;
      // 新字段优先；老数据没有 style 时按旧的 forum_tabs_floating 迁移（true=悬浮，false=胶囊）。
      const tabsStyle = store.getSync('forum_tabs_style', -1);
      if (typeof tabsStyle === 'number' && tabsStyle >= ForumTabsStyle.STICKY && tabsStyle <= ForumTabsStyle.FLOATING) {
        this.forumTabsStyle = tabsStyle as ForumTabsStyle;
      } else {
        const tabsFloating = store.getSync('forum_tabs_floating', true);
        this.forumTabsStyle = (typeof tabsFloating === 'boolean' && !tabsFloating)
          ? ForumTabsStyle.CAPSULE : ForumTabsStyle.FLOATING;
      }
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
    } catch (_) { this.status = '偏好读取失败，本次使用默认显示与位置'; }
  }

  async setHomeComposeEnabled(value: boolean, context: common.UIAbilityContext): Promise<void> {
    this.homeComposeEnabled = value; await this.save(context);
  }
  /** 只控制首页发帖按钮是否渲染；与握姿总开关、跟随握姿开关互相独立。 */
  async setHomeComposeVisible(value: boolean, context: common.UIAbilityContext): Promise<void> {
    this.homeComposeVisible = value; await this.save(context);
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

  async setForumTabsStyle(style: ForumTabsStyle, context: common.UIAbilityContext): Promise<void> {
    this.forumTabsStyle = style;
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
    const homeVisible = this.homeComposeVisible;
    const hx = this.homeXRatio;
    const hy = this.homeYRatio;
    const imageEnabled = this.imageMenuEnabled;
    const imageLongPress = this.imageMenuLongPress;
    const ix = this.imageXRatio;
    const iy = this.imageYRatio;
    const enabled = this.enabled;
    const tabsEnabled = this.forumTabsEnabled;
    const tabsStyle = this.forumTabsStyle;
    const x = this.xRatio;
    const y = this.yRatio;
    const threadX = this.threadXRatio;
    const threadY = this.threadYRatio;
    const operation = this.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, 'tieba_smart_reach_prefs');
      await store.put('home_compose_enabled', homeEnabled);
      await store.put('home_compose_visible', homeVisible);
      await store.put('home_compose_x', hx);
      await store.put('home_compose_y', hy);
      await store.put('image_menu_enabled', imageEnabled);
      await store.put('image_menu_long_press', imageLongPress);
      await store.put('image_menu_x', ix);
      await store.put('image_menu_y', iy);
      await store.put('enabled', enabled);
      await store.put('forum_tabs_enabled', tabsEnabled);
      await store.put('forum_tabs_style', tabsStyle);
      await store.put('refresh_x', x);
      await store.put('refresh_y', y);
      await store.put('thread_action_x', threadX);
      await store.put('thread_action_y', threadY);
      await store.flush();
    });
    this.writes = operation.catch(() => {});
    try { await operation; }
    catch (_) { throw new Error('悬浮按钮偏好保存失败，本次生效，重启后可能恢复旧值'); }
  }
}

export const smartReachStore: SmartReachStore = new SmartReachStore();
