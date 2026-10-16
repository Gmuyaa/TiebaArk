

export enum SettingsPane {

  NONE = 0,

  MATERIAL = 1,

  ACTION_BAR = 2,

  TOP_NAV = 3,

  ABOUT = 4,

  DARK_MODE = 5,

  ACCOUNT = 7,
  APPEARANCE = 8,
  BROWSING = 9,

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

  VERSION = 23,

  OFFICIAL_MESSAGES = 24,

  BLOCK_MANAGE = 25,
  FORUM_LEVEL = 26,
  SIGN_SETTINGS = 27,

  PERSONALIZATION = 28,

  HARMONY_FEATURES = 29,

  OTHER_SETTINGS = 30,

  FORUM_DEFAULT_TAB = 31
}

export enum SettingsEntryKind {

  PANE = 0,

  ACTION = 1,

  INFO = 2,

  SWITCH = 3
}

export const SETTINGS_ACTION_LOGIN: string = 'login';
export const SETTINGS_ACTION_LOGOUT: string = 'logout';

export interface SettingsEntry {

  key: string;

  label: string;

  value: string;

  subtitle?: string;
  kind: SettingsEntryKind;

  pane: SettingsPane;

  action: string;

  enabled: boolean;

  danger: boolean;

  checked?: boolean;
}

export interface SettingsGroup {
  key: string;

  title: string;
  entries: SettingsEntry[];
}

export interface SettingsState {

  loggedIn: boolean;

  materialLabel: string;

  actionBarLabel: string;

  topNavLabel: string;

  darkModeLabel: string;

  fontLabel: string;

  forumDefaultTabLabel: string;
  hideStatusBar: boolean;
  hideTopNavigation: boolean;
  hideBottomNavigation: boolean;

  lowFlow: boolean;

  superResolution: boolean;

  cacheLabel: string;
}

export interface SettingsAboutItem {
  label: string;
  value: string;
}

export const SETTINGS_APP_VERSION: string = '1.0.41';
export const SETTINGS_VERSION_CODE: string = '2610040';

export const SETTINGS_TARGET_PLATFORM: string = 'HarmonyOS API 26';

function paneEntry(key: string, label: string, value: string, pane: SettingsPane): SettingsEntry {
  return {
    key: key, label: label, value: value, kind: SettingsEntryKind.PANE,
    pane: pane, action: '', enabled: true, danger: false
  };
}

function switchEntry(key: string, label: string, checked: boolean): SettingsEntry {
  return {
    key: key, label: label, value: '', kind: SettingsEntryKind.SWITCH,
    pane: SettingsPane.NONE, action: key, enabled: true, danger: false, checked: checked
  };
}

export function buildSettingsGroups(state: SettingsState): SettingsGroup[] {
  return [
    {
      key: 'experience', title: '使用体验', entries: [
        paneEntry('appearance', '外观设计', appearanceSummaryOf(state.darkModeLabel, state.fontLabel), SettingsPane.APPEARANCE),
        paneEntry('browsing', '浏览设置', '', SettingsPane.BROWSING)
      ]
    },
    {
      key: 'harmony', title: '鸿蒙特性', entries: [

        paneEntry('harmony_features', '鸿蒙特性设置', browsingSummaryOf(state.topNavLabel), SettingsPane.HARMONY_FEATURES)
      ]
    },
    {
      key: 'personalization', title: '个性化', entries: [
        paneEntry('personalization', '个性化', '', SettingsPane.PERSONALIZATION)
      ]
    },
    {
      key: 'account_prefs', title: '贴吧账号偏好', entries: [
        paneEntry('messages', '消息设置', '', SettingsPane.MESSAGE)
      ]
    },
    {
      key: 'data_privacy', title: '数据与隐私', entries: [

        paneEntry('cache_clean', '缓存清理', state.cacheLabel, SettingsPane.CACHE),
        paneEntry('permissions', '隐私设置', '', SettingsPane.PRIVACY_SETTINGS)
      ]
    },
    {
      key: 'other', title: '其它', entries: [

        paneEntry('other_settings', '其它设置', '', SettingsPane.OTHER_SETTINGS)
      ]
    },
    {
      key: 'app_info', title: '应用信息', entries: [
        paneEntry('about', '关于贴吧Ark', SETTINGS_APP_VERSION, SettingsPane.ABOUT)
      ]
    }
  ];
}

export function buildSettingsCategoryEntries(pane: SettingsPane, state: SettingsState): SettingsEntry[] {
  switch (pane) {
    case SettingsPane.BROWSING:

      return [
        switchEntry('low_flow', '低流量模式', state.lowFlow),
        paneEntry('image_watermark', '图片水印', '', SettingsPane.IMAGE_WATERMARK),
        paneEntry('forum_default_tab', '吧内分区默认导航', state.forumDefaultTabLabel,
          SettingsPane.FORUM_DEFAULT_TAB)
      ];
    case SettingsPane.HARMONY_FEATURES:

      return [
        paneEntry('material_mode', '沉浸光感强度', state.materialLabel.trim(), SettingsPane.MATERIAL),
        paneEntry('action_bar_style', '帖子详情操作栏样式', state.actionBarLabel.trim(), SettingsPane.ACTION_BAR),
        paneEntry('home_top_nav_style', '首页顶栏样式', state.topNavLabel.trim(), SettingsPane.TOP_NAV),
        switchEntry('hide_status_bar', '隐藏状态栏', state.hideStatusBar),
        switchEntry('hide_top_navigation', '隐藏顶部导航栏', state.hideTopNavigation),
        switchEntry('hide_bottom_navigation', '隐藏底部导航栏', state.hideBottomNavigation),

        switchEntry('super_resolution', '图像超分', state.superResolution)
      ];
    case SettingsPane.PERSONALIZATION:

      return [
        paneEntry('sign_settings', '签到设置', '', SettingsPane.SIGN_SETTINGS),
        paneEntry('tails', '小尾巴', '', SettingsPane.TAILS),

        paneEntry('privacy_marks', '吧务身份标记', '', SettingsPane.PRIVACY_MARKS)
      ];
    case SettingsPane.PRIVACY_SETTINGS:

      return [
        paneEntry('forbidden_forums', '屏蔽吧', '', SettingsPane.FORBIDDEN_FORUMS),

        paneEntry('block_manage', '拉黑与隐藏', '', SettingsPane.BLOCK_MANAGE),
        paneEntry('app_permissions', '系统权限', '', SettingsPane.APP_PERMISSIONS),
        paneEntry('data_use', '数据使用说明', '', SettingsPane.DATA_USE)
      ];
    case SettingsPane.OTHER_SETTINGS:

      return [];
    default:
      return [];
  }
}

export function settingsEntryRenderKey(entry: SettingsEntry): string {
  return `${entry.key}|${entry.label}|${entry.value}|${entry.enabled ? 1 : 0}|${entry.checked ? 1 : 0}`;
}

export function settingsGroupRenderKey(group: SettingsGroup): string {
  return `${group.key}#${group.entries.map(settingsEntryRenderKey).join(',')}`;
}

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

export function settingsPaneTitle(pane: SettingsPane): string {
  switch (pane) {
    case SettingsPane.FORUM_LEVEL:
      return '吧等级标签';
    case SettingsPane.SIGN_SETTINGS:
      return '签到设置';
    case SettingsPane.MATERIAL:
      return '沉浸光感强度';
    case SettingsPane.ACTION_BAR:
      return '帖子详情操作栏样式';
    case SettingsPane.TOP_NAV:
      return '首页顶栏样式';
    case SettingsPane.FORUM_DEFAULT_TAB:
      return '吧内分区默认导航';
    case SettingsPane.DARK_MODE:
      return '深色模式';
    case SettingsPane.ABOUT:
      return '关于贴吧Ark';
    case SettingsPane.ACCOUNT:
      return '账号与资料';
    case SettingsPane.APPEARANCE:
      return '外观设计';
    case SettingsPane.BROWSING:
      return '浏览设置';
    case SettingsPane.HARMONY_FEATURES:
      return '鸿蒙特性设置';
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
      return '拉黑与隐藏';
    case SettingsPane.PRIVACY_MARKS:
      return '吧务身份标记';
    case SettingsPane.IMAGE_WATERMARK:
      return '图片水印';
    case SettingsPane.APP_PERMISSIONS:
      return '系统权限';
    case SettingsPane.PRIVACY_SETTINGS:
      return '隐私设置';
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

export enum SettingsPanePresentation {

  POPUP = 0,

  PAGE = 1
}

export function settingsPanePresentation(pane: SettingsPane): SettingsPanePresentation {
  switch (pane) {
    case SettingsPane.MATERIAL:
    case SettingsPane.ACTION_BAR:
    case SettingsPane.TOP_NAV:
    case SettingsPane.DARK_MODE:
    case SettingsPane.FONT_SIZE:
    case SettingsPane.FORUM_LEVEL:
    case SettingsPane.FORUM_DEFAULT_TAB:
      return SettingsPanePresentation.POPUP;
    case SettingsPane.ABOUT:
    case SettingsPane.NONE:
    default:
      return SettingsPanePresentation.PAGE;
  }
}

export function settingsPageTitle(pane: SettingsPane): string {
  return settingsPanePresentation(pane) === SettingsPanePresentation.PAGE
    ? settingsPaneTitle(pane)
    : settingsPaneTitle(SettingsPane.NONE);
}

export interface SettingsOptionItem {

  key: string;

  label: string;

  selected: boolean;
}

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

export function aboutItems(): SettingsAboutItem[] {
  return [
    { label: '版本', value: SETTINGS_APP_VERSION },
    { label: '版本代码', value: SETTINGS_VERSION_CODE },
    { label: '目标平台', value: SETTINGS_TARGET_PLATFORM }
  ];
}

export function aboutNotes(): string[] {
  return [
    '设备标识：应用在本机生成并保存匿名设备标识，用于构造贴吧客户端请求；请求中的设备信息会发送至贴吧服务端。',
    '登录凭据：手动登录得到的 BDUSS 与写操作令牌（tbs）只保存在本机系统级安全存储'
      + '（Asset Store Kit）中，不写入应用配置文件、不打印到日志、不上传任何第三方。'
      + '退出登录会清除这些凭据，但不会重置上面的匿名设备标识。',
    '浏览历史：访问过的帖子会保存在本机，供「浏览历史」页面展示。浏览使用贴吧接口；登录后才可能发出点赞等写请求。'
  ];
}

export function appearanceSummaryOf(darkModeLabel: string, fontLabel: string): string {
  const font: string = fontLabel.trim();

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
