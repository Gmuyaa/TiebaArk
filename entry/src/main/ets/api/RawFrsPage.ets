

export interface RawForum {
  is_like?: number | string;
  id?: number;
  name?: string;

  thread_num?: number;

  post_num?: number;

  member_num?: number;
  avatar?: string;
  first_class?: string;
  second_class?: string;
  slogan?: string;

  level_id?: number | string;
  level_name?: string;
  cur_score?: number | string;
  levelup_score?: number | string;
  is_exists?: number;

  theme_color?: RawForumThemeColor;
}

export interface RawForumThemeColor {
  day?: RawForumThemeVariant;
  night?: RawForumThemeVariant;
  dark?: RawForumThemeVariant;
}

export interface RawForumThemeVariant {

  font_color?: string;

  common_color?: string;
  dark_color?: string;
  light_color?: string;

  pattern_image?: string;
}

export interface RawPage {
  current_page?: number;
  page_size?: number;
  total_count?: number;
  total_page?: number;

  has_more?: number;
  has_prev?: number;
}

export interface RawFrsTab {
  tab_id?: number;
  tab_name?: string;
  tab_type?: number;
  net_tab_type?: number;
  tab_url?: string;
}

export interface RawAbstractItem {

  type?: number;

  text?: string;
}

export interface RawThread {
  id?: number;
  tid?: number;
  fid?: number;

  nid?: string;
  title?: string;
  author_id?: number;

  reply_num?: number;

  comment_num?: number;
  view_num?: number;
  share_num?: number;

  agree?: RawFeedAgree;

  last_time?: string;

  last_time_int?: number;

  create_time?: number;

  is_top?: number;
  is_good?: number;

  is_excellent_thread?: number;
  is_notice?: number;
  is_bakan?: number;
  is_membertop?: number;
  is_activity?: number;
  is_vote?: number;
  is_highlight?: number;

  is_partial_visible?: number;
  abstract?: RawAbstractItem[];
  rich_abstract?: RawAbstractItem[];
  thread_share_link?: string;
  forum_info?: RawForum;
}

export interface RawListUser {
  id?: number;
  name?: string;
  name_show?: string;
  portrait?: string;
}

export interface RawFrsPage {

  error_code?: number;
  error_msg?: string;
  forum?: RawForum;
  sign_in_info?: RawForumSignInfo;
  page?: RawPage;
  thread_list?: RawThread[];
  user_list?: RawListUser[];

  page_data?: RawFeedPageData;
  frs_main_tab_list?: RawFrsTab[];
  frs_tab_default?: number;
  page_data_tab_id?: number;
}

export interface RawForumSignInfo {
  user_info?: RawForumSignUser;
}
export interface RawForumSignUser {
  is_sign_in?: number | string;
  miss_sign_num?: number | string;
  cont_sign_num?: number | string;
  cout_total_sign_num?: number | string;
}

export interface RawFeedTextNode {

  type?: number;

  text?: RawFeedTextInner;

  text_info?: RawFeedTextInfo;
}

export interface RawFeedTextInner {
  text?: string;
  priority?: number;
  can_degrade?: number;
}

export interface RawFeedTextInfo {

  text?: string;
}

export interface RawFeedTextBlock {
  data?: RawFeedTextNode[];
}

export interface RawFeedImage {
  img_url?: string;
  shape_type?: number;
  pendant_url?: string;
  corner_url?: string;
}

export interface RawFeedHead {

  main_data?: RawFeedTextNode[];

  extra_data?: RawFeedTextNode[];
  image_data?: RawFeedImage;
}

export interface RawFeedPic {
  small_pic_url?: string;
  big_pic_url?: string;
  origin_pic_url?: string;
  width?: number;
  height?: number;
  is_long_pic?: number;
}

export interface RawFeedPicBlock {
  pics?: RawFeedPic[];
  is_slide?: number;
  text?: string;
}

export interface RawFeedAgree {
  agree_num?: number;
  has_agree?: number;
}

export interface RawFeedSocial {
  tid?: number;
  fid?: number;

  first_post_id?: number;

  comment_num?: number;
  share_num?: number;
  agree?: RawFeedAgree;
  is_store?: number;
}

export interface RawFeedComponent {

  component?: string;
  feed_head?: RawFeedHead;
  feed_title?: RawFeedTextBlock;
  feed_abstract?: RawFeedTextBlock;
  feed_pic?: RawFeedPicBlock;
  feed_social?: RawFeedSocial;
}

export interface RawFeedBizItem {
  key?: string;
  value?: string;
}

export interface RawFeedBizMap {
  forum_avatar?: string;
  forum_name?: string;
  create_time?: string;
  view_num?: string;
  thread_id?: string;
}

export interface RawFeed {

  schema?: string;
  components?: RawFeedComponent[];

  business_info?: RawFeedBizItem[];

  business_info_map?: RawFeedBizMap;
}

export interface RawFeedItem {

  layout?: string;
  feed?: RawFeed;
}

export interface RawFeedPageData {
  feed_list?: RawFeedItem[];
}
