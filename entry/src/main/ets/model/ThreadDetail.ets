/**
 * 帖子详情的领域模型。
 *
 * 与 `api/RawThreadPage.ets` 的分工：那边照抄服务端字段名，这边只保留界面要用的、
 * 且有确定值的信息。转换集中在各个 `from*` 静态方法里，服务端缺字段时落默认值，
 * UI 层因此不必写 `?? 0` 这类防御代码。
 *
 * 三处容易做错、已在注释里钉死的地方：
 *   1. 楼层作者是 `author_id` + 顶层 `user_list` 的映射，不是内联对象；
 *      而楼中楼作者是内联 `author`。两者共用 UserBrief，但取值路径不同。
 *   2. 显示名优先 `name_show`，空才用 `name`（实测两者常不同）。
 *   3. `bsize` 是 "宽,高" 的字符串，要拆成两个数；拆不出就留 0，由 UI 兜底。
 */

import {
  RawAgree, RawContentItem, RawDetailForum, RawDetailPage, RawPost, RawSubPost, RawSubPostPage,
  RawSubPostPageResponse, RawThreadHead, RawThreadPage, RawUser
} from '../api/RawThreadPage';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { VoiceClip, parseVoiceClip, voiceClipLabel } from './VoiceClip';
import { VideoClip, parseVideoClip } from './VideoClip';

const FLOW_TAG: string = 'AgreeFlow';
const FLOW_DOMAIN: number = 0x0000;

/** 把 0/1 标志位转成布尔。实测服务端只用 1 表示真，别的值一律当假 */
function toFlag(value: number | undefined): boolean {
  return value === 1;
}

/** 可空数字 → 数字 */
function toNum(value: number | undefined): number {
  return value === undefined ? 0 : value;
}

/** 可空字符串 → 字符串 */
function toStr(value: string | undefined): string {
  return value === undefined ? '' : value;
}

/** 两位补零。不用 padStart 是为了避免平台实现差异 */
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
/** 旧式 client 源（30×30）：只剩兜底分支用，正常路径不再命中 */
const EMOJI_SD_BASE: string = 'https://tb2.bdstatic.com/tb/editor/images/client/';

const EMOJI_LEGACY_FACE_BASE: string = 'https://tb3.bdstatic.com/tb/editor/images/face/';

const EMOJI_RAW_PREFIX: string = 'rawfile://emoji/';

/** 表情图源解析，兼容 image_emoticon 与 shoubai_emoji_face 标记。 */
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
    // 1 号 = 裸码文件；rawfile 内置包统一编号命名（image_emoticon1.png）
    return `${EMOJI_RAW_PREFIX}image_emoticon1.png`;
  }
  if (!known || suffix.length === 0) {
    return '';
  }
  // 前缀后面必须全是数字：`shoubai_emoji_face_`（缺下标）这类残码不能拼出地址
  for (let i = 0; i < suffix.length; i++) {
    const ch: string = suffix[i];
    if (ch < '0' || ch > '9') {
      return '';
    }
  }
  if (prefix === 'image_emoticon') {
    const n: number = Number(suffix);
    if (n === 1) {
      // 面板/正文传来的正常形态 image_emoticon1 与裸码同图（rawfile 统一编号）
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
    // 132-137：APK 内置只有 60×60，官方 tb3 CDN 更大（132=64、133=168×172、
    // 134-137=90）→ 保留在线源；138 起两处都 404，UI 自吞空图
    return `${EMOJI_HD_BASE}${code}@2x.png`;
  }
  // shoubai 族走官方 webp 高清源（90×90；HAR base.js getShoubaiEmojiSrc 同款
  // 拼接：两位补零编号、1-229 白名单；107/109/204 官方排除表内无文件，
  // 返回空串由 UI 退化成文字——对齐官方白名单行为）。旧 tb2 client png（30×30）
  // 保留作认知注释：该源仍 200 但仅为 1/3 尺寸。
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

/**
 * 楼层时间展示。纯函数，便于在 Node 上固定 now 做断言。
 *
 * 规则：同一天显示 "HH:mm"；同年显示 "M-D HH:mm"；跨年显示 "YYYY-M-D"。
 * 时间戳非法（<=0）时返回空串，界面据此不显示时间。
 */
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

/**
 * 主帖头部的时间文案。
 *
 * 与 `formatPostTime` 的唯一区别：**当天也要带日期**。
 * 回复只给 `HH:mm` 是因为它在对话上下文里，看不出是哪天也不影响阅读；
 * 而主帖头部回答的是"这帖什么时候发的"，光一个 `10:03` 没有信息量。
 * 其余规则（同年 `M-D HH:mm`、跨年带年份）两处保持一致。
 *
 * 时间戳非法（<=0）返回空串，界面据此只显示地区。
 * 纯函数，便于在 Node 上固定 now 做断言。
 */
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

/**
 * 从贴吧的跳转链接里取出真实目标地址。
 *
 * 实测链接片段的 link 是 `https://tieba.baidu.com/mo/q/checkurl?url=<URL编码的真实地址>&urlrefer=...`，
 * 直接展示这个只会看到一堆编码。取不到时原样返回，保证不丢信息。
 */
export function resolveRealLink(link: string): string {
  let current: string = link.trim();
  // 只解开贴吧自身的跳转包装；参数顺序可变，最多处理三层。
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

/** 只接受 HTTP(S) 网页地址，避免正文触发任意应用协议。 */
export function webLinkUrl(link: string): string {
  const real: string = resolveRealLink(link);
  const url: string = /^www\./i.test(real) ? `https://${real}` : real;
  return /^https?:\/\/[^\s/?#@]+(?:[/?#][^\s]*)?$/i.test(url) ? url : '';
}

/** 取 URL 的域名部分，查询参数和片段不属于域名。 */
export function hostOf(url: string): string {
  const match: RegExpMatchArray | null = url.match(/^(?:https?:\/\/)?([^/?#]+)/i);
  return match === null ? '' : match[1];
}

/** 有意义的锚文本保持原样；“网页链接”及裸网址显示真实域名。 */
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

/** 阅读入口共用的纯路由判断，可在无设备环境中测试。 */
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
        // 错误编码保留为网页跳转，不构造错误吧名。
      }
    }
  }
  return target;
}

/** 富文本片段的种类；话题为界面内部分类，其余对应已确认的 content[].type。 */
export enum ContentKind {
  /** type=10；当前 APK gn7/TbRichTextVoiceInfo 已证实，播放传输尚未接入。 */
  VOICE = 10,
  /** type=0 纯文本 */
  TEXT = 0,
  /** type=1 链接 */
  LINK = 1,
  /** type=2 表情 */
  EMOJI = 2,
  /** type=3 图片 */
  IMAGE = 3,

  REPLY_TARGET = 4,
  /** 界面内部的话题种类，不对应服务端 type 编号 */
  TOPIC = 5,
  /** 未实测到的类型，按纯文本兜底处理，不丢内容也不崩 */
  UNKNOWN = 99
}

/** 富文本的一个片段。字段按 kind 取用，未用到的保持默认值 */
export class ContentPiece {
  voice: VoiceClip | undefined = undefined;
  kind: ContentKind = ContentKind.TEXT;
  /** TEXT/LINK/TOPIC 的显示文本 */
  text: string = '';
  /** LINK/TOPIC 的目标地址；纯文字话题可为空 */
  link: string = '';
  /** EMOJI 的图片地址；空串表示只能显示文字 */
  emojiUrl: string = '';
  /** EMOJI 的中文名，如"欢呼" */
  emojiName: string = '';
  /** IMAGE 展示用地址 */
  imageUrl: string = '';
  /** IMAGE 原图地址 */
  originImageUrl: string = '';
  /** IMAGE 宽高，解析失败为 0 */
  width: number = 0;
  height: number = 0;

  /** 批量转换。集中放这里，便于对每种 type 各写一条用例 */
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

  /**
   * 拆分普通文本里的网址、话题和官方表情编码。
   *
   * 贴吧接口并不总把表情单独标成 type=2；实测 type=0 文本会直接包含
   * `image_emoticon22`，甚至一段里出现多个编码。这里只复用 emojiImageUrl
   * 已验证过的前缀和官方 CDN 规则，不维护编号到图片的临时映射。
   */
  private static splitTextAndEmoji(text: string): ContentPiece[] {
    const out: ContentPiece[] = [];
    let plainStart: number = 0;
    let cursor: number = 0;

    while (cursor < text.length) {
      // 网页与话题先整体识别，防止网址中的表情编码、#片段被拆开。
      const initial: string = text[cursor].toLowerCase();
      const rest: string = initial === 'h' || initial === 'w' || initial === '#'
        ? text.substring(cursor) : '';
      const urlMatch: RegExpMatchArray | null = rest.match(/^(?:https?:\/\/|www\.)[^\s<>"“”‘’，。！？、；]+/i);
      const topicMatch: RegExpMatchArray | null = rest.match(/^(##?)([^#\r\n]{1,100})\1/);
      let interactive: ContentPiece | null = null;
      let end: number = cursor;
      if (urlMatch !== null && (cursor === 0 || !/[a-z0-9_@]/i.test(text[cursor - 1]))) {
        let url: string = urlMatch[0].replace(/[.,!;?:]+$/g, '');
        // 保留路径中成对括号，剥离句末多出的右括号。
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

  /**
   * 裸码后面若紧跟字母/数字/下划线，说明它其实是更长单词的一部分
   * （如 `image_emoticonabc`），不当表情拆。数字分支已在前面吃掉下标，
   * 这里只会拦住字母和下划线这类残码。
   */
  private static tokenContinues(text: string, at: number): boolean {
    // 摘要会把相邻的独立表情片段拼成连续编码，不能把下一个编码当成英文后缀。
    let boundary: number = at;
    while (text.startsWith('image_emoticon', boundary)) { boundary += 'image_emoticon'.length; }
    if (text.startsWith('shoubai_emoji_face_', boundary)) {
      const next: string = text[boundary + 'shoubai_emoji_face_'.length];
      if (next >= '0' && next <= '9') { return false; }
    }
    if (boundary >= text.length) {
      return false;
    }
    const ch: string = text[boundary];
    return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch === '_';
  }
  /**
   * 单个片段转换。type 取值全部来自实测：
   *   0 文本 {text}（可能内嵌表情编码）/ 1 链接 {text,link}
   *   2 表情 {text:image_emoticon<N>, c:中文名}
   *   3 图片 {origin_src, cdn_src, cdn_src_active, bsize:"宽,高"}
   *   4 被回复人昵称 {text}（仅楼中楼，见 ContentKind.REPLY_TARGET）
   * 其他类型若有 link 则保留链接，完整话题标记可识别；其余归 UNKNOWN 保留文字。
   */
  private static fromRaw(raw: RawContentItem): ContentPiece {
    const c: ContentPiece = new ContentPiece();
    const type: number = toNum(raw.type);
    c.text = toStr(raw.text);

    if (type === 10) {
      c.kind = ContentKind.VOICE;
      c.voice = parseVoiceClip(raw);
      // 明确媒体边界：不能把语音字段/未知 link 当作音频地址或网页链接。
      c.text = voiceClipLabel(c.voice);
      return c;
    }

    if (type === 1 || (type !== 2 && type !== 3 && type !== 4 && toStr(raw.link).length > 0)) {
      c.kind = /^(##?)[^#\r\n]{1,100}\1$/.test(c.text) ? ContentKind.TOPIC : ContentKind.LINK;
      c.link = toStr(raw.link);
      // 有意义的锚文本保持原样，“网页链接”等通用标签在展示时替换成域名。
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
      // 活动图优先，它在各端适配最好；退回常规图
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

  /** 解析 "560,919" 形式的尺寸。任何异常都返回 [0, 0]，由 UI 兜底 */
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

/**
 * 一个渲染块。
 *
 * 为什么要在片段之上再分一层：图片自成一格（**连续的图片合并成一张横向图集**），
 * 文本和表情才适合流式排布。若让 UI 直接遍历片段，就得在 @Builder 里做
 * "上一个是图片吗"这类状态判断，又难读又难测。这里先切成块，UI 只管按块给组件。
 */
/**
 * 图片块里的**一张**图。
 *
 * 为什么单独建类：正文里**连续的图片会合并成一个可左右滑动的图集**，
 * 一个块里可能有多张，ContentBlock 上那三个标量字段表达不了。
 */
export class ContentImage {
  /** 展示用地址 */
  imageUrl: string = '';
  /** 原图地址；为空时查看器退回 imageUrl */
  originImageUrl: string = '';
  /** 原始宽高；0 表示服务端没给，由 UI 用默认比例兜底 */
  width: number = 0;
  height: number = 0;
}

export class ContentBlock {
  isVoice: boolean = false;
  voice: VoiceClip | undefined = undefined;
  /** 是否是图片块。true 时只读 images，false 时只读 pieces */
  isImage: boolean = false;
  /**
   * 图片块的图片序列。**连续的图片会合并进同一块**，UI 把它渲染成一个横向图集；
   * isImage 为 true 时至少 1 张。
   */
  images: ContentImage[] = [];
  /**
   * 本块**第一张**图在整篇内容图片序列里的下标（0 起）。
   *
   * 全屏查看器的初始页直接用它 + 页内序号算出来，不必再按 URL 反查
   * （同一张图可能在正文里出现多次，按 URL 查会定位到第一处）。
   */
  imageStartIndex: number = 0;
  /** 首图镜像。旧调用方（只关心首图的地方）继续可用，等于 images[0] 的对应字段 */
  imageUrl: string = '';
  /** 首图原图地址；为空时查看器退回 imageUrl */
  originImageUrl: string = '';
  /** 首图原始宽高；0 表示服务端没给，由 UI 用默认比例兜底 */
  width: number = 0;
  height: number = 0;
  /** 文本块包含的片段（文本/链接/表情），至少一个 */
  pieces: ContentPiece[] = [];
}

/**
 * 把片段序列切成渲染块：连续的文本类片段合成一块，**连续的图片合并成一块图集**。
 * 纯函数，便于用固定输入在 Node 上断言。
 */
export function groupContentBlocks(pieces: ContentPiece[]): ContentBlock[] {
  const blocks: ContentBlock[] = [];
  let pending: ContentPiece[] = [];
  /** 已经排进 blocks 的图片总数，用来给下一张图算全局下标 */
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
    // 首图镜像：只关心首图的调用方（缩略图、预览）继续读这几个字段
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
      // 图片前面积攒的文本先落成一块，保证顺序不变
      flush();
      // **紧挨着的图片并进同一块** → 一张可左右滑动的图集；
      // 中间隔着文字就另起一块（图文混排里每段图各自成组）
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

/** 服务端没给宽高时的兜底宽高比（宽/高） */
export const FALLBACK_IMAGE_ASPECT: number = 1.5;

/**
 * 图集整体高度所用宽高比的上下限。
 *
 * 不夹紧会走极端：一组全是竖长截图（实测 560×995 → 0.563）会把图集撑到屏高的
 * 一大半，一组全是横图又只剩一条缝。夹紧后图集高度落在「宽的 0.625~1.5 倍」之间。
 */
export const GALLERY_ASPECT_MIN: number = 0.66;
export const GALLERY_ASPECT_MAX: number = 1.6;

/** 单张图的宽高比（宽/高）；服务端没给宽高时返回 0 表示未知 */
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

/**
 * 收集一组正文片段中可用于全屏预览的图片地址。
 *
 * 原图地址优先，服务端未提供原图时退回展示图；没有任何有效地址的图片片段会被跳过。
 * 保持正文中的图片顺序，不去重，因为相同地址也可能对应用户重复插入的不同位置。
 */
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

/** 去掉正文开头多余的分隔符。实测被回复人后面紧跟的正文以 " :" 开头 */
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

/** 楼中楼"谁回复谁"的拆分结果 */
export class ReplyTargetParse {
  /** 被回复人昵称；空串表示这条不是回复某人的 */
  replyToName: string = '';
  /** 去掉 "回复 X :" 前缀后的正文片段 */
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

/** 用户的展示信息。详情页作者与楼中楼作者共用 */export class UserBrief {
  id: number = 0;
  /** 展示名：name_show 优先，空则用 name */
  displayName: string = '';
  /** 用户名（@名） */
  userName: string = '';
  /** 头像地址，可能为空 */
  portraitUrl: string = '';
  /** 吧内等级 */
  level: number = 0;
  levelName: string = '';
  /** IP 归属地，可能为空 */
  ipLocation: string = '';
  /** 是否吧务 */
  isBawu: boolean = false;
  /** 吧务头衔描述 */
  bawuTitle: string = '';

  /** 从服务端用户对象构造。两种来源（user_list 元素 / 楼中楼 author）字段同名 */
  static fromRaw(raw: RawUser | undefined): UserBrief {
    const u: UserBrief = new UserBrief();
    if (raw === undefined) {
      // 服务端没给作者时也要能渲染，给一个占位名而不是空白
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

/** 使用顶层 user_list 中相同 ID 的资料补全主题作者缺失字段。 */
export function mergeAuthorFallback(primary: UserBrief, fallback: UserBrief | undefined): UserBrief {
  if (fallback === undefined) {
    return primary;
  }
  // primary.id <= 0 说明 thread.author 整个没给（`fromRaw(undefined)` 的占位对象），
  // 这时连昵称都是占位名，直接整份改用备用条目
  if (primary.id <= 0) {
    return fallback;
  }
  const out: UserBrief = new UserBrief();
  out.id = primary.id;
  // 昵称在 fromRaw 里已保证非空（且相同时不会变），这里不覆盖
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

/** 详情页分页信息。`totalCount` 仅保留服务端原始分页值，不参与回复数或楼层展示。 */export class DetailPageInfo {
  currentPage: number = 1;
  pageSize: number = 0;
  /** 服务端 `page.total_num` 原始值；实测可能等于请求窗口 30 */
  totalCount: number = 0;
  totalPage: number = 0;
  hasMore: boolean = false;
}

/**
 * 一级回复排序。数值 0/1/2 与 `/c/f/pb/page` 的 `r` 参数一致；
 * ONLY_AUTHOR 通过独立的 `lz=1` 请求，不能作为 `r` 发送。
 */
export enum ReplySortType {
  ASC = 0,
  DESC = 1,
  HOT = 2,
  ONLY_AUTHOR = 3
}

export function isReplySortSupported(type: ReplySortType): boolean {
  return type !== ReplySortType.HOT;
}

/** 点到不支持的排序时给用户的原话。带原因，不敷衍成"暂未开放" */
export function unsupportedSortTip(type: ReplySortType): string {
  return type === ReplySortType.HOT
    ? '热门排序：贴吧接口暂不支持（服务端会忽略排序参数）'
    : '该排序暂不支持';
}

/** 点赞目标有效性判断，区分主题、楼层与楼中楼的标识；缺失必要标识时不发送请求。 */

/** 主帖点赞的 `obj_type`。与 `net/TiebaParams` 的 `AgreeObjType.THREAD` 同值（3） */
export const AGREE_OBJ_TYPE_THREAD: number = 3;

/** 该 `obj_type` 的点赞当前是否可用 */
export function isAgreeSupported(objType: number): boolean {
  return objType === 1 || objType === 2 || objType === AGREE_OBJ_TYPE_THREAD;
}

export function unsupportedAgreeTip(objType: number): string {
  if (isAgreeSupported(objType)) {
    return '';
  }
  return '点赞结果需以服务端最终状态为准';
}

/**
 * 界面显示的点赞态。
 *
 * 基准必须是服务端的 `agree.has_agree`（实测存在，未登录恒 0），
 * 本地"还没同步到服务端的那一次点击"只作为一次翻转叠加在上面。
 * 这样重进页面时显示的就是服务端真实状态，不会拿本地缓存冒充。
 */
export function resolveAgreeLiked(serverAgreed: boolean, localToggled: boolean): boolean {
  return serverAgreed !== localToggled;
}

/** 界面显示的点赞数：服务端原值 + 本地翻转带来的 ±1，不会降到负数以下 */
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

/**
 * 详情页顶栏吧标的**占位文案**。
 *
 * **它只表示"这项信息没拿到"**，不是任何真实吧名 —— 别拿它去请求吧内容，
 * 判断"能否进吧"要问 `resolveForumName`（空串才是真没拿到）。
 */
export const FORUM_CHIP_PLACEHOLDER: string = '贴吧';

export function forumChipText(responseName: string, sourceName: string): string {
  const name: string = resolveForumName(responseName, sourceName);
  return name.length > 0 ? name : FORUM_CHIP_PLACEHOLDER;
}

/** 一个楼层 */
export class PostItem {
  /** 楼层 id */
  pid: number = 0;
  /** 楼层号。实测会跳号，不能当序号用 */
  floor: number = 0;
  /** 首楼的标题（与主题标题同）；后续楼层为空 */
  title: string = '';
  timeMs: number = 0;
  /** 已格式化好的时间文本，由 fromRaw 依据传入的 nowMs 计算 */
  timeText: string = '';
  author: UserBrief = new UserBrief();
  contents: ContentPiece[] = [];
  /** 点赞数 */
  agreeCount: number = 0;

  isAgreed: boolean = false;
  /** 楼中楼条数。>0 表示要点开才能看到，详情响应里不带内容 */
  subPostCount: number = 0;
  /** 该楼被折叠 */
  isFold: boolean = false;
  foldTip: string = '';

  /**
   * 从服务端楼层构造。
   * `users` 是本页顶层的用户表，用 `author_id` 去查——实测覆盖率 100%。
   */
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

  /** 按 uid 取用户；查不到时给占位，避免界面空白 */
  private static lookupUser(users: Map<number, UserBrief>, uid: number): UserBrief {
    const found: UserBrief | undefined = users.get(uid);
    return found === undefined ? UserBrief.fromRaw(undefined) : found;
  }
}

/**
 * 复制一个楼层。
 *
 * 用途：点赞写接口成功后要把服务端状态写回模型。
 * `@Trace` 只跟踪数组整体替换，直接改对象字段界面不刷新，
 * 所以必须换新对象再整体替换数组。
 */
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

/** 楼中楼的一条回复 */
export class SubPostItem {
  pid: number = 0;
  timeMs: number = 0;
  timeText: string = '';
  author: UserBrief = new UserBrief();
  contents: ContentPiece[] = [];
  /** 是否是楼主自己的回复，界面上通常加"楼主"标记 */
  isThreadAuthor: boolean = false;
  /**
   * 被回复人昵称。空串表示这条不是回复某人。
   * 来源不是独立字段，而是正文开头的 type=4 片段，见 `parseReplyTarget`。
   */
  replyToName: string = '';
  /** 被回复人是不是楼主。只能按昵称比对：楼中楼响应里没有被回复人的 uid */
  replyToIsThreadAuthor: boolean = false;
  /** 点赞数与当前用户点赞态，来自楼中楼响应的 agree 字段。 */
  agreeCount: number = 0;
  isAgreed: boolean = false;
}

/** 一次详情请求的完整结果 */
export class ThreadDetail {
  video: VideoClip | undefined = undefined;
  tid: number = 0;
  title: string = '';
  replyCount: number = 0;
  agreeCount: number = 0;
  /** 服务端分享数与累计收藏数；-1表示未返回有效计数，收藏数不代表个人收藏态。 */
  shareCount: number = -1;
  collectCount: number = -1;
  /**
   * 首楼（主帖）pid，来自服务端 `thread.post_id`（`RawThreadPage.ets:143` 注释：
   * "首楼 pid，实测等于 `post_list[0].id`"）。
   *
   * **主帖定位的权威来源**：底栏点赞必须按 `post.pid === mainPostId` 查找，
   * **不能靠 `posts[0]` 的位置** —— 热门/倒序响应里首位可能是 `floor=0` 的回复，
   * 已有用例锁住这个坑（`hot_reply_without_floor_is_not_mistaken_for_first_post`）。
   * 为 0 表示响应缺 `thread` 或没给该字段，此时由调用方退到 `floor === 1`。
   */
  mainPostId: number = 0;
  /**
   * 主帖的服务端点赞态，来自 `post_list[0].agree.has_agree`。
   *
   * 与 `agreeCount` 配对：底栏同时需要"数量"和"我点没点"，
   * 只存数量会导致刷新后无法回显已点赞状态。
   */
  isAgreed: boolean = false;
  createTimeMs: number = 0;

  isStored: boolean = false;
  /** 楼主 */
  author: UserBrief = new UserBrief();
  /** 本页楼层 */
  posts: PostItem[] = [];

  forumName: string = '';
  forumId: number = 0;
  /** 吧头像完整地址；服务端缺失时为空串，界面退回默认图 */
  forumAvatar: string = '';
  /** 关注数 */
  forumMemberNum: number = 0;
  page: DetailPageInfo = new DetailPageInfo();

  /**
   * 从 `/c/f/pb/page` 响应构造。
   *
   * `tid` 由调用方传入：服务端在异常响应里可能不带 thread，而调用方一定知道自己在看哪帖，
   * 传进来可以保证出错时也能显示正确的标题栏。
   */
  static fromRaw(raw: RawThreadPage, tid: number, nowMs: number): ThreadDetail {
    const d: ThreadDetail = new ThreadDetail();
    d.tid = tid;

    // 先建用户表：楼层作者要用它查昵称/头像
    const users: Map<number, UserBrief> = new Map<number, UserBrief>();
    const rawUsers: RawUser[] | undefined = raw.user_list;
    if (rawUsers !== undefined) {
      for (let i = 0; i < rawUsers.length; i++) {
        const u: UserBrief = UserBrief.fromRaw(rawUsers[i]);
        users.set(u.id, u);
      }
    }

    const thread: RawThreadHead | undefined = raw.thread;
    /*
     * 主题级点赞对象。**主帖点赞的权威来源**（见下方赋值处的说明），
     * 单独留一个局部变量，供"楼层解析完之后"那段使用。
     */
    let threadAgree: RawAgree | undefined = undefined;
    if (thread !== undefined) {
      d.video = parseVideoClip(thread.video_info);
      d.title = toStr(thread.title);
      // `/c/f/pb/page` 的 thread.reply_num 包含 1 楼主帖，列表页 reply_num 不包含。
      // 详情页统一展示真正的回复数，因此扣除主帖并钳制为非负数。
      d.replyCount = Math.max(0, toNum(thread.reply_num) - 1);
      threadAgree = thread.agree;
      // 有主题级 agree 就取它的计数；老形态（没有该对象）才退 thread.agree_num
      d.agreeCount = threadAgree === undefined ? toNum(thread.agree_num) : toNum(threadAgree.agree_num);
      // 主帖定位的权威字段；缺失时为 0，由调用方退到 floor === 1
      d.mainPostId = toNum(thread.post_id);
      d.createTimeMs = toNum(thread.create_time) * 1000;
      // 收藏态：collect_status 非 0 即已收藏（实测收藏后=2，不能用 toFlag 的 ===1）
      d.isStored = toNum(thread.collect_status) !== 0;
      d.shareCount = thread.share_num !== undefined && Number.isFinite(thread.share_num) && thread.share_num >= 0 ?
        Math.floor(thread.share_num) : -1;
      d.collectCount = thread.collect_num !== undefined && Number.isFinite(thread.collect_num) && thread.collect_num >= 0 ?
        Math.floor(thread.collect_num) : -1;
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

    /**
     * 主帖作者的补齐放在楼层解析之后：
     *   1. 正常情况按 `thread.author.id` 去 `user_list` 找同 id 条目；
     *   2. `thread` 整个缺失时 `d.author.id` 为 0，改从首楼（`floor === 1`）的作者取——
     *      首楼作者本来就是主帖作者，而且它已经是 `user_list` 里的对象。
     * 实测 `ip_address` 只在 `user_list` 上，不补的话作者区的"地区"永远是空的。
     */
    let fallback: UserBrief | undefined = users.get(d.author.id);
    if (fallback === undefined && d.posts.length > 0 && d.posts[0].floor === 1) {
      fallback = d.posts[0].author;
    }
    d.author = mergeAuthorFallback(d.author, fallback);

    // 首楼标题为空时用主题标题补：实测首楼 title 与 thread.title 相同，
    // 但服务端若只给一个，界面也不该空着
    if (d.posts.length > 0 && d.posts[0].floor === 1 && d.posts[0].title.length === 0) {
      d.posts[0].title = d.title;
    }

    /** 主帖点赞状态以 thread.agree 为准，不能用首楼 has_agree 替代。 */
    const main: PostItem | undefined = ThreadDetail.locateMainPost(d);
    // 追踪用：楼层解析后的首楼原始点赞态（覆盖前的 B 层真值）
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
      // 主帖 has_agree 有值、但 thread.agree_num 缺失时，用楼层里的数兜底
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

  /**
   * 定位主帖（首楼）。
   *
   * 优先级（**不允许退到 `posts[0]` 的位置**）：
   *   1. `pid === mainPostId` —— 服务端 `thread.post_id`，权威；
   *   2. `mainPostId` 为 0/缺失时，退到第一个 `floor === 1` 的楼层（兼容旧响应）；
   *   3. 都没有 → 返回 undefined，由调用方决定"不提供该操作"，绝不猜。
   *
   * 为什么不用数组位置：热门/倒序响应的首位可能是 `floor=0` 的热门回复，
   * 已有用例 `hot_reply_without_floor_is_not_mistaken_for_first_post` 锁住这一点。
   * 点错楼的赞比不实现更糟。
   */
  static locateMainPost(detail: ThreadDetail): PostItem | undefined {
    if (detail.mainPostId > 0) {
      for (let i = 0; i < detail.posts.length; i++) {
        if (detail.posts[i].pid === detail.mainPostId) {
          return detail.posts[i];
        }
      }
      // 权威 id 存在但本页没有该楼层（例如倒序翻到中间页）→ 不猜
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

/**
 * 只看楼主：只保留作者为楼主本人的楼层，保持服务端顺序不变。
 *
 * `authorId` 是主题作者 id，来自详情响应的 `thread.author.id`。
 * 楼层作者在解析层已保证非空（查不到用户表时也有占位 UserBrief），
 * 因此这里只按 id 精确比对。
 *
 * `authorId` 无效（<=0，常见于响应缺 thread 字段）时**不过滤**直接返回原数组：
 * 拿不到楼主身份时宁可全部显示，也不能让页面变成空白。
 * 纯函数，便于用固定输入在 Node 上断言。
 */
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

/** `/c/f/pb/floor` 的结果：某楼的楼中楼 */
export class SubPostPage {
  subPosts: SubPostItem[] = [];
  /** 楼中楼总数（服务端给的，可能大于本页条数） */
  totalCount: number = 0;
  currentPage: number = 1;
  totalPage: number = 1;
  hasMore: boolean = false;

  /**
   * `threadAuthorId` 用于标记"楼主"，取自详情页的主题作者。
   * 楼主昵称从本响应的 `thread.author` 取（实测 floor 端点会带 thread），
   * 因为被回复人只有昵称、没有 uid，判断"被回复的是不是楼主"只能按名字比对。
   */
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
      // 本端点无 has_more 字段，实测靠 total_count 与 current_page 推算
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

  /** 楼主昵称；`thread` 缺失时返回空串，此时不标记被回复人身份 */
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

/**
 * 某层楼中楼的界面状态。
 *
 * 放在 model 层而不是 viewmodel：它不依赖鸿蒙 API，只做数据结构与同步规则，
 * 可以像协议解析一样在 Node 侧用固定输入验证。
 */
export class SubPostThreadState {
  /** 所属楼层 id */
  pid: number = 0;
  /** 是否展开 */
  expanded: boolean = false;
  /** 是否正在请求楼中楼 */
  loading: boolean = false;
  /** 是否成功加载过第一页 */
  loadedOnce: boolean = false;
  /** 加载失败提示。首页失败与分页失败共用，界面按 subPosts 是否为空区分展示位置 */
  errorText: string = '';
  /** 已加载的楼中楼 */
  subPosts: SubPostItem[] = [];
  /** 楼中楼分页信息；currentPage 用于推进下一页 */
  page: SubPostPage = new SubPostPage();
  /** 是否还有下一页 */
  hasMore: boolean = false;
}

/**
 * 楼中楼里是否出现过楼主回复。
 *
 * 用于一级回复操作行上的"楼主回复了"标记：它表示这条讨论串有楼主参与，
 * 而不是"这条回复的作者是楼主"（后者看 `PostItem.author.id`）。
 * 纯函数，便于用固定输入断言。
 */
export function subPostsHaveThreadAuthor(subPosts: SubPostItem[]): boolean {
  for (let i = 0; i < subPosts.length; i++) {
    if (subPosts[i].isThreadAuthor) {
      return true;
    }
  }
  return false;
}

/** 状态表里是否已有该 pid。O(n) 足够：一页楼层数量有限 */
function hasSubPostThreadState(states: SubPostThreadState[], pid: number): boolean {
  for (let i = 0; i < states.length; i++) {
    if (states[i].pid === pid) {
      return true;
    }
  }
  return false;
}

/**
 * 根据当前楼层列表同步楼中楼状态表。
 *
 * 规则：
 *   1. 保留 existing 里已有状态（展开态、已加载内容、滚动位置语义等都不会因为 loadMore 丢失）；
 *   2. 只为 subPostCount > 0 且尚未建状态的楼层追加空状态；
 *   3. 不删除已有状态：楼层从列表移除通常只是分页刷新，保留也无害，且避免异步请求回来时找不到状态。
 *
 * 纯函数，便于测试"加载更多后展开态不被重置"这个回归点。
 */
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

/** 从内置资源或在线图片文件名提取官方发帖 token；未知表情不猜编码。 */
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

/** 草稿重建仅识别完整的官方 token，普通 #数字和未知名称保持文本。 */
export function emojiCodeFromReplyToken(token: string): string {
  const index: number = REPLY_EMOTICON_TOKENS.indexOf(token);
  return index < 0 ? '' : `image_emoticon${REPLY_EMOTICON_CODES[index]}`;
}
