

export interface RawContentItem {

  voice_md5?: string;

  during_time?: number | string;

  type?: number;

  text?: string;

  link?: string;

  c?: string;

  origin_src?: string;

  cdn_src?: string;

  cdn_src_active?: string;

  big_cdn_src?: string;

  bsize?: string;

  origin_size?: number;

  pic_id?: number;

  is_long_pic?: number;

  show_original_btn?: number;
  is_native_app?: number;
}

export interface RawAgree {
  agree_num?: number;
  disagree_num?: number;
  has_agree?: number;
  agree_type?: number;
  diff_agree_num?: number;
}

export interface RawBazhuGrade {
  desc?: string;
  level?: string;
}

export interface RawUser {
  id?: number;

  name?: string;

  name_show?: string;

  portrait?: string;
  level_id?: number;
  level_name?: string;

  ip_address?: string;
  gender?: number;
  is_bawu?: number;
  bawu_type?: string;

  bazhu_grade?: RawBazhuGrade;
}

export interface RawPost {

  id?: number;

  floor?: number;

  time?: number;
  title?: string;

  content?: RawContentItem[];

  author_id?: number;

  sub_post_number?: number;
  agree?: RawAgree;
  is_fold?: number;
  fold_tip?: string;

  is_post_visible?: number;
}

export interface RawSubPost {
  id?: number;
  time?: number;
  title?: string;
  content?: RawContentItem[];

  floor?: number;

  author?: RawUser;
  agree?: RawAgree;
  is_giftpost?: number;
  is_author_view?: number;
}

export interface RawThreadHead {

  video_info?: RawVideoInfo;
  id?: number;
  title?: string;

  reply_num?: number;
  agree_num?: number;

  agree?: RawAgree;

  create_time?: number;

  post_id?: number;
  author?: RawUser;
  is_excellent_thread?: number;
  is_membertop?: number;
  share_num?: number;
  collect_num?: number;

  collect_status?: number;
}

export interface RawVideoInfo {
  video_url?: string;
  thumbnail_url?: string;
  video_md5?: string;
  video_duration?: number | string;
  video_width?: number | string;
  video_height?: number | string;
}

export interface RawDetailPage {
  current_page?: number;
  page_size?: number;

  total_num?: number;
  total_page?: number;
  has_more?: number;
  has_prev?: number;
  req_num?: number;
  new_total_page?: number;
  offset?: number;
}

export interface RawDetailForum {
  id?: number;
  name?: string;
  thread_num?: number;
  post_num?: number;
  member_num?: number;
  avatar?: string;
  first_class?: string;
}

export interface RawThreadPage {
  error_code?: number;
  error_msg?: string;
  thread?: RawThreadHead;
  post_list?: RawPost[];
  user_list?: RawUser[];
  page?: RawDetailPage;
  forum?: RawDetailForum;
}

export interface RawSubPostPage {
  current_page?: number;
  page_size?: number;
  total_count?: number;
  total_page?: number;
}

export interface RawSubPostPageResponse {
  error_code?: number;
  error_msg?: string;

  post?: RawPost;
  subpost_list?: RawSubPost[];

  subpost_num?: number;
  page?: RawSubPostPage;
  thread?: RawThreadHead;
}
