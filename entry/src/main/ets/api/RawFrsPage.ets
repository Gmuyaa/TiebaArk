/** frs/page 同时支持顶层 thread_list 与 page_data.feed_list。旧格式回帖数为 reply_num；解析时按响应形态读取字段。 */

import { RawVideoInfo } from './RawThreadPage';

/** 吧信息。顶层 `forum` 与每个帖子里的 `forum_info` 是同一套结构。 */
export interface RawForum {
  is_like?: number | string;
  id?: number;
  name?: string;
  /** 主题数 */
  thread_num?: number;
  /** 帖子数（含回复） */
  post_num?: number;
  /** 关注人数 */
  member_num?: number;
  avatar?: string;
  first_class?: string;
  second_class?: string;
  slogan?: string;
  /** 本人在该吧的等级与经验；官方 LikeReturnData.parserJson。 */
  level_id?: number | string;
  level_name?: string;
  cur_score?: number | string;
  levelup_score?: number | string;
  is_exists?: number;

  theme_color?: RawForumThemeColor;
}

/** 吧主题色按 day、night、dark 分组下发，包含 pattern_image。 */
export interface RawForumThemeColor {
  day?: RawForumThemeVariant;
  night?: RawForumThemeVariant;
  dark?: RawForumThemeVariant;
}

/** `theme_color` 里的一套色值。色值均为 **6 位十六进制、不带 `#`**（实测 `"3F2F0F"`） */
export interface RawForumThemeVariant {
  /** 该档的文字色，如 `"D39923"` */
  font_color?: string;
  /** 吧主色 —— Hero 底色由它派生（`common/appearance/ForumHeroStyle.ets`） */
  common_color?: string;
  dark_color?: string;
  light_color?: string;
  /**
   * 吧页头部**底纹图**。实测 1080×600 的 PNG（`Content-Type` 与文件头都是 PNG，
   * 但 URL 与响应头写的扩展名是 `.jpg`，别按扩展名判断）。
   *
   * ⚠️ 内容是**极淡的浅色纹理**，不是可直接当深色头部背景的照片：
   * 必须叠在主题色暗化蒙层之下使用（见 `ForumHeroStyle.ets` 的 scrim 说明）。
   */
  pattern_image?: string;
}

/** 分页信息 */
export interface RawPage {
  current_page?: number;
  page_size?: number;
  total_count?: number;
  total_page?: number;
  /** 0 / 1 */
  has_more?: number;
  has_prev?: number;
}

/** FRS 顶部分类导航。仅本地列表型 tab 由 model 层接入。 */
export interface RawFrsTab {
  tab_id?: number;
  tab_name?: string;
  tab_type?: number;
  net_tab_type?: number;
  tab_url?: string;
}

/** 摘要里的富文本片段（`abstract` / `rich_abstract` 的元素） */
export interface RawAbstractItem {
  /** 0 = 纯文本 */
  type?: number;
  /** 实测可能在普通文字中直接内嵌 `image_emoticon<N>`，并不总是独立富文本节点 */
  text?: string;
}

/** 列表里的单条主题 */
export interface RawThread {
  video_info?: RawVideoInfo;
  thread_type?: number | string;
  author?: RawListUser;
  id?: number;
  tid?: number;
  fid?: number;
  /** 新版帖子标识，字符串形式 */
  nid?: string;
  title?: string;
  author_id?: number;
  /** 真实回帖数。三个吧 × 两个端点交叉实测均为真值 */
  reply_num?: number;
  /** 本端点上实测恒为 0（其它端点可能有值），别拿它当列表页的回帖数 */
  comment_num?: number;
  view_num?: number;
  share_num?: number;
  /** 主题点赞数来自 agree 对象。 */
  agree?: RawFeedAgree;
  /** 服务端给的相对时间，如 "4-17" */
  last_time?: string;
  /** 绝对时间戳（秒） */
  last_time_int?: number;
  /** 发帖时间戳（秒） */
  create_time?: number;
  /** 以下标志位均为 0 / 1 */
  /** 置顶。实测**只有这个字段**能标识置顶帖 */
  is_top?: number;
  is_good?: number;
  /** 另一个"精品"候选字段。实测暂无非零样本，与 is_good 一起认 */
  is_excellent_thread?: number;
  is_notice?: number;
  is_bakan?: number;
  is_membertop?: number;
  is_activity?: number;
  is_vote?: number;
  is_highlight?: number;
  /** 1 表示内容被折叠，需要单独请求才能看全 */
  is_partial_visible?: number;
  abstract?: RawAbstractItem[];
  rich_abstract?: RawAbstractItem[];
  thread_share_link?: string;
  forum_info?: RawForum;
}

/**
 * 旧格式列表响应顶层的作者表。
 * `thread_list[].author_id` 通过 id 关联到这里，昵称和头像不在帖子对象本身。
 */
export interface RawListUser {
  id?: number;
  name?: string;
  name_show?: string;
  portrait?: string;
}

/** 顶层响应 */
export interface RawFrsPage {
  /** 业务错误码。0 表示成功；110001 表示签名/参数校验失败 */
  error_code?: number;
  error_msg?: string;
  forum?: RawForum;
  sign_in_info?: RawForumSignInfo;
  page?: RawPage;
  thread_list?: RawThread[];
  user_list?: RawListUser[];
  /** 新版列表结构。与 `thread_list` 二选一，见下 */
  page_data?: RawFeedPageData;
  frs_main_tab_list?: RawFrsTab[];
  frs_tab_default?: number;
  page_data_tab_id?: number;
}

/** 官方 FRS SignInfo.user_info / SignUser；缺失不等于未签到。 */
export interface RawForumSignInfo {
  user_info?: RawForumSignUser;
}
export interface RawForumSignUser {
  is_sign_in?: number | string;
  miss_sign_num?: number | string;
  cont_sign_num?: number | string;
  cout_total_sign_num?: number | string;
}

/** 新版帖子列表为 page_data.feed_list 混合卡片流；只解析 layout=feed 的帖子，内容分布在 head、title、abstract 与 business_info 中。 */

/** 文本字段的嵌套形态不同：head 使用 text.text，title 与 abstract 使用 text_info.text。 */
export interface RawFeedTextNode {
  /** 实测 1 = 文本 */
  type?: number;
  /** `feed_head.main_data` / `extra_data` 用的形式 */
  text?: RawFeedTextInner;
  /** `feed_title` / `feed_abstract` 用的形式 */
  text_info?: RawFeedTextInfo;
}

/** 扁平文本的实际载荷。实测形如 `{"text":"DongLi_1z","priority":8,"can_degrade":1}` */
export interface RawFeedTextInner {
  text?: string;
  priority?: number;
  can_degrade?: number;
}

export interface RawFeedTextInfo {
  /** `feed_abstract` 的摘要文字可能直接内嵌 `image_emoticon<N>` */
  text?: string;
}

/** `feed_title` / `feed_abstract` 的组件体 */
export interface RawFeedTextBlock {
  data?: RawFeedTextNode[];
}

/** 头像块 */
export interface RawFeedImage {
  img_url?: string;
  shape_type?: number;
  pendant_url?: string;
  corner_url?: string;
}

/** `feed_head` 的组件体 */
export interface RawFeedHead {
  /** [0] 是昵称（读 text.text），后续项是标签图标 */
  main_data?: RawFeedTextNode[];
  /** [0] 是发帖时间戳的**字符串**形式（秒），可能缺失 */
  extra_data?: RawFeedTextNode[];
  image_data?: RawFeedImage;
}

/** 图片项 */
export interface RawFeedPic {
  small_pic_url?: string;
  big_pic_url?: string;
  origin_pic_url?: string;
  width?: number;
  height?: number;
  is_long_pic?: number;
}

/** `feed_pic` 的组件体 */
export interface RawFeedPicBlock {
  pics?: RawFeedPic[];
  is_slide?: number;
  text?: string;
}

export interface RawFeedAgree {
  agree_num?: number;
  has_agree?: number;
}

/** `feed_social` 的组件体。回帖数在这里叫 `comment_num`，与旧格式相反 */
export interface RawFeedSocial {
  tid?: number;
  fid?: number;
  /** 首楼 pid */
  first_post_id?: number;
  /** **真实回帖数**（新版） */
  comment_num?: number;
  share_num?: number;
  agree?: RawFeedAgree;
  is_store?: number;
}

/** 卡片里的一个组件 */
export interface RawFeedComponent {
  feed_video?: RawFeedVideo;
  /** 组件名：feed_head / feed_title / feed_abstract / feed_pic / feed_social … */
  component?: string;
  feed_head?: RawFeedHead;
  feed_title?: RawFeedTextBlock;
  feed_abstract?: RawFeedTextBlock;
  feed_pic?: RawFeedPicBlock;
  feed_social?: RawFeedSocial;
}

export interface RawFeedVideo { video_info?: RawFeedVideoInfo; }
export interface RawFeedVideoInfo {
  url?: string;
  duration?: number | string;
  width?: number | string;
  height?: number | string;
  thumbnail?: RawFeedThumbnail;
}
export interface RawFeedThumbnail { url?: string; }

/** 固定APK GeneralTabList.DataRes 与匿名只读响应交叉确认。 */
export interface RawGeneralTabList {
  general_list?: RawThread[];
  user_list?: RawListUser[];
  has_more?: number | string;
  sort_type?: number | string;
}

export interface RawFeedBizItem {
  key?: string;
  value?: string;
}

/** business_info_map 为卡片业务信息的对象形态，forum_avatar 为完整吧头像 URL；数组形态使用 business_info 键值对。 */
export interface RawFeedBizMap {
  forum_avatar?: string;
  forum_name?: string;
  create_time?: string;
  view_num?: string;
  thread_id?: string;
}

/** 帖子卡片体 */
export interface RawFeed {
  /** 跳转链接，tid 也藏在里面（编码后），仅作兜底 */
  schema?: string;
  components?: RawFeedComponent[];
  /** 浏览数等统计：键值对数组，见 RawFeedBizItem 的说明 */
  business_info?: RawFeedBizItem[];
  /** 同一份统计的对象形态（PC 网页）；见 RawFeedBizMap */
  business_info_map?: RawFeedBizMap;
}

/** 卡片流里的一项。`layout` 决定读哪个字段 */
export interface RawFeedItem {
  /** "feed" = 帖子卡；"hot_topic_card" = 热话题卡（忽略） */
  layout?: string;
  feed?: RawFeed;
}

/** 新版列表容器 */
export interface RawFeedPageData {
  feed_list?: RawFeedItem[];
}
