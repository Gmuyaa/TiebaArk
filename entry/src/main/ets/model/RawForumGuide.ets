/** 关注吧列表的原始响应。端点参考 aiotieba get_self_follow_forums（Unlicense）；无签名，使用 Cookie 与 tbs。like_forum 位于顶层，数字字段由模型层格式化。 */

export interface RawFollowForum {
  forum_id?: number;
  forum_name?: string;
  level_id?: number;
  is_sign?: number | string | boolean;
  avatar?: string;
  member_count?: number;
  /** 主题数 */
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
  /** `data` 包一层：实际在顶层，但 `FollowForum.fromRaw` 仍读这个字段兜底 —— 两处要一起删，删前先做一次真机 raw 取证 */
  data?: RawForumGuideData;
}
