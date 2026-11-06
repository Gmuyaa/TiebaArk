import { VisualTheme } from '../common/appearance/VisualTheme';
import { visualThemeStore } from '../common/appearance/VisualThemeStore';

/** 主题资源角色；数组与枚举顺序对应，中性角色留空并使用调用方的经典资源。 */
export enum ThemeColorRole {
  ACCENT,
  ACCENT_LIGHT,
  ACCENT_DARK,
  ON_ACCENT,
  BG,
  CARD,
  SURFACE_MUTED,
  TEXT_MAIN,
  TEXT_SUB,
  TEXT_MUTED,
  DIVIDER,
  ICON,
  AVATAR_BG,
  NAV_SELECTED,
  HEADER_START,
  HEADER_END,
  NAV_FADE,
  NAV_FADE_CLEAR,
  BOTTOM_MASK,
  BOTTOM_BAR,
  SHADOW,
  SR_ACTIVE,
  ERROR,
  HELP_ANSWER,
  GOLD,
  GOLD_LIGHT,
  JADE,
  JADE_LIGHT,
  MSG_RED_BG,
  MSG_RED_FG,
  MSG_ORANGE_BG,
  MSG_ORANGE_FG,
  MSG_GREEN_BG,
  MSG_GREEN_FG,
  MSG_BLUE_BG,
  MSG_BLUE_FG,
  NOTIFY_BG,
  NOTIFY_TEXT,
  LEGACY_GLOW_BORDER,
  LEGACY_GLOW_SHADOW,
  BUSY_ACCENT,
  SELECTION_BACKGROUND,
  MATERIAL_TINT,
  TOUCH_LIGHT,
  FLOW_EDGE_PRIMARY,
  FLOW_EDGE_SECONDARY,
  FLOW_BACKGROUND_START,
  FLOW_BACKGROUND_MIDDLE,
  FLOW_BACKGROUND_END,
  MEDIA_ACCENT,
  HOME_TOP_BACKDROP,
  HOME_TOP_BACKDROP_CLEAR
}

/** 雾松：固定资源标识可复用；主题选择必须在 getter 调用时读取。 */
const PINE_COLORS: Array<Resource | undefined> = [
  $r('app.color.theme_pine_accent'), // ACCENT
  $r('app.color.theme_pine_accent_light'), // ACCENT_LIGHT
  $r('app.color.theme_pine_accent_dark'), // ACCENT_DARK
  $r('app.color.theme_pine_on_accent'), // ON_ACCENT
  undefined, // BG uses the caller's classic resource
  undefined, // CARD uses the caller's classic resource
  undefined, // SURFACE_MUTED uses the caller's classic resource
  undefined, // TEXT_MAIN uses the caller's classic resource
  undefined, // TEXT_SUB uses the caller's classic resource
  undefined, // TEXT_MUTED uses the caller's classic resource
  undefined, // DIVIDER uses the caller's classic resource
  undefined, // ICON uses the caller's classic resource
  undefined, // AVATAR_BG uses the caller's classic resource
  $r('app.color.theme_pine_nav_selected'), // NAV_SELECTED
  undefined, // HEADER_START uses the caller's classic resource
  undefined, // HEADER_END uses the caller's classic resource
  undefined, // NAV_FADE uses the caller's classic resource
  undefined, // NAV_FADE_CLEAR uses the caller's classic resource
  undefined, // BOTTOM_MASK uses the caller's classic resource
  undefined, // BOTTOM_BAR uses the caller's classic resource
  undefined, // SHADOW uses the caller's classic resource
  $r('app.color.theme_pine_sr_active'), // SR_ACTIVE
  $r('app.color.theme_semantic_error'), // ERROR
  $r('app.color.theme_semantic_gold'), // HELP_ANSWER
  $r('app.color.theme_semantic_gold'), // GOLD
  $r('app.color.theme_semantic_gold_light'), // GOLD_LIGHT
  $r('app.color.theme_semantic_jade'), // JADE
  $r('app.color.theme_semantic_jade_light'), // JADE_LIGHT
  $r('app.color.theme_semantic_red_bg'), // MSG_RED_BG
  $r('app.color.theme_semantic_red_fg'), // MSG_RED_FG
  $r('app.color.theme_semantic_orange_bg'), // MSG_ORANGE_BG
  $r('app.color.theme_semantic_orange_fg'), // MSG_ORANGE_FG
  $r('app.color.theme_semantic_green_bg'), // MSG_GREEN_BG
  $r('app.color.theme_semantic_green_fg'), // MSG_GREEN_FG
  $r('app.color.theme_semantic_blue_bg'), // MSG_BLUE_BG
  $r('app.color.theme_semantic_blue_fg'), // MSG_BLUE_FG
  $r('app.color.notify_badge_background'), // NOTIFY_BG
  $r('app.color.notify_badge_text'), // NOTIFY_TEXT
  $r('app.color.forum_tab_glow_border'), // LEGACY_GLOW_BORDER
  $r('app.color.forum_tab_glow_shadow'), // LEGACY_GLOW_SHADOW
  $r('app.color.theme_pine_busy_accent'), // BUSY_ACCENT
  $r('app.color.theme_pine_selection_background'), // SELECTION_BACKGROUND
  $r('app.color.theme_pine_material_tint'), // MATERIAL_TINT
  $r('app.color.theme_pine_touch_light'), // TOUCH_LIGHT
  $r('app.color.theme_pine_flow_edge_primary'), // FLOW_EDGE_PRIMARY
  $r('app.color.theme_pine_flow_edge_secondary'), // FLOW_EDGE_SECONDARY
  $r('app.color.theme_pine_flow_background_start'), // FLOW_BACKGROUND_START
  $r('app.color.theme_pine_flow_background_middle'), // FLOW_BACKGROUND_MIDDLE
  $r('app.color.theme_pine_flow_background_end'), // FLOW_BACKGROUND_END
  $r('app.color.theme_pine_media_accent'), // MEDIA_ACCENT
  undefined, // HOME_TOP_BACKDROP uses the caller's classic resource
  undefined, // HOME_TOP_BACKDROP_CLEAR uses the caller's classic resource
];

/** 烟紫：固定资源标识可复用；主题选择必须在 getter 调用时读取。 */
const LILAC_COLORS: Array<Resource | undefined> = [
  $r('app.color.theme_lilac_accent'), // ACCENT
  $r('app.color.theme_lilac_accent_light'), // ACCENT_LIGHT
  $r('app.color.theme_lilac_accent_dark'), // ACCENT_DARK
  $r('app.color.theme_lilac_on_accent'), // ON_ACCENT
  undefined, // BG uses the caller's classic resource
  undefined, // CARD uses the caller's classic resource
  undefined, // SURFACE_MUTED uses the caller's classic resource
  undefined, // TEXT_MAIN uses the caller's classic resource
  undefined, // TEXT_SUB uses the caller's classic resource
  undefined, // TEXT_MUTED uses the caller's classic resource
  undefined, // DIVIDER uses the caller's classic resource
  undefined, // ICON uses the caller's classic resource
  undefined, // AVATAR_BG uses the caller's classic resource
  $r('app.color.theme_lilac_nav_selected'), // NAV_SELECTED
  undefined, // HEADER_START uses the caller's classic resource
  undefined, // HEADER_END uses the caller's classic resource
  undefined, // NAV_FADE uses the caller's classic resource
  undefined, // NAV_FADE_CLEAR uses the caller's classic resource
  undefined, // BOTTOM_MASK uses the caller's classic resource
  undefined, // BOTTOM_BAR uses the caller's classic resource
  undefined, // SHADOW uses the caller's classic resource
  $r('app.color.theme_lilac_sr_active'), // SR_ACTIVE
  $r('app.color.theme_semantic_error'), // ERROR
  $r('app.color.theme_semantic_gold'), // HELP_ANSWER
  $r('app.color.theme_semantic_gold'), // GOLD
  $r('app.color.theme_semantic_gold_light'), // GOLD_LIGHT
  $r('app.color.theme_semantic_jade'), // JADE
  $r('app.color.theme_semantic_jade_light'), // JADE_LIGHT
  $r('app.color.theme_semantic_red_bg'), // MSG_RED_BG
  $r('app.color.theme_semantic_red_fg'), // MSG_RED_FG
  $r('app.color.theme_semantic_orange_bg'), // MSG_ORANGE_BG
  $r('app.color.theme_semantic_orange_fg'), // MSG_ORANGE_FG
  $r('app.color.theme_semantic_green_bg'), // MSG_GREEN_BG
  $r('app.color.theme_semantic_green_fg'), // MSG_GREEN_FG
  $r('app.color.theme_semantic_blue_bg'), // MSG_BLUE_BG
  $r('app.color.theme_semantic_blue_fg'), // MSG_BLUE_FG
  $r('app.color.notify_badge_background'), // NOTIFY_BG
  $r('app.color.notify_badge_text'), // NOTIFY_TEXT
  $r('app.color.forum_tab_glow_border'), // LEGACY_GLOW_BORDER
  $r('app.color.forum_tab_glow_shadow'), // LEGACY_GLOW_SHADOW
  $r('app.color.theme_lilac_busy_accent'), // BUSY_ACCENT
  $r('app.color.theme_lilac_selection_background'), // SELECTION_BACKGROUND
  $r('app.color.theme_lilac_material_tint'), // MATERIAL_TINT
  $r('app.color.theme_lilac_touch_light'), // TOUCH_LIGHT
  $r('app.color.theme_lilac_flow_edge_primary'), // FLOW_EDGE_PRIMARY
  $r('app.color.theme_lilac_flow_edge_secondary'), // FLOW_EDGE_SECONDARY
  $r('app.color.theme_lilac_flow_background_start'), // FLOW_BACKGROUND_START
  $r('app.color.theme_lilac_flow_background_middle'), // FLOW_BACKGROUND_MIDDLE
  $r('app.color.theme_lilac_flow_background_end'), // FLOW_BACKGROUND_END
  $r('app.color.theme_lilac_media_accent'), // MEDIA_ACCENT
  undefined, // HOME_TOP_BACKDROP uses the caller's classic resource
  undefined, // HOME_TOP_BACKDROP_CLEAR uses the caller's classic resource
];

/** 砂陶：固定资源标识可复用；主题选择必须在 getter 调用时读取。 */
const CLAY_COLORS: Array<Resource | undefined> = [
  $r('app.color.theme_clay_accent'), // ACCENT
  $r('app.color.theme_clay_accent_light'), // ACCENT_LIGHT
  $r('app.color.theme_clay_accent_dark'), // ACCENT_DARK
  $r('app.color.theme_clay_on_accent'), // ON_ACCENT
  undefined, // BG uses the caller's classic resource
  undefined, // CARD uses the caller's classic resource
  undefined, // SURFACE_MUTED uses the caller's classic resource
  undefined, // TEXT_MAIN uses the caller's classic resource
  undefined, // TEXT_SUB uses the caller's classic resource
  undefined, // TEXT_MUTED uses the caller's classic resource
  undefined, // DIVIDER uses the caller's classic resource
  undefined, // ICON uses the caller's classic resource
  undefined, // AVATAR_BG uses the caller's classic resource
  $r('app.color.theme_clay_nav_selected'), // NAV_SELECTED
  undefined, // HEADER_START uses the caller's classic resource
  undefined, // HEADER_END uses the caller's classic resource
  undefined, // NAV_FADE uses the caller's classic resource
  undefined, // NAV_FADE_CLEAR uses the caller's classic resource
  undefined, // BOTTOM_MASK uses the caller's classic resource
  undefined, // BOTTOM_BAR uses the caller's classic resource
  undefined, // SHADOW uses the caller's classic resource
  $r('app.color.theme_clay_sr_active'), // SR_ACTIVE
  $r('app.color.theme_semantic_error'), // ERROR
  $r('app.color.theme_semantic_gold'), // HELP_ANSWER
  $r('app.color.theme_semantic_gold'), // GOLD
  $r('app.color.theme_semantic_gold_light'), // GOLD_LIGHT
  $r('app.color.theme_semantic_jade'), // JADE
  $r('app.color.theme_semantic_jade_light'), // JADE_LIGHT
  $r('app.color.theme_semantic_red_bg'), // MSG_RED_BG
  $r('app.color.theme_semantic_red_fg'), // MSG_RED_FG
  $r('app.color.theme_semantic_orange_bg'), // MSG_ORANGE_BG
  $r('app.color.theme_semantic_orange_fg'), // MSG_ORANGE_FG
  $r('app.color.theme_semantic_green_bg'), // MSG_GREEN_BG
  $r('app.color.theme_semantic_green_fg'), // MSG_GREEN_FG
  $r('app.color.theme_semantic_blue_bg'), // MSG_BLUE_BG
  $r('app.color.theme_semantic_blue_fg'), // MSG_BLUE_FG
  $r('app.color.notify_badge_background'), // NOTIFY_BG
  $r('app.color.notify_badge_text'), // NOTIFY_TEXT
  $r('app.color.forum_tab_glow_border'), // LEGACY_GLOW_BORDER
  $r('app.color.forum_tab_glow_shadow'), // LEGACY_GLOW_SHADOW
  $r('app.color.theme_clay_busy_accent'), // BUSY_ACCENT
  $r('app.color.theme_clay_selection_background'), // SELECTION_BACKGROUND
  $r('app.color.theme_clay_material_tint'), // MATERIAL_TINT
  $r('app.color.theme_clay_touch_light'), // TOUCH_LIGHT
  $r('app.color.theme_clay_flow_edge_primary'), // FLOW_EDGE_PRIMARY
  $r('app.color.theme_clay_flow_edge_secondary'), // FLOW_EDGE_SECONDARY
  $r('app.color.theme_clay_flow_background_start'), // FLOW_BACKGROUND_START
  $r('app.color.theme_clay_flow_background_middle'), // FLOW_BACKGROUND_MIDDLE
  $r('app.color.theme_clay_flow_background_end'), // FLOW_BACKGROUND_END
  $r('app.color.theme_clay_media_accent'), // MEDIA_ACCENT
  undefined, // HOME_TOP_BACKDROP uses the caller's classic resource
  undefined, // HOME_TOP_BACKDROP_CLEAR uses the caller's classic resource
];

/** 晴空：固定资源标识可复用；主题选择必须在 getter 调用时读取。 */
const SKY_COLORS: Array<Resource | undefined> = [
  $r('app.color.theme_sky_accent'), // ACCENT
  $r('app.color.theme_sky_accent_light'), // ACCENT_LIGHT
  $r('app.color.theme_sky_accent_dark'), // ACCENT_DARK
  $r('app.color.theme_sky_on_accent'), // ON_ACCENT
  undefined, // BG uses the caller's classic resource
  undefined, // CARD uses the caller's classic resource
  undefined, // SURFACE_MUTED uses the caller's classic resource
  undefined, // TEXT_MAIN uses the caller's classic resource
  undefined, // TEXT_SUB uses the caller's classic resource
  undefined, // TEXT_MUTED uses the caller's classic resource
  undefined, // DIVIDER uses the caller's classic resource
  undefined, // ICON uses the caller's classic resource
  undefined, // AVATAR_BG uses the caller's classic resource
  $r('app.color.theme_sky_nav_selected'), // NAV_SELECTED
  undefined, // HEADER_START uses the caller's classic resource
  undefined, // HEADER_END uses the caller's classic resource
  undefined, // NAV_FADE uses the caller's classic resource
  undefined, // NAV_FADE_CLEAR uses the caller's classic resource
  undefined, // BOTTOM_MASK uses the caller's classic resource
  undefined, // BOTTOM_BAR uses the caller's classic resource
  undefined, // SHADOW uses the caller's classic resource
  $r('app.color.theme_sky_sr_active'), // SR_ACTIVE
  $r('app.color.theme_semantic_error'), // ERROR
  $r('app.color.theme_semantic_gold'), // HELP_ANSWER
  $r('app.color.theme_semantic_gold'), // GOLD
  $r('app.color.theme_semantic_gold_light'), // GOLD_LIGHT
  $r('app.color.theme_semantic_jade'), // JADE
  $r('app.color.theme_semantic_jade_light'), // JADE_LIGHT
  $r('app.color.theme_semantic_red_bg'), // MSG_RED_BG
  $r('app.color.theme_semantic_red_fg'), // MSG_RED_FG
  $r('app.color.theme_semantic_orange_bg'), // MSG_ORANGE_BG
  $r('app.color.theme_semantic_orange_fg'), // MSG_ORANGE_FG
  $r('app.color.theme_semantic_green_bg'), // MSG_GREEN_BG
  $r('app.color.theme_semantic_green_fg'), // MSG_GREEN_FG
  $r('app.color.theme_semantic_blue_bg'), // MSG_BLUE_BG
  $r('app.color.theme_semantic_blue_fg'), // MSG_BLUE_FG
  $r('app.color.notify_badge_background'), // NOTIFY_BG
  $r('app.color.notify_badge_text'), // NOTIFY_TEXT
  $r('app.color.forum_tab_glow_border'), // LEGACY_GLOW_BORDER
  $r('app.color.forum_tab_glow_shadow'), // LEGACY_GLOW_SHADOW
  $r('app.color.theme_sky_busy_accent'), // BUSY_ACCENT
  $r('app.color.theme_sky_selection_background'), // SELECTION_BACKGROUND
  $r('app.color.theme_sky_material_tint'), // MATERIAL_TINT
  $r('app.color.theme_sky_touch_light'), // TOUCH_LIGHT
  $r('app.color.theme_sky_flow_edge_primary'), // FLOW_EDGE_PRIMARY
  $r('app.color.theme_sky_flow_edge_secondary'), // FLOW_EDGE_SECONDARY
  $r('app.color.theme_sky_flow_background_start'), // FLOW_BACKGROUND_START
  $r('app.color.theme_sky_flow_background_middle'), // FLOW_BACKGROUND_MIDDLE
  $r('app.color.theme_sky_flow_background_end'), // FLOW_BACKGROUND_END
  $r('app.color.theme_sky_media_accent'), // MEDIA_ACCENT
  undefined, // HOME_TOP_BACKDROP uses the caller's classic resource
  undefined, // HOME_TOP_BACKDROP_CLEAR uses the caller's classic resource
];

/** 莓果：固定资源标识可复用；主题选择必须在 getter 调用时读取。 */
const BERRY_COLORS: Array<Resource | undefined> = [
  $r('app.color.theme_berry_accent'), // ACCENT
  $r('app.color.theme_berry_accent_light'), // ACCENT_LIGHT
  $r('app.color.theme_berry_accent_dark'), // ACCENT_DARK
  $r('app.color.theme_berry_on_accent'), // ON_ACCENT
  undefined, // BG uses the caller's classic resource
  undefined, // CARD uses the caller's classic resource
  undefined, // SURFACE_MUTED uses the caller's classic resource
  undefined, // TEXT_MAIN uses the caller's classic resource
  undefined, // TEXT_SUB uses the caller's classic resource
  undefined, // TEXT_MUTED uses the caller's classic resource
  undefined, // DIVIDER uses the caller's classic resource
  undefined, // ICON uses the caller's classic resource
  undefined, // AVATAR_BG uses the caller's classic resource
  $r('app.color.theme_berry_nav_selected'), // NAV_SELECTED
  undefined, // HEADER_START uses the caller's classic resource
  undefined, // HEADER_END uses the caller's classic resource
  undefined, // NAV_FADE uses the caller's classic resource
  undefined, // NAV_FADE_CLEAR uses the caller's classic resource
  undefined, // BOTTOM_MASK uses the caller's classic resource
  undefined, // BOTTOM_BAR uses the caller's classic resource
  undefined, // SHADOW uses the caller's classic resource
  $r('app.color.theme_berry_sr_active'), // SR_ACTIVE
  $r('app.color.theme_semantic_error'), // ERROR
  $r('app.color.theme_semantic_gold'), // HELP_ANSWER
  $r('app.color.theme_semantic_gold'), // GOLD
  $r('app.color.theme_semantic_gold_light'), // GOLD_LIGHT
  $r('app.color.theme_semantic_jade'), // JADE
  $r('app.color.theme_semantic_jade_light'), // JADE_LIGHT
  $r('app.color.theme_semantic_red_bg'), // MSG_RED_BG
  $r('app.color.theme_semantic_red_fg'), // MSG_RED_FG
  $r('app.color.theme_semantic_orange_bg'), // MSG_ORANGE_BG
  $r('app.color.theme_semantic_orange_fg'), // MSG_ORANGE_FG
  $r('app.color.theme_semantic_green_bg'), // MSG_GREEN_BG
  $r('app.color.theme_semantic_green_fg'), // MSG_GREEN_FG
  $r('app.color.theme_semantic_blue_bg'), // MSG_BLUE_BG
  $r('app.color.theme_semantic_blue_fg'), // MSG_BLUE_FG
  $r('app.color.notify_badge_background'), // NOTIFY_BG
  $r('app.color.notify_badge_text'), // NOTIFY_TEXT
  $r('app.color.forum_tab_glow_border'), // LEGACY_GLOW_BORDER
  $r('app.color.forum_tab_glow_shadow'), // LEGACY_GLOW_SHADOW
  $r('app.color.theme_berry_busy_accent'), // BUSY_ACCENT
  $r('app.color.theme_berry_selection_background'), // SELECTION_BACKGROUND
  $r('app.color.theme_berry_material_tint'), // MATERIAL_TINT
  $r('app.color.theme_berry_touch_light'), // TOUCH_LIGHT
  $r('app.color.theme_berry_flow_edge_primary'), // FLOW_EDGE_PRIMARY
  $r('app.color.theme_berry_flow_edge_secondary'), // FLOW_EDGE_SECONDARY
  $r('app.color.theme_berry_flow_background_start'), // FLOW_BACKGROUND_START
  $r('app.color.theme_berry_flow_background_middle'), // FLOW_BACKGROUND_MIDDLE
  $r('app.color.theme_berry_flow_background_end'), // FLOW_BACKGROUND_END
  $r('app.color.theme_berry_media_accent'), // MEDIA_ACCENT
  undefined, // HOME_TOP_BACKDROP uses the caller's classic resource
  undefined, // HOME_TOP_BACKDROP_CLEAR uses the caller's classic resource
];

/** 橘光：固定资源标识可复用；主题选择必须在 getter 调用时读取。 */
const ORANGE_COLORS: Array<Resource | undefined> = [
  $r('app.color.theme_orange_accent'), // ACCENT
  $r('app.color.theme_orange_accent_light'), // ACCENT_LIGHT
  $r('app.color.theme_orange_accent_dark'), // ACCENT_DARK
  $r('app.color.theme_orange_on_accent'), // ON_ACCENT
  undefined, // BG uses the caller's classic resource
  undefined, // CARD uses the caller's classic resource
  undefined, // SURFACE_MUTED uses the caller's classic resource
  undefined, // TEXT_MAIN uses the caller's classic resource
  undefined, // TEXT_SUB uses the caller's classic resource
  undefined, // TEXT_MUTED uses the caller's classic resource
  undefined, // DIVIDER uses the caller's classic resource
  undefined, // ICON uses the caller's classic resource
  undefined, // AVATAR_BG uses the caller's classic resource
  $r('app.color.theme_orange_nav_selected'), // NAV_SELECTED
  undefined, // HEADER_START uses the caller's classic resource
  undefined, // HEADER_END uses the caller's classic resource
  undefined, // NAV_FADE uses the caller's classic resource
  undefined, // NAV_FADE_CLEAR uses the caller's classic resource
  undefined, // BOTTOM_MASK uses the caller's classic resource
  undefined, // BOTTOM_BAR uses the caller's classic resource
  undefined, // SHADOW uses the caller's classic resource
  $r('app.color.theme_orange_sr_active'), // SR_ACTIVE
  $r('app.color.theme_semantic_error'), // ERROR
  $r('app.color.theme_semantic_gold'), // HELP_ANSWER
  $r('app.color.theme_semantic_gold'), // GOLD
  $r('app.color.theme_semantic_gold_light'), // GOLD_LIGHT
  $r('app.color.theme_semantic_jade'), // JADE
  $r('app.color.theme_semantic_jade_light'), // JADE_LIGHT
  $r('app.color.theme_semantic_red_bg'), // MSG_RED_BG
  $r('app.color.theme_semantic_red_fg'), // MSG_RED_FG
  $r('app.color.theme_semantic_orange_bg'), // MSG_ORANGE_BG
  $r('app.color.theme_semantic_orange_fg'), // MSG_ORANGE_FG
  $r('app.color.theme_semantic_green_bg'), // MSG_GREEN_BG
  $r('app.color.theme_semantic_green_fg'), // MSG_GREEN_FG
  $r('app.color.theme_semantic_blue_bg'), // MSG_BLUE_BG
  $r('app.color.theme_semantic_blue_fg'), // MSG_BLUE_FG
  $r('app.color.notify_badge_background'), // NOTIFY_BG
  $r('app.color.notify_badge_text'), // NOTIFY_TEXT
  $r('app.color.forum_tab_glow_border'), // LEGACY_GLOW_BORDER
  $r('app.color.forum_tab_glow_shadow'), // LEGACY_GLOW_SHADOW
  $r('app.color.theme_orange_busy_accent'), // BUSY_ACCENT
  $r('app.color.theme_orange_selection_background'), // SELECTION_BACKGROUND
  $r('app.color.theme_orange_material_tint'), // MATERIAL_TINT
  $r('app.color.theme_orange_touch_light'), // TOUCH_LIGHT
  $r('app.color.theme_orange_flow_edge_primary'), // FLOW_EDGE_PRIMARY
  $r('app.color.theme_orange_flow_edge_secondary'), // FLOW_EDGE_SECONDARY
  $r('app.color.theme_orange_flow_background_start'), // FLOW_BACKGROUND_START
  $r('app.color.theme_orange_flow_background_middle'), // FLOW_BACKGROUND_MIDDLE
  $r('app.color.theme_orange_flow_background_end'), // FLOW_BACKGROUND_END
  $r('app.color.theme_orange_media_accent'), // MEDIA_ACCENT
  undefined, // HOME_TOP_BACKDROP uses the caller's classic resource
  undefined, // HOME_TOP_BACKDROP_CLEAR uses the caller's classic resource
];

/** 新增六色仅覆盖强调与交互色，页面和内容表面始终沿用调用方的经典资源。 */
function isClassicSurface(role: ThemeColorRole): boolean {
  switch (role) {
    case ThemeColorRole.BG:
    case ThemeColorRole.CARD:
    case ThemeColorRole.SURFACE_MUTED:
    case ThemeColorRole.TEXT_MAIN:
    case ThemeColorRole.TEXT_SUB:
    case ThemeColorRole.TEXT_MUTED:
    case ThemeColorRole.DIVIDER:
    case ThemeColorRole.ICON:
    case ThemeColorRole.AVATAR_BG:
    case ThemeColorRole.HEADER_START:
    case ThemeColorRole.HEADER_END:
    case ThemeColorRole.NAV_FADE:
    case ThemeColorRole.NAV_FADE_CLEAR:
    case ThemeColorRole.BOTTOM_MASK:
    case ThemeColorRole.BOTTOM_BAR:
    case ThemeColorRole.SHADOW:
    case ThemeColorRole.HOME_TOP_BACKDROP:
    case ThemeColorRole.HOME_TOP_BACKDROP_CLEAR:
      return true;
    default: return false;
  }
}

/** 经典与纸境保留原配色；六色只切换局部强调，不改变页面背景或布局。 */
export function themeResource(classic: Resource, paper: Resource, role: ThemeColorRole): Resource {
  const theme: VisualTheme = visualThemeStore.theme;
  if (theme !== VisualTheme.CLASSIC && theme !== VisualTheme.PAPER && isClassicSurface(role)) {
    return classic;
  }
  switch (theme) {
    case VisualTheme.PAPER: return paper;
    case VisualTheme.PINE: return PINE_COLORS[role] ?? classic;
    case VisualTheme.LILAC: return LILAC_COLORS[role] ?? classic;
    case VisualTheme.CLAY: return CLAY_COLORS[role] ?? classic;
    case VisualTheme.SKY: return SKY_COLORS[role] ?? classic;
    case VisualTheme.BERRY: return BERRY_COLORS[role] ?? classic;
    case VisualTheme.ORANGE: return ORANGE_COLORS[role] ?? classic;
    default: return classic;
  }
}
