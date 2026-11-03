/** E-01 普通头像：调用方必须提供已裁剪/解码确认的960×960 JPEG。 */
export class AvatarUploadInput {
  bytes: Uint8Array = new Uint8Array(0);
  width: number = 0;
  height: number = 0;
}
export function avatarUploadInputError(input: AvatarUploadInput): string {
  if (input.width !== 960 || input.height !== 960) { return '头像裁剪尺寸未确认'; }
  // 本机内存预算，不代表服务端限制；JPEG标记不替代平台解码。
  const b: Uint8Array = input.bytes;
  if (b.length < 4 || b.length > 8 * 1024 * 1024 || b[0] !== 255 || b[1] !== 216 ||
    b[b.length - 2] !== 255 || b[b.length - 1] !== 217) { return '头像JPEG内容未确认'; }
  return '';
}
interface AvatarError { errno?: number | string; errmsg?: string; }
interface AvatarEnvelope {
  error?: AvatarError; error_code?: number | string; error_msg?: string;
  errno?: number | string; errmsg?: string;
}

const AVATAR_CODE_OK: number = 0;
const AVATAR_CODE_PENDING_REVIEW: number = 300003;
export class AvatarUploadResult {
  code: number = -1;
  message: string = '头像上传结果未确认';
  /** 服务端明确成功（`code=0`），仍不证明头像已更新；调用方须读回确认。 */
  accepted(): boolean { return this.code === AVATAR_CODE_OK; }
  /** 已上传、审核中：服务端已接收本次上传，远端记录可能稍后才更新。 */
  pendingReview(): boolean { return this.code === AVATAR_CODE_PENDING_REVIEW; }
  /**
   * 服务端是否**已经接收**这次上传（明确成功或审核中）。
   * 只表示"可以按已接收处理（发布本地预览并读回）"，**不**表示资料已经更新。
   */
  received(): boolean { return this.accepted() || this.pendingReview(); }
}
function avatarCode(value: number | string | undefined): number {
  if (typeof value !== 'number' && (typeof value !== 'string' || !/^-?\d+$/.test(value))) { return -1; }
  const code: number = Number(value);
  return Number.isInteger(code) && code >= -2147483648 && code <= 2147483647 ? code : -1;
}
/** 当前 ErrorData 的字段优先级；不复刻 optInt 缺失码默认为0。 */
export function parseAvatarUpload(text: string): AvatarUploadResult {
  const result: AvatarUploadResult = new AvatarUploadResult();
  try {
    const raw: AvatarEnvelope = JSON.parse(text) as AvatarEnvelope;
    if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) { return result; }
    let code: number = -1;
    let message: string | undefined = undefined;
    if (raw.error !== undefined && raw.error !== null && typeof raw.error === 'object' && !Array.isArray(raw.error)) {
      code = avatarCode(raw.error.errno); message = raw.error.errmsg;
    } else {
      code = avatarCode(raw.errno !== undefined ? raw.errno : raw.error_code);
      message = raw.errmsg !== undefined ? raw.errmsg : raw.error_msg;
    }
    result.code = code;
    if (typeof message === 'string' && message.length > 0) { result.message = message; }
    else if (code === 0) { result.message = ''; }
    else if (code !== -1) { result.message = '头像上传被拒绝'; }
  } catch (err) { /* 未确认保持失败，不推断头像hash。 */ }
  return result;
}

export function avatarUploadEnvelopeShape(text: string): string {
  if (text.length === 0) { return 'empty'; }
  let raw: Object | undefined = undefined;
  try { raw = JSON.parse(text) as Object; } catch (err) { return 'invalid'; }
  if (raw === null || raw === undefined || typeof raw !== 'object' || Array.isArray(raw)) { return 'invalid'; }
  const record: Record<string, Object> = raw as Record<string, Object>;
  const keys: string[] = Object.keys(record);
  const shown: string[] = [];
  for (let i = 0; i < keys.length && i < 8; i++) { shown.push(keys[i]); }
  let out: string = `keys=${shown.join(',')}`;
  if (keys.length > 8) { out += `(+${keys.length - 8})`; }
  const nested: Object | undefined = record['error'];
  if (nested !== undefined && nested !== null && typeof nested === 'object' && !Array.isArray(nested)) {
    const nestedKeys: string[] = Object.keys(nested as Record<string, Object>);
    const nestedShown: string[] = [];
    for (let i = 0; i < nestedKeys.length && i < 6; i++) { nestedShown.push(nestedKeys[i]); }
    out += ` error.keys=${nestedShown.join(',')}`;
  }
  const candidates: string[] = ['no', 'errno', 'error_code', 'code', 'errmsg', 'error_msg'];
  const types: string[] = [];
  for (const name of candidates) {
    const value: Object | undefined = record[name];
    const kind: string = value === undefined ? 'absent'
      : (typeof value === 'number' ? 'num' : (typeof value === 'string' ? 'str' : 'other'));
    types.push(`${name}:${kind}`);
  }
  return `${out} types=${types.join(' ')}`;
}

/** 原图像素坐标的正方形区域；默认居中只是初始裁剪，UI仍需用户确认。 */
export class AvatarCrop { left: number = 0; top: number = 0; edge: number = 0; }
export function avatarCropRegion(width: number, height: number, requested?: AvatarCrop): AvatarCrop | undefined {
  if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width <= 0 || height <= 0 ||
    width * height > 32 * 1024 * 1024) { return undefined; }
  const crop: AvatarCrop = new AvatarCrop();
  if (requested !== undefined) { crop.left = requested.left; crop.top = requested.top; crop.edge = requested.edge; }
  else { crop.edge = Math.min(width, height); crop.left = Math.floor((width - crop.edge) / 2); crop.top = Math.floor((height - crop.edge) / 2); }
  if (!Number.isSafeInteger(crop.left) || !Number.isSafeInteger(crop.top) || !Number.isSafeInteger(crop.edge) ||
    crop.left < 0 || crop.top < 0 || crop.edge <= 0 || crop.left + crop.edge > width || crop.top + crop.edge > height) { return undefined; }
  return crop;
}

/** 裁剪视图内图像可平移的范围（原图像素）：放大后超出裁剪框的部分左右/上下各分一半。 */
export class AvatarCropLimits { x: number = 0; y: number = 0; }
export function avatarCropOffsetLimits(width: number, height: number, zoom: number, frameEdge: number): AvatarCropLimits | undefined {
  if (!Number.isFinite(zoom) || zoom < 1 || zoom > 4 || !Number.isFinite(frameEdge) || frameEdge <= 0 ||
    avatarCropRegion(width, height) === undefined) { return undefined; }
  // 裁剪框边长固定，图像按原图宽高比铺满裁剪框后随倍率放大。
  const scale: number = frameEdge / Math.min(width, height) * zoom;
  const limits: AvatarCropLimits = new AvatarCropLimits();
  limits.x = Math.max(0, (width * scale - frameEdge) / 2);
  limits.y = Math.max(0, (height * scale - frameEdge) / 2);
  return limits;
}
/**
 * 裁剪界面的平移/缩放映射：offsetX/offsetY 是图像相对裁剪框中心的位移（vp），换算回原图像素。
 * 图像右移 offsetX 等价于裁剪窗口左移，故取负号。
 */
export function avatarCropFromViewport(width: number, height: number, zoom: number, offsetX: number, offsetY: number,
  frameEdge: number): AvatarCrop | undefined {
  if (!Number.isFinite(offsetX) || !Number.isFinite(offsetY) || avatarCropRegion(width, height) === undefined) { return undefined; }
  const limits: AvatarCropLimits | undefined = avatarCropOffsetLimits(width, height, zoom, frameEdge);
  if (limits === undefined) { return undefined; }
  const scale: number = frameEdge / Math.min(width, height) * zoom;
  const crop: AvatarCrop = new AvatarCrop(); crop.edge = Math.max(1, Math.floor(Math.min(width, height) / zoom));
  const left: number = Math.round((width - crop.edge) / 2 - offsetX / scale);
  const top: number = Math.round((height - crop.edge) / 2 - offsetY / scale);
  crop.left = Math.min(Math.max(left, 0), width - crop.edge); crop.top = Math.min(Math.max(top, 0), height - crop.edge);
  return avatarCropRegion(width, height, crop);
}
