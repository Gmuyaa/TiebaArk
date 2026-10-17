

import { ThreadBrief } from './ThreadList';
import { getForumAvatar } from './ForumAvatarStore';
import { ProtoReader, WireType } from '../proto/ProtoWire';

const RES_ERROR: number = 1;
const RES_DATA: number = 2;
const DATA_THREAD_LIST: number = 2;

const T_ID: number = 1;
const T_TID: number = 2;
const T_POST_ID: number = 52;
const T_ORIGIN: number = 141;
const T_TITLE: number = 3;
const T_REPLY_NUM: number = 4;
const T_VIEW_NUM: number = 5;
const T_LAST_TIME_TEXT: number = 6;
const T_LAST_TIME: number = 7;
const T_AUTHOR: number = 18;
const T_FORUM_ID: number = 27;
const T_FORUM_NAME: number = 28;
const T_CREATE_TIME: number = 45;
const T_CONTENT: number = 112;
const T_AGREE_NUM: number = 124;
const T_COVER: number = 159;
// 固定基准APK ThreadInfo 的 ProtoField 注解：video_info=79，thread_type=26。
const T_VIDEO_INFO: number = 79;
const T_THREAD_TYPE: number = 26;

const CONTENT_TYPE: number = 1;
// PbContent.text=2；与正文片段112同源，不使用推荐附图159中的文字。
const CONTENT_TEXT: number = 2;
const CONTENT_NORMAL_IMAGE: number = 8;
const CONTENT_ACTIVE_IMAGE: number = 36;

const U_UID: number = 2;
const U_NAME: number = 3;
const U_NAME_SHOW: number = 4;
const U_PORTRAIT: number = 5;

/** 旧格式 user_list 给的是 portrait 标识，拼成可加载的头像地址（与 ThreadList 同款） */
function authorAvatarUrl(portrait: string): string {
  return portrait.length === 0 ? '' : `https://himg.bdimg.com/sys/portrait/item/${portrait}`;
}

/** 官方推荐流里的一条帖子（解析中间态，字段名与 wire 字段一一对应） */
export class PersonalizedThread {
  feedItemId: number = 0;
  targetPid: number = 0;
  isVideo: boolean = false;
  tid: number = 0;
  title: string = '';
  summary: string = '';
  /** 回复数（不含主楼口径） */
  replyCount: number = 0;
  /** 浏览数（口径未与官方界面对照，见文件头说明） */
  viewCount: number = 0;
  agreeCount: number = 0;
  /** 相对时间文本，如 "9-20" */
  lastTimeText: string = '';
  /** 最后活跃时间（毫秒；0 = 服务端没给） */
  lastTimeMs: number = 0;
  /** 创建时间（毫秒；0 = 服务端没给） */
  createTimeMs: number = 0;
  authorId: number = 0;
  authorName: string = '';
  authorNick: string = '';
  authorPortrait: string = '';
  forumId: number = 0;
  forumName: string = '';
  /** 已由主帖正文片段 `112` 验证归属的展示图，按正文顺序保留。 */
  images: string[] = [];
  /**
   * 推荐接口附带的图片 URL。该字段可能指向评论附件，不能作为主帖正文图片展示。
   * 仅保留给协议解析取证，转换为首页卡片时必须丢弃。
   */
  coverImage: string = '';
}

/**
 * 取 pb 响应里的业务错误码（`error.errorno`）。
 * 拿不到返回 `-1`（本地伪码）：与"服务端明确回 0（成功）"区分开，
 * 避免把"解析失败"当成"业务成功"（与 `MyContent.parseUserPostErrorno` 同一约定）。
 */
export function parsePersonalizedErrorno(bytes: Uint8Array): number {
  if (bytes.length === 0) {
    return -1;
  }
  try {
    const root: ProtoReader = new ProtoReader(bytes);
    while (root.hasMore()) {
      const f: number = root.readTag();
      if (f === RES_ERROR && root.wireType === WireType.LENGTH_DELIMITED) {
        const err: ProtoReader = new ProtoReader(root.readBytes());
        while (err.hasMore()) {
          const ef: number = err.readTag();
          if (ef === 1) {
            return Number(err.readVarint());
          }
          err.skipField();
        }
        return -1;
      }
      root.skipField();
    }
  } catch (err) {
    return -1;
  }
  return -1;
}

/**
 * personalized pb → 帖子列表。解析失败返回空数组（成败由 errorno 先判别）。
 * tid 为 0 的项跳过（畸形项不该进流）。
 */
export function parsePersonalizedFeed(bytes: Uint8Array): PersonalizedThread[] {
  const out: PersonalizedThread[] = [];
  if (bytes.length === 0) {
    return out;
  }
  try {
    const root: ProtoReader = new ProtoReader(bytes);
    while (root.hasMore()) {
      const f: number = root.readTag();
      if (f === RES_DATA && root.wireType === WireType.LENGTH_DELIMITED) {
        const data: ProtoReader = new ProtoReader(root.readBytes());
        while (data.hasMore()) {
          const df: number = data.readTag();
          if (df === DATA_THREAD_LIST && data.wireType === WireType.LENGTH_DELIMITED) {
            const item: PersonalizedThread = readThreadInfo(data.readBytes());
            if (item.tid > 0) {
              out.push(item);
            }
          } else {
            data.skipField();
          }
        }
      } else {
        root.skipField();
      }
    }
  } catch (err) {
    return out;
  }
  return out;
}

function readThreadInfo(bytes: Uint8Array): PersonalizedThread {
  const t: PersonalizedThread = new PersonalizedThread();
  let itemId: number = 0;
  let threadType: number = 0;
  let postId: number = 0;
  let originTid: number = 0;
  const reader: ProtoReader = new ProtoReader(bytes);
  while (reader.hasMore()) {
    const f: number = reader.readTag();
    switch (f) {
      case T_ID:
        itemId = Number(reader.readUint64());
        break;
      case T_TID:
        t.tid = Number(reader.readUint64());
        break;
      case T_POST_ID:
        postId = Number(reader.readUint64());
        break;
      case T_ORIGIN:
        if (reader.wireType === WireType.LENGTH_DELIMITED) {
          const origin = new ProtoReader(reader.readBytes());
          while (origin.hasMore()) {
            const of: number = origin.readTag();
            if (of === 5 && origin.wireType === WireType.LENGTH_DELIMITED) {
              const value: string = origin.readString();
              if (/^[0-9]+$/.test(value)) { originTid = Number(value); }
            } else { origin.skipField(); }
          }
        } else { reader.skipField(); }
        break;
      case T_TITLE:
        t.title = reader.readString();
        break;
      case T_REPLY_NUM:
        t.replyCount = Number(reader.readVarint());
        break;
      case T_VIEW_NUM:
        t.viewCount = Number(reader.readVarint());
        break;
      case T_LAST_TIME_TEXT:
        t.lastTimeText = reader.readString();
        break;
      case T_LAST_TIME: {
        const seconds: number = Number(reader.readVarint());
        t.lastTimeMs = seconds > 0 ? seconds * 1000 : 0;
        break;
      }
      case T_AUTHOR:
        if (reader.wireType === WireType.LENGTH_DELIMITED) {
          readAuthor(reader.readBytes(), t);
        } else {
          reader.skipField();
        }
        break;
      case T_FORUM_ID:
        t.forumId = Number(reader.readVarint());
        break;
      case T_FORUM_NAME:
        t.forumName = reader.readString();
        break;
      case T_CREATE_TIME: {
        const seconds: number = Number(reader.readVarint());
        t.createTimeMs = seconds > 0 ? seconds * 1000 : 0;
        break;
      }
      case T_CONTENT:
        if (reader.wireType === WireType.LENGTH_DELIMITED) {
          appendPrimaryContent(reader.readBytes(), t);
        } else {
          reader.skipField();
        }
        break;
      case T_AGREE_NUM:
        t.agreeCount = Number(reader.readVarint());
        break;
      case T_COVER:
        t.coverImage = reader.readString();
        break;
      case T_VIDEO_INFO:
        t.isVideo = true; reader.skipField(); break;
      case T_THREAD_TYPE:
        if (reader.wireType === WireType.VARINT) {
          threadType = Number(reader.readVarint()); t.isVideo = threadType === 40 || t.isVideo;
        }
        else { reader.skipField(); }
        break;
      default:
        reader.skipField();
        break;
    }
  }
  // 回复推荐的 id 可能是回复身份；官方 getTid 优先 tid，仅缺省时回退 id。
  if (t.tid === 0) { t.tid = itemId; }
  // type=81 的回复推荐使用虚拟 tid，pb/page 必须读 origin_thread_info.tid。
  if (threadType === 81) {
    t.feedItemId = t.tid;
    t.tid = originTid;
    t.targetPid = Number.isSafeInteger(postId) && postId > 0 ? postId : 0;
    if (!Number.isSafeInteger(t.feedItemId) || t.feedItemId <= 0) { t.feedItemId = 0; }
  }
  if (!Number.isSafeInteger(t.tid) || t.tid <= 0) { t.tid = 0; }
  return t;
}

/**
 * `ThreadInfo.112` 是主帖正文片段序列。文字与表情编码按顺序拼接；type=3 的图片遵循详情页同一
 * 优先级：活动图（36）优先、缺失时回退常规图（8）。这与 `159` 的推荐附图不同，
 * 前者与正文文本、表情处在同一有序片段中，因而不会混入评论附件。
 */
function appendPrimaryContent(bytes: Uint8Array, thread: PersonalizedThread): void {
  let type: number = 0;
  let text: string = '';
  let normal: string = '';
  let active: string = '';
  const reader: ProtoReader = new ProtoReader(bytes);
  while (reader.hasMore()) {
    const field: number = reader.readTag();
    if (field === CONTENT_TYPE && reader.wireType === WireType.VARINT) {
      type = Number(reader.readVarint());
    } else if (field === CONTENT_TEXT && reader.wireType === WireType.LENGTH_DELIMITED) {
      text = reader.readString();
    } else if (field === CONTENT_NORMAL_IMAGE && reader.wireType === WireType.LENGTH_DELIMITED) {
      normal = reader.readString();
    } else if (field === CONTENT_ACTIVE_IMAGE && reader.wireType === WireType.LENGTH_DELIMITED) {
      active = reader.readString();
    } else {
      reader.skipField();
    }
  }
  if (type === 3) {
    const image: string = active.length > 0 ? active : normal;
    if (image.length > 0) { thread.images.push(image); }
  } else if (type === 0 || type === 1 || type === 2 || type === 4) {
    // 文本、链接名称、表情编码与提及保持正文顺序，不把媒体URL当正文。
    thread.summary += text;
  }
}

/** 作者子树（ThreadInfo.18）：昵称优先，头像由 portrait 拼接 */
function readAuthor(bytes: Uint8Array, t: PersonalizedThread): void {
  const reader: ProtoReader = new ProtoReader(bytes);
  while (reader.hasMore()) {
    const f: number = reader.readTag();
    switch (f) {
      case U_UID:
        t.authorId = Number(reader.readVarint());
        break;
      case U_NAME:
        t.authorName = reader.readString();
        break;
      case U_NAME_SHOW: {
        const nick: string = reader.readString();
        // 昵称优先（与收藏列表/我的内容同一取舍）：有值就覆盖用户名
        if (nick.length > 0) {
          t.authorNick = nick;
        }
        break;
      }
      case U_PORTRAIT:
        t.authorPortrait = reader.readString();
        break;
      default:
        reader.skipField();
        break;
    }
  }
}

/**
 * 转成首页信息流卡片用的 `ThreadBrief`。
 *
 * `sourceForum` = 该帖自己的吧（官方流每条可能来自不同吧，卡片展示与进吧跳转都靠它）；
 * 点赞/回复口径见文件头。`lastTimeMs` 取"最后活跃"（字段 7），与列表排序语义一致。
 */
export function personalizedToBrief(t: PersonalizedThread): ThreadBrief {
  const b: ThreadBrief = new ThreadBrief();
  b.tid = t.tid;
  b.feedItemId = t.feedItemId;
  b.targetPid = t.targetPid;
  b.isVideo = t.isVideo;
  b.title = t.title;
  b.summary = t.summary;
  b.authorId = t.authorId;
  b.authorName = t.authorNick.length > 0 ? t.authorNick : t.authorName;
  b.authorAvatar = authorAvatarUrl(t.authorPortrait);
  // 只映射 `112` 中的主帖正文图片；`159` 会混入评论附件，绝不能作为兜底。
  b.images = t.images;
  b.replyCount = t.replyCount;
  b.agreeCount = t.agreeCount;
  b.viewCount = t.viewCount;
  b.postedMs = t.createTimeMs;
  b.lastTimeText = t.lastTimeText;
  b.lastTimeMs = t.lastTimeMs;
  b.sourceForum = t.forumName;
  b.sourceForumId = t.forumId;

  b.sourceForumAvatar = getForumAvatar(t.forumName);
  return b;
}

/** 批量转换 */
export function personalizedToBriefs(items: PersonalizedThread[]): ThreadBrief[] {
  const out: ThreadBrief[] = [];
  for (let i = 0; i < items.length; i++) {
    out.push(personalizedToBrief(items[i]));
  }
  return out;
}
