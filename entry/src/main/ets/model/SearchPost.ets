

import { RawSearchPostEntry, RawSearchPostPage, RawSearchPostResponse } from '../api/RawSearchPost';

export function searchScopeForum(forumName: string | undefined): string {
  if (forumName === undefined) {
    return '';
  }
  return forumName.trim();
}

export function searchPlaceholder(forumName: string | undefined): string {
  const scope: string = searchScopeForum(forumName);
  return scope.length === 0 ? '搜索' : `在「${scope}」吧内搜索`;
}

export function searchScopeLabel(forumName: string | undefined): string {
  const scope: string = searchScopeForum(forumName);
  return scope.length === 0 ? '' : `吧内搜索 · ${scope}`;
}

export function searchEmptyHint(forumName: string | undefined): string {
  const scope: string = searchScopeForum(forumName);
  return scope.length === 0 ? '输入关键词开始搜索' : `输入关键词，搜索「${scope}」吧内的帖子`;
}

export function searchNoResultText(forumName: string | undefined, word: string): string {
  const scope: string = searchScopeForum(forumName);
  if (scope.length === 0) {
    return `没有找到与「${word}」相关的帖子`;
  }
  return `「${scope}」吧内没有找到与「${word}」相关的帖子`;
}

const EMOJI_CODE_PREFIXES: string[] = ['image_emoticon', 'shoubai_emoji_face_'];

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

export function cleanSnippet(raw: string): string {
  return cleanHtml(raw, true);
}

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

export function cleanTitle(raw: string): string {
  return dropEmojiCodes(cleanHtml(raw, false));
}

export class SearchPostItem {
  tid: number = 0;
  pid: number = 0;

  title: string = '';

  snippet: string = '';

  forumName: string = '';
  authorName: string = '';

  timeMs: number = 0;

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

export class SearchPostPage {
  items: SearchPostItem[] = [];

  page: number = 1;
  hasMore: boolean = false;

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

        item.authorName = str(entry.author.name_show).length > 0
          ? str(entry.author.name_show) : str(entry.author.name);
      }
      result.items.push(item);
    }
    return result;
  }
}
