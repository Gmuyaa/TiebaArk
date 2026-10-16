/**
 * 搜吧（web 端 `/mo/q/search/forum`）的领域模型。
 *
 * 服务端把结果分成 `exactMatch`（精确匹配吧）与 `fuzzyMatch[]`（模糊匹配列表），
 * 界面按"精确在前、模糊随后"合并成一张列表；按 forum_id 去重（精确吧常同时出现在模糊列表）。
 * 关注/帖子数直接用服务端格式化好的展示串（"2W"/"31W"），自己再做数字格式化属于重复劳动。
 */

import { RawForumMatch, RawForumSearchResponse } from '../api/RawForumSearch';

function numOrZero(value: number | undefined): number {
  return value === undefined ? 0 : value;
}

function displayStr(value: string | number | undefined): string {
  return value === undefined ? '' : String(value);
}

function text(value: string | undefined): string {
  return value === undefined ? '' : value;
}

/** 一条吧搜索结果 */
export class ForumSearchItem {
  forumId: number = 0;
  /** 吧名（kw，进吧用这个） */
  forumName: string = '';
  /** 展示名 */
  forumNameShow: string = '';
  /** 吧头像 URL */
  avatar: string = '';
  /** 关注数展示串（服务端格式化，如 "2W"） */
  concernNum: string = '';
  /** 帖子数展示串（如 "31W"） */
  postNum: string = '';
  /** 吧简介（模糊匹配结果可能为空） */
  slogan: string = '';
  isOfficial: boolean = false;

  displayName(): string {
    return this.forumNameShow.length > 0 ? this.forumNameShow : this.forumName;
  }

  /** 头像拉不到时界面退占位图；吧名缺失的结果没有意义，进吧跳转会用它当 kw */
  usable(): boolean {
    return this.forumName.length > 0;
  }
}

/** 一页吧搜索结果 + 分页游标 */
export class ForumSearchPage {
  items: ForumSearchItem[] = [];
  /** 本结果的页码（请求时的 pn） */
  page: number = 1;
  hasMore: boolean = false;

  /** 追加下一页；按 forum_id 去重 */
  append(next: ForumSearchPage): void {
    const seen: Set<number> = new Set<number>();
    for (const item of this.items) {
      seen.add(item.forumId);
    }
    for (const item of next.items) {
      if (item.forumId > 0 && seen.has(item.forumId)) {
        continue;
      }
      seen.add(item.forumId);
      this.items.push(item);
    }
    if (next.page > this.page) {
      this.page = next.page;
    }
    this.hasMore = next.hasMore;
  }

  static fromRaw(raw: RawForumSearchResponse): ForumSearchPage {
    const result: ForumSearchPage = new ForumSearchPage();
    const data = raw.data;
    if (data === undefined) {
      return result;
    }
    result.page = numOrZero(data.pn) > 0 ? numOrZero(data.pn) : 1;
    result.hasMore = data.has_more === 1;

    // 精确在前，模糊随后；forum_id 去重（精确吧常重复出现在模糊列表）
    const matches: RawForumMatch[] = [];
    if (data.exactMatch !== undefined && data.exactMatch !== null) {
      matches.push(data.exactMatch);
    }
    if (data.fuzzyMatch !== undefined && data.fuzzyMatch !== null) {
      for (const m of data.fuzzyMatch) {
        matches.push(m);
      }
    }
    const seen: Set<number> = new Set<number>();
    for (const m of matches) {
      const item: ForumSearchItem = ForumSearchPage.fromMatch(m);
      if (!item.usable() || (item.forumId > 0 && seen.has(item.forumId))) {
        continue;
      }
      seen.add(item.forumId);
      result.items.push(item);
    }
    return result;
  }

  private static fromMatch(raw: RawForumMatch): ForumSearchItem {
    const item: ForumSearchItem = new ForumSearchItem();
    item.forumId = numOrZero(raw.forum_id);
    item.forumName = text(raw.forum_name);
    item.forumNameShow = text(raw.forum_name_show);
    item.avatar = text(raw.avatar);
    item.concernNum = displayStr(raw.concern_num);
    item.postNum = displayStr(raw.post_num);
    // slogan 缺省时退 intro（两个字段语义相同，实测精确匹配有 slogan、部分模糊结果只有 intro）
    item.slogan = text(raw.slogan).length > 0 ? text(raw.slogan) : text(raw.intro);
    item.isOfficial = raw.is_official_forum === 1;
    return item;
  }
}
