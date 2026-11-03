import { visualThemeStore } from '../common/appearance/VisualThemeStore';

/** 应用主题颜色与共享尺寸。颜色资源随系统主题切换，玻璃材质由材质配置管理。 */
export class AppTheme {
  /** 分类选中胶囊沿用已确定的蓝色光边，独立于页面主题强调色。 */
  static get FORUM_TAB_GLOW_BORDER(): Resource { return $r('app.color.forum_tab_glow_border'); }
  static get FORUM_TAB_GLOW_SHADOW(): Resource { return $r('app.color.forum_tab_glow_shadow'); }
  static get SR_ACTIVE_BACKGROUND(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_sr_active_background') : $r('app.color.sr_active_background');
  }
  static get HELP_ANSWER(): Resource { return $r('app.color.help_answer_tag'); }
  /** 强调色：选中态、发布按钮、链接（浅 `#0A59F7` / 深 `#317AF7`，对齐 detail_accent） */
  static get ACCENT(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_accent') : $r('app.color.app_accent');
  }
  /** 强调色浅底：计数徽章、选中背景 */
  static get ACCENT_LIGHT(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_accent_light') : $r('app.color.app_accent_light');
  }
  /** 强调色深字：浅底上的文字（深色模式翻转为亮蓝 `#6EA6FF`，落在深蓝底上可读） */
  static get ACCENT_DARK(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_accent_dark') : $r('app.color.app_accent_dark');
  }

  static get ICON(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_icon') : $r('app.color.app_icon');
  }
  /** 页面浅灰背景（深 `#101112`，对齐 detail_page_background dark） */
  static get BG(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_bg') : $r('app.color.app_bg');
  }
  /** 卡片白（深 `#1E2023`，比页面底亮一档，保持卡片分层） */
  static get CARD(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_card') : $r('app.color.app_card');
  }
  /** 主文字 */
  static get TEXT_MAIN(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_text_main') : $r('app.color.app_text_main');
  }
  /** 次要文字 */
  static get TEXT_SUB(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_text_sub') : $r('app.color.app_text_sub');
  }
  /** 分割线 */
  static get DIVIDER(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_divider') : $r('app.color.app_divider');
  }
  /** 弱化表面：搜索框、楼中楼、标签 */
  static get SURFACE_MUTED(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_surface_muted') : $r('app.color.app_surface_muted');
  }
  /** 三级说明文字与禁用态 */
  static get TEXT_MUTED(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_text_muted') : $r('app.color.app_text_muted');
  }

  static get TAB_PILL_TEXT(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_tab_pill_text') : $r('app.color.app_tab_pill_text');
  }
  /** 下划线式页签未选中字色（原 `#66666B`） */
  static get TAB_UNDERLINE_TEXT(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_tab_underline_text') : $r('app.color.app_tab_underline_text');
  }
  /** 「返回推荐」等行内次级链接（原 `#75757A`） */
  static get LINK_HINT(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_link_hint') : $r('app.color.app_link_hint');
  }
  /** 搜索胶囊占位字（原 `#8A8A8E`） */
  static get SEARCH_HINT(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_search_hint') : $r('app.color.app_search_hint');
  }
  /** 楼中楼 / 弱化信息字（原 ForumListView `#606065`） */
  static get META_TEXT(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_meta_text') : $r('app.color.app_meta_text');
  }
  /** 吧页页签字（原 ForumPage / ForumListView `#4C4C50`） */
  static get BAR_TAB_TEXT(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_bar_tab_text') : $r('app.color.app_bar_tab_text');
  }
  /** 「我的」页功能行字（原 ProfileView `#333333`） */
  static get TEXT_ROW(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_text_row') : $r('app.color.app_text_row');
  }
  /** 页脚小字（原 ProfileView `#BBBBBB`） */
  static get TEXT_CAPTION(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_text_caption') : $r('app.color.app_text_caption');
  }
  /** 功能行右箭头 ›（原 ProfileView `#CCCCCC`） */
  static get ARROW_ROW(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_arrow_row') : $r('app.color.app_arrow_row');
  }
  /** 消息列表右箭头（原 MessageView `#C8C8CC`） */
  static get ARROW_LIST(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_arrow_list') : $r('app.color.app_arrow_list');
  }
  /** 设置页右侧值文字（原 SettingsCardStyle.VALUE_TEXT `#767676`） */
  static get VALUE_TEXT(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_value_text') : $r('app.color.app_value_text');
  }
  /** 设置页右侧细箭头（原 SettingsCardStyle.CHEVRON_TINT `#BABABA`） */
  static get CHEVRON_TINT(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_chevron_tint') : $r('app.color.app_chevron_tint');
  }
  /** 危险项字（原 SettingsCardStyle.DANGER_TEXT `#C7161C`；深色对齐 detail_error dark） */
  static get DANGER_TEXT(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_danger_text') : $r('app.color.app_danger_text');
  }
  /** 设置弹层选项分隔线（原 SettingsCardStyle.POPUP_LINE `#CBCBCB`） */
  static get POPUP_LINE(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_popup_line') : $r('app.color.app_popup_line');
  }
  /** 关于页数据说明字（原 Settings.ets `#666666`） */
  static get NOTE_TEXT(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_note_text') : $r('app.color.app_note_text');
  }
  /** 头像占位底（原 AvatarComponent 默认 `#F1F1F3`） */
  static get AVATAR_BG(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_avatar_bg') : $r('app.color.app_avatar_bg');
  }
  /** 吧页页签条底（原 ForumPage `#F5F7FA`） */
  static get FORUM_TAB_BG(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_forum_tab_bg') : $r('app.color.app_forum_tab_bg');
  }
  /** 设置页顶栏渐隐的起始色（原 SettingsCardStyle.NAV_FADE_COLOR `#FFFFFF`；深色=页面底）。
   *  终点恒用 `#00FFFFFF`（全透明不受模式影响）。 */
  static get NAV_FADE(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_nav_fade') : $r('app.color.app_nav_fade');
  }

  static get NAV_FADE_CLEAR(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_nav_fade_clear') : $r('app.color.app_nav_fade_clear');
  }
  /** 首页底栏 `gradientMask.maskColor`（原 `#33F5F5F7` = 页面底色 20%）。
   *  ⚠️ 这层是"页面底色的延伸"，不是玻璃 —— 深色下必须跟着页面底走，否则浅雾突兀。 */
  static get BOTTOM_BAR_MASK(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_bottom_mask') : $r('app.color.app_bottom_mask');
  }
  /** 消息页分类徽章四组「浅彩底 + 彩字」（原 MessageView 字面量；深色 = 深彩底 + 亮字） */
  static get MSG_BADGE_RED_BG(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_emphasis_light') : $r('app.color.app_msg_badge_red_bg');
  }
  static get MSG_BADGE_RED_FG(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_emphasis') : $r('app.color.app_msg_badge_red_fg');
  }
  static get MSG_BADGE_ORANGE_BG(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_gold_light') : $r('app.color.app_msg_badge_orange_bg');
  }
  static get MSG_BADGE_ORANGE_FG(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_gold') : $r('app.color.app_msg_badge_orange_fg');
  }
  static get MSG_BADGE_GREEN_BG(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_jade_light') : $r('app.color.app_msg_badge_green_bg');
  }
  static get MSG_BADGE_GREEN_FG(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_jade') : $r('app.color.app_msg_badge_green_fg');
  }
  static get MSG_BADGE_BLUE_BG(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_accent_light') : $r('app.color.app_msg_badge_blue_bg');
  }
  static get MSG_BADGE_BLUE_FG(): Resource {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_accent_dark') : $r('app.color.app_msg_badge_blue_fg');
  }
  /** 系统状态栏 / 手势条的内容色（EntryAbility 按 `themeModeStore.isDark` 取值） */
  static readonly STATUS_BAR_CONTENT: Resource = $r('app.color.app_status_bar_content');

  /** 敦煌矿物色用于品牌、分类和互动；正文仍使用独立墨色。 */
  static get EMPHASIS(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_emphasis') : AppTheme.ACCENT;
  }
  static get EMPHASIS_LIGHT(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_emphasis_light') : AppTheme.ACCENT_LIGHT;
  }
  static get ON_ACCENT(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_on_accent') : Color.White;
  }
  static get ON_EMPHASIS(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_on_emphasis') : Color.White;
  }
  static get GOLD(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_gold') : AppTheme.ACCENT;
  }
  static get GOLD_LIGHT(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_gold_light') : AppTheme.ACCENT_LIGHT;
  }
  static get JADE(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_jade') : AppTheme.ACCENT;
  }
  static get JADE_LIGHT(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_jade_light') : AppTheme.ACCENT_LIGHT;
  }
  static get HEADER_START(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_header_start') : AppTheme.CARD;
  }
  static get HEADER_END(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_header_end') : AppTheme.CARD;
  }
  /** 导航前景独立于内容矿物色，原生玻璃不增加衬底。 */
  static get NAV_TEXT(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_nav_text') : AppTheme.ICON;
  }
  static get NAV_SELECTED(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_nav_selected') : AppTheme.EMPHASIS;
  }

  /** 全局页面左右安全留白 */
  static readonly PAGE_GUTTER: number = 12;
  /** 信息流卡片圆角 */
  static readonly CARD_RADIUS: number = 16;
  /** 悬浮胶囊圆角 */
  static readonly PILL_RADIUS: number = 28;

  /** 主界面悬浮底栏高度：对齐参考图的 56vp 胶囊。 */
  static readonly BAR_CONTENT_H: number = 56;

  static readonly BAR_SIDE: number = 24;
  /** 悬浮底栏底边到物理屏底的距离：参考图与本机均为 28vp。 */
  static readonly BAR_SAFE_H: number = 28;

  static readonly BAR_TOTAL_H: number = AppTheme.BAR_CONTENT_H + AppTheme.BAR_SAFE_H;
}

/** 帖子详情页语义颜色；由 base/dark 资源自动跟随系统深浅色。 */
export class DetailTheme {
  /** 评论区试调语义色；深浅色资源分别配置，链接与已选状态仍用 ACCENT。 */
  static get COMMENT_NICKNAME(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_comment_nickname') : $r('app.color.detail_comment_nickname');
  }
  static get COMMENT_BODY(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_comment_body') : $r('app.color.detail_comment_body');
  }
  static get COMMENT_META(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_comment_meta') : $r('app.color.detail_comment_meta');
  }
  static get COMMENT_ACTION(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_comment_action') : $r('app.color.detail_comment_action');
  }
  static get SUB_REPLY_BODY(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_sub_reply_body') : $r('app.color.detail_sub_reply_body');
  }
  static get SUB_REPLY_NAME(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_sub_reply_name') : $r('app.color.detail_sub_reply_name');
  }
  static get SUB_REPLY_BACKGROUND(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_sub_reply_background') : $r('app.color.detail_sub_reply_background');
  }
  static get AUTHOR_BADGE_TEXT(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_author_badge_text') : $r('app.color.detail_author_badge_text');
  }
  static get AUTHOR_BADGE_BACKGROUND(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_author_badge_background') : $r('app.color.detail_author_badge_background');
  }
  static get BOTTOM_FLOAT_SHADOW(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_bottom_float_shadow') : $r('app.color.detail_bottom_float_shadow');
  }
  static get BG(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_page_background') : $r('app.color.detail_page_background');
  }
  static get CARD(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_content_background') : $r('app.color.detail_content_background');
  }
  static get SURFACE_MUTED(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_secondary_background') : $r('app.color.detail_secondary_background');
  }
  static get TEXT_MAIN(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_text_primary') : $r('app.color.detail_text_primary');
  }
  static get TEXT_SUB(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_text_secondary') : $r('app.color.detail_text_secondary');
  }
  static get TEXT_MUTED(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_text_tertiary') : $r('app.color.detail_text_tertiary');
  }
  static get DIVIDER(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_divider') : $r('app.color.detail_divider');
  }
  static get ACCENT(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_accent') : $r('app.color.detail_accent');
  }
  static get ACCENT_DARK(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_accent') : $r('app.color.detail_accent');
  }
  static get ACCENT_LIGHT(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_accent_background') : $r('app.color.detail_accent_background');
  }

  static get ICON(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_icon') : $r('app.color.detail_icon');
  }
  static get ERROR(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_error') : $r('app.color.detail_error');
  }
  static readonly OVERLAY: ResourceColor = $r('app.color.detail_overlay');
  static get BOTTOM_BAR(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_bottom_bar_background') : $r('app.color.detail_bottom_bar_background');
  }

  static get EMOJI_PANEL_TEXT(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_emoji_panel_text') : $r('app.color.app_emoji_panel_text');
  }

  static get FLOAT_SHADOW(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_detail_float_shadow') : $r('app.color.detail_float_shadow');
  }
  static get EMOJI_PANEL_SUB_TEXT(): ResourceColor {
    return visualThemeStore.isPaper ? $r('app.color.paper_app_emoji_panel_sub_text') : $r('app.color.app_emoji_panel_sub_text');
  }
}
