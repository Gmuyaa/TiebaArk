

import {
  RawAgree, RawContentItem, RawDetailForum, RawDetailPage, RawPost, RawSubPost, RawSubPostPage,
  RawSubPostPageResponse, RawThreadHead, RawThreadPage, RawUser
} from '../api/RawThreadPage';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { VoiceClip, parseVoiceClip, voiceClipLabel } from './VoiceClip';
import { VideoClip, parseVideoClip } from './VideoClip';

const FLOW_TAG: string = 'AgreeFlow';
const FLOW_DOMAIN: number = 0x0000;

function toFlag(value: number | undefined): boolean {
  return value === 1;
}

function toNum(value: number | undefined): number {
  return value === undefined ? 0 : value;
}

function toStr(value: string | undefined): string {
  return value === undefined ? '' : value;
}

function pad2(value: number): string {
  return value < 10 ? `0${value}` : String(value);
}

export function portraitUrl(portrait: string, revision: number = 0): string {
  if (portrait.length === 0) {
    return '';
  }
  const url: string = `https://himg.bdimg.com/sys/portrait/item/${portrait}`;
  if (!Number.isFinite(revision) || revision <= 0) { return url; }
  const query: number = url.indexOf('?');
  const base: string = query < 0 ? url : url.substring(0, query);
  const fields: string[] = query < 0 ? [] : url.substring(query + 1).split('&')
    .filter((field: string) => field.length > 0 && field.split('=')[0] !== 't');
  fields.push(`t=${revision}`);
  return `${base}?${fields.join('&')}`;
}

const EMOJI_PREFIXES: string[] = ['image_emoticon', 'shoubai_emoji_face_'];

const EMOJI_HD_BASE: string = 'https://tb3.bdstatic.com/emoji/';

const EMOJI_SD_BASE: string = 'https://tb2.bdstatic.com/tb/editor/images/client/';

const EMOJI_LEGACY_FACE_BASE: string = 'https://tb3.bdstatic.com/tb/editor/images/face/';

const EMOJI_RAW_PREFIX: string = 'rawfile://emoji/';

export function emojiImageUrl(code: string): string {
  let isBareEmoticon: boolean = code === 'image_emoticon';
  let prefix: string = '';
  let suffix: string = '';
  let known: boolean = false;
  for (let i = 0; i < EMOJI_PREFIXES.length; i++) {
    const p: string = EMOJI_PREFIXES[i];
    if (code.startsWith(p) && code.length > p.length) {
      prefix = p;
      suffix = code.substring(p.length);
      known = true;
      break;
    }
  }
  if (isBareEmoticon) {

    return `${EMOJI_RAW_PREFIX}image_emoticon1.png`;
  }
  if (!known || suffix.length === 0) {
    return '';
  }

  for (let i = 0; i < suffix.length; i++) {
    const ch: string = suffix[i];
    if (ch < '0' || ch > '9') {
      return '';
    }
  }
  if (prefix === 'image_emoticon') {
    const n: number = Number(suffix);
    if (n === 1) {

      return `${EMOJI_RAW_PREFIX}image_emoticon1.png`;
    }
    if (n >= 51 && n <= 60) {

      const nn: string = n < 10 ? `0${n}` : `${n}`;
      return n <= 55
        ? `${EMOJI_LEGACY_FACE_BASE}i_f${nn}.png`
        : `${EMOJI_LEGACY_FACE_BASE}i_f${nn}.gif`;
    }
    if ((n >= 2 && n <= 50) || (n >= 61 && n <= 131)) {

      return `${EMOJI_RAW_PREFIX}${code}.png`;
    }

    return `${EMOJI_HD_BASE}${code}@2x.png`;
  }

  if (prefix === 'shoubai_emoji_face_') {
    const sn: number = Number(suffix);
    if (sn === 107 || sn === 109 || sn === 204) {
      return '';
    }
    const nn: string = sn < 10 ? `0${sn}` : `${sn}`;
    return `https://tb3.bdstatic.com/shoubai_emoji/shoubai_emoji_face_${nn}.webp`;
  }
  return `${EMOJI_SD_BASE}${code}.png`;
}

export function formatPostTime(ms: number, nowMs: number): string {
  if (ms <= 0) {
    return '';
  }
  const d: Date = new Date(ms);
  const now: Date = new Date(nowMs);
  const sameDay: boolean = d.getFullYear() === now.getFullYear()
    && d.getMonth() === now.getMonth() && d.getDate() === now.getDate();
  if (sameDay) {
    return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
  }
  if (d.getFullYear() === now.getFullYear()) {
    return `${d.getMonth() + 1}-${d.getDate()} ${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
  }
  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
}

export function formatThreadHeadTime(ms: number, nowMs: number): string {
  if (ms <= 0) {
    return '';
  }
  const d: Date = new Date(ms);
  const now: Date = new Date(nowMs);
  if (d.getFullYear() !== now.getFullYear()) {
    return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
  }
  return `${d.getMonth() + 1}-${d.getDate()} ${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

export function resolveRealLink(link: string): string {
  let current: string = link.trim();

  for (let depth = 0; depth < 3; depth++) {
    if (!/^https?:\/\/(?:tieba\.baidu\.com|www\.tieba\.com)\/mo\/q\/checkurl\?/i.test(current)) {
      break;
    }
    const match: RegExpMatchArray | null = current.match(/[?&]url=([^&#]*)/);
    if (match === null || match[1].length === 0) {
      break;
    }
    try {
      const decoded: string = decodeURIComponent(match[1]);
      if (decoded === current) {
        break;
      }
      current = decoded;
    } catch (err) {
      break;
    }
  }
  return current;
}

export function webLinkUrl(link: string): string {
  const real: string = resolveRealLink(link);
  const url: string = /^www\./i.test(real) ? `https://${real}` : real;
  return /^https?:\/\/[^\s/?#@]+(?:[/?#][^\s]*)?$/i.test(url) ? url : '';
}

export function hostOf(url: string): string {
  const match: RegExpMatchArray | null = url.match(/^(?:https?:\/\/)?([^/?#]+)/i);
  return match === null ? '' : match[1];
}

export function linkLabel(link: string, text: string = ''): string {
  if (text.length > 0 && text !== '网页链接' && !/^(?:https?:\/\/|www\.)/i.test(text)) {
    return text;
  }
  const host: string = hostOf(resolveRealLink(link));
  return host.length > 0 ? host : (text.length > 0 ? text : '网页链接');
}

export enum ContentDestinationKind {
  INVALID = 0,
  WEB = 1,
  THREAD = 2,
  FORUM = 3,
  SEARCH = 4
}

export class ContentDestination {
  kind: ContentDestinationKind = ContentDestinationKind.INVALID;
  url: string = '';
  tid: number = 0;
  word: string = '';
}

export function contentDestination(piece: ContentPiece): ContentDestination {
  const target: ContentDestination = new ContentDestination();
  if (piece.kind === ContentKind.TOPIC && piece.link.length === 0) {
    target.word = piece.text.replace(/^#+|#+$/g, '').trim();
    if (target.word.length > 0) {
      target.kind = ContentDestinationKind.SEARCH;
    }
    return target;
  }
  target.url = webLinkUrl(piece.link);
  if (target.url.length === 0) {
    return target;
  }
  target.kind = ContentDestinationKind.WEB;
  const match: RegExpMatchArray | null = target.url.match(/^https?:\/\/(?:tieba\.baidu\.com|www\.tieba\.com)(\/[^#]*)?(?:#.*)?$/i);
  if (match === null) {
    return target;
  }
  const path: string = match[1] === undefined ? '/' : match[1];
  const post: RegExpMatchArray | null = path.match(/^\/p\/(\d+)(?:[/?]|$)/);
  if (post !== null) {
    const tid: number = Number(post[1]);
    if (Number.isSafeInteger(tid) && tid > 0) {
      target.kind = ContentDestinationKind.THREAD;
      target.tid = tid;
    }
  } else if (/^\/f(?:\?|$)/.test(path)) {
    const forum: RegExpMatchArray | null = path.match(/[?&]kw=([^&#]+)/);
    if (forum !== null) {
      try {
        target.word = decodeURIComponent(forum[1].replace(/\+/g, ' ')).trim();
        if (target.word.length > 0) {
          target.kind = ContentDestinationKind.FORUM;
        }
      } catch (err) {

      }
    }
  }
  return target;
}

export enum ContentKind {

  VOICE = 10,

  TEXT = 0,

  LINK = 1,

  EMOJI = 2,

  IMAGE = 3,

  REPLY_TARGET = 4,

  TOPIC = 5,

  UNKNOWN = 99
}

export class ContentPiece {
  voice: VoiceClip | undefined = undefined;
  kind: ContentKind = ContentKind.TEXT;

  text: string = '';

  link: string = '';

  emojiUrl: string = '';

  emojiName: string = '';

  imageUrl: string = '';

  originImageUrl: string = '';

  width: number = 0;
  height: number = 0;

  static listFromRaw(items: RawContentItem[] | undefined): ContentPiece[] {
    const out: ContentPiece[] = [];
    if (items === undefined) {
      return out;
    }
    for (let i = 0; i < items.length; i++) {
      const raw: RawContentItem = items[i];
      if (toNum(raw.type) === 0 && toStr(raw.link).length === 0) {
        const textPieces: ContentPiece[] = ContentPiece.splitTextAndEmoji(toStr(raw.text));
        for (let j = 0; j < textPieces.length; j++) {
          out.push(textPieces[j]);
        }
      } else {
        out.push(ContentPiece.fromRaw(raw));
      }
    }
    return out;
  }

  private static splitTextAndEmoji(text: string): ContentPiece[] {
    const out: ContentPiece[] = [];
    let plainStart: number = 0;
    let cursor: number = 0;

    while (cursor < text.length) {

      const initial: string = text[cursor].toLowerCase();
      const rest: string = initial === 'h' || initial === 'w' || initial === '#'
        ? text.substring(cursor) : '';
      const urlMatch: RegExpMatchArray | null = rest.match(/^(?:https?:\/\/|www\.)[^\s<>"“”‘’，。！？、；]+/i);
      const topicMatch: RegExpMatchArray | null = rest.match(/^(##?)([^#\r\n]{1,100})\1/);
      let interactive: ContentPiece | null = null;
      let end: number = cursor;
      if (urlMatch !== null && (cursor === 0 || !/[a-z0-9_@]/i.test(text[cursor - 1]))) {
        let url: string = urlMatch[0].replace(/[.,!;?:]+$/g, '');

        while (url.endsWith(')') && url.split(')').length > url.split('(').length) {
          url = url.substring(0, url.length - 1);
        }
        if (webLinkUrl(url).length > 0) {
          interactive = new ContentPiece();
          interactive.kind = ContentKind.LINK;
          interactive.text = url;
          interactive.link = webLinkUrl(url);
          end = cursor + url.length;
        }
      } else if (topicMatch !== null && topicMatch[2].trim().length > 0) {
        interactive = new ContentPiece();
        interactive.kind = ContentKind.TOPIC;
        interactive.text = topicMatch[0];
        end = cursor + topicMatch[0].length;
      }
      if (interactive !== null) {
        if (cursor > plainStart) {
          out.push(ContentPiece.textPiece(text.substring(plainStart, cursor)));
        }
        out.push(interactive);
        cursor = end;
        plainStart = end;
        continue;
      }
      let prefix: string = '';
      for (let i = 0; i < EMOJI_PREFIXES.length; i++) {
        if (text.startsWith(EMOJI_PREFIXES[i], cursor)) {
          prefix = EMOJI_PREFIXES[i];
          break;
        }
      }
      if (prefix.length === 0) {
        cursor++;
        continue;
      }

      const digitStart: number = cursor + prefix.length;
      let codeEnd: number = digitStart;
      while (codeEnd < text.length && text[codeEnd] >= '0' && text[codeEnd] <= '9') {
        codeEnd++;
      }

      if (codeEnd === digitStart) {
        if (prefix === 'image_emoticon' && !ContentPiece.tokenContinues(text, codeEnd)) {
          if (cursor > plainStart) {
            out.push(ContentPiece.textPiece(text.substring(plainStart, cursor)));
          }
          const bare: ContentPiece = new ContentPiece();
          bare.kind = ContentKind.EMOJI;
          bare.text = 'image_emoticon1';
          bare.emojiUrl = emojiImageUrl(bare.text);
          out.push(bare);
          cursor = codeEnd;
          plainStart = codeEnd;
          continue;
        }
        cursor++;
        continue;
      }

      if (cursor > plainStart) {
        out.push(ContentPiece.textPiece(text.substring(plainStart, cursor)));
      }
      const code: string = text.substring(cursor, codeEnd);
      const emoji: ContentPiece = new ContentPiece();
      emoji.kind = ContentKind.EMOJI;
      emoji.text = code;
      emoji.emojiUrl = emojiImageUrl(code);
      out.push(emoji);

      cursor = codeEnd;
      plainStart = codeEnd;
    }

    if (plainStart < text.length || out.length === 0) {
      out.push(ContentPiece.textPiece(text.substring(plainStart)));
    }
    return out;
  }

  private static textPiece(text: string): ContentPiece {
    const piece: ContentPiece = new ContentPiece();
    piece.kind = ContentKind.TEXT;
    piece.text = text;
    return piece;
  }

  private static tokenContinues(text: string, at: number): boolean {
    if (at >= text.length) {
      return false;
    }
    const ch: string = text[at];
    return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch === '_';
  }

  private static fromRaw(raw: RawContentItem): ContentPiece {
    const c: ContentPiece = new ContentPiece();
    const type: number = toNum(raw.type);
    c.text = toStr(raw.text);

    if (type === 10) {
      c.kind = ContentKind.VOICE;
      c.voice = parseVoiceClip(raw);

      c.text = voiceClipLabel(c.voice);
      return c;
    }

    if (type === 1 || (type !== 2 && type !== 3 && type !== 4 && toStr(raw.link).length > 0)) {
      c.kind = /^(##?)[^#\r\n]{1,100}\1$/.test(c.text) ? ContentKind.TOPIC : ContentKind.LINK;
      c.link = toStr(raw.link);

      if (c.text.length === 0) {
        c.text = '网页链接';
      }
      return c;
    }
    if (type === 2) {
      c.kind = ContentKind.EMOJI;
      c.emojiName = toStr(raw.c);
      c.emojiUrl = emojiImageUrl(c.text);
      return c;
    }
    if (type === 3) {
      c.kind = ContentKind.IMAGE;

      const active: string = toStr(raw.cdn_src_active);
      const normal: string = toStr(raw.cdn_src);
      c.imageUrl = active.length > 0 ? active : normal;
      c.originImageUrl = toStr(raw.origin_src);
      const size: number[] = ContentPiece.parseSize(toStr(raw.bsize));
      c.width = size[0];
      c.height = size[1];
      return c;
    }
    if (type === 4) {
      c.kind = ContentKind.REPLY_TARGET;
      return c;
    }
    c.kind = /^(##?)[^#\r\n]{1,100}\1$/.test(c.text)
      ? ContentKind.TOPIC : (type === 0 ? ContentKind.TEXT : ContentKind.UNKNOWN);
    return c;
  }

  private static parseSize(bsize: string): number[] {
    const result: number[] = [0, 0];
    if (bsize.length === 0) {
      return result;
    }
    const comma: number = bsize.indexOf(',');
    if (comma <= 0) {
      return result;
    }
    const w: number = Number.parseInt(bsize.substring(0, comma), 10);
    const h: number = Number.parseInt(bsize.substring(comma + 1), 10);
    if (!Number.isNaN(w)) {
      result[0] = w;
    }
    if (!Number.isNaN(h)) {
      result[1] = h;
    }
    return result;
  }
}

export class ContentImage {

  imageUrl: string = '';

  originImageUrl: string = '';

  width: number = 0;
  height: number = 0;
}

export class ContentBlock {
  isVoice: boolean = false;
  voice: VoiceClip | undefined = undefined;

  isImage: boolean = false;

  images: ContentImage[] = [];

  imageStartIndex: number = 0;

  imageUrl: string = '';

  originImageUrl: string = '';

  width: number = 0;
  height: number = 0;

  pieces: ContentPiece[] = [];
}

export function groupContentBlocks(pieces: ContentPiece[]): ContentBlock[] {
  const blocks: ContentBlock[] = [];
  let pending: ContentPiece[] = [];

  let imageCount: number = 0;

  const flush = (): void => {
    if (pending.length === 0) {
      return;
    }
    const b: ContentBlock = new ContentBlock();
    b.isImage = false;
    b.pieces = pending;
    blocks.push(b);
    pending = [];
  };

  const appendImage = (block: ContentBlock, piece: ContentPiece): void => {
    const img: ContentImage = new ContentImage();
    img.imageUrl = piece.imageUrl;
    img.originImageUrl = piece.originImageUrl;
    img.width = piece.width;
    img.height = piece.height;
    block.images.push(img);
    if (block.images.length === 1) {
      block.imageStartIndex = imageCount;
    }

    block.imageUrl = block.images[0].imageUrl;
    block.originImageUrl = block.images[0].originImageUrl;
    block.width = block.images[0].width;
    block.height = block.images[0].height;
  };

  for (let i = 0; i < pieces.length; i++) {
    const p: ContentPiece = pieces[i];
    if (p.kind === ContentKind.VOICE) {
      flush(); const voiceBlock: ContentBlock = new ContentBlock();
      voiceBlock.isVoice = true; voiceBlock.voice = p.voice; voiceBlock.pieces = [p];
      blocks.push(voiceBlock); continue;
    }
    if (p.kind === ContentKind.IMAGE) {

      flush();

      if (blocks.length > 0 && blocks[blocks.length - 1].isImage) {
        appendImage(blocks[blocks.length - 1], p);
      } else {
        const gallery: ContentBlock = new ContentBlock();
        gallery.isImage = true;
        appendImage(gallery, p);
        blocks.push(gallery);
      }
      imageCount++;
    } else {
      pending.push(p);
    }
  }
  flush();
  return blocks;
}

export const FALLBACK_IMAGE_ASPECT: number = 1.5;

export const GALLERY_ASPECT_MIN: number = 0.66;
export const GALLERY_ASPECT_MAX: number = 1.6;

export function imageAspectRatio(img: ContentImage): number {
  if (img.width > 0 && img.height > 0) {
    return img.width / img.height;
  }
  return 0;
}

export function galleryAspectRatio(images: ContentImage[]): number {
  if (images.length === 0) {
    return FALLBACK_IMAGE_ASPECT;
  }
  let sum: number = 0;
  for (let i = 0; i < images.length; i++) {
    const ratio: number = imageAspectRatio(images[i]);
    sum += ratio > 0 ? ratio : FALLBACK_IMAGE_ASPECT;
  }
  const avg: number = sum / images.length;
  if (avg < GALLERY_ASPECT_MIN) {
    return GALLERY_ASPECT_MIN;
  }
  if (avg > GALLERY_ASPECT_MAX) {
    return GALLERY_ASPECT_MAX;
  }
  return avg;
}

export function collectPreviewImageUrls(pieces: ContentPiece[]): string[] {
  const urls: string[] = [];
  for (let i = 0; i < pieces.length; i++) {
    const piece: ContentPiece = pieces[i];
    if (piece.kind !== ContentKind.IMAGE) {
      continue;
    }
    const url: string = piece.originImageUrl.length > 0 ? piece.originImageUrl : piece.imageUrl;
    if (url.length > 0) {
      urls.push(url);
    }
  }
  return urls;
}

function stripLeadingSeparator(text: string): string {
  let i: number = 0;
  while (i < text.length) {
    const ch: string = text[i];
    if (ch === ' ' || ch === ':' || ch === '：') {
      i++;
    } else {
      break;
    }
  }
  return text.substring(i);
}

export class ReplyTargetParse {

  replyToName: string = '';

  contents: ContentPiece[] = [];
}

export function parseReplyTarget(pieces: ContentPiece[]): ReplyTargetParse {
  const out: ReplyTargetParse = new ReplyTargetParse();
  out.contents = pieces;

  if (pieces.length < 2) {
    return out;
  }
  if (pieces[0].kind !== ContentKind.TEXT || pieces[1].kind !== ContentKind.REPLY_TARGET) {
    return out;
  }
  const lead: string = pieces[0].text.trim();
  if (lead !== '回复') {
    return out;
  }

  out.replyToName = pieces[1].text;
  const rest: ContentPiece[] = pieces.slice(2);
  if (rest.length > 0 && rest[0].kind === ContentKind.TEXT) {
    const first: ContentPiece = new ContentPiece();
    first.kind = rest[0].kind;
    first.text = stripLeadingSeparator(rest[0].text);
    first.link = rest[0].link;
    first.emojiUrl = rest[0].emojiUrl;
    first.emojiName = rest[0].emojiName;
    first.imageUrl = rest[0].imageUrl;
    first.originImageUrl = rest[0].originImageUrl;
    first.width = rest[0].width;
    first.height = rest[0].height;
    rest[0] = first;
  }
  out.contents = rest;
  return out;
}

export class UserBrief {
  id: number = 0;

  displayName: string = '';

  userName: string = '';

  portraitUrl: string = '';

  level: number = 0;
  levelName: string = '';

  ipLocation: string = '';

  isBawu: boolean = false;

  bawuTitle: string = '';

  static fromRaw(raw: RawUser | undefined): UserBrief {
    const u: UserBrief = new UserBrief();
    if (raw === undefined) {

      u.displayName = '匿名用户';
      return u;
    }
    u.id = toNum(raw.id);
    u.userName = toStr(raw.name);
    const show: string = toStr(raw.name_show);
    u.displayName = show.length > 0 ? show : (u.userName.length > 0 ? u.userName : '匿名用户');
    u.portraitUrl = portraitUrl(toStr(raw.portrait));
    u.level = toNum(raw.level_id);
    u.levelName = toStr(raw.level_name);
    u.ipLocation = toStr(raw.ip_address);
    u.isBawu = toFlag(raw.is_bawu);
    const grade = raw.bazhu_grade;
    u.bawuTitle = grade === undefined ? '' : toStr(grade.desc);
    return u;
  }
}

export function mergeAuthorFallback(primary: UserBrief, fallback: UserBrief | undefined): UserBrief {
  if (fallback === undefined) {
    return primary;
  }

  if (primary.id <= 0) {
    return fallback;
  }
  const out: UserBrief = new UserBrief();
  out.id = primary.id;

  out.displayName = primary.displayName;
  out.userName = primary.userName.length > 0 ? primary.userName : fallback.userName;
  out.portraitUrl = primary.portraitUrl.length > 0 ? primary.portraitUrl : fallback.portraitUrl;
  out.level = primary.level > 0 ? primary.level : fallback.level;
  out.levelName = primary.levelName.length > 0 ? primary.levelName : fallback.levelName;
  out.ipLocation = primary.ipLocation.length > 0 ? primary.ipLocation : fallback.ipLocation;
  out.isBawu = primary.isBawu || fallback.isBawu;
  out.bawuTitle = primary.bawuTitle.length > 0 ? primary.bawuTitle : fallback.bawuTitle;
  return out;
}

export class DetailPageInfo {
  currentPage: number = 1;
  pageSize: number = 0;

  totalCount: number = 0;
  totalPage: number = 0;
  hasMore: boolean = false;
}

export enum ReplySortType {
  ASC = 0,
  DESC = 1,
  HOT = 2,
  ONLY_AUTHOR = 3
}

export function isReplySortSupported(type: ReplySortType): boolean {
  return type !== ReplySortType.HOT;
}

export function unsupportedSortTip(type: ReplySortType): string {
  return type === ReplySortType.HOT
    ? '热门排序：贴吧接口暂不支持（服务端会忽略排序参数）'
    : '该排序暂不支持';
}

export const AGREE_OBJ_TYPE_THREAD: number = 3;

export function isAgreeSupported(objType: number): boolean {
  return objType === 1 || objType === 2 || objType === AGREE_OBJ_TYPE_THREAD;
}

export function unsupportedAgreeTip(objType: number): string {
  if (isAgreeSupported(objType)) {
    return '';
  }
  return '点赞结果需以服务端最终状态为准';
}

export function resolveAgreeLiked(serverAgreed: boolean, localToggled: boolean): boolean {
  return serverAgreed !== localToggled;
}

export function resolveAgreeCount(serverCount: number, serverAgreed: boolean,
  localToggled: boolean): number {
  const likedNow: boolean = resolveAgreeLiked(serverAgreed, localToggled);
  const delta: number = (likedNow ? 1 : 0) - (serverAgreed ? 1 : 0);
  const result: number = serverCount + delta;
  return result < 0 ? 0 : result;
}

export function resolveForumName(responseName: string, sourceName: string): string {
  const fromResponse: string = responseName.trim();
  if (fromResponse.length > 0) {
    return fromResponse;
  }
  return sourceName.trim();
}

export const FORUM_CHIP_PLACEHOLDER: string = '贴吧';

export function forumChipText(responseName: string, sourceName: string): string {
  const name: string = resolveForumName(responseName, sourceName);
  return name.length > 0 ? name : FORUM_CHIP_PLACEHOLDER;
}

export class PostItem {

  pid: number = 0;

  floor: number = 0;

  title: string = '';
  timeMs: number = 0;

  timeText: string = '';
  author: UserBrief = new UserBrief();
  contents: ContentPiece[] = [];

  agreeCount: number = 0;

  isAgreed: boolean = false;

  subPostCount: number = 0;

  isFold: boolean = false;
  foldTip: string = '';

  static fromRaw(raw: RawPost, users: Map<number, UserBrief>, nowMs: number): PostItem {
    const p: PostItem = new PostItem();
    p.pid = toNum(raw.id);
    p.floor = toNum(raw.floor);
    p.title = toStr(raw.title);
    p.timeMs = toNum(raw.time) * 1000;
    p.timeText = formatPostTime(p.timeMs, nowMs);
    p.author = PostItem.lookupUser(users, toNum(raw.author_id));
    p.contents = ContentPiece.listFromRaw(raw.content);
    const agree = raw.agree;
    p.agreeCount = agree === undefined ? 0 : toNum(agree.agree_num);
    p.isAgreed = agree === undefined ? false : toFlag(agree.has_agree);
    p.subPostCount = toNum(raw.sub_post_number);
    p.isFold = toFlag(raw.is_fold);
    p.foldTip = toStr(raw.fold_tip);
    return p;
  }

  private static lookupUser(users: Map<number, UserBrief>, uid: number): UserBrief {
    const found: UserBrief | undefined = users.get(uid);
    return found === undefined ? UserBrief.fromRaw(undefined) : found;
  }
}

export function copyPostItem(src: PostItem): PostItem {
  const c: PostItem = new PostItem();
  c.pid = src.pid;
  c.floor = src.floor;
  c.title = src.title;
  c.timeMs = src.timeMs;
  c.timeText = src.timeText;
  c.author = src.author;
  c.contents = src.contents;
  c.agreeCount = src.agreeCount;
  c.isAgreed = src.isAgreed;
  c.subPostCount = src.subPostCount;
  c.isFold = src.isFold;
  c.foldTip = src.foldTip;
  return c;
}

export class SubPostItem {
  pid: number = 0;
  timeMs: number = 0;
  timeText: string = '';
  author: UserBrief = new UserBrief();
  contents: ContentPiece[] = [];

  isThreadAuthor: boolean = false;

  replyToName: string = '';

  replyToIsThreadAuthor: boolean = false;

  agreeCount: number = 0;
  isAgreed: boolean = false;
}

export class ThreadDetail {
  video: VideoClip | undefined = undefined;
  tid: number = 0;
  title: string = '';
  replyCount: number = 0;
  agreeCount: number = 0;

  mainPostId: number = 0;

  isAgreed: boolean = false;
  createTimeMs: number = 0;

  isStored: boolean = false;

  author: UserBrief = new UserBrief();

  posts: PostItem[] = [];

  forumName: string = '';
  forumId: number = 0;

  forumAvatar: string = '';

  forumMemberNum: number = 0;
  page: DetailPageInfo = new DetailPageInfo();

  static fromRaw(raw: RawThreadPage, tid: number, nowMs: number): ThreadDetail {
    const d: ThreadDetail = new ThreadDetail();
    d.tid = tid;

    const users: Map<number, UserBrief> = new Map<number, UserBrief>();
    const rawUsers: RawUser[] | undefined = raw.user_list;
    if (rawUsers !== undefined) {
      for (let i = 0; i < rawUsers.length; i++) {
        const u: UserBrief = UserBrief.fromRaw(rawUsers[i]);
        users.set(u.id, u);
      }
    }

    const thread: RawThreadHead | undefined = raw.thread;

    let threadAgree: RawAgree | undefined = undefined;
    if (thread !== undefined) {
      d.video = parseVideoClip(thread.video_info);
      d.title = toStr(thread.title);

      d.replyCount = Math.max(0, toNum(thread.reply_num) - 1);
      threadAgree = thread.agree;

      d.agreeCount = threadAgree === undefined ? toNum(thread.agree_num) : toNum(threadAgree.agree_num);

      d.mainPostId = toNum(thread.post_id);
      d.createTimeMs = toNum(thread.create_time) * 1000;

      d.isStored = toNum(thread.collect_status) !== 0;
      d.author = UserBrief.fromRaw(thread.author);
    }

    const forum: RawDetailForum | undefined = raw.forum;
    if (forum !== undefined) {
      d.forumName = toStr(forum.name);
      d.forumId = toNum(forum.id);
      d.forumAvatar = toStr(forum.avatar);
      d.forumMemberNum = toNum(forum.member_num);
    }

    const page: RawDetailPage | undefined = raw.page;
    if (page !== undefined) {
      const current: number = toNum(page.current_page);
      d.page.currentPage = current === 0 ? 1 : current;
      d.page.pageSize = toNum(page.page_size);
      d.page.totalCount = toNum(page.total_num);
      d.page.totalPage = toNum(page.total_page);
      d.page.hasMore = toFlag(page.has_more);
    }

    const posts: RawPost[] | undefined = raw.post_list;
    if (posts !== undefined) {
      for (let i = 0; i < posts.length; i++) {
        d.posts.push(PostItem.fromRaw(posts[i], users, nowMs));
      }
    }

    let fallback: UserBrief | undefined = users.get(d.author.id);
    if (fallback === undefined && d.posts.length > 0 && d.posts[0].floor === 1) {
      fallback = d.posts[0].author;
    }
    d.author = mergeAuthorFallback(d.author, fallback);

    if (d.posts.length > 0 && d.posts[0].floor === 1 && d.posts[0].title.length === 0) {
      d.posts[0].title = d.title;
    }

    const main: PostItem | undefined = ThreadDetail.locateMainPost(d);

    const floorRawAgreed: boolean = main === undefined ? false : main.isAgreed;
    const floorRawCount: number = main === undefined ? 0 : main.agreeCount;
    if (threadAgree !== undefined) {
      d.isAgreed = toFlag(threadAgree.has_agree);
      if (main !== undefined) {
        main.isAgreed = d.isAgreed;
        main.agreeCount = d.agreeCount;
      }
      hilog.info(FLOW_DOMAIN, FLOW_TAG,
        'source=thread.agree tid=%{public}d mainPostId=%{public}d'
          + ' theme[has_agree=%{public}d agree_num=%{public}d]'
          + ' floorRaw[has_agree=%{public}s agree_num=%{public}d]'
          + ' -> detail.isAgreed=%{public}s main.isAgreed=%{public}s main.agreeCount=%{public}d',
        tid, d.mainPostId, toFlag(threadAgree.has_agree) ? 1 : 0,
        threadAgree.agree_num === undefined ? 0 : threadAgree.agree_num,
        floorRawAgreed ? 1 : 0, floorRawCount,
        d.isAgreed ? 1 : 0, main === undefined ? -1 : (main.isAgreed ? 1 : 0),
        main === undefined ? -1 : main.agreeCount);
    } else if (main !== undefined) {
      d.isAgreed = main.isAgreed;

      if (d.agreeCount === 0 && main.agreeCount > 0) {
        d.agreeCount = main.agreeCount;
      }
      hilog.info(FLOW_DOMAIN, FLOW_TAG,
        'source=mainPost.agree(fallback:响应无thread.agree) tid=%{public}d mainPostId=%{public}d'
          + ' floorRaw[has_agree=%{public}s agree_num=%{public}d]'
          + ' -> detail.isAgreed=%{public}s detail.agreeCount=%{public}d',
        tid, d.mainPostId, floorRawAgreed ? 1 : 0, floorRawCount,
        d.isAgreed ? 1 : 0, d.agreeCount);
    }
    hilog.info(FLOW_DOMAIN, FLOW_TAG,
      'parse-done source=fromRaw tid=%{public}d mainPostId=%{public}d'
        + ' theme[has_agree=%{public}s] detail.isAgreed=%{public}s detail.agreeCount=%{public}d'
        + ' main.isAgreed=%{public}s main.agreeCount=%{public}d floorRaw.has_agree=%{public}s',
      tid, d.mainPostId, threadAgree === undefined ? 'absent' : String(toFlag(threadAgree.has_agree) ? 1 : 0),
      d.isAgreed ? 1 : 0, d.agreeCount,
      main === undefined ? -1 : (main.isAgreed ? 1 : 0),
      main === undefined ? -1 : main.agreeCount, floorRawAgreed ? 1 : 0);

    return d;
  }

  static locateMainPost(detail: ThreadDetail): PostItem | undefined {
    if (detail.mainPostId > 0) {
      for (let i = 0; i < detail.posts.length; i++) {
        if (detail.posts[i].pid === detail.mainPostId) {
          return detail.posts[i];
        }
      }

      return undefined;
    }
    for (let i = 0; i < detail.posts.length; i++) {
      if (detail.posts[i].floor === 1) {
        return detail.posts[i];
      }
    }
    return undefined;
  }
}

export function filterPostsByOp(posts: PostItem[], authorId: number): PostItem[] {
  if (authorId <= 0) {
    return posts;
  }
  const out: PostItem[] = [];
  for (let i = 0; i < posts.length; i++) {
    if (posts[i].author.id === authorId) {
      out.push(posts[i]);
    }
  }
  return out;
}

export class SubPostPage {
  subPosts: SubPostItem[] = [];

  totalCount: number = 0;
  currentPage: number = 1;
  totalPage: number = 1;
  hasMore: boolean = false;

  static fromRaw(raw: RawSubPostPageResponse, threadAuthorId: number, nowMs: number): SubPostPage {
    const p: SubPostPage = new SubPostPage();
    const authorName: string = SubPostPage.threadAuthorName(raw);
    const list: RawSubPost[] | undefined = raw.subpost_list;
    if (list !== undefined) {
      for (let i = 0; i < list.length; i++) {
        p.subPosts.push(SubPostPage.subFromRaw(list[i], threadAuthorId, authorName, nowMs));
      }
    }
    p.totalCount = toNum(raw.subpost_num);
    const page: RawSubPostPage | undefined = raw.page;
    if (page !== undefined) {
      const current: number = toNum(page.current_page);
      p.currentPage = current === 0 ? 1 : current;
      const totalPage: number = toNum(page.total_page);
      p.totalPage = totalPage === 0 ? 1 : totalPage;

      p.hasMore = p.currentPage < p.totalPage;
    }
    return p;
  }

  private static subFromRaw(raw: RawSubPost, threadAuthorId: number, threadAuthorName: string,
    nowMs: number): SubPostItem {
    const s: SubPostItem = new SubPostItem();
    s.pid = toNum(raw.id);
    s.timeMs = toNum(raw.time) * 1000;
    s.timeText = formatPostTime(s.timeMs, nowMs);
    s.author = UserBrief.fromRaw(raw.author);
    const parsed: ReplyTargetParse = parseReplyTarget(ContentPiece.listFromRaw(raw.content));
    s.contents = parsed.contents;
    s.replyToName = parsed.replyToName;
    s.isThreadAuthor = threadAuthorId !== 0 && s.author.id === threadAuthorId;
    s.replyToIsThreadAuthor = threadAuthorName.length > 0
      && s.replyToName.length > 0 && s.replyToName === threadAuthorName;
    const agree: RawAgree | undefined = raw.agree;
    s.agreeCount = agree === undefined ? 0 : toNum(agree.agree_num);
    s.isAgreed = agree === undefined ? false : toFlag(agree.has_agree);
    return s;
  }

  private static threadAuthorName(raw: RawSubPostPageResponse): string {
    const thread: RawThreadHead | undefined = raw.thread;
    if (thread === undefined) {
      return '';
    }
    const author: RawUser | undefined = thread.author;
    if (author === undefined) {
      return '';
    }
    const show: string = toStr(author.name_show);
    if (show.length > 0) {
      return show;
    }
    return toStr(author.name);
  }
}

export class SubPostThreadState {

  pid: number = 0;

  expanded: boolean = false;

  loading: boolean = false;

  loadedOnce: boolean = false;

  errorText: string = '';

  subPosts: SubPostItem[] = [];

  page: SubPostPage = new SubPostPage();

  hasMore: boolean = false;
}

export function subPostsHaveThreadAuthor(subPosts: SubPostItem[]): boolean {
  for (let i = 0; i < subPosts.length; i++) {
    if (subPosts[i].isThreadAuthor) {
      return true;
    }
  }
  return false;
}

function hasSubPostThreadState(states: SubPostThreadState[], pid: number): boolean {
  for (let i = 0; i < states.length; i++) {
    if (states[i].pid === pid) {
      return true;
    }
  }
  return false;
}

export function syncSubPostThreadStates(
  existing: SubPostThreadState[], posts: PostItem[]): SubPostThreadState[] {
  const next: SubPostThreadState[] = [];
  for (let i = 0; i < existing.length; i++) {
    next.push(existing[i]);
  }
  for (let i = 0; i < posts.length; i++) {
    const post: PostItem = posts[i];
    if (post.subPostCount <= 0) {
      continue;
    }
    if (!hasSubPostThreadState(next, post.pid)) {
      const state: SubPostThreadState = new SubPostThreadState();
      state.pid = post.pid;
      next.push(state);
    }
  }
  return next;
}

export const REPLY_EMOTICON_CODES: number[] = [
  1, 2, 3, 24, 22, 20, 66, 28, 67, 25,
  68, 12, 6, 8, 10, 9, 13, 33, 30, 16,
  11, 5, 4, 27, 69, 15, 70, 71, 19, 32,
  29, 72, 73, 17, 74, 75, 76, 26, 7, 14,
  18, 21, 23, 61, 97, 100, 95, 88, 91, 86,
  92, 93, 90, 85, 94, 87, 89, 98, 96, 133,
  99, 128, 126, 127, 130, 131, 136, 137, 134, 135,
  132, 129, 125, 34, 35, 36, 37, 38, 40, 39,
  41, 43, 44, 48, 47, 46, 50, 77, 78, 79,
  80, 81, 82, 83, 84, 45, 42
];
const REPLY_EMOTICON_TOKENS: string[] = [
  '#(呵呵)',
  '#(哈哈)',
  '#(吐舌)',
  '#(太开心)',
  '#(笑眼)',
  '#(花心)',
  '#(小乖)',
  '#(乖)',
  '#(捂嘴笑)',
  '#(滑稽)',
  '#(你懂的)',
  '#(不高兴)',
  '#(怒)',
  '#(汗)',
  '#(黑线)',
  '#(泪)',
  '#(真棒)',
  '#(喷)',
  '#(惊哭)',
  '#(阴险)',
  '#(鄙视)',
  '#(酷)',
  '#(啊)',
  '#(狂汗)',
  '#(what)',
  '#(疑问)',
  '#(酸爽)',
  '#(呀咩爹)',
  '#(委屈)',
  '#(惊讶)',
  '#(睡觉)',
  '#(笑尿)',
  '#(挖鼻)',
  '#(吐)',
  '#(犀利)',
  '#(小红脸)',
  '#(懒得理)',
  '#(勉强)',
  '#(开心)',
  '#(钱)',
  '#(咦)',
  '#(呼~)',
  '#(冷)',
  '#(升起)',
  '#(突然兴奋)',
  '#(黑头高兴)',
  '#(欢呼)',
  '#(嘿嘿嘿)',
  '#(微微一笑)',
  '#(吃瓜)',
  '#(托腮)',
  '#(摊手)',
  '#(困成狗)',
  '#(暗中观察)',
  '#(柯基暗中观察)',
  '#(喝酒)',
  '#(噗)',
  '#(紧张)',
  '#(炸药)',
  '#(香槟)',
  '#(黑头瞪眼)',
  '#(望远镜)',
  '#(不听)',
  '#(干饭)',
  '#(老虎)',
  '#(嗷呜)',
  '#(鼠1)',
  '#(鼠2)',
  '#(文字啊)',
  '#(文字对)',
  '#(烟花)',
  '#(菜狗)',
  '#(奥特曼)',
  '#(爱心)',
  '#(心碎)',
  '#(玫瑰)',
  '#(礼物)',
  '#(彩虹)',
  '#(太阳)',
  '#(星星月亮)',
  '#(钱币)',
  '#(茶杯)',
  '#(蛋糕)',
  '#(大拇指)',
  '#(胜利)',
  '#(haha)',
  '#(OK)',
  '#(沙发)',
  '#(手纸)',
  '#(香蕉)',
  '#(便便)',
  '#(药丸)',
  '#(红领巾)',
  '#(蜡烛)',
  '#(三道杠)',
  '#(音乐)',
  '#(灯泡)',
];

export function emojiTokenFromUrl(url: string): string {
  let file: string = url.substring(url.lastIndexOf('/') + 1);
  const dot: number = file.lastIndexOf('.');
  if (dot > 0) {
    file = file.substring(0, dot);
  }
  const at: number = file.lastIndexOf('@');
  if (at > 0) {
    file = file.substring(0, at);
  }
  const prefix: string = 'image_emoticon';
  if (!file.startsWith(prefix)) {
    return '';
  }
  const digits: string = file.substring(prefix.length);
  for (let i: number = 0; i < digits.length; i++) {
    if (digits[i] < '0' || digits[i] > '9') {
      return '';
    }
  }
  const code: number = digits.length === 0 ? 1 : Number(digits);
  const index: number = REPLY_EMOTICON_CODES.indexOf(code);
  return index < 0 ? '' : REPLY_EMOTICON_TOKENS[index];
}

export function emojiCodeFromReplyToken(token: string): string {
  const index: number = REPLY_EMOTICON_TOKENS.indexOf(token);
  return index < 0 ? '' : `image_emoticon${REPLY_EMOTICON_CODES[index]}`;
}
