

import { ProtoReader, WireType } from '../proto/ProtoWire';
import { decodeUtf8 } from '../utils/TextCodec';
import { ContentKind, ContentPiece, emojiCodeFromReplyToken, emojiImageUrl } from './ThreadDetail';

export interface RawStoredError {
  errno?: string;
  errmsg?: string;
}

export interface RawStoredAuthor {
  name?: string;
  name_show?: string;
  user_portrait?: string;
}

export interface RawStoredMedia {
  small_pic?: string;
  water_pic?: string;
}

export interface RawStoredThreadResponse {
  error?: RawStoredError;
  store_thread?: RawStoredThread[];
}

export interface RawStoredThread {
  thread_id?: string;
  title?: string;
  forum_name?: string;
  reply_num?: string;
  create_time?: string;

  is_deleted?: string | number;
  author?: RawStoredAuthor;
  media?: RawStoredMedia[];
}

export class StoredThread {
  tid: number = 0;
  title: string = '';
  forumName: string = '';
  replyNum: number = 0;

  createTimeMs: number = 0;
  authorName: string = '';

  coverUrl: string = '';

  isDeleted: boolean = false;
}

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

    const seconds: number = toInt(raw.create_time);
    item.createTimeMs = seconds > 0 ? seconds * 1000 : 0;
    const author = raw.author;
    if (author !== undefined) {

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

function toInt(value: string | undefined): number {
  if (value === undefined || value.length === 0) {
    return 0;
  }
  const parsed: number = Number.parseInt(value, 10);
  return Number.isNaN(parsed) ? 0 : parsed;
}

/* 协议参考：lumina37/aiotieba（Unlicense）。 */
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

export class UserPostItem {
  tid: number = 0;
  pid: number = 0;
  forumId: number = 0;
  forumName: string = '';

  title: string = '';

  content: string = '';
  authorName: string = '';
  replyNum: number = 0;

  createTimeMs: number = 0;

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
