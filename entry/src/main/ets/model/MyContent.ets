/** 浏览历史、收藏、回复与帖子列表的数据解析。 */

import { ProtoReader, WireType } from '../proto/ProtoWire';
import { decodeUtf8 } from '../utils/TextCodec';
import { ContentKind, ContentPiece, emojiCodeFromReplyToken, emojiImageUrl } from './ThreadDetail';

/** 收藏响应的错误段（与别处不同：字段叫 `errno`，值是**字符串**） */
export interface RawStoredError {
  errno?: string;
  errmsg?: string;
}

/** 收藏条目的作者段 */
export interface RawStoredAuthor {
  name?: string;
  name_show?: string;
  user_portrait?: string;
}

/** 收藏条目的媒体段（只要图，尺寸/类型一概不读） */
export interface RawStoredMedia {
  small_pic?: string;
  water_pic?: string;
}

/** 收藏响应信封（只声明要读的键） */
export interface RawStoredThreadResponse {
  error?: RawStoredError;
  store_thread?: RawStoredThread[];
}

/** 收藏列表一项（只声明要读的键，其余忽略） */
export interface RawStoredThread {
  thread_id?: string;
  title?: string;
  forum_name?: string;
  reply_num?: string;
  create_time?: string;
  /** 是否已删除。实测是**字符串** "1"/"0"（数字 1/0 也接受） */
  is_deleted?: string | number;
  author?: RawStoredAuthor;
  media?: RawStoredMedia[];
}

/**
 * 一条"我收藏的帖子"。
 *
 * 字段一律给**默认值**：列表页是逐字段渲染，缺字段不该让整行变 undefined。
 */
export class StoredThread {
  tid: number = 0;
  title: string = '';
  forumName: string = '';
  replyNum: number = 0;
  /** 收藏时间（秒 → 毫秒）；为 0 表示服务端没给 */
  createTimeMs: number = 0;
  authorName: string = '';
  /** 封面图（media[0].small_pic），没有则空串 */
  coverUrl: string = '';
  /** 已被删除/屏蔽（服务端 `is_deleted="1"`）→ 列表灰显并标"该帖子已被删除" */
  isDeleted: boolean = false;
}

/** 收藏响应解析结果 */
export class StoredThreadList {
  errorCode: number = 0;
  errorMsg: string = '';
  items: StoredThread[] = [];

  static fromRaw(raw: RawStoredThreadResponse): StoredThreadList {
    const out: StoredThreadList = new StoredThreadList();
    const errno: string = raw.error === undefined ? '' : (raw.error.errno ?? '');
    if (errno.length > 0 && errno !== '0') {
      const parsed: number = Number.parseInt(errno, 10);
      out.errorCode = Number.isNaN(parsed) ? -1 : parsed;
      out.errorMsg = raw.error === undefined ? '' : (raw.error.errmsg ?? '');
      return out;
    }
    const list: RawStoredThread[] = raw.store_thread ?? [];
    for (let i: number = 0; i < list.length; i++) {
      out.items.push(StoredThreadList.toItem(list[i]));
    }
    return out;
  }

  private static toItem(raw: RawStoredThread): StoredThread {
    const item: StoredThread = new StoredThread();
    item.tid = toInt(raw.thread_id);
    item.title = (raw.title ?? '').trim();
    item.forumName = (raw.forum_name ?? '').trim();
    item.replyNum = toInt(raw.reply_num);
    // 秒 → 毫秒；非数字/0 保持 0（界面据此不显示时间）
    const seconds: number = toInt(raw.create_time);
    item.createTimeMs = seconds > 0 ? seconds * 1000 : 0;
    const author = raw.author;
    if (author !== undefined) {
      // 昵称优先（`name_show`），没有才退用户名（`name`）—— 与详情页同一取舍
      item.authorName = (author.name_show ?? '').length > 0
        ? (author.name_show ?? '') : (author.name ?? '');
    }
    item.isDeleted = toDeleted(raw.is_deleted);
    const media = raw.media;
    if (media !== undefined && media.length > 0) {
      item.coverUrl = media[0].small_pic ?? media[0].water_pic ?? '';
    }
    return item;
  }
}

/**
 * 删帖标记：`is_deleted` 可能是字符串也可能数字（贴吧 JSON 字段两态都有先例），
 * 只有明确的 1 / "1" / true 才算已删除 —— **不把"字段缺失"当成删除**
 * （老响应可能根本不带这个键，误判会让整个列表变灰）。
 */
function toDeleted(value: string | number | undefined): boolean {
  if (value === undefined) {
    return false;
  }
  if (typeof value === 'number') {
    return value === 1;
  }
  const text: string = value.trim();
  return text === '1' || text.toLowerCase() === 'true';
}

/** 把"可能是字符串的数字"转成 number；转不出来给 0 */
function toInt(value: string | undefined): number {
  if (value === undefined || value.length === 0) {
    return 0;
  }
  const parsed: number = Number.parseInt(value, 10);
  return Number.isNaN(parsed) ? 0 : parsed;
}

/* ─────────────── 我的回复 / 我的主题（protobuf） ─────────────── */

/** 用户内容响应字段早期参考 aiotieba protobuf（Unlicense），并核对官方 UserPostResIdl、DataRes 与 PostInfoList 的字段注解。error=1、data=2，内容列表为 DataRes.post_list=1。 */
const RES_ERROR: number = 1;
const RES_DATA: number = 2;
const ERROR_ERRNO: number = 1;
const DATA_POST_LIST: number = 1;

const POST_FORUM_ID: number = 1;
const POST_THREAD_ID: number = 2;
const POST_POST_ID: number = 3;
const POST_CREATE_TIME: number = 5;
const POST_FORUM_NAME: number = 6;
const POST_TITLE: number = 7;
const POST_CONTENT: number = 8;
const POST_USER_NAME: number = 10;
const POST_REPLY_NUM: number = 17;
const POST_NAME_SHOW: number = 35;

const CONTENT_POST_CONTENT: number = 1;
const ABSTRACT_TEXT: number = 2;

/** 我的回复 / 我的主题 列表一项 */
export class UserPostItem {
  tid: number = 0;
  pid: number = 0;
  forumId: number = 0;
  forumName: string = '';
  /** 主题帖才有标题；回复行的标题留空，界面改用正文 */
  title: string = '';
  /** 正文摘要（content[].post_content[].text 拼起来，取前 80 字） */
  content: string = '';
  authorName: string = '';
  replyNum: number = 0;
  /** 创建时间（秒 → 毫秒） */
  createTimeMs: number = 0;
  /** 同一帖子下的历史回复各自带 pid、时间和内容，不能拼成一条。 */
  replies: UserReplyContent[] = [];
  pieces: ContentPiece[] = [];
  isComment: boolean = false;
}

export class UserReplyContent {
  pid: number = 0;
  createTimeMs: number = 0;
  isComment: boolean = false;
  text: string = '';
  pieces: ContentPiece[] = [];
}

/** userpost 按帖子分组；回复列表按 content[] 展开，并使用回复自己的 id 和时间。 */
export function expandUserReplies(groups: UserPostItem[]): UserPostItem[] {
  const out: UserPostItem[] = [];
  for (const group of groups) {
    for (const reply of group.replies) {
      const item: UserPostItem = new UserPostItem();
      item.tid = group.tid;
      item.pid = reply.pid;
      item.forumId = group.forumId;
      item.forumName = group.forumName;
      item.title = group.title;
      item.content = reply.text;
      item.pieces = reply.pieces;
      item.createTimeMs = reply.createTimeMs;
      item.authorName = group.authorName;
      item.isComment = reply.isComment;
      if (item.tid > 0) {
        out.push(item);
      }
    }
  }
  return mergeUserReplies([], out);
}

export function userReplyKey(item: UserPostItem): string {
  return item.pid > 0 ? `${item.tid}:${item.pid}`
    : `${item.tid}:missing:${item.createTimeMs}:${item.content}`;
}

/** 翻页边界可能重复出现同一回复；去重后按回复时间倒序，缺时间保持原序。 */
export function mergeUserReplies(existing: UserPostItem[], incoming: UserPostItem[]): UserPostItem[] {
  const seen: Set<string> = new Set<string>();
  const out: UserPostItem[] = [];
  for (const item of existing.concat(incoming)) {
    const key: string = userReplyKey(item);
    if (!seen.has(key)) {
      seen.add(key);
      out.push(item);
    }
  }
  out.sort((a: UserPostItem, b: UserPostItem) => b.createTimeMs - a.createTimeMs);
  return out;
}

/**
 * 取 pb 响应里的业务错误码（`UserPostResIdl.error.errorno`）。
 *
 * 拿不到返回 `-1`（本地伪码）：与"服务端明确回 0（成功）"区分开，
 * 避免把"解析失败"当成"业务成功"（与 `UserProfile.parseProtoErrorno` 同一约定）。
 */
export function parseUserPostErrorno(bytes: Uint8Array): number {
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
          if (ef === ERROR_ERRNO) {
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

/** userpost pb → 帖子/回复列表。解析失败返回空数组（由 errorno 判别"是真空"） */
export function parseUserPostProto(bytes: Uint8Array): UserPostItem[] {
  const out: UserPostItem[] = [];
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
          if (df === DATA_POST_LIST && data.wireType === WireType.LENGTH_DELIMITED) {
            out.push(readPostInfo(data.readBytes()));
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

function readPostInfo(bytes: Uint8Array): UserPostItem {
  const item: UserPostItem = new UserPostItem();
  const reader: ProtoReader = new ProtoReader(bytes);
  while (reader.hasMore()) {
    const f: number = reader.readTag();
    switch (f) {
      case POST_FORUM_ID:
        item.forumId = Number(reader.readVarint());
        break;
      case POST_THREAD_ID:
        item.tid = Number(reader.readVarint());
        break;
      case POST_POST_ID:
        item.pid = Number(reader.readVarint());
        break;
      case POST_CREATE_TIME: {
        const seconds: number = Number(reader.readVarint());
        item.createTimeMs = seconds > 0 ? seconds * 1000 : 0;
        break;
      }
      case POST_FORUM_NAME:
        item.forumName = reader.readString();
        break;
      case POST_TITLE:
        item.title = reader.readString();
        break;
      case POST_CONTENT:
        // 正文是 repeated：每段内部还有 post_content[]，文本在 abstract.text
        if (reader.wireType === WireType.LENGTH_DELIMITED) {
          const reply: UserReplyContent = readReplyContent(reader.readBytes());
          item.replies.push(reply);
          item.content = (item.content + reply.text).slice(0, 80);
        } else {
          reader.skipField();
        }
        break;
      case POST_USER_NAME:
        item.authorName = reader.readString();
        break;
      case POST_NAME_SHOW: {
        const nick: string = reader.readString();
        // 昵称优先（与收藏列表同一取舍）：有值就覆盖用户名
        if (nick.length > 0) {
          item.authorName = nick;
        }
        break;
      }
      case POST_REPLY_NUM:
        item.replyNum = Number(reader.readVarint());
        break;
      default:
        reader.skipField();
        break;
    }
  }
  return item;
}

/** PostInfoContent：保留单条回复的完整摘要、独立 pid、时间和有序片段。 */
function readReplyContent(bytes: Uint8Array): UserReplyContent {
  const reply: UserReplyContent = new UserReplyContent();
  const reader: ProtoReader = new ProtoReader(bytes);
  while (reader.hasMore()) {
    const f: number = reader.readTag();
    if (f === CONTENT_POST_CONTENT && reader.wireType === WireType.LENGTH_DELIMITED) {
      const abstract: ProtoReader = new ProtoReader(reader.readBytes());
      let type: number = 0;
      let text: string = '';
      let link: string = '';
      while (abstract.hasMore()) {
        const af: number = abstract.readTag();
        if (af === ABSTRACT_TEXT && abstract.wireType === WireType.LENGTH_DELIMITED) {
          text = decodeUtf8(abstract.readBytes());
        } else if (af === 1 && abstract.wireType === WireType.VARINT) {
          type = Number(abstract.readVarint());
        } else if (af === 3 && abstract.wireType === WireType.LENGTH_DELIMITED) {
          link = abstract.readString();
        } else {
          abstract.skipField();
        }
      }
      reply.text += text;
      if (type === 2) {
        const code: string = emojiCodeFromReplyToken(text.startsWith('#(') ? text : `#${text}`);
        const piece: ContentPiece = new ContentPiece();
        piece.kind = ContentKind.EMOJI;
        piece.text = code.length > 0 ? code : text;
        piece.emojiName = text;
        piece.emojiUrl = emojiImageUrl(piece.text);
        reply.pieces.push(piece);
      } else if (type === 3 || type === 10 || type === 5) {
        reply.pieces = reply.pieces.concat(ContentPiece.listFromRaw([{ type: 0,
          text: type === 10 ? '[语音]' : (type === 5 ? '[视频]' : '[图片]') }]));
      } else {
        const pieces: ContentPiece[] = ContentPiece.listFromRaw([{ type: type, text: text, link: link }]);
        for (const piece of pieces) {
          reply.pieces = reply.pieces.concat(piece.kind === ContentKind.TEXT
            ? replySummaryPieces(piece.text) : [piece]);
        }
      }
    } else if (f === 2 && reader.wireType === WireType.VARINT) {
      reply.createTimeMs = Number(reader.readVarint()) * 1000;
    } else if (f === 3 && reader.wireType === WireType.VARINT) {
      reply.isComment = Number(reader.readVarint()) !== 0;
    } else if (f === 4 && reader.wireType === WireType.VARINT) {
      reply.pid = Number(reader.readVarint());
    } else {
      reader.skipField();
    }
  }
  return reply;
}

/** userpost 的文本摘要会把表情写成 (名字)，只在摘要文本里识别已知名称。 */
function replySummaryPieces(text: string): ContentPiece[] {
  const out: ContentPiece[] = [];
  const pattern: RegExp = /#?\([^()\n]+\)/g;
  let offset: number = 0;
  let match: RegExpExecArray | null = pattern.exec(text);
  while (match !== null) {
    const token: string = match[0].startsWith('#') ? match[0] : `#${match[0]}`;
    const code: string = emojiCodeFromReplyToken(token);
    if (code.length > 0) {
      out.push(...ContentPiece.listFromRaw([{ type: 0, text: text.substring(offset, match.index) }]));
      out.push(...ContentPiece.listFromRaw([{ type: 2, text: code }]));
      offset = match.index + match[0].length;
    }
    match = pattern.exec(text);
  }
  out.push(...ContentPiece.listFromRaw([{ type: 0, text: text.substring(offset) }]));
  return out;
}
