/** 搜帖返回 JSON，数字字段可能为字符串；content 包含 HTML 与表情标记，不能直接作为纯文本展示。 */

export interface RawSearchPostEntry {
  tid?: string;
  pid?: string;
  /** 回复型结果可能为空串 */
  title?: string;
  /** **是 HTML 片段**，必须经 `cleanSnippet` 清洗 */
  content?: string;
  fname?: string;
  /** 秒级时间戳 */
  time?: string;
  author?: RawSearchPostAuthor;
}

export interface RawSearchPostAuthor {
  /** 可能下发昵称，不能视作稳定账号名或用户身份。 */
  name?: string;
  name_show?: string;
}

/** 分页字段都是字符串形式的数字 */
export interface RawSearchPostPage {
  current_page?: string;
  total_page?: string;
  has_more?: string;
}

export interface RawSearchPostResponse {
  post_list?: RawSearchPostEntry[];
  page?: RawSearchPostPage;
  error_code?: number;
  error_msg?: string;
}
