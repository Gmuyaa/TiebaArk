import { ThemeColorRole, themeResource } from './ThemePalette';

/** 应用配色入口与共享尺寸。新增六色只覆盖强调与交互，浅深中性色沿用经典资源。 */
export class AppTheme {
  /** 通知数字角标：固定语义红与白字，深浅主题均保持可读。 */
  static get NOTIFY_BADGE_BACKGROUND(): Resource {
    return themeResource($r('app.color.notify_badge_background'), $r('app.color.notify_badge_background'), ThemeColorRole.NOTIFY_BG);
  }
  static get NOTIFY_BADGE_TEXT(): Resource {
    return themeResource($r('app.color.notify_badge_text'), $r('app.color.notify_badge_text'), ThemeColorRole.NOTIFY_TEXT);
  }
  /** 旧蓝色光边资源仅兼容历史声明；现有官方材质不额外恢复自绘光边。 */
  static get FORUM_TAB_GLOW_BORDER(): Resource {
    return themeResource($r('app.color.forum_tab_glow_border'), $r('app.color.forum_tab_glow_border'), ThemeColorRole.LEGACY_GLOW_BORDER);
  }
  static get FORUM_TAB_GLOW_SHADOW(): Resource {
    return themeResource($r('app.color.forum_tab_glow_shadow'), $r('app.color.forum_tab_glow_shadow'), ThemeColorRole.LEGACY_GLOW_SHADOW);
  }
  static get SR_ACTIVE_BACKGROUND(): Resource {
    return themeResource($r('app.color.sr_active_background'), $r('app.color.paper_sr_active_background'), ThemeColorRole.SR_ACTIVE);
  }
  static get HELP_ANSWER(): Resource {
    return themeResource($r('app.color.help_answer_tag'), $r('app.color.help_answer_tag'), ThemeColorRole.HELP_ANSWER);
  }
  /** 强调色：选中态、发布按钮、链接（浅 `#0A59F7` / 深 `#317AF7`，对齐 detail_accent） */
  static get ACCENT(): Resource {
    return themeResource($r('app.color.app_accent'), $r('app.color.paper_app_accent'), ThemeColorRole.ACCENT);
  }
  /** 强调色浅底：计数徽章、选中背景 */
  static get ACCENT_LIGHT(): Resource {
    return themeResource($r('app.color.app_accent_light'), $r('app.color.paper_app_accent_light'), ThemeColorRole.ACCENT_LIGHT);
  }
  /** 强调色深字：浅底上的文字（深色模式翻转为亮蓝 `#6EA6FF`，落在深蓝底上可读） */
  static get ACCENT_DARK(): Resource {
    return themeResource($r('app.color.app_accent_dark'), $r('app.color.paper_app_accent_dark'), ThemeColorRole.ACCENT_DARK);
  }

  static get ICON(): Resource {
    return themeResource($r('app.color.app_icon'), $r('app.color.paper_app_icon'), ThemeColorRole.ICON);
  }
  /** 页面浅灰背景（深 `#101112`，对齐 detail_page_background dark） */
  static get BG(): Resource {
    return themeResource($r('app.color.app_bg'), $r('app.color.paper_app_bg'), ThemeColorRole.BG);
  }
  /** 卡片白（深 `#1E2023`，比页面底亮一档，保持卡片分层） */
  static get CARD(): Resource {
    return themeResource($r('app.color.app_card'), $r('app.color.paper_app_card'), ThemeColorRole.CARD);
  }
  /** 主文字 */
  static get TEXT_MAIN(): Resource {
    return themeResource($r('app.color.app_text_main'), $r('app.color.paper_app_text_main'), ThemeColorRole.TEXT_MAIN);
  }
  /** 次要文字 */
  static get TEXT_SUB(): Resource {
    return themeResource($r('app.color.app_text_sub'), $r('app.color.paper_app_text_sub'), ThemeColorRole.TEXT_SUB);
  }
  /** 分割线 */
  static get DIVIDER(): Resource {
    return themeResource($r('app.color.app_divider'), $r('app.color.paper_app_divider'), ThemeColorRole.DIVIDER);
  }
  /** 弱化表面：搜索框、楼中楼、标签 */
  static get SURFACE_MUTED(): Resource {
    return themeResource($r('app.color.app_surface_muted'), $r('app.color.paper_app_surface_muted'), ThemeColorRole.SURFACE_MUTED);
  }
  /** 三级说明文字与禁用态 */
  static get TEXT_MUTED(): Resource {
    return themeResource($r('app.color.app_text_muted'), $r('app.color.paper_app_text_muted'), ThemeColorRole.TEXT_MUTED);
  }

  static get TAB_PILL_TEXT(): Resource {
    return themeResource($r('app.color.app_tab_pill_text'), $r('app.color.paper_app_tab_pill_text'), ThemeColorRole.TEXT_MAIN);
  }
  /** 下划线式页签未选中字色（原 `#66666B`） */
  static get TAB_UNDERLINE_TEXT(): Resource {
    return themeResource($r('app.color.app_tab_underline_text'), $r('app.color.paper_app_tab_underline_text'), ThemeColorRole.TEXT_SUB);
  }
  /** 「返回推荐」等行内次级链接（原 `#75757A`） */
  static get LINK_HINT(): Resource {
    return themeResource($r('app.color.app_link_hint'), $r('app.color.paper_app_link_hint'), ThemeColorRole.TEXT_SUB);
  }
  /** 搜索胶囊占位字（原 `#8A8A8E`） */
  static get SEARCH_HINT(): Resource {
    return themeResource($r('app.color.app_search_hint'), $r('app.color.paper_app_search_hint'), ThemeColorRole.TEXT_MUTED);
  }
  /** 楼中楼 / 弱化信息字（原 ForumListView `#606065`） */
  static get META_TEXT(): Resource {
    return themeResource($r('app.color.app_meta_text'), $r('app.color.paper_app_meta_text'), ThemeColorRole.TEXT_SUB);
  }
  /** 吧页页签字（原 ForumPage / ForumListView `#4C4C50`） */
  static get BAR_TAB_TEXT(): Resource {
    return themeResource($r('app.color.app_bar_tab_text'), $r('app.color.paper_app_bar_tab_text'), ThemeColorRole.TEXT_MAIN);
  }
  /** 「我的」页功能行字（原 ProfileView `#333333`） */
  static get TEXT_ROW(): Resource {
    return themeResource($r('app.color.app_text_row'), $r('app.color.paper_app_text_row'), ThemeColorRole.TEXT_MAIN);
  }
  /** 页脚小字（原 ProfileView `#BBBBBB`） */
  static get TEXT_CAPTION(): Resource {
    return themeResource($r('app.color.app_text_caption'), $r('app.color.paper_app_text_caption'), ThemeColorRole.TEXT_MUTED);
  }
  /** 功能行右箭头 ›（原 ProfileView `#CCCCCC`） */
  static get ARROW_ROW(): Resource {
    return themeResource($r('app.color.app_arrow_row'), $r('app.color.paper_app_arrow_row'), ThemeColorRole.TEXT_MUTED);
  }
  /** 消息列表右箭头（原 MessageView `#C8C8CC`） */
  static get ARROW_LIST(): Resource {
    return themeResource($r('app.color.app_arrow_list'), $r('app.color.paper_app_arrow_list'), ThemeColorRole.TEXT_MUTED);
  }
  /** 设置页右侧值文字（原 SettingsCardStyle.VALUE_TEXT `#767676`） */
  static get VALUE_TEXT(): Resource {
    return themeResource($r('app.color.app_value_text'), $r('app.color.paper_app_value_text'), ThemeColorRole.TEXT_SUB);
  }
  /** 设置页右侧细箭头（原 SettingsCardStyle.CHEVRON_TINT `#BABABA`） */
  static get CHEVRON_TINT(): Resource {
    return themeResource($r('app.color.app_chevron_tint'), $r('app.color.paper_app_chevron_tint'), ThemeColorRole.TEXT_MUTED);
  }
  /** 危险项字（原 SettingsCardStyle.DANGER_TEXT `#C7161C`；深色对齐 detail_error dark） */
  static get DANGER_TEXT(): Resource {
    return themeResource($r('app.color.app_danger_text'), $r('app.color.paper_app_danger_text'), ThemeColorRole.ERROR);
  }
  /** 设置弹层选项分隔线（原 SettingsCardStyle.POPUP_LINE `#CBCBCB`） */
  static get POPUP_LINE(): Resource {
    return themeResource($r('app.color.app_popup_line'), $r('app.color.paper_app_popup_line'), ThemeColorRole.DIVIDER);
  }
  /** 关于页数据说明字（原 Settings.ets `#666666`） */
  static get NOTE_TEXT(): Resource {
    return themeResource($r('app.color.app_note_text'), $r('app.color.paper_app_note_text'), ThemeColorRole.TEXT_SUB);
  }
  /** 头像占位底（原 AvatarComponent 默认 `#F1F1F3`） */
  static get AVATAR_BG(): Resource {
    return themeResource($r('app.color.app_avatar_bg'), $r('app.color.paper_app_avatar_bg'), ThemeColorRole.AVATAR_BG);
  }
  /** 吧页页签条底（原 ForumPage `#F5F7FA`） */
  static get FORUM_TAB_BG(): Resource {
    return themeResource($r('app.color.app_forum_tab_bg'), $r('app.color.paper_app_forum_tab_bg'), ThemeColorRole.CARD);
  }
  /** 设置页顶栏渐隐的起始色（原 SettingsCardStyle.NAV_FADE_COLOR `#FFFFFF`；深色=页面底）。
   *  透明终点保留同一页面色相。 */
  static get NAV_FADE(): Resource {
    return themeResource($r('app.color.app_nav_fade'), $r('app.color.paper_app_nav_fade'), ThemeColorRole.NAV_FADE);
  }

  static get NAV_FADE_CLEAR(): Resource {
    return themeResource($r('app.color.app_nav_fade_clear'), $r('app.color.paper_app_nav_fade_clear'), ThemeColorRole.NAV_FADE_CLEAR);
  }
  /** 首页底栏 `gradientMask.maskColor`（原 `#33F5F5F7` = 页面底色 20%）。
   *  ⚠️ 这层是"页面底色的延伸"，不是玻璃 —— 深色下必须跟着页面底走，否则浅雾突兀。 */
  static get BOTTOM_BAR_MASK(): Resource {
    return themeResource($r('app.color.app_bottom_mask'), $r('app.color.paper_app_bottom_mask'), ThemeColorRole.BOTTOM_MASK);
  }
  /** 消息页分类徽章四组「浅彩底 + 彩字」（原 MessageView 字面量；深色 = 深彩底 + 亮字） */
  static get MSG_BADGE_RED_BG(): Resource {
    return themeResource($r('app.color.app_msg_badge_red_bg'), $r('app.color.paper_emphasis_light'), ThemeColorRole.MSG_RED_BG);
  }
  static get MSG_BADGE_RED_FG(): Resource {
    return themeResource($r('app.color.app_msg_badge_red_fg'), $r('app.color.paper_emphasis'), ThemeColorRole.MSG_RED_FG);
  }
  static get MSG_BADGE_ORANGE_BG(): Resource {
    return themeResource($r('app.color.app_msg_badge_orange_bg'), $r('app.color.paper_gold_light'), ThemeColorRole.MSG_ORANGE_BG);
  }
  static get MSG_BADGE_ORANGE_FG(): Resource {
    return themeResource($r('app.color.app_msg_badge_orange_fg'), $r('app.color.paper_gold'), ThemeColorRole.MSG_ORANGE_FG);
  }
  static get MSG_BADGE_GREEN_BG(): Resource {
    return themeResource($r('app.color.app_msg_badge_green_bg'), $r('app.color.paper_jade_light'), ThemeColorRole.MSG_GREEN_BG);
  }
  static get MSG_BADGE_GREEN_FG(): Resource {
    return themeResource($r('app.color.app_msg_badge_green_fg'), $r('app.color.paper_jade'), ThemeColorRole.MSG_GREEN_FG);
  }
  static get MSG_BADGE_BLUE_BG(): Resource {
    return themeResource($r('app.color.app_msg_badge_blue_bg'), $r('app.color.paper_app_accent_light'), ThemeColorRole.MSG_BLUE_BG);
  }
  static get MSG_BADGE_BLUE_FG(): Resource {
    return themeResource($r('app.color.app_msg_badge_blue_fg'), $r('app.color.paper_app_accent_dark'), ThemeColorRole.MSG_BLUE_FG);
  }
  /** 系统状态栏 / 手势条的内容色（EntryAbility 按 `themeModeStore.isDark` 取值） */
  static get STATUS_BAR_CONTENT(): Resource {
    return themeResource($r('app.color.app_status_bar_content'), $r('app.color.app_status_bar_content'), ThemeColorRole.ICON);
  }

  /** 品牌强调与金色、绿色语义分别映射；正文使用独立文字色。 */
  static get EMPHASIS(): Resource {
    return themeResource(AppTheme.ACCENT, $r('app.color.paper_emphasis'), ThemeColorRole.ACCENT);
  }
  static get EMPHASIS_LIGHT(): Resource {
    return themeResource(AppTheme.ACCENT_LIGHT, $r('app.color.paper_emphasis_light'), ThemeColorRole.ACCENT_LIGHT);
  }
  static get ON_ACCENT(): Resource {
    return themeResource($r('app.color.theme_classic_on_accent'), $r('app.color.paper_on_accent'), ThemeColorRole.ON_ACCENT);
  }
  static get ON_EMPHASIS(): Resource {
    return themeResource($r('app.color.theme_classic_on_accent'), $r('app.color.paper_on_emphasis'), ThemeColorRole.ON_ACCENT);
  }
  static get GOLD(): Resource {
    return themeResource(AppTheme.ACCENT, $r('app.color.paper_gold'), ThemeColorRole.GOLD);
  }
  static get GOLD_LIGHT(): Resource {
    return themeResource(AppTheme.ACCENT_LIGHT, $r('app.color.paper_gold_light'), ThemeColorRole.GOLD_LIGHT);
  }
  static get JADE(): Resource {
    return themeResource(AppTheme.ACCENT, $r('app.color.paper_jade'), ThemeColorRole.JADE);
  }
  static get JADE_LIGHT(): Resource {
    return themeResource(AppTheme.ACCENT_LIGHT, $r('app.color.paper_jade_light'), ThemeColorRole.JADE_LIGHT);
  }
  static get HEADER_START(): Resource {
    return themeResource(AppTheme.CARD, $r('app.color.paper_header_start'), ThemeColorRole.HEADER_START);
  }
  static get HEADER_END(): Resource {
    return themeResource(AppTheme.CARD, $r('app.color.paper_header_end'), ThemeColorRole.HEADER_END);
  }
  /** 导航前景独立于内容矿物色，原生玻璃不增加衬底。 */
  static get NAV_TEXT(): Resource {
    return themeResource(AppTheme.ICON, $r('app.color.paper_nav_text'), ThemeColorRole.ICON);
  }
  static get NAV_SELECTED(): Resource {
    return themeResource(AppTheme.EMPHASIS, $r('app.color.paper_nav_selected'), ThemeColorRole.NAV_SELECTED);
  }

  /** 交互前景、选择与官方材质支持的色调；透明度已包含在资源中。 */
  static get BUSY_ACCENT(): Resource {
    return themeResource($r('app.color.theme_classic_busy_accent'), $r('app.color.theme_paper_busy_accent'), ThemeColorRole.BUSY_ACCENT);
  }
  static get SELECTION_BACKGROUND(): Resource {
    return themeResource($r('app.color.theme_classic_selection_background'), $r('app.color.theme_paper_selection_background'), ThemeColorRole.SELECTION_BACKGROUND);
  }
  static get MATERIAL_TINT(): Resource {
    return themeResource($r('app.color.theme_classic_material_tint'), $r('app.color.theme_paper_material_tint'), ThemeColorRole.MATERIAL_TINT);
  }
  static get TOUCH_LIGHT(): Resource {
    return themeResource($r('app.color.theme_classic_touch_light'), $r('app.color.theme_paper_touch_light'), ThemeColorRole.TOUCH_LIGHT);
  }
  static get FLOW_EDGE_PRIMARY(): Resource {
    return themeResource($r('app.color.theme_classic_flow_edge_primary'), $r('app.color.theme_paper_flow_edge_primary'), ThemeColorRole.FLOW_EDGE_PRIMARY);
  }
  static get FLOW_EDGE_SECONDARY(): Resource {
    return themeResource($r('app.color.theme_classic_flow_edge_secondary'), $r('app.color.theme_paper_flow_edge_secondary'), ThemeColorRole.FLOW_EDGE_SECONDARY);
  }
  static get FLOW_BACKGROUND_START(): Resource {
    return themeResource($r('app.color.theme_classic_flow_background_start'), $r('app.color.theme_paper_flow_background_start'), ThemeColorRole.FLOW_BACKGROUND_START);
  }
  static get FLOW_BACKGROUND_MIDDLE(): Resource {
    return themeResource($r('app.color.theme_classic_flow_background_middle'), $r('app.color.theme_paper_flow_background_middle'), ThemeColorRole.FLOW_BACKGROUND_MIDDLE);
  }
  static get FLOW_BACKGROUND_END(): Resource {
    return themeResource($r('app.color.theme_classic_flow_background_end'), $r('app.color.theme_paper_flow_background_end'), ThemeColorRole.FLOW_BACKGROUND_END);
  }
  static get MEDIA_ACCENT(): Resource {
    return themeResource($r('app.color.theme_classic_media_accent'), $r('app.color.theme_paper_media_accent'), ThemeColorRole.MEDIA_ACCENT);
  }
  static get HOME_TOP_BACKDROP(): Resource {
    return themeResource($r('app.color.theme_classic_home_top_backdrop'), $r('app.color.theme_paper_home_top_backdrop'), ThemeColorRole.HOME_TOP_BACKDROP);
  }
  static get HOME_TOP_BACKDROP_CLEAR(): Resource {
    return themeResource($r('app.color.theme_classic_home_top_backdrop_clear'), $r('app.color.theme_paper_home_top_backdrop_clear'), ThemeColorRole.HOME_TOP_BACKDROP_CLEAR);
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
  static get COMMENT_NICKNAME(): Resource {
    return themeResource($r('app.color.detail_comment_nickname'), $r('app.color.paper_detail_comment_nickname'), ThemeColorRole.TEXT_SUB);
  }
  static get COMMENT_BODY(): Resource {
    return themeResource($r('app.color.detail_comment_body'), $r('app.color.paper_detail_comment_body'), ThemeColorRole.TEXT_MAIN);
  }
  static get COMMENT_META(): Resource {
    return themeResource($r('app.color.detail_comment_meta'), $r('app.color.paper_detail_comment_meta'), ThemeColorRole.TEXT_SUB);
  }
  static get COMMENT_ACTION(): Resource {
    return themeResource($r('app.color.detail_comment_action'), $r('app.color.paper_detail_comment_action'), ThemeColorRole.TEXT_SUB);
  }
  static get SUB_REPLY_BODY(): Resource {
    return themeResource($r('app.color.detail_sub_reply_body'), $r('app.color.paper_detail_sub_reply_body'), ThemeColorRole.TEXT_MAIN);
  }
  static get SUB_REPLY_NAME(): Resource {
    return themeResource($r('app.color.detail_sub_reply_name'), $r('app.color.paper_detail_sub_reply_name'), ThemeColorRole.ACCENT_DARK);
  }
  static get SUB_REPLY_BACKGROUND(): Resource {
    return themeResource($r('app.color.detail_sub_reply_background'), $r('app.color.paper_detail_sub_reply_background'), ThemeColorRole.SURFACE_MUTED);
  }
  static get AUTHOR_BADGE_TEXT(): Resource {
    return themeResource($r('app.color.detail_author_badge_text'), $r('app.color.paper_detail_author_badge_text'), ThemeColorRole.ACCENT_DARK);
  }
  static get AUTHOR_BADGE_BACKGROUND(): Resource {
    return themeResource($r('app.color.detail_author_badge_background'), $r('app.color.paper_detail_author_badge_background'), ThemeColorRole.ACCENT_LIGHT);
  }
  static get BOTTOM_FLOAT_SHADOW(): Resource {
    return themeResource($r('app.color.detail_bottom_float_shadow'), $r('app.color.paper_detail_bottom_float_shadow'), ThemeColorRole.SHADOW);
  }
  static get BG(): Resource {
    return themeResource($r('app.color.detail_page_background'), $r('app.color.paper_detail_page_background'), ThemeColorRole.CARD);
  }
  static get CARD(): Resource {
    return themeResource($r('app.color.detail_content_background'), $r('app.color.paper_detail_content_background'), ThemeColorRole.CARD);
  }
  static get SURFACE_MUTED(): Resource {
    return themeResource($r('app.color.detail_secondary_background'), $r('app.color.paper_detail_secondary_background'), ThemeColorRole.SURFACE_MUTED);
  }
  static get TEXT_MAIN(): Resource {
    return themeResource($r('app.color.detail_text_primary'), $r('app.color.paper_detail_text_primary'), ThemeColorRole.TEXT_MAIN);
  }
  static get TEXT_SUB(): Resource {
    return themeResource($r('app.color.detail_text_secondary'), $r('app.color.paper_detail_text_secondary'), ThemeColorRole.TEXT_SUB);
  }
  static get TEXT_MUTED(): Resource {
    return themeResource($r('app.color.detail_text_tertiary'), $r('app.color.paper_detail_text_tertiary'), ThemeColorRole.TEXT_MUTED);
  }
  static get DIVIDER(): Resource {
    return themeResource($r('app.color.detail_divider'), $r('app.color.paper_detail_divider'), ThemeColorRole.DIVIDER);
  }
  static get ACCENT(): Resource {
    return themeResource($r('app.color.detail_accent'), $r('app.color.paper_detail_accent'), ThemeColorRole.ACCENT);
  }
  static get ACCENT_DARK(): Resource {
    return themeResource($r('app.color.detail_accent'), $r('app.color.paper_detail_accent'), ThemeColorRole.ACCENT_DARK);
  }
  static get ACCENT_LIGHT(): Resource {
    return themeResource($r('app.color.detail_accent_background'), $r('app.color.paper_detail_accent_background'), ThemeColorRole.ACCENT_LIGHT);
  }

  static get ICON(): Resource {
    return themeResource($r('app.color.detail_icon'), $r('app.color.paper_detail_icon'), ThemeColorRole.ICON);
  }
  static get ERROR(): Resource {
    return themeResource($r('app.color.detail_error'), $r('app.color.paper_detail_error'), ThemeColorRole.ERROR);
  }
  static readonly OVERLAY: ResourceColor = $r('app.color.detail_overlay');
  static get BOTTOM_BAR(): Resource {
    return themeResource($r('app.color.detail_bottom_bar_background'), $r('app.color.paper_detail_bottom_bar_background'), ThemeColorRole.BOTTOM_BAR);
  }

  static get EMOJI_PANEL_TEXT(): Resource {
    return themeResource($r('app.color.app_emoji_panel_text'), $r('app.color.paper_app_emoji_panel_text'), ThemeColorRole.TEXT_MAIN);
  }

  static get FLOAT_SHADOW(): Resource {
    return themeResource($r('app.color.detail_float_shadow'), $r('app.color.paper_detail_float_shadow'), ThemeColorRole.SHADOW);
  }
  static get EMOJI_PANEL_SUB_TEXT(): Resource {
    return themeResource($r('app.color.app_emoji_panel_sub_text'), $r('app.color.paper_app_emoji_panel_sub_text'), ThemeColorRole.TEXT_SUB);
  }
}
