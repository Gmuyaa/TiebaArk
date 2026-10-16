
interface RawImageDimensions { width?: number | string; height?: number | string; picUrl?: string; }
interface RawImageVariants { originPic?: RawImageDimensions; }
interface RawImageUpload {
  error_code?: number | string;
  error_msg?: string;
  chunkNo?: number | string;
  picId?: string;
  picInfo?: RawImageVariants;
}
export class UploadedPostImage {
  id: string = '';
  width: number = 0;
  height: number = 0;

  previewUrl: string = '';

  localPreview: string = '';
}
export class ImageUploadResult {
  code: number = -1;
  message: string = '';
  resumeChunk: number = -1;
  image: UploadedPostImage | undefined = undefined;
  complete(): boolean { return this.code === 0 && this.image !== undefined; }
}
function positiveDimension(raw: number | string | undefined): number {
  if (typeof raw !== 'number' && (typeof raw !== 'string' || !/^\d+$/.test(raw))) { return 0; }
  const value: number = Number(raw);
  return Number.isInteger(value) && value > 0 && value <= 2147483647 ? value : 0;
}
function validImageId(id: string | undefined): boolean {
  return typeof id === 'string' && id.length > 0 && id !== 'null' && id !== 'undefined' &&
    !/[\s,()\u0000-\u001f\u007f]/.test(id);
}

export function uploadedImagePreviewUrl(raw: string | undefined): string {
  return typeof raw === 'string' && /^https?:\/\/[^\s/?#@\\]+(?:[/?#][^\s\\]*)?$/i.test(raw) &&
    !/[\u0000-\u001f\u007f]/.test(raw) ? raw : '';
}

export function uploadedImageToken(image: UploadedPostImage): string {
  if (!validImageId(image.id) || positiveDimension(image.width) === 0 || positiveDimension(image.height) === 0) { return ''; }
  return `#(pic,${image.id},${image.width},${image.height})`;
}
export function parseImageUpload(text: string): ImageUploadResult {
  const result: ImageUploadResult = new ImageUploadResult();
  try {
    const raw: RawImageUpload = JSON.parse(text) as RawImageUpload;
    if (typeof raw.error_code !== 'number' && (typeof raw.error_code !== 'string' || !/^-?\d+$/.test(raw.error_code))) {
      result.message = '图片上传响应缺少明确结果'; return result;
    }
    const code: number = Number(raw.error_code);
    if (!Number.isInteger(code) || code < -2147483648 || code > 2147483647) {
      result.message = '图片上传响应结果无效'; return result;
    }
    result.code = code;
    result.resumeChunk = positiveDimension(raw.chunkNo);
    if (result.resumeChunk === 0) { result.resumeChunk = -1; }
    result.message = typeof raw.error_msg === 'string' ? raw.error_msg : '';
    if (code !== 0) { return result; }
    const origin: RawImageDimensions | undefined = raw.picInfo?.originPic;
    if (origin === undefined || origin === null || !validImageId(raw.picId)) {
      result.message = '图片上传响应尚未确认完整图片'; return result;
    }
    const image: UploadedPostImage = new UploadedPostImage();
    image.id = raw.picId as string; image.width = positiveDimension(origin.width); image.height = positiveDimension(origin.height);
    image.previewUrl = uploadedImagePreviewUrl(origin.picUrl);
    if (uploadedImageToken(image).length === 0) { result.message = '图片上传响应缺少有效原图尺寸'; return result; }
    result.image = image;
  } catch (err) { result.code = -1; result.image = undefined; result.message = '图片上传响应格式无效'; }
  return result;
}

export class ImageUploadChunk {
  bytes: Uint8Array = new Uint8Array(0);
  digest: string = '';
  totalSize: number = 0;
  chunkSize: number = 512000;
  chunkNo: number = 1;
  width: number = 0;
  height: number = 0;
  watermarkType: number = -1;
  userName: string = '';
  forumName: string = '';
  finish(): boolean { return this.chunkNo === Math.ceil(this.totalSize / this.chunkSize); }
}
export function imageUploadChunkError(chunk: ImageUploadChunk): string {
  if (!/^[a-f0-9]{32}$/.test(chunk.digest)) { return '图片摘要未确认'; }
  if (!Number.isSafeInteger(chunk.totalSize) || chunk.totalSize <= 0 ||
    !Number.isSafeInteger(chunk.chunkSize) || chunk.chunkSize <= 0 || chunk.chunkSize > 512000 ||
    !Number.isSafeInteger(chunk.chunkNo) || chunk.chunkNo < 1 || chunk.chunkNo > Math.ceil(chunk.totalSize / chunk.chunkSize)) {
    return '图片分片参数无效';
  }
  const offset: number = (chunk.chunkNo - 1) * chunk.chunkSize;
  if (chunk.bytes.length !== Math.min(chunk.chunkSize, chunk.totalSize - offset)) { return '图片分片长度不匹配'; }
  if (positiveDimension(chunk.width) === 0 || positiveDimension(chunk.height) === 0) { return '图片尺寸未确认'; }
  if (!Number.isInteger(chunk.watermarkType) || chunk.watermarkType < 0 || chunk.watermarkType > 2147483647) {
    return '图片水印设置未确认';
  }
  if (chunk.watermarkType === 1 && chunk.userName.length === 0) { return '水印账号名未确认'; }
  if (chunk.watermarkType === 2 && chunk.forumName.length === 0) { return '水印吧名未确认'; }
  return '';
}

export class ImageUploadInput {
  bytes: Uint8Array = new Uint8Array(0);
  width: number = 0;
  height: number = 0;
  forumName: string = '';
}
export function imageUploadInputError(input: ImageUploadInput): string {
  if (input.bytes.length === 0) { return '图片内容为空'; }
  if (positiveDimension(input.width) === 0 || positiveDimension(input.height) === 0) { return '图片尺寸未确认'; }
  if (input.forumName.trim().length === 0) { return '图片所属吧未确认'; }
  return '';
}
