

export class MemePicItem {

  picId: string = '';

  picUrl: string = '';

  width: number = 0;

  height: number = 0;

  thumbnail: string = '';

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

export class MemeEmojiData {

  picUpdateTime: number = 0;

  pics: MemePicItem[] = [];

  diyUpdateTime: number = 0;

  diyPics: MemePicItem[] = [];

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

export function memeEmojiHashBody(pkgId: string, picId: string, width: number,
  height: number): string {
  const core: string = pkgId.length > 0 ? `collect_${pkgId}_${picId}` : '';
  return `meme,${core},${width},${height},`;
}

export function memeEmojiHashInput(pkgId: string, picId: string, width: number,
  height: number): string {
  return memeEmojiHashBody(pkgId, picId, width, height).replace('collect_', '');
}

export function memeEmojiToken(pkgId: string, picId: string, width: number, height: number,
  md5LowerHex: string): string {
  return `#(${memeEmojiHashBody(pkgId, picId, width, height)}${md5LowerHex})`;
}
