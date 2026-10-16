/** 详情与楼中楼接口返回 JSON。楼层作者通过 author_id 关联顶层 user_list；字段解析与 protobuf 通道分开。 */

/** 富文本片段。type 决定后面哪些字段有效，实测取值见 model/ThreadDetail.ets */
export interface RawContentItem {
  /** type=10，当前 APK TbRichTextVoiceInfo 静态证据；真实语音帖待验收。 */
  voice_md5?: string;
  /** 语音时长毫秒；官方 JSON optInt 同时接受数字字符串。 */
  during_time?: number | string;
  /** 0=文本 1=链接 2=表情 3=图片 */
  type?: number;
  /**
   * 文本内容；链接的锚文本；表情的编码名（如 image_emoticon95）。
   * 实际响应里 type=0 的普通文本也可能内嵌一个或多个表情编码。
   */
  text?: string;
  /** type=1 时的目标地址 */
  link?: string;
  /** type=2 时的表情中文名（如"欢呼"） */
  c?: string;
  /** type=3 原图地址 */
  origin_src?: string;
  /** type=3 常规展示图（宽度 720） */
  cdn_src?: string;
  /** type=3 活动图，优先用这个 */
  cdn_src_active?: string;
  /** type=3 大图（宽度 960） */
  big_cdn_src?: string;
  /** type=3 尺寸，形如 "560,919" */
  bsize?: string;
  /** type=3 原图字节数 */
  origin_size?: number;
  /** type=3 图片 id */
  pic_id?: number;
  /** type=3 是否长图 */
  is_long_pic?: number;
  /** type=3 是否展示"查看原图" */
  show_original_btn?: number;
  is_native_app?: number;
}

/** 点赞信息 */
export interface RawAgree {
  agree_num?: number;
  disagree_num?: number;
  has_agree?: number;
  agree_type?: number;
  diff_agree_num?: number;
}

/** 吧务等级信息 */
export interface RawBazhuGrade {
  desc?: string;
  level?: string;
}

/** 用户信息。既用于详情页顶层 `user_list`，也用于楼中楼内联的 `author` */
export interface RawUser {
  id?: number;
  /** 用户名 */
  name?: string;
  /** 显示名（昵称）。实测常与 name 不同，展示优先用这个 */
  name_show?: string;
  /** 头像标识，需要拼成 URL（见 model/ThreadDetail.ets 的 portraitUrl） */
  portrait?: string;
  level_id?: number;
  level_name?: string;
  /** IP 归属地，如 "北京"；楼中楼里实测缺失 */
  ip_address?: string;
  gender?: number;
  is_bawu?: number;
  bawu_type?: string;
  /** 吧务头衔，desc 形如 "贴吧吧主吧吧主" */
  bazhu_grade?: RawBazhuGrade;
}

/** 详情页里的一个楼层 */
export interface RawPost {
  /** 楼层 id */
  id?: number;
  /** 楼层号。实测会跳号；热门序的部分回复不返回此字段 */
  floor?: number;
  /** 发帖时间（秒） */
  time?: number;
  title?: string;
  /** 富文本正文 */
  content?: RawContentItem[];
  /** 作者 uid，去 user_list 里查 */
  author_id?: number;
  /** 楼中楼条数。实测：非零也不代表本响应带 sub_post_list */
  sub_post_number?: number;
  agree?: RawAgree;
  is_fold?: number;
  fold_tip?: string;
  /** 实测本字段恒为 0，楼层可见性不能靠它判断 */
  is_post_visible?: number;
}

/** 楼中楼的一条回复（`/c/f/pb/floor` 的 subpost_list 元素） */
export interface RawSubPost {
  id?: number;
  time?: number;
  title?: string;
  content?: RawContentItem[];
  /** 实测恒为 0 */
  floor?: number;
  /** 内联作者对象，不是 author_id */
  author?: RawUser;
  agree?: RawAgree;
  is_giftpost?: number;
  is_author_view?: number;
}

/** 主题（楼主信息与标题在这里，不在 post_list 里） */
export interface RawThreadHead {
  /** 当前 APK ThreadData/VideoItemData 的 JSON video_info；真实视频帖待验收。 */
  video_info?: RawVideoInfo;
  id?: number;
  title?: string;
  /** 详情端点的帖子总条数，包含 1 楼主帖；转换为回复数时必须减 1 */
  reply_num?: number;
  agree_num?: number;
  /** 主题点赞状态读取 thread.agree，不能用首楼的 agree.has_agree 代替。 */
  agree?: RawAgree;
  /** 秒 */
  create_time?: number;
  /** 首楼 pid，实测等于 post_list[0].id */
  post_id?: number;
  author?: RawUser;
  is_excellent_thread?: number;
  is_membertop?: number;
  share_num?: number;
  collect_num?: number;
  /** 主题收藏状态以 collect_status 非零判断；collect_num 是累计计数，不表示当前收藏状态。 */
  collect_status?: number;
}

/** 当前 APK ThreadData.parseJson 的视频元数据；不能从 video_md5 猜下载地址。 */
export interface RawVideoInfo {
  video_url?: string;
  thumbnail_url?: string;
  video_md5?: string;
  video_duration?: number | string;
  video_width?: number | string;
  video_height?: number | string;
}

/** 详情页分页信息。`total_num` 是端点分页原始值，不得作为回复数或最大楼层展示。 */
export interface RawDetailPage {
  current_page?: number;
  page_size?: number;
  /** 实测小帖也会返回请求窗口值 30，不是可靠的楼层总数 */
  total_num?: number;
  total_page?: number;
  has_more?: number;
  has_prev?: number;
  req_num?: number;
  new_total_page?: number;
  offset?: number;
}

/** 通用吧信息（详情页也会带一份） */
export interface RawDetailForum {
  id?: number;
  name?: string;
  thread_num?: number;
  post_num?: number;
  member_num?: number;
  avatar?: string;
  first_class?: string;
}

/** `/c/f/pb/page` 响应 */
export interface RawThreadPage {
  error_code?: number;
  error_msg?: string;
  thread?: RawThreadHead;
  post_list?: RawPost[];
  user_list?: RawUser[];
  page?: RawDetailPage;
  forum?: RawDetailForum;
}

/** `/c/f/pb/floor` 响应的分页信息，字段名与详情页又不同 */
export interface RawSubPostPage {
  current_page?: number;
  page_size?: number;
  total_count?: number;
  total_page?: number;
}

/** `/c/f/pb/floor` 响应 */
export interface RawSubPostPageResponse {
  error_code?: number;
  error_msg?: string;
  /** 父楼层，会重复返回一次完整内容 */
  post?: RawPost;
  subpost_list?: RawSubPost[];
  /** 楼中楼总数 */
  subpost_num?: number;
  page?: RawSubPostPage;
  thread?: RawThreadHead;
}
