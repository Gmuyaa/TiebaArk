

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

export class ForumSearchItem {
  forumId: number = 0;

  forumName: string = '';

  forumNameShow: string = '';

  avatar: string = '';

  concernNum: string = '';

  postNum: string = '';

  slogan: string = '';
  isOfficial: boolean = false;

  displayName(): string {
    return this.forumNameShow.length > 0 ? this.forumNameShow : this.forumName;
  }

  usable(): boolean {
    return this.forumName.length > 0;
  }
}

export class ForumSearchPage {
  items: ForumSearchItem[] = [];

  page: number = 1;
  hasMore: boolean = false;

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

    item.slogan = text(raw.slogan).length > 0 ? text(raw.slogan) : text(raw.intro);
    item.isOfficial = raw.is_official_forum === 1;
    return item;
  }
}
