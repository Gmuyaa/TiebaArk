

import { RawSearchPostEntry, RawSearchPostPage, RawSearchPostResponse } from '../api/RawSearchPost';
import { profilePortrait } from './PageDirectory';
import { portraitUrl } from './ThreadDetail';

interface RawAuthorPanel {
  no?: number | string;
  data?: RawAuthorPanelData;
}
interface RawAuthorPanelData {
  name?: string;
  portrait?: string;
}

/** 公开资料仅在账号名严格一致时补图，不能用昵称或模糊搜人结果认领身份。 */
export function searchAuthorAvatar(json: string, account: string): string {
  if (account.trim().length === 0) { return ''; }
  try {
    const raw: RawAuthorPanel = JSON.parse(json) as RawAuthorPanel;
    if (raw === null || (raw.no !== 0 && raw.no !== '0') || raw.data === undefined
      || raw.data === null || raw.data.name !== account || typeof raw.data.portrait !== 'string') { return ''; }
    return portraitUrl(profilePortrait(raw.data.portrait));
  } catch (_) { return ''; }
}

/**
 * 归一化吧内搜索范围：返回**要发给服务端的 `kw`**。
 * 空串 = 全站搜索（调用方据此**不发** `kw` 参数，而不是发一个空值）。
 */
export function searchScopeForum(forumName: string | undefined): string {
  if (forumName === undefined) {
    return '';
  }
  return forumName.trim();
}

/** 搜索框占位文案：全站是「搜索」，吧内写清在哪个吧里搜 */
export function searchPlaceholder(forumName: string | undefined): string {
  const scope: string = searchScopeForum(forumName);
  return scope.length === 0 ? '搜索' : `在「${scope}」吧内搜索`;
}

/** 结果页顶部的范围标签；全站搜索返回空串（= 不显示这一行） */
export function searchScopeLabel(forumName: string | undefined): string {
  const scope: string = searchScopeForum(forumName);
  return scope.length === 0 ? '' : `吧内搜索 · ${scope}`;
}

/** 还没输入关键词时的提示（吧内搜索进页面就是这一态） */
export function searchEmptyHint(forumName: string | undefined): string {
  const scope: string = searchScopeForum(forumName);
  return scope.length === 0 ? '输入关键词开始搜索' : `输入关键词，搜索「${scope}」吧内的帖子`;
}

/** 搜到 0 条时的文案；吧内搜索必须写明"是这个吧里没有"，不能被读成"全站没有" */
export function searchNoResultText(forumName: string | undefined, word: string): string {
  const scope: string = searchScopeForum(forumName);
  if (scope.length === 0) {
    return `没有找到与「${word}」相关的帖子`;
  }
  return `「${scope}」吧内没有找到与「${word}」相关的帖子`;
}

/** 两族官方表情前缀，与 `model/ThreadDetail.ets` 的 EMOJI_PREFIXES 同源（那边负责渲染） */
const EMOJI_CODE_PREFIXES: string[] = ['image_emoticon', 'shoubai_emoji_face_'];

/** 该端点的数字全部以字符串形式下发 */
function numStr(value: string | number | undefined): number {
  if (value === undefined) {
    return 0;
  }
  const parsed: number = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function str(value: string | undefined): string {
  return value === undefined ? '' : value;
}

/**
 * 从 `<img ...>` 标签体里取出表情编码；不是表情图就返回空串。
 *
 * `tag` 是尖括号之间的内容（不含尖括号）。只认官方两族表情的文件名——
 * 贴吧摘要里除表情外还可能出现普通图片，那些应当直接丢掉而不是当文字显示。
 */
function emojiCodeOfImgTag(tag: string): string {
  if (!tag.startsWith('img')) {
    return '';
  }
  const srcAt: number = tag.indexOf('src="');
  if (srcAt < 0) {
    return '';
  }
  const valueStart: number = srcAt + 5;
  const valueEnd: number = tag.indexOf('"', valueStart);
  const src: string = valueEnd < 0 ? tag.substring(valueStart) : tag.substring(valueStart, valueEnd);
  const slash: number = src.lastIndexOf('/');
  const file: string = slash < 0 ? src : src.substring(slash + 1);
  const dot: number = file.indexOf('.');
  const name: string = dot < 0 ? file : file.substring(0, dot);

  // 两族官方表情：image_emoticon / image_emoticon<N> / shoubai_emoji_face_<N>
  let suffix: string = '';
  if (name.startsWith('image_emoticon')) {
    suffix = name.substring('image_emoticon'.length);
  } else if (name.startsWith('shoubai_emoji_face_')) {
    suffix = name.substring('shoubai_emoji_face_'.length);
  } else {
    return '';
  }
  for (let i = 0; i < suffix.length; i++) {
    const ch: string = suffix[i];
    if (ch < '0' || ch > '9') {
      return '';
    }
  }
  return name;
}

/** 常见 HTML 实体。不追求完整实现，只覆盖摘要里实际会出现的几个 */
function decodeEntities(text: string): string {
  return text
    .replace(/&nbsp;/g, ' ')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, '\'')
    .replace(/&apos;/g, '\'')
    .replace(/&amp;/g, '&');
}

/**
 * 剥掉标签、还原表情编码。`keepEmoji` 为 false 时表情图也一并丢掉
 * （用于只能显示纯文字的位置，如标题）。
 *
 * 手写扫描而不是正则：标签可能跨多行、属性顺序不定，逐字符扫更好读也便于断言；
 * 不闭合的 `<` 按普通文字保留，宁可难看也不吞内容。
 */
function cleanHtml(raw: string, keepEmoji: boolean): string {
  const parts: string[] = [];
  let cursor: number = 0;
  while (cursor < raw.length) {
    const lt: number = raw.indexOf('<', cursor);
    if (lt < 0) {
      parts.push(raw.substring(cursor));
      break;
    }
    if (lt > cursor) {
      parts.push(raw.substring(cursor, lt));
    }
    const gt: number = raw.indexOf('>', lt);
    if (gt < 0) {
      parts.push(raw.substring(lt));
      break;
    }
    if (keepEmoji) {
      parts.push(emojiCodeOfImgTag(raw.substring(lt + 1, gt)));
    }
    cursor = gt + 1;
  }
  return decodeEntities(parts.join(''));
}

/** 摘要清洗：去掉标签，表情还原成 `image_emoticon<N>` 之类的编码，供片段解析器渲染 */
export function cleanSnippet(raw: string): string {
  return cleanHtml(raw, true);
}

/**
 * 丢掉已经变成普通文字的官方表情编码。
 *
 * 为什么需要：回复型结果没有标题，界面用**清洗后的摘要**顶替标题位（`displayTitle`），
 * 而标题位是纯文本渲染 —— 那里再出现 `image_emoticon25` 就是同一个"字面编码"问题。
 * 只删两族官方前缀的编码，其余文字原样保留。
 */
function dropEmojiCodes(text: string): string {
  const parts: string[] = [];
  let plainStart: number = 0;
  let cursor: number = 0;
  while (cursor < text.length) {
    let prefix: string = '';
    for (let i = 0; i < EMOJI_CODE_PREFIXES.length; i++) {
      if (text.startsWith(EMOJI_CODE_PREFIXES[i], cursor)) {
        prefix = EMOJI_CODE_PREFIXES[i];
        break;
      }
    }
    if (prefix.length === 0) {
      cursor++;
      continue;
    }
    let end: number = cursor + prefix.length;
    while (end < text.length && text[end] >= '0' && text[end] <= '9') {
      end++;
    }
    parts.push(text.substring(plainStart, cursor));
    cursor = end;
    plainStart = end;
  }
  parts.push(text.substring(plainStart));
  return parts.join('');
}

/** 标题清洗：只留文字（标题不做富文本渲染，留着编码反而会显示成字面量） */
export function cleanTitle(raw: string): string {
  return dropEmojiCodes(cleanHtml(raw, false));
}

/** 一条搜帖结果 */
export class SearchPostItem {
  tid: number = 0;
  pid: number = 0;
  /** 标题；回复型结果可能为空，界面用摘要顶替 */
  title: string = '';
  /** 服务端拼好的纯文本摘要 */
  snippet: string = '';
  /** 来源吧名 */
  forumName: string = '';
  authorName: string = '';
  /** 稳定账号名，保留与展示昵称的区别，用于公开资料精确反查。 */
  authorAccount: string = '';
  /** 毫秒时间戳（服务端给秒，转换时乘 1000） */
  timeMs: number = 0;

  /**
   * 界面展示用标题：标题为空（回复型结果）时用摘要顶替，绝不显示空行。
   *
   * 顶替时要再剥一次表情编码——标题位是纯文本渲染，直接把 `image_emoticon25`
   * 显示出来等于又回到"字面编码"的老问题。
   */
  displayTitle(): string {
    if (this.title.length > 0) {
      return this.title;
    }
    const fallback: string = cleanTitle(this.snippet);
    if (fallback.length > 0) {
      return fallback;
    }
    return '（无标题）';
  }
}

/** 一页搜帖结果 + 分页游标 */
export class SearchPostPage {
  items: SearchPostItem[] = [];
  /** 本结果的页码（请求时的 pn） */
  page: number = 1;
  hasMore: boolean = false;

  /** 追加下一页结果；按 tid+pid 去重，翻页时服务端偶发的重叠条目不会重复显示 */
  append(next: SearchPostPage): void {
    const seen: Set<string> = new Set<string>();
    for (const item of this.items) {
      seen.add(`${item.tid}-${item.pid}`);
    }
    for (const item of next.items) {
      const key: string = `${item.tid}-${item.pid}`;
      if (!seen.has(key)) {
        seen.add(key);
        this.items.push(item);
      }
    }
    if (next.page > this.page) {
      this.page = next.page;
    }
    this.hasMore = next.hasMore;
  }

  static fromRaw(raw: RawSearchPostResponse): SearchPostPage {
    const result: SearchPostPage = new SearchPostPage();
    // RawSearchPostPage 是 interface 不能 new；缺 page 字段时按空对象解析出默认值
    const emptyPage: RawSearchPostPage = {};
    const rawPage: RawSearchPostPage = raw.page === undefined ? emptyPage : raw.page;
    result.page = numStr(rawPage.current_page);
    result.hasMore = str(rawPage.has_more) === '1';
    const entries: RawSearchPostEntry[] = raw.post_list === undefined ? [] : raw.post_list;
    for (const entry of entries) {
      const item: SearchPostItem = new SearchPostItem();
      item.tid = numStr(entry.tid);
      item.pid = numStr(entry.pid);
      item.title = cleanTitle(str(entry.title));
      item.snippet = cleanSnippet(str(entry.content));
      item.forumName = str(entry.fname);
      item.timeMs = numStr(entry.time) * 1000;
      if (entry.author !== undefined) {
        item.authorAccount = str(entry.author.name).trim();
        // 端点实测只保证 name / name_show；展示优先 name_show（昵称），没有退 name
        item.authorName = str(entry.author.name_show).length > 0
          ? str(entry.author.name_show) : str(entry.author.name);
      }
      result.items.push(item);
    }
    return result;
  }
}
