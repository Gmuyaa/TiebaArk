/** 网页搜吧的原始响应，业务码在 `no`（客户端端点则叫 `error_code`）。协议与签名算法参考 lumina37/aiotieba（Unlicense）。 */

export interface RawForumMatch {
  forum_id?: number;
  /** 请求侧称 kw，进吧用这个名字 */
  forum_name?: string;
  forum_name_show?: string;
  avatar?: string;
  /** 服务端可能下发格式化展示串（"31W"），解析要兼容数字 */
  post_num?: string | number;
  concern_num?: string | number;
  /** 精确匹配才有 */
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
