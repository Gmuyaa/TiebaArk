

import { ThreadBrief } from './ThreadList';
import { getForumAvatar } from './ForumAvatarStore';
import { ProtoReader, WireType } from '../proto/ProtoWire';

const RES_ERROR: number = 1;
const RES_DATA: number = 2;
const DATA_THREAD_LIST: number = 2;

const T_TID: number = 1;
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

const CONTENT_TYPE: number = 1;

const CONTENT_TEXT: number = 2;
const CONTENT_NORMAL_IMAGE: number = 8;
const CONTENT_ACTIVE_IMAGE: number = 36;

const U_UID: number = 2;
const U_NAME: number = 3;
const U_NAME_SHOW: number = 4;
const U_PORTRAIT: number = 5;

function authorAvatarUrl(portrait: string): string {
  return portrait.length === 0 ? '' : `https://himg.bdimg.com/sys/portrait/item/${portrait}`;
}

export class PersonalizedThread {
  tid: number = 0;
  title: string = '';
  summary: string = '';

  replyCount: number = 0;

  viewCount: number = 0;
  agreeCount: number = 0;

  lastTimeText: string = '';

  lastTimeMs: number = 0;

  createTimeMs: number = 0;
  authorId: number = 0;
  authorName: string = '';
  authorNick: string = '';
  authorPortrait: string = '';
  forumId: number = 0;
  forumName: string = '';

  images: string[] = [];

  coverImage: string = '';
}

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
  const reader: ProtoReader = new ProtoReader(bytes);
  while (reader.hasMore()) {
    const f: number = reader.readTag();
    switch (f) {
      case T_TID:
        t.tid = Number(reader.readVarint());
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
      default:
        reader.skipField();
        break;
    }
  }
  return t;
}

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

    thread.summary += text;
  }
}

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

export function personalizedToBrief(t: PersonalizedThread): ThreadBrief {
  const b: ThreadBrief = new ThreadBrief();
  b.tid = t.tid;
  b.title = t.title;
  b.summary = t.summary;
  b.authorId = t.authorId;
  b.authorName = t.authorNick.length > 0 ? t.authorNick : t.authorName;
  b.authorAvatar = authorAvatarUrl(t.authorPortrait);

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

export function personalizedToBriefs(items: PersonalizedThread[]): ThreadBrief[] {
  const out: ThreadBrief[] = [];
  for (let i = 0; i < items.length; i++) {
    out.push(personalizedToBrief(items[i]));
  }
  return out;
}
