/** 吧头条横幅解析与会话内缓存。 */

import { ProtoReader, WireType } from '../proto/ProtoWire';

/** `FrsPageResIdl` 一级字段 */
const RES_ERROR = 1;
const RES_DATA = 2;
/** `Error` 消息里的业务码 */
const ERROR_ERRNO = 1;
/** `DataRes` 里与头图相关的字段 */
const DATA_HEADLINE = 52;
const DATA_HEAD_SDK = 34;
/** `ForumHeadlineImgInfo` 的图片字段 */
const HEADLINE_IMG_URL = 4;
/** `HeadSdk` 的图片字段 */
const HEAD_SDK_PIC = 1;

/** 一次头图解析的结果。`imgUrl` 为空串 = 没有可用头图（调用方回退底纹/主题色） */
export class ForumHeadlineResult {
  /** 吧头条图（`forum_headline_img_info.img_url`） */
  imgUrl: string = '';
  /** 头部 SDK 图（`head_sdk.head_pic`），仅作 imgUrl 为空时的次选 */
  headPic: string = '';
  /** 服务端业务错误码（`error.errorno`）；解析失败为 -1 */
  errorno: number = -1;

  /** 最终应显示的图：头条图优先，SDK 图次之 */
  resolved(): string {
    return this.imgUrl.length > 0 ? this.imgUrl : this.headPic;
  }
}

/**
 * 解析 frs/page(pb) 响应里的头图。
 *
 * ⚠️ 响应是**全量吧页数据**（~260KB），这里只取头图两支，其余一律 skipField。
 * 任何解析异常都兜底成空结果 —— 头图是锦上添花，绝不能拖垮吧页。
 */
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
        // `FrsPageResIdl.error` 是消息（`Error{ errorno=1, ... }`），errorno 在子字段 1
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
    // 头图是装饰性数据：解析失败回退空结果，不抛、不拖垮调用方
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

/** `activityhead.head_imgs[]` 元素（`type` 含义未考证，仅透传 `img_url`） */
class RawHeadImg {
  img_url: string = '';
}

/** `activityhead` 段 */
class RawActivityHead {
  head_imgs: RawHeadImg[] = [];
}

/** `frsBottom_pc` 响应里与头图相关的最小字段集 */
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
    // 用 truthy 判断：JSON 缺字段时是 undefined（不等于 null），!== null 会漏
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
    // 头图是装饰性数据：解析失败回退空结果，不抛、不拖垮调用方
    return new ForumHeadlineResult();
  }
  return out;
}

/* ============================================================================
 * 会话级缓存
 * ========================================================================== */

/** 上限：吧数量远小于帖子量，256 足够覆盖重度使用一整天的吧 */
const MAX_ENTRIES: number = 256;

const headlineCache: Map<string, string> = new Map();

/**
 * 回填一个吧的头图（空名 / 空 URL 忽略；同名覆盖为最新值）。
 * 命中失败的吧**不写缓存** —— 这样下次进吧还能重试（服务端可能随时开始下发）。
 */
export function putForumHeadline(forumName: string, url: string): void {
  const name: string = forumName.trim();
  const value: string = url.trim();
  if (name.length === 0 || value.length === 0) {
    return;
  }
  if (!headlineCache.has(name) && headlineCache.size >= MAX_ENTRIES) {
    // 淘汰最早插入的一条（Map 迭代序 = 插入序；同名覆盖不更新插入序，可接受）
    const oldest: IteratorResult<string> = headlineCache.keys().next();
    if (!oldest.done) {
      headlineCache.delete(oldest.value);
    }
  }
  headlineCache.set(name, value);
}

/** 查一个吧的头图缓存；没缓存过返回空串（调用方决定是否发 pb 请求） */
export function getForumHeadline(forumName: string): string {
  const name: string = forumName.trim();
  if (name.length === 0) {
    return '';
  }
  return headlineCache.get(name) ?? '';
}

/** 当前缓存条数（诊断 / 测试用） */
export function forumHeadlineCount(): number {
  return headlineCache.size;
}

/** 清空（Node 用例隔离用；生产链路不调） */
export function clearForumHeadlines(): void {
  headlineCache.clear();
}
