import { UploadedPostImage, uploadedImageToken } from './ImageUpload';


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
  /** 只有显式完整数组且每条ID可信时，才允许全量收藏写入。 */
  collectionComplete: boolean = false;
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
    const rawPics: Object | undefined = data['pic_ids'];
    out.collectionComplete = Array.isArray(rawPics) && rawPics.length === out.pics.length &&
      (rawPics as Record<string, Object>[]).every((entry: Record<string, Object>) =>
        typeof entry['pic_id'] === 'string' && validMemeId(entry['pic_id'] as string));
    out.diyUpdateTime = MemeEmojiData.numOr0(data['diy_pic_update_time']);
    out.diyPics = MemeEmojiData.parsePics(data['diy_pic_ids']);
    out.packageIds = MemePicItem.textOrEmpty(data['package_ids']);
    return out;
  }
}

/** 收藏条目引用已在图床上的图片，发送复用普通图片通道；包ID仅供云端分类。 */
export function memeImageToken(item: MemePicItem): string {
  const image: UploadedPostImage = new UploadedPostImage();
  image.id = item.picId; image.width = item.width; image.height = item.height;
  return uploadedImageToken(image);
}

export function validMemeId(id: string): boolean {
  return id.length > 0 && id !== 'null' && id !== 'undefined' && !/[\s,()\u0000-\u001f\u007f]/.test(id);
}
interface MemeCollectItem { pic_id: string; }
/** 全量目标仅序列化云端ID，绝不从可展示的过滤列表反推。 */
export function memeCollectionPayload(pics: MemePicItem[]): string {
  if (pics.some((item: MemePicItem) => !validMemeId(item.picId))) { return ''; }
  return pics.length === 0 ? 'all_delete' : JSON.stringify(pics.map((item: MemePicItem): MemeCollectItem => ({ pic_id: item.picId })));
}
export function sameMemeCollection(a: MemePicItem[], b: MemePicItem[]): boolean {
  const ids: string[] = a.map((item: MemePicItem) => item.picId).sort();
  const other: string[] = b.map((item: MemePicItem) => item.picId).sort();
  return ids.length === other.length && ids.every((id: string, index: number) => id === other[index]);
}
