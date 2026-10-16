/** 关注吧列表的原始响应。端点参考 aiotieba get_self_follow_forums（Unlicense）；无签名，使用 Cookie 与 tbs。like_forum 位于顶层，数字字段由模型层格式化。 */

/** 一条关注吧（只声明界面要用的字段） */
export interface RawFollowForum {
  forum_id?: number;
  forum_name?: string;
  /** 用户在该吧的等级 */
  level_id?: number;
  /** 今天是否已签到（0/1） */
  is_sign?: number | string | boolean;
  /** 吧头像 URL */
  avatar?: string;
  /** 关注数，原始数字 */
  member_count?: number;
  /** 帖子数（主题数），原始数字 */
  thread_num?: number;
}

export interface RawForumGuideData {
  like_forum?: RawFollowForum[];
  like_forum_has_more?: number | string | boolean;
}

export interface RawForumGuideResponse {
  error_code?: number | string;
  error_msg?: string;
  like_forum?: RawFollowForum[];
  like_forum_has_more?: number | string | boolean;
  /** 兼容 data 包一层的情况（实测在顶层，这里只作多余兜底） */
  data?: RawForumGuideData;
}
