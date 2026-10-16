

/** 响应里的单个收藏/DIY 表情（`GetCloudFaceGroupMessage.parseData` 的元素） */
export class MemePicItem {
  /** 贴吧图床图片全局 ID —— 收藏的本质是引用它 */
  picId: string = '';
  /** 原图 URL */
  picUrl: string = '';
  /** 原图宽（发帖 token 要写进串里） */
  width: number = 0;
  /** 原图高 */
  height: number = 0;
  /** 缩略图 URL（面板显示用；响应可能缺，缺则回落 picUrl） */
  thumbnail: string = '';
  /** 所属表情包 ID（收藏散图时为空；响应键名是 `pck_id`） */
  pkgId: string = '';

  static textOrEmpty(v: Object | undefined | null): string {
    if (v === undefined || v === null) {
      return '';
    }
    return String(v);
  }

  static numOr0(v: Object | undefined | null): number {
    if (v === undefined || v === null) {
      return 0;
    }
    const n: number = Number(String(v));
    return Number.isNaN(n) ? 0 : n;
  }

  static fromRaw(rec: Record<string, Object>): MemePicItem {
    const item: MemePicItem = new MemePicItem();
    item.picId = MemePicItem.textOrEmpty(rec['pic_id']);
    item.picUrl = MemePicItem.textOrEmpty(rec['pic_url']);
    item.width = MemePicItem.numOr0(rec['width']);
    item.height = MemePicItem.numOr0(rec['height']);
    item.thumbnail = MemePicItem.textOrEmpty(rec['thumbnail']);
    item.pkgId = MemePicItem.textOrEmpty(rec['pck_id']);
    return item;
  }
}

/** `getAllMeme` 响应 data 段的解析结果 */
export class MemeEmojiData {
  /** 收藏表情最后更新时间（毫秒；官方客户端用它做增量比对） */
  picUpdateTime: number = 0;
  /** 收藏表情列表（云端为空时是空数组，不是错误） */
  pics: MemePicItem[] = [];
  /** DIY 表情最后更新时间（毫秒） */
  diyUpdateTime: number = 0;
  /** DIY 表情列表（与收藏同构；一期不消费，解析留着对账） */
  diyPics: MemePicItem[] = [];
  /** 已拥有表情包 ID（下划线分隔字符串，服务端原样） */
  packageIds: string = '';

  private static numOr0(v: Object | undefined | null): number {
    return MemePicItem.numOr0(v);
  }

  private static parsePics(v: Object | undefined | null): MemePicItem[] {
    const out: MemePicItem[] = [];
    if (v === undefined || v === null || !Array.isArray(v)) {
      return out;
    }
    const arr: Object[] = v as Object[];
    for (let i = 0; i < arr.length; i++) {
      const rec: Object | undefined = arr[i];
      if (rec === undefined || rec === null || typeof rec !== 'object' || Array.isArray(rec)) {
        continue;
      }
      out.push(MemePicItem.fromRaw(rec as Record<string, Object>));
    }
    return out;
  }

  /**
   * 从响应里解析 data 段。c/ 通道常规是 `{error_code, data:{...}}` 信封；
   * 若实测没有 data 包装（整包就是 data），退回按根节点解析——两种都认，
   * 不猜（形状以 MemeProbe 真机日志为准）。
   */
  static fromEnvelope(root: Record<string, Object>): MemeEmojiData {
    const out: MemeEmojiData = new MemeEmojiData();
    let data: Record<string, Object> = root;
    const raw: Object | undefined = root['data'];
    if (raw !== undefined && raw !== null && typeof raw === 'object' && !Array.isArray(raw)) {
      data = raw as Record<string, Object>;
    }
    out.picUpdateTime = MemeEmojiData.numOr0(data['pic_update_time']);
    out.pics = MemeEmojiData.parsePics(data['pic_ids']);
    out.diyUpdateTime = MemeEmojiData.numOr0(data['diy_pic_update_time']);
    out.diyPics = MemeEmojiData.parsePics(data['diy_pic_ids']);
    out.packageIds = MemePicItem.textOrEmpty(data['package_ids']);
    return out;
  }
}

export const MEME_TOKEN_SALT: string = '7S6wbXjEKL9N';

/**
 * 发帖 token 的正文段（`#(` 与 `)` 之间、不含尾部 md5）。
 *
 * 证据（`GetCloudFaceGroupMessage.parseCollectData`，n95.h = "meme,collect_"）：
 *   - 有包：`meme,collect_<pkgId>_<picId>,<w>,<h>,`
 *   - 无包（收藏散图 pkgId 为空）：`meme,,<w>,<h>,`
 */
export function memeEmojiHashBody(pkgId: string, picId: string, width: number,
  height: number): string {
  const core: string = pkgId.length > 0 ? `collect_${pkgId}_${picId}` : '';
  return `meme,${core},${width},${height},`;
}

/**
 * md5 的输入串 = 正文去掉 `collect_` 前缀段 + 盐（官方原样：replace 恰好把
 * 两种前缀都归一到 `meme,` 开头，DIY 同理）。调用方对它做
 * `MD5(输入 + MEME_TOKEN_SALT)` 小写 hex。
 */
export function memeEmojiHashInput(pkgId: string, picId: string, width: number,
  height: number): string {
  return memeEmojiHashBody(pkgId, picId, width, height).replace('collect_', '');
}

/**
 * 完整发帖 token：`#(<正文><md5小写hex>)`。
 *
 * `md5LowerHex` 由调用方传入：`CryptoUtil.md5(memeEmojiHashInput(...) +
 * MEME_TOKEN_SALT)`（平台 MD5 异步，模型层不碰 @kit）。
 * 服务端认这个签名文本直接把 content 渲染成图——发帖不传图片。
 */
export function memeEmojiToken(pkgId: string, picId: string, width: number, height: number,
  md5LowerHex: string): string {
  return `#(${memeEmojiHashBody(pkgId, picId, width, height)}${md5LowerHex})`;
}
