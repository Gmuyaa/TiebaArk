/** 原生话题详情：移动网页公开元信息与 PC 相关帖响应的纯解析。 */
import { cleanSnippet, cleanTitle } from './SearchPost';
import { ThreadBrief } from './ThreadList';
import { portraitUrl } from './ThreadDetail';
import { wireString } from './Wire';

export interface RawHotTopicInfo {
  topic_id?: number | string;
  topic_name?: string;
  topic_desc?: string;
  topic_pic?: string;
  discuss_num?: number | string;
  interaction_num_page?: number | string;
}

export interface RawHotTopicInfoResponse {
  error_code?: number | string;
  error_msg?: string;
  topic_info?: RawHotTopicInfo;
  area_card_list?: RawHotTopicMobileArea[];
}

export interface RawHotTopicMobileForum {
  id?: number | string;
  name?: string;
  avatar?: string;
}

export interface RawHotTopicMobileAgree {
  agree_num?: number | string;
}

export interface RawHotTopicMobileThread {
  tid?: number | string;
  create_time?: number | string;
  author_id?: number | string;
  author?: RawHotTopicThreadAuthor;
  agree_num?: number | string;
  share_num?: number | string;
  agree?: RawHotTopicMobileAgree;
  forum_info?: RawHotTopicMobileForum;
}

export interface RawHotTopicMobileCardData {
  thread_info?: RawHotTopicMobileThread;
}

export interface RawHotTopicMobileCard {
  card_type?: string;
  data?: RawHotTopicMobileCardData;
}

export interface RawHotTopicMobileArea {
  card_data?: RawHotTopicMobileCard[];
}

export interface RawHotTopicThreadAuthor {
  id?: number | string;
  name?: string;
  name_show?: string;
  portrait?: string;
  avatar?: string;
}

export interface RawHotTopicThreadMedia {
  type?: string;
  small_pic?: string;
  big_pic?: string;
  water_pic?: string;
}

export interface RawHotTopicThread {
  id?: number | string;
  tid?: number | string;
  title?: string;
  abstract?: string;
  forum_name?: string;
  reply_num?: number | string;
  view_num?: number | string;
  last_time_int?: number | string;
  is_top?: number | string;
  is_good?: number | string;
  author?: RawHotTopicThreadAuthor;
  media?: RawHotTopicThreadMedia[];
}

export interface RawHotTopicThreadPagination {
  current_page?: number | string;
  has_more?: number | string;
  last_id?: number | string;
}

export interface RawHotTopicThreadData {
  thread_list?: RawHotTopicThread[];
  page?: RawHotTopicThreadPagination;
}

export interface RawHotTopicThreadResponse {
  errno?: number | string;
  errmsg?: string;
  data?: RawHotTopicThreadData;
}

export class HotTopicDetail {
  title: string = '';
  description: string = '';
  imageUrl: string = '';
  /** 官方移动网页明确把 discuss_num 标为“热度”。 */
  heat: number = -1;
  /** 官方移动网页的“讨论”使用 interaction_num_page。 */
  discussCount: number = -1;
}

export class HotTopicDetailPage {
  detail: HotTopicDetail = new HotTopicDetail();
  items: ThreadBrief[] = [];
  hasMore: boolean = false;
  lastId: string = '';
}


function count(raw: number | string | undefined, fallback: number = -1): number {
  if (typeof raw !== 'number' && (typeof raw !== 'string' || !/^\d+$/.test(raw))) {
    return fallback;
  }
  const value: number = Number(raw);
  return Number.isSafeInteger(value) && value >= 0 ? value : fallback;
}

/** 缺失、空串或畸形业务码不可被 Number() 转成成功。 */
export function hotTopicErrorCode(raw: number | string | undefined): number | undefined {
  if (typeof raw !== 'number' && (typeof raw !== 'string' || !/^-?\d+$/.test(raw))) {
    return undefined;
  }
  const value: number = Number(raw);
  return Number.isSafeInteger(value) ? value : undefined;
}

/** 仅已验证支持 HTTPS 的贴吧图片域允许由 HTTP 升级；不发送明文图片请求。 */
export function hotTopicImageUrl(raw: string | undefined): string {
  let value: string = wireString(raw).trim();
  if (/^http:\/\/(?:tiebapic\.baidu\.com|imgsa\.baidu\.com|imgsrc\.baidu\.com|himg\.bdimg\.com)\//i.test(value)) {
    value = `https://${value.substring(7)}`;
  }
  return /^https:\/\/[^\s/?#@]+(?:[/?#][^\s]*)?$/i.test(value) ? value : '';
}

/** 参数校验供接口与测试复用；游标保持字符串，不截断大 ID。 */
export function hotTopicRequestError(topicId: number, topicName: string,
  sort: number, page: number, lastId: string): string {
  if (!Number.isSafeInteger(topicId) || topicId <= 0) { return '话题地址无效'; }
  if (sort !== 1 && sort !== 2) { return '话题排序无效'; }
  if (!Number.isSafeInteger(page) || page <= 0) { return '话题页码无效'; }
  if (page > 1 && (typeof topicName !== 'string' || topicName.trim().length === 0)) {
    return '话题名称缺失，请刷新后重试';
  }
  if (typeof lastId !== 'string' ||
    (lastId.length > 0 && !/^(0|[1-9]\d*)$/.test(lastId)) ||
    (lastId.length > 0 && count(lastId) < 0) || (page > 1 && count(lastId) <= 0)) {
    return '话题分页游标无效，请刷新后重试';
  }
  return '';
}

export function parseHotTopicInfo(raw: RawHotTopicInfo | undefined,
  expectedId: number): HotTopicDetail | undefined {
  if (raw === undefined || raw === null || typeof raw !== 'object' || Array.isArray(raw) ||
    count(raw.topic_id) !== expectedId || expectedId <= 0) { return undefined; }
  const detail: HotTopicDetail = new HotTopicDetail();
  detail.title = cleanTitle(wireString(raw.topic_name)).trim();
  if (detail.title.length === 0) { return undefined; }
  detail.description = cleanTitle(wireString(raw.topic_desc)).trim();
  detail.imageUrl = hotTopicImageUrl(raw.topic_pic);
  detail.heat = count(raw.discuss_num);
  detail.discussCount = count(raw.interaction_num_page);
  return detail;
}

function parseThread(raw: RawHotTopicThread): ThreadBrief | undefined {
  if (raw === undefined || raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
    return undefined;
  }
  const tid: number = count(raw.tid === undefined ? raw.id : raw.tid, 0);
  if (tid <= 0) { return undefined; }
  const item: ThreadBrief = new ThreadBrief();
  item.tid = tid;
  item.title = cleanTitle(wireString(raw.title)).trim();
  item.summary = cleanSnippet(wireString(raw.abstract)).trim();
  item.sourceForum = cleanTitle(wireString(raw.forum_name)).trim();
  item.replyCount = count(raw.reply_num);
  item.viewCount = count(raw.view_num);
  item.agreeCount = -1;
  item.shareCount = -1;
  item.isTop = count(raw.is_top, 0) === 1;
  item.isGood = count(raw.is_good, 0) === 1;
  // last_time_int 是最后回复时间，不冒充发帖时间；postedMs / lastTimeMs 保持未知。
  // PC author 的 UID 可相同但 name_show 与移动接口已实测不一致，不发布未核实的显示名。
  // 先留空，随后只接受同 tid 的移动 thread_info 或精确 pb/page 回填。
  if (Array.isArray(raw.media)) {
    for (const media of raw.media) {
      if (media === undefined || media === null || typeof media !== 'object' || media.type !== 'pic') { continue; }
      const image: string = hotTopicImageUrl(media.big_pic) || hotTopicImageUrl(media.water_pic) ||
        hotTopicImageUrl(media.small_pic);
      if (image.length > 0 && !item.images.includes(image)) { item.images.push(image); }
    }
  }
  item.coverImage = item.images.length > 0 ? item.images[0] : '';
  return item;
}

/** 缺列表、畸形分页或整页坏 ID 都是读取失败，不伪装成空话题。 */
export function parseHotTopicThreads(raw: RawHotTopicThreadData | undefined,
  expectedPage: number): HotTopicDetailPage | undefined {
  if (raw === undefined || raw === null || typeof raw !== 'object' || Array.isArray(raw) ||
    !Array.isArray(raw.thread_list)) { return undefined; }
  const page: RawHotTopicThreadPagination | undefined = raw.page;
  if (page === undefined || page === null || typeof page !== 'object' || Array.isArray(page) ||
    count(page.current_page) !== expectedPage || (count(page.has_more) !== 0 && count(page.has_more) !== 1)) {
    return undefined;
  }
  const cursor: number = count(page.last_id);
  if (cursor < 0 || (count(page.has_more) === 1 && cursor === 0)) { return undefined; }
  const result: HotTopicDetailPage = new HotTopicDetailPage();
  const seen: Set<number> = new Set<number>();
  for (const rawThread of raw.thread_list) {
    const item: ThreadBrief | undefined = parseThread(rawThread);
    if (item !== undefined && !seen.has(item.tid)) {
      seen.add(item.tid);
      result.items.push(item);
    }
  }
  if (raw.thread_list.length > 0 && result.items.length === 0) { return undefined; }
  result.hasMore = count(page.has_more) === 1;
  result.lastId = String(cursor);
  return result;
}

/** 同一次元信息请求已带帖子补充字段；按 tid 精确补齐，不改变 PC 排序或对象身份。 */
export function applyHotTopicSupplements(items: ThreadBrief[], areas: RawHotTopicMobileArea[] | undefined): void {
  if (!Array.isArray(areas)) { return; }
  for (const area of areas) {
    if (area === null || area === undefined || !Array.isArray(area.card_data)) { continue; }
    for (const card of area.card_data) {
      if (card === null || card === undefined ||
        (card.card_type !== 'common_thread' && card.card_type !== 'relate_thread')) { continue; }
      const raw: RawHotTopicMobileThread | undefined = card.data?.thread_info;
      if (raw === null || raw === undefined || typeof raw !== 'object' || Array.isArray(raw)) { continue; }
      const tid: number = count(raw.tid, 0);
      if (tid <= 0) { continue; }
      const item: ThreadBrief | undefined = items.find((value: ThreadBrief): boolean => value.tid === tid);
      if (item === undefined) { continue; }
      // 移动主题创建时间已与同 tid 的 pb/thread 和首楼 time 核对；不是最后回复时间。
      const created: number = count(raw.create_time);
      const createdMs: number = created * 1000;
      if (created > 0 && Number.isSafeInteger(createdMs) && Number.isFinite(new Date(createdMs).getTime())) {
        item.postedMs = createdMs;
      }
      const author: RawHotTopicThreadAuthor | undefined = raw.author;
      if (author !== null && author !== undefined && typeof author === 'object' && !Array.isArray(author)) {
        const authorId: number = count(author.id, 0);
        if (authorId > 0 && authorId === count(raw.author_id, 0)) {
          item.authorId = authorId;
          // 与详情页UserBrief一致，昵称是纯Text内容，不剥除合法的尖括号。
          item.authorName = wireString(author.name_show) || wireString(author.name);
          const portrait: string = wireString(author.portrait);
          const directAvatar: string = hotTopicImageUrl(portrait);
          item.authorAvatar = directAvatar.length > 0 ? directAvatar :
            (/^[a-zA-Z0-9._-]+(?:\?t=[a-fA-F0-9]+)?$/.test(portrait) ? portraitUrl(portrait) :
            hotTopicImageUrl(author.avatar));
        }
      }
      const agrees: number = count(raw.agree_num, count(raw.agree?.agree_num));
      const shares: number = count(raw.share_num);
      if (agrees >= 0) { item.agreeCount = agrees; }
      if (shares >= 0) { item.shareCount = shares; }
      const forum: RawHotTopicMobileForum | undefined = raw.forum_info;
      if (forum === null || forum === undefined || typeof forum !== 'object' || Array.isArray(forum)) { continue; }
      // 吧资料必须与当前来源名称一致，不能把作者头像或另一条卡片的吧图移接过来。
      if (cleanTitle(wireString(forum.name)).trim() !== item.sourceForum || item.sourceForum.length === 0) { continue; }
      const forumId: number = count(forum.id, 0);
      if (forumId > 0) { item.sourceForumId = forumId; }
      const avatar: string = hotTopicImageUrl(forum.avatar);
      if (avatar.length > 0) { item.sourceForumAvatar = avatar; }
    }
  }
}
