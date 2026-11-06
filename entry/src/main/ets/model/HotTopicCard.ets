/** 话题卡片的轻量补充资料；只取匹配主题的公开展示字段，不持有完整详情。 */
import { RawThreadPage, RawThreadHead, RawDetailForum, RawUser } from '../api/RawThreadPage';
import { hotTopicImageUrl } from './HotTopicDetail';
import { portraitUrl } from './ThreadDetail';

export class HotTopicCardInfo {
  tid: number = 0;
  forumId: number = 0;
  forumName: string = '';
  forumAvatar: string = '';
  authorId: number = 0;
  authorName: string = '';
  authorAvatar: string = '';
  agreeCount: number = -1;
  shareCount: number = -1;
  postedMs: number = 0;
}

/** 区分真实零与缺失；不把空串、负数、分数或超界值补成零。 */
function knownCount(value: number | string | undefined): number {
  if (typeof value !== 'number' && (typeof value !== 'string' || !/^\d+$/.test(value))) { return -1; }
  const parsed: number = Number(value);
  return Number.isSafeInteger(parsed) && parsed >= 0 ? parsed : -1;
}

export function parseHotTopicCard(raw: RawThreadPage, expectedTid: number): HotTopicCardInfo | undefined {
  if (!Number.isSafeInteger(expectedTid) || expectedTid <= 0 || raw === undefined || raw === null ||
    typeof raw !== 'object' || Array.isArray(raw)) { return undefined; }
  const thread: RawThreadHead | undefined = raw.thread;
  if (thread === undefined || thread === null || typeof thread !== 'object' || Array.isArray(thread) ||
    knownCount(thread.id) !== expectedTid) { return undefined; }

  const result: HotTopicCardInfo = new HotTopicCardInfo();
  result.tid = expectedTid;
  const agree: number = thread.agree !== undefined && thread.agree !== null &&
    typeof thread.agree === 'object' && !Array.isArray(thread.agree) ? knownCount(thread.agree.agree_num) : -1;
  result.agreeCount = agree >= 0 ? agree : knownCount(thread.agree_num);
  result.shareCount = knownCount(thread.share_num);
  const created: number = knownCount(thread.create_time);
  const createdMs: number = created * 1000;
  if (created > 0 && Number.isSafeInteger(createdMs) && Number.isFinite(new Date(createdMs).getTime())) {
    result.postedMs = createdMs;
  }

  const forum: RawDetailForum | undefined = raw.forum;
  if (forum !== undefined && forum !== null && typeof forum === 'object' && !Array.isArray(forum)) {
    result.forumName = typeof forum.name === 'string' ? forum.name.trim() : '';
    if (result.forumName.length > 0) {
      const forumId: number = knownCount(forum.id);
      if (forumId > 0) { result.forumId = forumId; }
      result.forumAvatar = hotTopicImageUrl(forum.avatar);
    }
  }
  // pb/page 的 thread.author 是主题作者；rn=2 的三帖公开核对与 post_id 指向的首楼用户完全一致。
  // 不使用 PC 列表的 author，也不根据 post_list[0] 的数组位置推断楼主。
  const author: RawUser | undefined = thread.author;
  if (author !== undefined && author !== null && typeof author === 'object' && !Array.isArray(author)) {
    const authorId: number = knownCount(author.id);
    if (authorId > 0) {
      result.authorId = authorId;
      // 与详情UserBrief一致：昵称按原文显示，不trim或剥除合法尖括号。
      const show: string = typeof author.name_show === 'string' ? author.name_show : '';
      result.authorName = show.length > 0 ? show : (typeof author.name === 'string' ? author.name : '');
      const portrait: string = typeof author.portrait === 'string' ? author.portrait : '';
      result.authorAvatar = hotTopicImageUrl(portrait);
      // 官方头像标识保留?t版本；非法scheme/路径不能伪装成头像标识拼接。
      if (result.authorAvatar.length === 0 && /^[a-zA-Z0-9._-]+(?:\?t=[a-fA-F0-9]+)?$/.test(portrait)) {
        result.authorAvatar = hotTopicImageUrl(portraitUrl(portrait));
      }
    }
  }
  return result;
}
