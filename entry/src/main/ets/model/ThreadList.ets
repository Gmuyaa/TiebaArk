

import {
  RawAbstractItem, RawFeed, RawFeedBizItem, RawFeedBizMap, RawFeedComponent, RawFeedHead, RawFeedItem,
  RawFeedPic, RawFeedSocial, RawFeedTextBlock, RawFeedTextInner, RawForum, RawForumThemeColor,
  RawForumThemeVariant, RawFrsPage, RawFrsTab, RawListUser, RawPage, RawThread
} from '../api/RawFrsPage';

import { rememberFeedImage } from './HomeFeedPresentation';

import { putForumAvatar } from './ForumAvatarStore';
import { normalizeForumColor } from '../common/appearance/ForumHeroStyle';

function flag(value: number | undefined): boolean {
  return value === 1;
}

function num(value: number | undefined): number {
  return value === undefined ? 0 : value;
}

function str(value: string | undefined): string {
  return value === undefined ? '' : value;
}

function listPortraitUrl(portrait: string): string {
  return portrait.length === 0 ? '' : `https://himg.bdimg.com/sys/portrait/item/${portrait}`;
}

function joinAbstract(items: RawAbstractItem[] | undefined): string {
  if (items === undefined || items.length === 0) {
    return '';
  }
  let text: string = '';
  for (let i = 0; i < items.length; i++) {
    const item: RawAbstractItem = items[i];

    if (item !== undefined && item !== null) {
      text += str(item.text);
    }
  }
  return text;
}

export class ForumBrief {
  followed: boolean | undefined = undefined;
  id: number = 0;
  name: string = '';

  threadCount: number = 0;

  postCount: number = 0;

  memberCount: number = 0;
  avatar: string = '';

  category: string = '';
  slogan: string = '';

  heroImage: string = '';

  heroColor: string = '';
}

function membershipCount(raw: number | string | undefined): number {
  if (typeof raw !== 'number' && (typeof raw !== 'string' || !/^\d+$/.test(raw))) { return -1; }
  const value: number = Number(raw);
  return Number.isSafeInteger(value) && value >= 0 ? value : -1;
}

export class ForumMembership {
  level: number = -1;
  levelName: string = '';
  currentScore: number = -1;
  nextScore: number = -1;
  signed: boolean | undefined = undefined;
  missedDays: number = -1;
  continuousCount: number = -1;
  totalCount: number = -1;

  static fromRaw(raw: RawFrsPage): ForumMembership {
    const value: ForumMembership = new ForumMembership();
    if (raw.forum !== undefined && raw.forum !== null) {
      value.level = membershipCount(raw.forum.level_id);
      value.levelName = str(raw.forum.level_name);
      value.currentScore = membershipCount(raw.forum.cur_score);
      value.nextScore = membershipCount(raw.forum.levelup_score);
    }
    const sign = raw.sign_in_info?.user_info;
    if (sign !== undefined && sign !== null) {
      const state: number = membershipCount(sign.is_sign_in);
      value.signed = state === 1 ? true : (state === 0 ? false : undefined);
      value.missedDays = membershipCount(sign.miss_sign_num);
      value.continuousCount = membershipCount(sign.cont_sign_num);
      value.totalCount = membershipCount(sign.cout_total_sign_num);
    }
    return value;
  }
}

export class PageInfo {
  currentPage: number = 1;
  pageSize: number = 0;
  totalCount: number = 0;
  totalPage: number = 0;
  hasMore: boolean = false;
}

export class ForumTab {
  id: number = 0;
  name: string = '';
}

export class ThreadBrief {

  tid: number = 0;
  title: string = '';

  authorId: number = 0;

  authorName: string = '';

  authorAvatar: string = '';

  coverImage: string = '';

  images: string[] = [];

  replyCount: number = 0;

  agreeCount: number = 0;
  shareCount: number = 0;
  viewCount: number = 0;

  lastTimeText: string = '';

  lastTimeMs: number = 0;

  summary: string = '';
  isGood: boolean = false;
  isNotice: boolean = false;

  isTop: boolean = false;

  sourceForum: string = '';

  sourceForumId: number = 0;

  sourceForumAvatar: string = '';

  postedMs: number = 0;

  avatarStamp: number = 0;
}

export function mergeThreadPages(current: ThreadBrief[], incoming: ThreadBrief[]): ThreadBrief[] {
  const merged: ThreadBrief[] = [];
  const tids: Set<number> = new Set<number>();
  for (let i = 0; i < current.length; i++) {
    merged.push(current[i]);
    if (current[i].tid > 0) {
      tids.add(current[i].tid);
    }
  }
  for (let i = 0; i < incoming.length; i++) {
    const item: ThreadBrief = incoming[i];
    if (item.tid > 0 && tids.has(item.tid)) {
      continue;
    }
    merged.push(item);
    if (item.tid > 0) {
      tids.add(item.tid);
    }
  }
  return merged;
}

export class ThreadListResult {
  forum: ForumBrief = new ForumBrief();
  page: PageInfo = new PageInfo();
  threads: ThreadBrief[] = [];
  tabs: ForumTab[] = [];
  selectedTabId: number = 0;
  membership: ForumMembership = new ForumMembership();

  static fromRaw(raw: RawFrsPage): ThreadListResult {
    const result: ThreadListResult = new ThreadListResult();
    result.membership = ForumMembership.fromRaw(raw);

    const rawTabs: RawFrsTab[] = raw.frs_main_tab_list === undefined ? [] : raw.frs_main_tab_list;
    for (let i = 0; i < rawTabs.length; i++) {
      const rawTab: RawFrsTab = rawTabs[i];
      if (rawTab === undefined || rawTab === null) {
        continue;
      }
      const tabUrl: string = str(rawTab.tab_url);
      const tabType: number = num(rawTab.net_tab_type);
      if (num(rawTab.tab_id) <= 0 || str(rawTab.tab_name).length === 0 || tabUrl.length > 0 || tabType === 4) {
        continue;
      }
      const tab: ForumTab = new ForumTab();
      tab.id = num(rawTab.tab_id);
      tab.name = str(rawTab.tab_name);
      result.tabs.push(tab);
    }
    const preferredTabId: number = num(raw.frs_tab_default);
    const fallbackTabId: number = num(raw.page_data_tab_id);
    result.selectedTabId = preferredTabId > 0 ? preferredTabId : fallbackTabId;

    const rawForum: RawForum | undefined = raw.forum;
    if (rawForum !== undefined && rawForum !== null) {
      result.forum.followed = rawForum.is_like === 1 || rawForum.is_like === '1' ? true :
        (rawForum.is_like === 0 || rawForum.is_like === '0' ? false : undefined);
      result.forum.id = num(rawForum.id);
      result.forum.name = str(rawForum.name);
      result.forum.threadCount = num(rawForum.thread_num);
      result.forum.postCount = num(rawForum.post_num);
      result.forum.memberCount = num(rawForum.member_num);
      result.forum.avatar = str(rawForum.avatar);
      result.forum.category = str(rawForum.first_class);
      result.forum.slogan = str(rawForum.slogan);

      const themeColor: RawForumThemeColor | undefined = rawForum.theme_color;
      if (themeColor !== undefined && themeColor !== null) {
        const dayTheme: RawForumThemeVariant | undefined = themeColor.day;
        if (dayTheme !== undefined && dayTheme !== null) {
          result.forum.heroImage = str(dayTheme.pattern_image);
          result.forum.heroColor = normalizeForumColor(str(dayTheme.common_color));
        }
      }
    }

    const rawPage: RawPage | undefined = raw.page;
    if (rawPage !== undefined && rawPage !== null) {
      result.page.currentPage = num(rawPage.current_page) === 0 ? 1 : num(rawPage.current_page);
      result.page.pageSize = num(rawPage.page_size);
      result.page.totalCount = num(rawPage.total_count);
      result.page.totalPage = num(rawPage.total_page);
      result.page.hasMore = flag(rawPage.has_more);
    }

    const list: RawThread[] | undefined = raw.thread_list;
    if (list !== undefined && list.length > 0) {
      const users: RawListUser[] = raw.user_list === undefined ? [] : raw.user_list;
      for (let i = 0; i < list.length; i++) {
        const rawThread: RawThread = list[i];
        if (rawThread !== undefined && rawThread !== null) {
          result.threads.push(ThreadListResult.threadFromRaw(rawThread, users));
        }
      }
    } else {
      result.threads = ThreadListResult.threadsFromFeed(raw);
    }

    return result;
  }

  private static threadFromRaw(raw: RawThread, users: RawListUser[]): ThreadBrief {
    const t: ThreadBrief = new ThreadBrief();

    const tid: number = num(raw.tid);
    t.tid = tid === 0 ? num(raw.id) : tid;

    t.title = str(raw.title);
    t.authorId = num(raw.author_id);
    const author: RawListUser | undefined = ThreadListResult.userById(users, t.authorId);
    if (author !== undefined) {
      const showName: string = str(author.name_show);
      t.authorName = showName.length > 0 ? showName : str(author.name);
      t.authorAvatar = listPortraitUrl(str(author.portrait));
    }

    const replies: number = num(raw.reply_num);
    t.replyCount = replies > 0 ? replies : num(raw.comment_num);
    t.viewCount = num(raw.view_num);
    t.shareCount = num(raw.share_num);

    if (raw.agree !== undefined && raw.agree !== null) {
      t.agreeCount = num(raw.agree.agree_num);
    }
    t.postedMs = num(raw.create_time) * 1000;
    t.lastTimeText = str(raw.last_time);
    t.lastTimeMs = num(raw.last_time_int) * 1000;

    const summary: string = joinAbstract(raw.rich_abstract);
    t.summary = summary.length > 0 ? summary : joinAbstract(raw.abstract);

    t.isGood = flag(raw.is_good) || flag(raw.is_excellent_thread);
    t.isNotice = flag(raw.is_notice);

    t.isTop = flag(raw.is_top) || flag(raw.is_membertop) || flag(raw.is_bakan) || flag(raw.is_activity);

    return t;
  }

  private static userById(users: RawListUser[], authorId: number): RawListUser | undefined {
    if (authorId === 0) {
      return undefined;
    }
    for (let i = 0; i < users.length; i++) {
      const user: RawListUser = users[i];
      if (user !== undefined && user !== null && num(user.id) === authorId) {
        return user;
      }
    }
    return undefined;
  }

  private static threadsFromFeed(raw: RawFrsPage): ThreadBrief[] {
    const out: ThreadBrief[] = [];
    const pageData = raw.page_data;
    if (pageData === undefined || pageData.feed_list === undefined) {
      return out;
    }
    const feeds: RawFeedItem[] = pageData.feed_list;
    for (let i = 0; i < feeds.length; i++) {
      const item: RawFeedItem = feeds[i];
      if (item === undefined || item === null) {
        continue;
      }
      const t: ThreadBrief | undefined = ThreadListResult.threadFromFeedCard(item);
      if (t !== undefined) {
        out.push(t);
      }
    }
    return out;
  }

  static threadFromFeedCard(item: RawFeedItem): ThreadBrief | undefined {
    if (item === null || item === undefined || item.layout !== 'feed') {
      return undefined;
    }
    const feed: RawFeed | undefined = item.feed;
    if (feed === undefined || feed === null) {
      return undefined;
    }
    const components: RawFeedComponent[] = feed.components === undefined ? [] : feed.components;

    const socialComp: RawFeedComponent | undefined = ThreadListResult.componentNamed(components, 'feed_social');
    const social: RawFeedSocial | undefined = socialComp === undefined ? undefined : socialComp.feed_social;
    if (social === undefined || social === null) {
      return undefined;
    }
    const tid: number = num(social.tid);
    if (tid === 0) {
      return undefined;
    }

    const t: ThreadBrief = new ThreadBrief();
    t.tid = tid;
    t.title = ThreadListResult.blockText(components, 'feed_title');
    t.summary = ThreadListResult.blockText(components, 'feed_abstract');

    t.replyCount = num(social.comment_num);
    t.shareCount = num(social.share_num);
    if (social.agree !== undefined && social.agree !== null) {
      t.agreeCount = num(social.agree.agree_num);
    }

    const map: RawFeedBizMap | undefined = feed.business_info_map;
    t.viewCount = ThreadListResult.bizNumber(feed.business_info, 'view_num', map);

    t.isGood = false;
    t.isTop = false;
    t.isNotice = false;

    const headComp: RawFeedComponent | undefined = ThreadListResult.componentNamed(components, 'feed_head');
    if (headComp !== undefined) {
      const head: RawFeedHead | undefined = headComp.feed_head;
      if (head !== undefined && head !== null) {
        t.authorName = ThreadListResult.headNickname(head);
        if (head.image_data !== undefined && head.image_data !== null) {
          t.authorAvatar = str(head.image_data.img_url);
        }
      }
    }

    const avatar: string = ThreadListResult.bizText(feed.business_info, 'forum_avatar', map);
    const forumName: string = ThreadListResult.bizText(feed.business_info, 'forum_name', map);
    if (avatar.length > 0) {
      t.sourceForumAvatar = avatar;

      if (forumName.length > 0) { putForumAvatar(forumName, avatar); }
    }
    if (t.sourceForum.length === 0 && forumName.length > 0) { t.sourceForum = forumName; }

    const createdSec: number = ThreadListResult.bizNumber(feed.business_info, 'create_time', map);
    t.postedMs = createdSec * 1000;
    if (createdSec > 0) {
      t.lastTimeMs = createdSec * 1000;
      t.lastTimeText = ThreadListResult.monthDayText(createdSec);
    }

    const picComp: RawFeedComponent | undefined = ThreadListResult.componentNamed(components, 'feed_pic');
    if (picComp !== undefined && picComp.feed_pic !== undefined) {
      const pics: RawFeedPic[] | undefined = picComp.feed_pic.pics;
      if (pics !== undefined && pics.length > 0) {
        for (let i = 0; i < pics.length; i++) {
          const pic: RawFeedPic = pics[i];
          if (pic === undefined || pic === null) {
            continue;
          }
          const imageUrl: string = str(pic.small_pic_url);
          if (imageUrl.length > 0) {
            t.images.push(imageUrl);
            rememberFeedImage(imageUrl, num(pic.width), num(pic.height), pic.is_long_pic === 1,
              str(pic.origin_pic_url) || str(pic.big_pic_url));
          }
        }
        if (t.images.length > 0) {
          t.coverImage = t.images[0];
        }
      }
    }

    return t;
  }

  private static bizText(items: RawFeedBizItem[] | undefined, key: string,
    map?: RawFeedBizMap): string {
    if (items !== undefined) {
      for (let i = 0; i < items.length; i++) {
        const item: RawFeedBizItem = items[i];
        if (item === undefined || item === null || item.key !== key) {
          continue;
        }
        const raw: string = str(item.value);
        if (raw.length > 0) {
          return raw;
        }
      }
    }
    if (map === undefined) {
      return '';
    }
    if (key === 'forum_avatar') { return str(map.forum_avatar); }
    if (key === 'forum_name') { return str(map.forum_name); }
    if (key === 'create_time') { return str(map.create_time); }
    if (key === 'view_num') { return str(map.view_num); }
    return '';
  }

  private static bizNumber(items: RawFeedBizItem[] | undefined, key: string,
    map?: RawFeedBizMap): number {
    const raw: string = ThreadListResult.bizText(items, key, map);
    if (raw.length === 0) {
      return 0;
    }
    const parsed: number = Number.parseInt(raw, 10);
    return Number.isNaN(parsed) ? 0 : parsed;
  }

  private static componentNamed(components: RawFeedComponent[], name: string): RawFeedComponent | undefined {
    for (let i = 0; i < components.length; i++) {
      const component: RawFeedComponent = components[i];
      if (component !== undefined && component !== null && component.component === name) {
        return component;
      }
    }
    return undefined;
  }

  private static blockText(components: RawFeedComponent[], name: string): string {
    const comp: RawFeedComponent | undefined = ThreadListResult.componentNamed(components, name);
    if (comp === undefined) {
      return '';
    }
    const block: RawFeedTextBlock | undefined =
      name === 'feed_title' ? comp.feed_title : comp.feed_abstract;
    if (block === undefined || block.data === undefined) {
      return '';
    }
    let out: string = '';
    for (let i = 0; i < block.data.length; i++) {
      const node = block.data[i];
      if (node === undefined || node === null) {
        continue;
      }
      const info = node.text_info;
      if (info !== undefined && info !== null && info.text !== undefined) {
        out += info.text;
      }
    }
    return out;
  }

  private static headNickname(head: RawFeedHead): string {
    const main = head.main_data;
    if (main === undefined || main.length === 0) {
      return '';
    }
    const node = main[0];
    if (node === undefined || node === null) {
      return '';
    }
    const inner: RawFeedTextInner | undefined = node.text;
    return inner === undefined || inner === null ? '' : str(inner.text);
  }

  private static monthDayText(sec: number): string {
    const d: Date = new Date(sec * 1000);
    const day: number = d.getDate();
    const dayText: string = day < 10 ? `0${day}` : String(day);
    return `${d.getMonth() + 1}-${dayText}`;
  }
}

export function pickRandomForums(pool: string[], count: number): string[] {
  const shuffled: string[] = [];
  for (let i = 0; i < pool.length; i++) {
    shuffled.push(pool[i]);
  }

  for (let i = shuffled.length - 1; i > 0; i--) {
    const j: number = Math.floor(Math.random() * (i + 1));
    const tmp: string = shuffled[i];
    shuffled[i] = shuffled[j];
    shuffled[j] = tmp;
  }
  const take: number = count > shuffled.length ? shuffled.length : count;
  const out: string[] = [];
  for (let i = 0; i < take; i++) {
    out.push(shuffled[i]);
  }
  return out;
}

export function shuffleThreadList(items: ThreadBrief[]): ThreadBrief[] {
  const out: ThreadBrief[] = [];
  for (let i = 0; i < items.length; i++) {
    out.push(items[i]);
  }
  for (let i = out.length - 1; i > 0; i--) {
    const j: number = Math.floor(Math.random() * (i + 1));
    const tmp: ThreadBrief = out[i];
    out[i] = out[j];
    out[j] = tmp;
  }
  return out;
}

export function sortThreadsByTimeDesc(items: ThreadBrief[]): ThreadBrief[] {
  const out: ThreadBrief[] = [];
  for (let i = 0; i < items.length; i++) {
    out.push(items[i]);
  }
  for (let i = 1; i < out.length; i++) {
    const current: ThreadBrief = out[i];
    let j: number = i - 1;

    while (j >= 0 && out[j].lastTimeMs < current.lastTimeMs) {
      out[j + 1] = out[j];
      j--;
    }
    out[j + 1] = current;
  }
  return out;
}

export function takeNonPinnedThreads(threads: ThreadBrief[], limit: number): ThreadBrief[] {
  const out: ThreadBrief[] = [];
  for (let i = 0; i < threads.length && out.length < limit; i++) {
    if (threads[i].isTop) {
      continue;
    }
    out.push(threads[i]);
  }
  return out;
}

export function anySourceHasMore(flags: boolean[]): boolean {
  for (let i = 0; i < flags.length; i++) {
    if (flags[i]) {
      return true;
    }
  }
  return false;
}

export function appendTimeSortedBatch(current: ThreadBrief[], incoming: ThreadBrief[]): ThreadBrief[] {
  return mergeThreadPages(current, sortThreadsByTimeDesc(incoming));
}
