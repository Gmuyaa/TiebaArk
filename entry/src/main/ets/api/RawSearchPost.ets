/** 搜帖返回 JSON，数字字段可能为字符串；content 包含 HTML 与表情标记，不能直接作为纯文本展示。 */

/** 单条搜索结果的原始结构（只声明界面要用的字段） */
export interface RawSearchPostEntry {
  /** 主题 id，字符串形式的数字 */
  tid?: string;
  /** 楼层 id，字符串形式的数字 */
  pid?: string;
  /** 标题；回复型结果可能为空串 */
  title?: string;
  /** 摘要；**是 HTML 片段**，必须经 `cleanSnippet` 清洗（见文件头说明） */
  content?: string;
  /** 来源吧名 */
  fname?: string;
  /** 发布时间，秒级时间戳字符串 */
  time?: string;
  author?: RawSearchPostAuthor;
}

export interface RawSearchPostAuthor {
  name?: string;
  name_show?: string;
}

/** 分页信息（全部是字符串形式的数字/0|1） */
export interface RawSearchPostPage {
  current_page?: string;
  total_page?: string;
  has_more?: string;
}

/** 搜帖子响应信封 */
export interface RawSearchPostResponse {
  post_list?: RawSearchPostEntry[];
  page?: RawSearchPostPage;
  error_code?: number;
  error_msg?: string;
}
