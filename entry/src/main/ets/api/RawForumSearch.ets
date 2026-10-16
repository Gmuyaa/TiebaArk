/* 协议参考：lumina37/aiotieba（Unlicense）。 */

export interface RawForumMatch {

  forum_id?: number;

  forum_name?: string;

  forum_name_show?: string;

  avatar?: string;

  post_num?: string | number;

  concern_num?: string | number;

  slogan?: string;
  intro?: string;

  is_official_forum?: number;
}

export interface RawForumSearchData {
  pn?: number;
  has_more?: number;
  exactMatch?: RawForumMatch;
  fuzzyMatch?: RawForumMatch[];
}

export interface RawForumSearchResponse {

  no?: number;
  error?: string;
  data?: RawForumSearchData;
}
