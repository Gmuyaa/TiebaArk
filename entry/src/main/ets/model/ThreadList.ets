/**
 * 帖子列表的领域模型。
 *
 * 与 `api/RawFrsPage.ets` 的分工：那边照抄服务端字段，这边只保留界面真正要用的、
 * 且保证有确定值的信息。转换集中在 `ThreadListResult.fromRaw`，服务端字段缺失时
 * 给安全默认值——这样 UI 层永远不必写 `?? 0` 这类防御代码。
 *
 * 命名用「驼峰 + 语义化」，而不是服务端的下划线字段名：
 * 服务端哪天改字段名，改动只落在这个文件的 fromRaw 里，不会渗到页面。
 */

import {
  RawAbstractItem, RawFeed, RawFeedBizItem, RawFeedBizMap, RawFeedComponent, RawFeedHead, RawFeedItem,
  RawFeedPic, RawFeedSocial, RawFeedTextBlock, RawFeedTextInner, RawForum, RawForumThemeColor,
  RawForumThemeVariant, RawFrsPage, RawFrsTab, RawListUser, RawPage, RawThread
} from '../api/RawFrsPage';

import { rememberFeedImage } from './HomeFeedPresentation';
import { VideoClip, parseVideoClip } from './VideoClip';
// 卡片流响应里带上来的吧头像顺手灌进全局表（纯逻辑、不 import @kit，Node 可测）
import { putForumAvatar } from './ForumAvatarStore';
import { normalizeForumColor } from '../common/appearance/ForumHeroStyle';

/** 把 0/1 标志位转成布尔 */
function flag(value: number | string | undefined): boolean {
  return value === 1 || value === '1';
}

/** 把可空的数字转成有默认值的数字 */
function num(value: number | string | undefined): number {
  if (typeof value !== 'number' && (typeof value !== 'string' || !/^\d+$/.test(value))) { return 0; }
  const parsed: number = Number(value);
  return Number.isSafeInteger(parsed) && parsed >= 0 ? parsed : 0;
}

/** 把可空的字符串转成有默认值的字符串 */
function str(value: string | undefined): string {
  return value === undefined ? '' : value;
}

/** 旧格式 user_list 给的是 portrait 标识，需要拼成可加载的头像地址。 */
function listPortraitUrl(portrait: string): string {
  return portrait.length === 0 ? '' : `https://himg.bdimg.com/sys/portrait/item/${portrait}`;
}

/** 把富文本片段数组拼成纯文本 */
function joinAbstract(items: RawAbstractItem[] | undefined): string {
  if (items === undefined || items.length === 0) {
    return '';
  }
  let text: string = '';
  for (let i = 0; i < items.length; i++) {
    const item: RawAbstractItem = items[i];
    // JSON 响应可在数组中下发 null；不能让一条异常摘要拖垮整页列表。
    if (item !== undefined && item !== null) {
      text += str(item.text);
    }
  }
  return text;
}

/** 吧的简要信息，用于列表页顶部 */
export class ForumBrief {
  followed: boolean | undefined = undefined;
  id: number = 0;
  name: string = '';
  /** 主题数 */
  threadCount: number = 0;
  /** 帖子数（含回复） */
  postCount: number = 0;
  /** 关注人数 */
  memberCount: number = 0;
  avatar: string = '';
  /** 一级分类，如"个人贴吧" */
  category: string = '';
  slogan: string = '';

  heroImage: string = '';
  /** 吧主题色（`theme_color.day.common_color`，已规范化为 `#RRGGBB`）。取不到为空串 */
  heroColor: string = '';
}

function membershipCount(raw: number | string | undefined): number {
  if (typeof raw !== 'number' && (typeof raw !== 'string' || !/^\d+$/.test(raw))) { return -1; }
  const value: number = Number(raw);
  return Number.isSafeInteger(value) && value >= 0 ? value : -1;
}

/** 仅表示本人在当前吧的关系数据，未知经验/签到不会被默认成零。 */
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
  isVideo: boolean = false;
}

export class ThreadBrief {
  /** 回复推荐的稳定条目身份，不能用于详情请求；普通主题为0。 */
  feedItemId: number = 0;
  /** 回复推荐对应的楼层；详情加载失败或目标已删时保留原帖入口。 */
  targetPid: number = 0;
  isVideo: boolean = false;
  video: VideoClip | undefined = undefined;
  /** 帖子 id */
  tid: number = 0;
  title: string = '';
  /**
   * 作者 uid。
   * 旧格式帖子对象只返回 uid，昵称与头像需要从响应顶层 `user_list` 关联；
   * 新版卡片则直接把作者信息放在 `feed_head`。
   */
  authorId: number = 0;
  /**
   * 作者昵称。旧格式来自顶层 `user_list`，新版来自 `feed_head`；服务端缺失时为空串。
   */
  authorName: string = '';
  /** 作者头像。旧格式由 portrait 拼接，新版直接使用 feed_head 的 img_url。 */
  authorAvatar: string = '';
  /** 帖子封面图（新版卡片的首图）。旧格式为空串 */
  coverImage: string = '';
  /** 新版卡片的全部预览图；旧格式为空数组。 */
  images: string[] = [];
  /**
   * 回帖数。旧格式取 `reply_num`，新版取 `comment_num`——
   * 两个端点的字段语义**恰好相反**，由 fromRaw 按格式分派时填好，
   * 见 api/RawFrsPage.ets 头部说明。
   */
  replyCount: number = 0;
  /** 点赞与分享数；接口未提供时为 0，界面不伪造数据。 */
  agreeCount: number = 0;
  shareCount: number = 0;
  viewCount: number = 0;
  /** 服务端给的相对时间，如 "4-17" */
  lastTimeText: string = '';
  /** 绝对时间戳（毫秒）；服务端给的是秒，转换时乘 1000 */
  lastTimeMs: number = 0;
  /** 纯文本摘要，可能为空 */
  summary: string = '';
  isGood: boolean = false;
  isNotice: boolean = false;
  /** 置顶。认 `is_top`；mtop/bakan/activity 实测恒为 0，保留是防服务端换用它们 */
  isTop: boolean = false;
  /**
   * 来源吧名。首页推荐流里每条帖子可能来自不同吧，卡片展示与进吧跳转都要带上；
   * 指定吧列表模式下由界面用当前吧名兜底。
   */
  sourceForum: string = '';

  sourceForumId: number = 0;
  /**
   * 来源吧头像。推荐流按吧分批拉取，吧头像随响应的 `forum` 一起打点到每条帖子上；
   * 拉不到时为空串，界面退回占位图标，不为它再发一次请求。
   */
  sourceForumAvatar: string = '';

  postedMs: number = 0;

  avatarStamp: number = 0;
}

export function threadBriefIdentity(item: ThreadBrief): number {
  return item.feedItemId > 0 ? item.feedItemId : item.tid;
}

/**
 * 追加列表分页结果，按推荐条目身份（普通主题使用 tid）去重并保留服务端顺序。
 *
 * 置顶帖可能在后续页重复返回；这里只去掉重复项，不按置顶、时间或热度重排。
 */
export function mergeThreadPages(current: ThreadBrief[], incoming: ThreadBrief[]): ThreadBrief[] {
  const merged: ThreadBrief[] = [];
  const tids: Set<number> = new Set<number>();
  for (let i = 0; i < current.length; i++) {
    merged.push(current[i]);
    if (current[i].tid > 0) {
      tids.add(threadBriefIdentity(current[i]));
    }
  }
  for (let i = 0; i < incoming.length; i++) {
    const item: ThreadBrief = incoming[i];
    if (item.tid > 0 && tids.has(threadBriefIdentity(item))) {
      continue;
    }
    merged.push(item);
    if (item.tid > 0) {
      tids.add(threadBriefIdentity(item));
    }
  }
  return merged;
}

/** 一次列表请求的完整结果 */
export class ThreadListResult {
  forum: ForumBrief = new ForumBrief();
  page: PageInfo = new PageInfo();
  threads: ThreadBrief[] = [];
  tabs: ForumTab[] = [];
  selectedTabId: number = 0;
  membership: ForumMembership = new ForumMembership();

  /** 从原始响应构造领域模型。缺字段一律落到默认值，绝不抛异常。 */
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
      tab.isVideo = tabType === 3 && num(rawTab.tab_type) === 100;
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

    // 两种响应形态二选一：小吧给 `thread_list`，大吧给 `page_data.feed_list`。
    // 实测 harmonyos 走前者、iphone（114 万主题）走后者，必须都支持。
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
    t.video = parseVideoClip(raw.video_info);
    t.isVideo = raw.video_info !== undefined && raw.video_info !== null || num(raw.thread_type) === 40;

    // tid 与 id 实测相等，优先取 tid，缺失时退回 id
    const tid: number = num(raw.tid);
    t.tid = tid === 0 ? num(raw.id) : tid;

    t.title = str(raw.title);
    t.authorId = num(raw.author_id);
    if (t.authorId === 0) { t.authorId = num(raw.author?.id); }
    const author: RawListUser | undefined = ThreadListResult.userById(users, t.authorId);
    t.authorName = str(raw.author?.name_show) || str(author?.name_show) || str(raw.author?.name) || str(author?.name);
    t.authorAvatar = listPortraitUrl(str(raw.author?.portrait) || str(author?.portrait));
    // reply_num 是本端点的真值；万一服务端哪天改成只给 comment_num，这里兜住
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

    // 摘要优先用 rich_abstract（带结构），退回 abstract
    const summary: string = joinAbstract(raw.rich_abstract);
    t.summary = summary.length > 0 ? summary : joinAbstract(raw.abstract);

    // 精品：两个候选字段都认（实测都无非零样本，等遇到精品帖再收敛）
    t.isGood = flag(raw.is_good) || flag(raw.is_excellent_thread);
    t.isNotice = flag(raw.is_notice);
    // 置顶实测只由 is_top 标识；另三个字段实测恒为 0，保留以防服务端改回
    t.isTop = flag(raw.is_top) || flag(raw.is_membertop) || flag(raw.is_bakan) || flag(raw.is_activity);

    return t;
  }

  /** 旧格式的作者信息位于顶层用户表，按 thread.author_id 关联。 */
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

  /* ==========================================================================
   * 新版卡片流（page_data.feed_list）
   *
   * 实测背景：iphone 吧在设备上显示"这个吧还没有帖子"，但它有 114 万主题。
   * 原因是该吧不返回 `thread_list`，而返回 `page_data.feed_list`——
   * 一个混合卡片流（热话题卡 + 帖子卡），帖子卡的内容又分散在 components 数组里。
   * ========================================================================== */

  /** 新版卡片流 → 领域模型。非帖子卡会被过滤掉 */
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

  /**
   * 解析一张卡片。
   *
   * 不是 `layout === 'feed'` 的卡（如 hot_topic_card）直接跳过；
   * 拿不到 tid 的也跳过——宁可少一条，也不要显示点不进去的死链。
   */
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
    const videoComp: RawFeedComponent | undefined = ThreadListResult.componentNamed(components, 'feed_video');
    t.isVideo = videoComp !== undefined;
    if (videoComp?.feed_video?.video_info !== undefined) {
      const video = videoComp.feed_video.video_info;
      t.video = parseVideoClip({ video_url: video.url, thumbnail_url: video.thumbnail?.url,
        video_width: video.width, video_height: video.height, video_duration: video.duration });
    }
    // 新版回帖数在 comment_num —— 与旧格式（用 reply_num）恰好相反
    t.replyCount = num(social.comment_num);
    t.shareCount = num(social.share_num);
    if (social.agree !== undefined && social.agree !== null) {
      t.agreeCount = num(social.agree.agree_num);
    }

    const map: RawFeedBizMap | undefined = feed.business_info_map;
    t.viewCount = ThreadListResult.bizNumber(feed.business_info, 'view_num', map);
    // 新版卡片实测不带这些标记，保持默认值而不是猜
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
      // 顺带灌进全局表：推荐流（响应里确实没有这个字段）也就能白拿这份
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

  /**
   * 从卡片体的统计里按 key 取**字符串**：`feed.business_info`（数组形态，手机端）或
   * `feed.business_info_map`（对象形态，PC 网页版）—— 两者内容同源（HAR 取证，见 RawFeedBizMap）。
   *
   * 服务端给的值一律是字符串（`{key:'view_num', value:'49081'}`），直接当数字用会得到 NaN。
   */
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

  /** 同上，取**数值**；解析不出来就给 0，由调用方决定显示与否。 */
  private static bizNumber(items: RawFeedBizItem[] | undefined, key: string,
    map?: RawFeedBizMap): number {
    const raw: string = ThreadListResult.bizText(items, key, map);
    if (raw.length === 0) {
      return 0;
    }
    const parsed: number = Number.parseInt(raw, 10);
    return Number.isNaN(parsed) ? 0 : parsed;
  }

  /** 按组件名取组件。卡片里组件顺序不固定，不能按下标取 */
  private static componentNamed(components: RawFeedComponent[], name: string): RawFeedComponent | undefined {
    for (let i = 0; i < components.length; i++) {
      const component: RawFeedComponent = components[i];
      if (component !== undefined && component !== null && component.component === name) {
        return component;
      }
    }
    return undefined;
  }

  /** 取标题/摘要组件的文本。文本在 `data[].text_info.text`，要拼接 */
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

  /** 昵称在 `main_data[0].text.text` —— 两层嵌套，实测 `text` 是对象不是字符串 */
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

  /**
   * 新版卡片只给时间戳，要自己在本地格式化成旧格式那种 "M-D"（日补零、月不补）。
   * 实测旧格式服务端给的就是这个样式，保持两边一致，界面才不用分情况处理。
   */
  private static monthDayText(sec: number): string {
    const d: Date = new Date(sec * 1000);
    const day: number = d.getDate();
    const dayText: string = day < 10 ? `0${day}` : String(day);
    return `${d.getMonth() + 1}-${dayText}`;
  }
}

/**
 * 从吧池里随机抽取 count 个不重复的吧名。
 *
 * 首页推荐流没有专属接口，做法是随机挑几个热门吧各取一页合并——
 * 抽取逻辑单独成纯函数，便于在 Node 上断言数量与去重。
 * count 超过池子大小时返回整个池子的随机排列。
 */
export function pickRandomForums(pool: string[], count: number): string[] {
  const shuffled: string[] = [];
  for (let i = 0; i < pool.length; i++) {
    shuffled.push(pool[i]);
  }
  // Fisher-Yates：从后往前，每个位置与剩余前缀里的随机位置交换
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

/**
 * 洗牌一份帖子列表（Fisher-Yates，返回新数组，不改入参）。
 * 推荐流把多个吧的帖子合并后打乱，避免"前几页全来自同一个吧"。
 */
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

/**
 * 按绝对发布时间**倒序**排列（最新在前），返回新数组、不改入参。
 *
 * 用于首页顶栏「关注」频道 —— 它的语义是"我关注的吧**最新**的帖子"，
 * 必须按时间排；推荐频道用 `shuffleThreadList` 打乱。**两者不能互换**：
 * 关注流打乱会变成"随机几个吧的随机几条"，时间线不再成立。
 *
 * 两个必须钉住的行为：
 *   1. **稳定**：时间戳相同（服务端只给到分钟，或老帖同秒）时保持传入顺序 ——
 *      也就是各吧内部的服务端顺序不被搅乱。所以这里用插入排序而不是
 *      `Array.sort`：后者在运行时是否稳定不由我们决定，而这条行为要能断言。
 *      数据量本身很小（每轮最多几个吧 × 几条），O(n²) 无代价。
 *   2. **时间戳缺失（0）排最后**：宁可沉底，也不让"没有时间的帖子"插在最新帖前面
 *      （`lastTimeMs` 缺失时是 0，按普通倒序它恰好自然落底，这里显式写出来当契约）。
 */
export function sortThreadsByTimeDesc(items: ThreadBrief[]): ThreadBrief[] {
  const out: ThreadBrief[] = [];
  for (let i = 0; i < items.length; i++) {
    out.push(items[i]);
  }
  for (let i = 1; i < out.length; i++) {
    const current: ThreadBrief = out[i];
    let j: number = i - 1;
    // 严格小于才继续前移 —— 相等就停，保证稳定性
    while (j >= 0 && out[j].lastTimeMs < current.lastTimeMs) {
      out[j + 1] = out[j];
      j--;
    }
    out[j + 1] = current;
  }
  return out;
}

/**
 * 从一个吧的一页里挑**进聚合流**的帖子：**跳过置顶**，最多取 `limit` 条。
 *
 * 只用于跨吧聚合流（首页「关注」频道），**单吧列表页不要用** ——
 * 那个语境下置顶帖是有效的吧内信息（吧规 / 答疑），必须照常显示。
 *
 * 跳过置顶的理由：聚合流是按时间排的"最新动态"，而各吧的置顶互不相干、
 * 时间戳常是好几年以前；混进来会让人以为"关注了吧里最新的是 2019 年的帖"。
 *
 * 返回新数组（元素是原引用，`sourceForum` 等字段由调用方补）。
 */
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

/**
 * 多来源聚合流的**分页终止判据**：只要还有一个来源有下一页，就还能往下刷。
 *
 * 首页「关注」/「推荐」两条流都是"多个吧各取一页"拼出来的，各自的 `page.hasMore`
 * 相互独立（大吧能翻几十页、小吧一页到底），所以整体能不能继续只取决于
 * **是否还有任一来源没到底**。写成函数是为了让这条判据可被断言，
 * 而不是散在 VM 里各处 `.some()`。
 *
 * 空数组（一个来源都没成功）视为到底 —— 没有来源可翻，界面该显示"没有更多了"。
 */
export function anySourceHasMore(flags: boolean[]): boolean {
  for (let i = 0; i < flags.length; i++) {
    if (flags[i]) {
      return true;
    }
  }
  return false;
}

/**
 * 聚合流的**续页合并策略**：新一批按时间倒序后**追加到末尾**，不重排全表。
 *
 * 为什么不整体重排（那才是"严格时间倒序"）：触底加载时视口就在列表底部，
 * 若把新条目按时间插到用户上方，已看过的区域会整体下移 —— 表现是"页面猛跳一下"。
 * 取舍结果是**分段倒序**：段内严格递减、同一吧的相邻两页之间也递减
 * （下一页必然更旧），只有跨吧的段边界可能不是严格递减。
 *
 * 去重走 `mergeThreadPages`（按 tid，已存在的不再进流）。
 * 只用于首页这两条聚合流；单吧列表页的续页是服务端顺序，不需要它。
 */
export function appendTimeSortedBatch(current: ThreadBrief[], incoming: ThreadBrief[]): ThreadBrief[] {
  return mergeThreadPages(current, sortThreadsByTimeDesc(incoming));
}
