/** 网页搜吧的原始响应，业务码为 no；exactMatch 可缺省，fuzzyMatch 为列表。展示计数字段已格式化，*_ori 为原始数字。签名算法与协议参考 lumina37/aiotieba（Unlicense）。 */

/** 一条吧匹配结果（精确/模糊共用；只声明界面要用的字段） */
export interface RawForumMatch {
  /** 吧 id，数字 */
  forum_id?: number;
  /** 吧名（kw，进吧用这个） */
  forum_name?: string;
  /** 展示名（与 forum_name 通常同值） */
  forum_name_show?: string;
  /** 吧头像 URL */
  avatar?: string;
  /** 帖子数，服务端格式化展示串（"31W"）或数字 */
  post_num?: string | number;
  /** 关注数，同上 */
  concern_num?: string | number;
  /** 吧简介（精确匹配才有，模糊匹配可能无） */
  slogan?: string;
  intro?: string;
  /** 是否官方吧，0/1 */
  is_official_forum?: number;
}

export interface RawForumSearchData {
  pn?: number;
  has_more?: number;
  exactMatch?: RawForumMatch;
  fuzzyMatch?: RawForumMatch[];
}

export interface RawForumSearchResponse {
  /** 业务码：0 成功（注意与客户端端点的 error_code 命名不同） */
  no?: number;
  error?: string;
  data?: RawForumSearchData;
}
