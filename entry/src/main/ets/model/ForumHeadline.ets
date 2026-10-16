

import { ProtoReader, WireType } from '../proto/ProtoWire';

const RES_ERROR = 1;
const RES_DATA = 2;

const ERROR_ERRNO = 1;

const DATA_HEADLINE = 52;
const DATA_HEAD_SDK = 34;

const HEADLINE_IMG_URL = 4;

const HEAD_SDK_PIC = 1;

export class ForumHeadlineResult {

  imgUrl: string = '';

  headPic: string = '';

  errorno: number = -1;

  resolved(): string {
    return this.imgUrl.length > 0 ? this.imgUrl : this.headPic;
  }
}

export function parseForumHeadlineProto(bytes: Uint8Array): ForumHeadlineResult {
  const out: ForumHeadlineResult = new ForumHeadlineResult();
  if (bytes.length === 0) {
    return out;
  }
  try {
    const root: ProtoReader = new ProtoReader(bytes);
    while (root.hasMore()) {
      const f: number = root.readTag();
      if (f === RES_ERROR && root.wireType === WireType.LENGTH_DELIMITED) {

        const err: ProtoReader = root.readMessageView();
        while (err.hasMore()) {
          const ef: number = err.readTag();
          if (ef === ERROR_ERRNO && err.wireType === WireType.VARINT) {
            out.errorno = Number(err.readInt64());
          } else {
            err.skipField();
          }
        }
      } else if (f === RES_DATA && root.wireType === WireType.LENGTH_DELIMITED) {
        const data: ProtoReader = root.readMessageView();
        while (data.hasMore()) {
          const df: number = data.readTag();
          if (df === DATA_HEADLINE && data.wireType === WireType.LENGTH_DELIMITED) {
            out.imgUrl = readHeadlineImgUrl(data.readMessageView());
          } else if (df === DATA_HEAD_SDK && data.wireType === WireType.LENGTH_DELIMITED) {
            out.headPic = readHeadSdkPic(data.readMessageView());
          } else {
            data.skipField();
          }
        }
      } else {
        root.skipField();
      }
    }
  } catch (err) {

    return new ForumHeadlineResult();
  }
  return out;
}

function readHeadlineImgUrl(r: ProtoReader): string {
  let url: string = '';
  while (r.hasMore()) {
    const f: number = r.readTag();
    if (f === HEADLINE_IMG_URL && r.wireType === WireType.LENGTH_DELIMITED) {
      url = r.readString();
    } else {
      r.skipField();
    }
  }
  return url;
}

function readHeadSdkPic(r: ProtoReader): string {
  let pic: string = '';
  while (r.hasMore()) {
    const f: number = r.readTag();
    if (f === HEAD_SDK_PIC && r.wireType === WireType.LENGTH_DELIMITED) {
      pic = r.readString();
    } else {
      r.skipField();
    }
  }
  return pic;
}

class RawHeadImg {
  img_url: string = '';
}

class RawActivityHead {
  head_imgs: RawHeadImg[] = [];
}

class RawFrsBottom {
  error_code: number = -1;
  activityhead: RawActivityHead | null = null;
}

export function parseForumHeadlineJson(text: string): ForumHeadlineResult {
  const out: ForumHeadlineResult = new ForumHeadlineResult();
  const trimmed: string = text.trim();
  if (trimmed.length === 0) {
    return out;
  }
  try {
    const raw = JSON.parse(trimmed) as RawFrsBottom;
    out.errorno = raw.error_code;

    let imgs: RawHeadImg[] | null = null;
    if (raw.activityhead) {
      imgs = raw.activityhead.head_imgs;
    }
    if (imgs !== null && imgs !== undefined) {
      for (let i = 0; i < imgs.length; i++) {
        const url: string = (imgs[i].img_url ?? '').trim();
        if (url.length > 0) {
          out.imgUrl = url;
          break;
        }
      }
    }
  } catch (err) {

    return new ForumHeadlineResult();
  }
  return out;
}

const MAX_ENTRIES: number = 256;

const headlineCache: Map<string, string> = new Map();

export function putForumHeadline(forumName: string, url: string): void {
  const name: string = forumName.trim();
  const value: string = url.trim();
  if (name.length === 0 || value.length === 0) {
    return;
  }
  if (!headlineCache.has(name) && headlineCache.size >= MAX_ENTRIES) {

    const oldest: IteratorResult<string> = headlineCache.keys().next();
    if (!oldest.done) {
      headlineCache.delete(oldest.value);
    }
  }
  headlineCache.set(name, value);
}

export function getForumHeadline(forumName: string): string {
  const name: string = forumName.trim();
  if (name.length === 0) {
    return '';
  }
  return headlineCache.get(name) ?? '';
}

export function forumHeadlineCount(): number {
  return headlineCache.size;
}

export function clearForumHeadlines(): void {
  headlineCache.clear();
}
