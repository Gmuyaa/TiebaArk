/* 协议参考：lumina37/aiotieba（Unlicense）。 */

export interface RawFollowForum {
  forum_id?: number;
  forum_name?: string;

  level_id?: number;

  is_sign?: number | string | boolean;

  avatar?: string;

  member_count?: number;

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

  data?: RawForumGuideData;
}
