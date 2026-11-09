/** 设置分类、入口与展示文案的纯逻辑模型。 */

/** 设置页的分类、内容页与选项页。`NONE` = 入口列表。 */
export enum SettingsPane {
  /** 入口列表本身（不在任何二级页里） */
  NONE = 0,
  /** 沉浸光感强度 */
  MATERIAL = 1,
  /** 帖子详情页底部操作栏样式 */
  ACTION_BAR = 2,
  /** 首页顶部频道页签样式 */
  TOP_NAV = 3,
  /** 关于贴吧Ark（只读版本信息与项目链接） */
  ABOUT = 4,

  DARK_MODE = 5,

  ACCOUNT = 7,
  APPEARANCE = 8,
  BROWSING = 9,
  /** 字体大小：跟随系统或自定义；自定义再打开字号滑块。 */
  FONT_SIZE = 12,

  CACHE = 13,
  MESSAGE = 14,
  TAILS = 15,
  FORBIDDEN_FORUMS = 16,
  PRIVACY_MARKS = 17,
  APP_PERMISSIONS = 18,
  IMAGE_WATERMARK = 19,

  PRIVACY_SETTINGS = 21,

  DATA_USE = 22,
  /** 版本详情（关于页的二级页：版本代码、目标平台） */
  VERSION = 23,

  OFFICIAL_MESSAGES = 24,

  BLOCK_MANAGE = 25,
  FORUM_LEVEL = 26,
  SIGN_SETTINGS = 27,

  /** 已退役的旧分类；保留编号，不再提供入口。 */
  PERSONALIZATION = 28,
  /** 已退役的旧分类；保留编号，不再提供入口。 */
  HARMONY_FEATURES = 29,
  /** 已退役的空分类；保留编号，不再提供入口。 */
  OTHER_SETTINGS = 30,
  /** 吧内分区默认导航：热门或最新，本机偏好。 */
  FORUM_DEFAULT_TAB = 31,
  HDS_MATERIAL = 32,
  HIDDEN_THREADS = 33,
  IMAGE_MENU = 34,
  MOTION = 35,
  INTERACTION = 36,
  POSTING = 37,
  NAVIGATION_LAYOUT = 38,
  MATERIAL_EFFECTS = 39,
  IMAGE_LAYOUT = 40
}

/** 行的三种性质。渲染与点击分发都只看这个字段，不看 key。 */
export enum SettingsEntryKind {
  /** 入口：点了进 `pane` 指定的二级页，右侧有箭头 */
  PANE = 0,
  /** 动作：点了执行 `action`（去登录 / 退出登录） */
  ACTION = 1,
  /** 纯信息行：右侧只显示值，**不可点、无箭头**（如"已登录"） */
  INFO = 2,
  /** 独立开关：直接控制首页滚动时对应导航区域的显隐 */
  SWITCH = 3
}

/** 动作标识。页面对照它分发，避免在 UI 层比较中文文案。 */
export const SETTINGS_ACTION_LOGIN: string = 'login';
export const SETTINGS_ACTION_LOGOUT: string = 'logout';

/** 一行 */
export interface SettingsEntry {
  /** 稳定标识：ForEach 的 key + 点击分发 */
  key: string;
  /** 左侧主标签 */
  label: string;
  /** 右侧值文字；空串 = 不显示 */
  value: string;
  /**
   * 副标题（可选）：渲染在标签下方的一行小灰字，**用于需要解释代价的行**
   * 行高由 SettingsLayout 最小高度和实际文字高度共同决定。
   */
  subtitle?: string;
  kind: SettingsEntryKind;
  /** `kind === PANE` 时进哪个二级页，否则 `NONE` */
  pane: SettingsPane;
  /** `kind === ACTION` 时执行哪个动作，否则空串 */
  action: string;
  /** `false` = 置灰不可点（功能未实现，或当前状态下没有这个操作） */
  enabled: boolean;
  /** 危险项（红字居中，目前只有"退出登录"这种整卡单行的形态用它） */
  danger: boolean;
  /** SWITCH 行的当前值；其它行不使用。 */
  checked?: boolean;
}

/** 一张卡片 */
export interface SettingsGroup {
  key: string;
  /** 分组标题（「使用体验」这类）：**只是标题，不是中转页**，所以由模型给、页面照画 */
  title: string;
  entries: SettingsEntry[];
}

/** 拼装入口列表所需的**全部**外部状态。字段少且都是字符串/布尔，便于用例穷举。 */
export interface SettingsState {
  /** 是否已登录：决定账号行是"入口"还是"信息"，以及退出登录卡片在不在 */
  loggedIn: boolean;
  /** 当前沉浸光感档位文案（`modeLabel` 的结果，由页面传入） */
  materialLabel: string;
  hdsMaterialLabel?: string;
  /** 当前操作栏样式文案 */
  actionBarLabel: string;
  /** 当前首页顶栏样式文案 */
  topNavLabel: string;

  darkModeLabel: string;

  fontLabel: string;
  /** 新进入吧页默认显示的分区 */
  forumDefaultTabLabel: string;
  /** 内容图片排布（新版或旧版），本机偏好。 */
  imageLayoutLabel?: string;
  hideStatusBar: boolean;
  hideTopNavigation: boolean;
  hideBottomNavigation: boolean;
  /** A-08 低流量模式：不自动加载图片（列表、正文图集、视频流；本机偏好） */
  lowFlow: boolean;

  superResolution: boolean;
  /** 全应用统一智感握姿偏好，默认开。 */
  smartReach?: boolean;
  homeComposeSmartReach?: boolean;
  imageMenuSmartReach?: boolean;
  imageMenuLongPress?: boolean;
  forumTabsSmartReach?: boolean;
  forumTabsFloating?: boolean;

  cacheLabel: string;
}

/** 关于页里的一行「名 —— 值」 */
export interface SettingsAboutItem {
  label: string;
  value: string;
}

export const SETTINGS_APP_VERSION: string = '1.0.222';
export const SETTINGS_VERSION_CODE: string = '2611074';
/** 目标平台（与 `build-profile.json5` 的 compatibleSdkVersion 对齐） */
export const SETTINGS_TARGET_PLATFORM: string = 'HarmonyOS API 26';

/** 内部：造一个入口行 */
function paneEntry(key: string, label: string, value: string, pane: SettingsPane): SettingsEntry {
  return {
    key: key, label: label, value: value, kind: SettingsEntryKind.PANE,
    pane: pane, action: '', enabled: true, danger: false
  };
}

function switchEntry(key: string, label: string, checked: boolean, enabled: boolean = true,
  subtitle: string = ''): SettingsEntry {
  return {
    key: key, label: label, value: '', subtitle: subtitle, kind: SettingsEntryKind.SWITCH,
    pane: SettingsPane.NONE, action: key, enabled: enabled, danger: false, checked: checked
  };
}

export function buildSettingsGroups(state: SettingsState): SettingsGroup[] {
  return [
    {
      key: 'appearance', title: '外观与布局', entries: [
        paneEntry('appearance', '外观与布局', '', SettingsPane.APPEARANCE)
      ]
    },
    {
      key: 'browsing', title: '浏览与图片', entries: [
        paneEntry('browsing', '浏览与图片', '', SettingsPane.BROWSING)
      ]
    },
    {
      key: 'interaction', title: '操作与动效', entries: [
        paneEntry('interaction', '操作与动效', '', SettingsPane.INTERACTION)
      ]
    },
    {
      key: 'posting', title: '发帖与互动', entries: [
        paneEntry('posting', '发帖与互动', '', SettingsPane.POSTING)
      ]
    },
    {
      key: 'messages', title: '消息设置', entries: [
        paneEntry('messages', '消息设置', '', SettingsPane.MESSAGE)
      ]
    },
    {
      key: 'privacy', title: '屏蔽与隐私', entries: [
        paneEntry('permissions', '屏蔽与隐私', '', SettingsPane.PRIVACY_SETTINGS)
      ]
    },
    {
      key: 'cache', title: '缓存清理', entries: [
        // 右侧保留真实占用、空缓存或读取失败等阶段文案。
        paneEntry('cache_clean', '缓存清理', state.cacheLabel, SettingsPane.CACHE)
      ]
    },
    {
      key: 'app_info', title: '应用信息', entries: [
        paneEntry('about', '关于贴吧Ark', SETTINGS_APP_VERSION, SettingsPane.ABOUT)
      ]
    }
  ];
}

/** 分类页里的设置项；首页只展示分类入口，不混入具体开关。 */
export function buildSettingsCategoryEntries(pane: SettingsPane, state: SettingsState): SettingsEntry[] {
  switch (pane) {
    case SettingsPane.APPEARANCE:
      // 基础外观四项由页面直接渲染；这里仅提供有独立内容的两个子页。
      return [
        paneEntry('navigation_layout', '导航布局', '', SettingsPane.NAVIGATION_LAYOUT),
        paneEntry('material_effects', '材质效果', '', SettingsPane.MATERIAL_EFFECTS)
      ];
    case SettingsPane.BROWSING:
      return [
        paneEntry('forum_default_tab', '进吧默认分区', state.forumDefaultTabLabel,
          SettingsPane.FORUM_DEFAULT_TAB),
        paneEntry('image_layout', '图片排布', state.imageLayoutLabel ?? '新版', SettingsPane.IMAGE_LAYOUT),
        switchEntry('low_flow', '低流量模式', state.lowFlow, true, '列表与正文不自动加载图片'),
        paneEntry('image_menu', '看图菜单显示方式', state.imageMenuLongPress ? '长按显示' : '常显胶囊', SettingsPane.IMAGE_MENU),
        switchEntry('super_resolution', '显示超分按钮', state.superResolution)
      ];
    case SettingsPane.MATERIAL_EFFECTS:
      return [
        paneEntry('material_mode', '沉浸材质厚度', state.materialLabel.trim(), SettingsPane.MATERIAL),
        paneEntry('hds_material_level', '兼容材质效果', state.hdsMaterialLabel ?? '精美', SettingsPane.HDS_MATERIAL)
      ];
    case SettingsPane.NAVIGATION_LAYOUT:
      return [
        paneEntry('home_top_nav_style', '首页顶栏样式', state.topNavLabel.trim(), SettingsPane.TOP_NAV),
        paneEntry('action_bar_style', '帖子页底栏样式', state.actionBarLabel.trim(), SettingsPane.ACTION_BAR),
        switchEntry('forum_tabs_floating', '悬浮分类胶囊', state.forumTabsFloating ?? true),
        switchEntry('hide_status_bar', '隐藏状态栏', state.hideStatusBar),
        switchEntry('hide_top_navigation', '隐藏顶部导航栏', state.hideTopNavigation),
        switchEntry('hide_bottom_navigation', '隐藏底部导航栏', state.hideBottomNavigation)
      ];
    case SettingsPane.INTERACTION:
      return [
        switchEntry('smart_reach', '智感握姿', state.smartReach ?? true),
        switchEntry('home_compose_smart_reach', '首页发帖按钮跟随握姿', state.homeComposeSmartReach ?? true, state.smartReach ?? true),
        switchEntry('forum_tabs_smart_reach', '分类胶囊跟随握姿', state.forumTabsSmartReach ?? true,
          state.smartReach ?? true),
        switchEntry('image_menu_smart_reach', '看图胶囊跟随握姿', state.imageMenuSmartReach ?? true, state.smartReach ?? true),
        paneEntry('motion', '动效', '', SettingsPane.MOTION)
      ];
    case SettingsPane.POSTING:
      return [
        paneEntry('image_watermark', '图片水印', '', SettingsPane.IMAGE_WATERMARK),
        paneEntry('tails', '小尾巴', '', SettingsPane.TAILS),
        paneEntry('privacy_marks', '吧务身份标记', '', SettingsPane.PRIVACY_MARKS),
        paneEntry('sign_settings', '签到方案', '', SettingsPane.SIGN_SETTINGS)
      ];
    case SettingsPane.PRIVACY_SETTINGS:

      return [
        paneEntry('forbidden_forums', '屏蔽吧', '', SettingsPane.FORBIDDEN_FORUMS),

        paneEntry('block_manage', '拉黑的用户', '', SettingsPane.BLOCK_MANAGE),
        paneEntry('hidden_threads', '隐藏的帖子', '', SettingsPane.HIDDEN_THREADS),
        paneEntry('app_permissions', '系统权限', '', SettingsPane.APP_PERMISSIONS),
        paneEntry('data_use', '数据使用说明', '', SettingsPane.DATA_USE)
      ];
    default:
      return [];
  }
}

/** 设置行 key 包含影响展示的状态值，确保状态变化后 ForEach 重建对应行。 */
export function settingsEntryRenderKey(entry: SettingsEntry): string {
  return `${entry.key}|${entry.label}|${entry.value}|${entry.enabled ? 1 : 0}|${entry.checked ? 1 : 0}`;
}

/**
 * 分组在 `ForEach` 里的 key：把它名下所有入口行的 key 串起来。
 *
 * 为什么分组层也要带上 —— 外层 `ForEach` 复用分组节点时，`Card(entries)` 这个
 * item builder 同样不会重跑，内层 `ForEach` 就没机会看到新的 `entries`
 * （实测：只改内层 key 无效，因为"重新执行"这一步在更外层就被拦掉了）。
 */
export function settingsGroupRenderKey(group: SettingsGroup): string {
  return `${group.key}#${group.entries.map(settingsEntryRenderKey).join(',')}`;
}

/**
 * 这一行右侧要不要画箭头。
 *
 * 规则只有三条：
 * ```
 *   危险项（退出登录）  → 不画（整行是一颗按钮，居中红字）
 *   纯信息行            → 不画（如"已登录"，点了也没有去处）
 *   其余（入口 / 动作 / 置灰的"开发中"行）→ 画
 * ```
 *
 * 置灰行**保留箭头**：点击会给"该设置项开发中"的提示，不是死行；
 * 而"已登录"是真的没有去处，画了箭头等于骗用户去点。
 */
export function settingsRowHasChevron(entry: SettingsEntry): boolean {
  if (entry.danger) {
    return false;
  }
  if (entry.kind === SettingsEntryKind.INFO) {
    return !entry.enabled;
  }
  if (entry.kind === SettingsEntryKind.SWITCH) {
    return false;
  }
  return true;
}

/** 二级页顶栏标题；`NONE` 时是入口列表自己的标题。 */
export function settingsPaneTitle(pane: SettingsPane): string {
  switch (pane) {
    case SettingsPane.FORUM_LEVEL:
      return '吧等级标签';
    case SettingsPane.SIGN_SETTINGS:
      return '签到方案';
    case SettingsPane.MATERIAL:
      return '沉浸材质厚度';
    case SettingsPane.HDS_MATERIAL:
      return '兼容材质效果';
    case SettingsPane.ACTION_BAR:
      return '帖子页底栏样式';
    case SettingsPane.TOP_NAV:
      return '首页顶栏样式';
    case SettingsPane.IMAGE_MENU:
      return '看图菜单显示方式';
    case SettingsPane.IMAGE_LAYOUT:
      return '图片排布';
    case SettingsPane.FORUM_DEFAULT_TAB:
      return '进吧默认分区';
    case SettingsPane.DARK_MODE:
      return '深色模式';
    case SettingsPane.ABOUT:
      return '关于贴吧Ark';
    case SettingsPane.ACCOUNT:
      return '账号与资料';
    case SettingsPane.APPEARANCE:
      return '外观与布局';
    case SettingsPane.BROWSING:
      return '浏览与图片';
    case SettingsPane.INTERACTION:
      return '操作与动效';
    case SettingsPane.POSTING:
      return '发帖与互动';
    case SettingsPane.NAVIGATION_LAYOUT:
      return '导航布局';
    case SettingsPane.MATERIAL_EFFECTS:
      return '材质效果';
    case SettingsPane.HARMONY_FEATURES:
      return '鸿蒙特性设置';
    case SettingsPane.MOTION:
      return '动效';
    case SettingsPane.PERSONALIZATION:
      return '个性化';
    case SettingsPane.OTHER_SETTINGS:
      return '其它设置';
    case SettingsPane.FONT_SIZE:
      return '字体大小';
    case SettingsPane.CACHE:
      return '缓存清理';
    case SettingsPane.MESSAGE:
      return '消息设置';
    case SettingsPane.TAILS:
      return '小尾巴';
    case SettingsPane.FORBIDDEN_FORUMS:
      return '屏蔽吧';
    case SettingsPane.BLOCK_MANAGE:
      return '拉黑的用户';
    case SettingsPane.HIDDEN_THREADS:
      return '隐藏的帖子';
    case SettingsPane.PRIVACY_MARKS:
      return '吧务身份标记';
    case SettingsPane.IMAGE_WATERMARK:
      return '图片水印';
    case SettingsPane.APP_PERMISSIONS:
      return '系统权限';
    case SettingsPane.PRIVACY_SETTINGS:
      return '屏蔽与隐私';
    case SettingsPane.DATA_USE:
      return '数据使用说明';
    case SettingsPane.VERSION:
      return '版本详情';
    case SettingsPane.OFFICIAL_MESSAGES:
      return '官方账号消息提醒';
    case SettingsPane.NONE:
    default:
      return '设置';
  }
}

/** 内容页和选项菜单的逻辑父页；顶栏、系统返回与返回手势共用。 */
export function settingsParentPane(pane: SettingsPane): SettingsPane {
  switch (pane) {
    case SettingsPane.NAVIGATION_LAYOUT:
    case SettingsPane.MATERIAL_EFFECTS:
    case SettingsPane.DARK_MODE:
    case SettingsPane.FONT_SIZE:
    case SettingsPane.FORUM_LEVEL:
      return SettingsPane.APPEARANCE;
    case SettingsPane.TOP_NAV:
    case SettingsPane.ACTION_BAR:
      return SettingsPane.NAVIGATION_LAYOUT;
    case SettingsPane.MATERIAL:
    case SettingsPane.HDS_MATERIAL:
      return SettingsPane.MATERIAL_EFFECTS;
    case SettingsPane.FORUM_DEFAULT_TAB:
    case SettingsPane.IMAGE_MENU:
    case SettingsPane.IMAGE_LAYOUT:
      return SettingsPane.BROWSING;
    case SettingsPane.MOTION:
      return SettingsPane.INTERACTION;
    case SettingsPane.IMAGE_WATERMARK:
    case SettingsPane.TAILS:
    case SettingsPane.PRIVACY_MARKS:
    case SettingsPane.SIGN_SETTINGS:
      return SettingsPane.POSTING;
    case SettingsPane.OFFICIAL_MESSAGES:
      return SettingsPane.MESSAGE;
    case SettingsPane.FORBIDDEN_FORUMS:
    case SettingsPane.BLOCK_MANAGE:
    case SettingsPane.HIDDEN_THREADS:
    case SettingsPane.APP_PERMISSIONS:
    case SettingsPane.DATA_USE:
      return SettingsPane.PRIVACY_SETTINGS;
    case SettingsPane.VERSION:
      return SettingsPane.ABOUT;
    default:
      return SettingsPane.NONE;
  }
}

export enum SettingsPanePresentation {
  /** 弹一层选项菜单（选完即关，不换页） */
  POPUP = 0,
  /** 进二级页（换掉整个内容区与顶栏标题） */
  PAGE = 1
}

/**
 * 某个 pane 用哪种形态展开。**这就是全部规则，页面里不要再自己判断。**
 *
 * ```
 *   沉浸光感强度 / 操作栏样式 / 首页顶栏样式 / 深色模式 / 字体大小 → 弹层（就是一组选项）
 *   各个分类页与数据说明                              → 二级页
 * ```
 *
 * 「关于」为什么**不**跟着做成弹层：它是"只读信息 + 三段数据说明"，
 * 弹层里是 156vp 宽的窄条，三段说明会折成十几行 —— 形态是给内容服务的，
 * 不能为了统一把内容挤变形。
 */
export function settingsPanePresentation(pane: SettingsPane): SettingsPanePresentation {
  switch (pane) {
    case SettingsPane.MATERIAL:
    case SettingsPane.HDS_MATERIAL:
    case SettingsPane.ACTION_BAR:
    case SettingsPane.TOP_NAV:
    case SettingsPane.DARK_MODE:
    case SettingsPane.FONT_SIZE:
    case SettingsPane.FORUM_LEVEL:
    case SettingsPane.IMAGE_MENU:
    case SettingsPane.FORUM_DEFAULT_TAB:
    case SettingsPane.IMAGE_LAYOUT:
      return SettingsPanePresentation.POPUP;
    case SettingsPane.ABOUT:
    case SettingsPane.NONE:
    default:
      return SettingsPanePresentation.PAGE;
  }
}

/**
 * **页面顶栏**的标题（与 `settingsPaneTitle` 不是一回事）。
 *
 * `settingsPaneTitle` 是"这一组设置自己的名字"，改版后仍用于弹层语义；
 * 选项不换页，分类与内容页会换标题 ——
 * 用 `settingsPanePresentation` 判断，改形态时这里自动跟上，不用两处同步。
 */
export function settingsPageTitle(pane: SettingsPane): string {
  return settingsPanePresentation(pane) === SettingsPanePresentation.PAGE
    ? settingsPaneTitle(pane)
    : settingsPaneTitle(SettingsPane.NONE);
}

// ── 弹层里的选项 ─────────────────────────────────────────────────────────

/** 弹层里的一行选项 */
export interface SettingsOptionItem {
  /** 稳定标识（ForEach 的 key） */
  key: string;
  /** 档位名（弹层里唯一必有的文字） */
  label: string;
  /** 是否是当前生效的那一项（右侧打勾） */
  selected: boolean;
}

/** 由 labels 构造选项行。选中状态由 currentIndex 决定；越界时不选中任何项，空 labels 返回空数组。 */
export function buildOptions(labels: string[], currentIndex: number, keyPrefix: string): SettingsOptionItem[] {
  const items: SettingsOptionItem[] = [];
  for (let i = 0; i < labels.length; i++) {
    items.push({
      key: `${keyPrefix}_${i}`,
      label: labels[i],
      selected: i === currentIndex
    });
  }
  return items;
}

/** 关于页里的版本与平台信息。 */
export function aboutItems(): SettingsAboutItem[] {
  return [
    { label: '版本', value: SETTINGS_APP_VERSION },
    { label: '版本代码', value: SETTINGS_VERSION_CODE },
    { label: '目标平台', value: SETTINGS_TARGET_PLATFORM }
  ];
}

/**
 * 数据说明。写得越具体越好 —— 这是对使用者的透明承诺。
 *
 * 登录功能上线后必须同步：原文写的是"不包含账号体系"，已经不成立了。
 */
export function aboutNotes(): string[] {
  return [
    '设备标识：应用在本机生成并保存匿名设备标识，用于构造贴吧客户端请求；请求中的设备信息会发送至贴吧服务端。',
    '登录凭据：手动登录得到的 BDUSS 与写操作令牌（tbs）只保存在本机系统级安全存储'
      + '（Asset Store Kit）中，不写入应用配置文件、不打印到日志、不上传任何第三方。'
      + '退出登录会清除这些凭据，但不会重置上面的匿名设备标识。',
    '浏览历史：访问过的帖子会保存在本机，供「浏览历史」页面展示。浏览使用贴吧接口；登录后才可能发出点赞等写请求。'
  ];
}

/**
 * 首页「外观设计」摘要：**一行只讲一件事** —— 字号被改过就先讲字号，否则讲主题。
 * 空值/未取到档位时不编内容（返回空串，行右侧留空）。
 */
export function appearanceSummaryOf(darkModeLabel: string, fontLabel: string): string {
  const font: string = fontLabel.trim();
  // 入参就是界面档位文案（'跟随系统' 表示用系统字号），因此直接比较文案本身
  if (font.length > 0 && font !== '跟随系统') {
    return `字号 ${font}`;
  }
  const theme: string = darkModeLabel.trim();
  if (theme === '深色模式') {
    return '深色主题';
  }
  if (theme === '浅色模式') {
    return '浅色主题';
  }
  return theme.length > 0 ? '主题随系统' : '';
}

export function browsingSummaryOf(topNavLabel: string): string {
  return topNavLabel.trim();
}
