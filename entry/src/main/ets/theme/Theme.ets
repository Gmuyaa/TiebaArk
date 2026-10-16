/** 应用主题颜色与共享尺寸。颜色资源随系统主题切换，玻璃材质由材质配置管理。 */
export class AppTheme {
  /** 强调色：选中态、发布按钮、链接（浅 `#0A59F7` / 深 `#317AF7`，对齐 detail_accent） */
  static readonly ACCENT: Resource = $r('app.color.app_accent');
  /** 强调色浅底：计数徽章、选中背景 */
  static readonly ACCENT_LIGHT: Resource = $r('app.color.app_accent_light');
  /** 强调色深字：浅底上的文字（深色模式翻转为亮蓝 `#6EA6FF`，落在深蓝底上可读） */
  static readonly ACCENT_DARK: Resource = $r('app.color.app_accent_dark');

  static readonly ICON: Resource = $r('app.color.app_icon');
  /** 页面浅灰背景（深 `#101112`，对齐 detail_page_background dark） */
  static readonly BG: Resource = $r('app.color.app_bg');
  /** 卡片白（深 `#1E2023`，比页面底亮一档，保持卡片分层） */
  static readonly CARD: Resource = $r('app.color.app_card');
  /** 主文字 */
  static readonly TEXT_MAIN: Resource = $r('app.color.app_text_main');
  /** 次要文字 */
  static readonly TEXT_SUB: Resource = $r('app.color.app_text_sub');
  /** 分割线 */
  static readonly DIVIDER: Resource = $r('app.color.app_divider');
  /** 弱化表面：搜索框、楼中楼、标签 */
  static readonly SURFACE_MUTED: Resource = $r('app.color.app_surface_muted');
  /** 三级说明文字与禁用态 */
  static readonly TEXT_MUTED: Resource = $r('app.color.app_text_muted');

  static readonly TAB_PILL_TEXT: Resource = $r('app.color.app_tab_pill_text');
  /** 下划线式页签未选中字色（原 `#66666B`） */
  static readonly TAB_UNDERLINE_TEXT: Resource = $r('app.color.app_tab_underline_text');
  /** 「返回推荐」等行内次级链接（原 `#75757A`） */
  static readonly LINK_HINT: Resource = $r('app.color.app_link_hint');
  /** 搜索胶囊占位字（原 `#8A8A8E`） */
  static readonly SEARCH_HINT: Resource = $r('app.color.app_search_hint');
  /** 楼中楼 / 弱化信息字（原 ForumListView `#606065`） */
  static readonly META_TEXT: Resource = $r('app.color.app_meta_text');
  /** 吧页页签字（原 ForumPage / ForumListView `#4C4C50`） */
  static readonly BAR_TAB_TEXT: Resource = $r('app.color.app_bar_tab_text');
  /** 「我的」页功能行字（原 ProfileView `#333333`） */
  static readonly TEXT_ROW: Resource = $r('app.color.app_text_row');
  /** 页脚小字（原 ProfileView `#BBBBBB`） */
  static readonly TEXT_CAPTION: Resource = $r('app.color.app_text_caption');
  /** 功能行右箭头 ›（原 ProfileView `#CCCCCC`） */
  static readonly ARROW_ROW: Resource = $r('app.color.app_arrow_row');
  /** 消息列表右箭头（原 MessageView `#C8C8CC`） */
  static readonly ARROW_LIST: Resource = $r('app.color.app_arrow_list');
  /** 设置页右侧值文字（原 SettingsCardStyle.VALUE_TEXT `#767676`） */
  static readonly VALUE_TEXT: Resource = $r('app.color.app_value_text');
  /** 设置页右侧细箭头（原 SettingsCardStyle.CHEVRON_TINT `#BABABA`） */
  static readonly CHEVRON_TINT: Resource = $r('app.color.app_chevron_tint');
  /** 危险项字（原 SettingsCardStyle.DANGER_TEXT `#C7161C`；深色对齐 detail_error dark） */
  static readonly DANGER_TEXT: Resource = $r('app.color.app_danger_text');
  /** 设置弹层选项分隔线（原 SettingsCardStyle.POPUP_LINE `#CBCBCB`） */
  static readonly POPUP_LINE: Resource = $r('app.color.app_popup_line');
  /** 关于页数据说明字（原 Settings.ets `#666666`） */
  static readonly NOTE_TEXT: Resource = $r('app.color.app_note_text');
  /** 头像占位底（原 AvatarComponent 默认 `#F1F1F3`） */
  static readonly AVATAR_BG: Resource = $r('app.color.app_avatar_bg');
  /** 吧页页签条底（原 ForumPage `#F5F7FA`） */
  static readonly FORUM_TAB_BG: Resource = $r('app.color.app_forum_tab_bg');
  /** 设置页顶栏渐隐的起始色（原 SettingsCardStyle.NAV_FADE_COLOR `#FFFFFF`；深色=页面底）。
   *  终点恒用 `#00FFFFFF`（全透明不受模式影响）。 */
  static readonly NAV_FADE: Resource = $r('app.color.app_nav_fade');

  static readonly NAV_FADE_CLEAR: Resource = $r('app.color.app_nav_fade_clear');
  /** 首页底栏 `gradientMask.maskColor`（原 `#33F5F5F7` = 页面底色 20%）。
   *  ⚠️ 这层是"页面底色的延伸"，不是玻璃 —— 深色下必须跟着页面底走，否则浅雾突兀。 */
  static readonly BOTTOM_BAR_MASK: Resource = $r('app.color.app_bottom_mask');
  /** 消息页分类徽章四组「浅彩底 + 彩字」（原 MessageView 字面量；深色 = 深彩底 + 亮字） */
  static readonly MSG_BADGE_RED_BG: Resource = $r('app.color.app_msg_badge_red_bg');
  static readonly MSG_BADGE_RED_FG: Resource = $r('app.color.app_msg_badge_red_fg');
  static readonly MSG_BADGE_ORANGE_BG: Resource = $r('app.color.app_msg_badge_orange_bg');
  static readonly MSG_BADGE_ORANGE_FG: Resource = $r('app.color.app_msg_badge_orange_fg');
  static readonly MSG_BADGE_GREEN_BG: Resource = $r('app.color.app_msg_badge_green_bg');
  static readonly MSG_BADGE_GREEN_FG: Resource = $r('app.color.app_msg_badge_green_fg');
  static readonly MSG_BADGE_BLUE_BG: Resource = $r('app.color.app_msg_badge_blue_bg');
  static readonly MSG_BADGE_BLUE_FG: Resource = $r('app.color.app_msg_badge_blue_fg');
  /** 系统状态栏 / 手势条的内容色（EntryAbility 按 `themeModeStore.isDark` 取值） */
  static readonly STATUS_BAR_CONTENT: Resource = $r('app.color.app_status_bar_content');

  /** 全局页面左右安全留白 */
  static readonly PAGE_GUTTER: number = 12;
  /** 信息流卡片圆角 */
  static readonly CARD_RADIUS: number = 16;
  /** 悬浮胶囊圆角 */
  static readonly PILL_RADIUS: number = 28;

  static readonly BAR_CONTENT_H: number = 48;

  static readonly BAR_SIDE: number = 24;
  /** 悬浮底栏底边到物理屏底的距离（= 底部手势区，本机实测 28vp，勿照抄 34） */
  static readonly BAR_SAFE_H: number = 28;

  static readonly BAR_TOTAL_H: number = 84;
}

/** 帖子详情页语义颜色；由 base/dark 资源自动跟随系统深浅色。 */
export class DetailTheme {
  /** 评论区试调语义色；深浅色资源分别配置，链接与已选状态仍用 ACCENT。 */
  static readonly COMMENT_NICKNAME: ResourceColor = $r('app.color.detail_comment_nickname');
  static readonly COMMENT_BODY: ResourceColor = $r('app.color.detail_comment_body');
  static readonly COMMENT_META: ResourceColor = $r('app.color.detail_comment_meta');
  static readonly COMMENT_ACTION: ResourceColor = $r('app.color.detail_comment_action');
  static readonly SUB_REPLY_BODY: ResourceColor = $r('app.color.detail_sub_reply_body');
  static readonly SUB_REPLY_NAME: ResourceColor = $r('app.color.detail_sub_reply_name');
  static readonly SUB_REPLY_BACKGROUND: ResourceColor = $r('app.color.detail_sub_reply_background');
  static readonly AUTHOR_BADGE_TEXT: ResourceColor = $r('app.color.detail_author_badge_text');
  static readonly AUTHOR_BADGE_BACKGROUND: ResourceColor = $r('app.color.detail_author_badge_background');
  static readonly BOTTOM_FLOAT_SHADOW: ResourceColor = $r('app.color.detail_bottom_float_shadow');
  static readonly BG: ResourceColor = $r('app.color.detail_page_background');
  static readonly CARD: ResourceColor = $r('app.color.detail_content_background');
  static readonly SURFACE_MUTED: ResourceColor = $r('app.color.detail_secondary_background');
  static readonly TEXT_MAIN: ResourceColor = $r('app.color.detail_text_primary');
  static readonly TEXT_SUB: ResourceColor = $r('app.color.detail_text_secondary');
  static readonly TEXT_MUTED: ResourceColor = $r('app.color.detail_text_tertiary');
  static readonly DIVIDER: ResourceColor = $r('app.color.detail_divider');
  static readonly ACCENT: ResourceColor = $r('app.color.detail_accent');
  static readonly ACCENT_DARK: ResourceColor = $r('app.color.detail_accent');
  static readonly ACCENT_LIGHT: ResourceColor = $r('app.color.detail_accent_background');

  static readonly ICON: ResourceColor = $r('app.color.detail_icon');
  static readonly ERROR: ResourceColor = $r('app.color.detail_error');
  static readonly OVERLAY: ResourceColor = $r('app.color.detail_overlay');
  static readonly BOTTOM_BAR: ResourceColor = $r('app.color.detail_bottom_bar_background');

  static readonly EMOJI_PANEL_TEXT: ResourceColor = $r('app.color.app_emoji_panel_text');

  static readonly FLOAT_SHADOW: ResourceColor = $r('app.color.detail_float_shadow');
  static readonly EMOJI_PANEL_SUB_TEXT: ResourceColor = $r('app.color.app_emoji_panel_sub_text');
}
