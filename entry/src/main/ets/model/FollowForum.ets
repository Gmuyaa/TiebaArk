/* 协议参考：lumina37/aiotieba（Unlicense）。 */

import { RawFollowForum, RawForumGuideResponse } from '../api/RawForumGuide';
import { formatCount } from './UserProfile';

function numOrZero(value: number | undefined): number {
  return value === undefined ? 0 : value;
}

function text(value: string | undefined): string {
  return value === undefined ? '' : value;
}

function truthy(value: number | string | boolean | undefined): boolean {
  if (value === undefined || value === null) {
    return false;
  }
  if (typeof value === 'boolean') {
    return value;
  }
  if (typeof value === 'number') {
    return value !== 0;
  }
  return value === '1' || value === 'true';
}

function displayCount(value: string | number | undefined): string {
  if (value === undefined) {
    return '';
  }
  if (typeof value === 'number') {
    return formatCount(value);
  }
  return value;
}

export class FollowForumItem {
  fid: number = 0;

  fname: string = '';

  level: number = 0;

  isSigned: boolean = false;

  signKnown: boolean = false;

  avatar: string = '';

  concernNum: string = '';

  postNum: string = '';

  levelName: string = '';
  currentScore: number = -1;
  nextScore: number = -1;
  experienceError: string = '';
  continuousCount: number = -1;
  totalCount: number = -1;

  static copy(source: FollowForumItem): FollowForumItem {
    const item: FollowForumItem = new FollowForumItem();
    item.fid = source.fid; item.fname = source.fname; item.level = source.level;
    item.isSigned = source.isSigned; item.signKnown = source.signKnown;
    item.avatar = source.avatar; item.concernNum = source.concernNum; item.postNum = source.postNum;
    item.levelName = source.levelName; item.currentScore = source.currentScore;
    item.nextScore = source.nextScore; item.experienceError = source.experienceError;
    item.continuousCount = source.continuousCount; item.totalCount = source.totalCount;
    return item;
  }

  usable(): boolean {
    return this.fname.length > 0;
  }
}

export class FollowForumList {
  items: FollowForumItem[] = [];
  hasMore: boolean = false;

  static fromRaw(raw: RawForumGuideResponse): FollowForumList {
    const result: FollowForumList = new FollowForumList();
    /* 协议参考：lumina37/aiotieba（Unlicense）。 */
    let list: RawFollowForum[] | undefined = raw.like_forum;
    let hasMore: number | string | boolean | undefined = raw.like_forum_has_more;
    if (list === undefined && raw.data !== undefined) {
      list = raw.data.like_forum;
      hasMore = raw.data.like_forum_has_more;
    }
    if (list !== undefined) {
      for (const entry of list) {
        const item: FollowForumItem = FollowForumList.fromEntry(entry);
        if (item.usable()) {
          result.items.push(item);
        }
      }
    }
    result.hasMore = truthy(hasMore);
    return result;
  }

  private static fromEntry(raw: RawFollowForum): FollowForumItem {
    const item: FollowForumItem = new FollowForumItem();
    item.fid = numOrZero(raw.forum_id);
    item.fname = text(raw.forum_name);
    item.level = numOrZero(raw.level_id);
    item.isSigned = truthy(raw.is_sign);
    item.signKnown = raw.is_sign === 0 || raw.is_sign === 1 || raw.is_sign === '0' ||
      raw.is_sign === '1' || raw.is_sign === true || raw.is_sign === false;

    item.avatar = text(raw.avatar);
    item.concernNum = displayCount(raw.member_count);
    item.postNum = displayCount(raw.thread_num);
    return item;
  }
}
