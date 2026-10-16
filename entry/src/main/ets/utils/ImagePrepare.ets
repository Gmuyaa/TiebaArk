import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { ImageUploadInput } from '../model/ImageUpload';
import { IMAGE_SOURCE_BYTES, IMAGE_UPLOAD_BYTES, prepareImageSize } from '../model/ImagePrepare';

export async function createReplyImagePreview(input: ImageUploadInput, current: () => boolean): Promise<string> {
  if (!current() || input.bytes.length === 0 || input.bytes.length > IMAGE_UPLOAD_BYTES ||
    prepareImageSize(input.width, input.height) === undefined) { return ''; }
  let source: image.ImageSource | undefined = undefined;
  let pixels: image.PixelMap | undefined = undefined;
  let packer: image.ImagePacker | undefined = undefined;
  let preview: string = '';
  try {
    source = image.createImageSource(input.bytes.slice().buffer);
    const scale: number = Math.min(1, 160 / input.width, 112 / input.height);
    pixels = await source.createPixelMap({ desiredSize: {
      width: Math.max(1, Math.floor(input.width * scale)), height: Math.max(1, Math.floor(input.height * scale)) } });
    if (!current()) { return ''; }
    const info = await pixels.getImageInfo();
    if (!current() || !Number.isSafeInteger(info.size.width) || !Number.isSafeInteger(info.size.height) ||
      info.size.width <= 0 || info.size.height <= 0 ||
      info.size.width > 160 || info.size.height > 112) { return ''; }
    packer = image.createImagePacker();
    const bytes = await packer.packing(pixels, { format: 'image/png', quality: 90 });
    if (current() && bytes.byteLength > 0 && bytes.byteLength <= 128 * 1024) {
      preview = `data:image/png;base64,${new util.Base64Helper().encodeToStringSync(new Uint8Array(bytes))}`;
    }
  } catch (err) { preview = ''; }
  finally {
    let failed: boolean = false;
    if (packer !== undefined) { try { await packer.release(); } catch (err) { failed = true; } }
    if (pixels !== undefined) { try { await pixels.release(); } catch (err) { failed = true; } }
    if (source !== undefined) { try { await source.release(); } catch (err) { failed = true; } }
    if (failed) { throw new Error('图片预览资源释放失败'); }
  }
  return current() ? preview : '';
}
export class ImagePrepareResult {
  cancelled: boolean = false;
  message: string = '';
  input: ImageUploadInput | undefined = undefined;
}
function cancelled(): ImagePrepareResult { const result: ImagePrepareResult = new ImagePrepareResult(); result.cancelled = true; return result; }

export async function pickUploadImage(forumName: string, current: () => boolean): Promise<ImagePrepareResult> {
  if (!current()) { return cancelled(); }
  const result: ImagePrepareResult = new ImagePrepareResult();
  if (forumName.trim().length === 0) { result.message = '图片所属吧未确认'; return result; }
  try {
    const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
    const selected = await picker.select({ MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE, maxSelectNumber: 1 });
    if (!current() || selected.photoUris.length === 0) { return cancelled(); }
    if (selected.photoUris.length !== 1) { result.message = '请每次选择一张图片'; return result; }
    return await prepareUploadImage(selected.photoUris[0], forumName, current);
  } catch (err) { if (!current()) { return cancelled(); } result.message = '选图失败，请重试'; return result; }
}

export async function prepareUploadImage(uri: string, forumName: string, current: () => boolean): Promise<ImagePrepareResult> {
  if (!current()) { return cancelled(); }
  const result: ImagePrepareResult = new ImagePrepareResult();
  if (!uri.startsWith('file://') || forumName.trim().length === 0) { result.message = '所选图片或所属吧无效'; return result; }
  let file: fileIo.File | undefined = undefined;
  let source: image.ImageSource | undefined = undefined;
  let pixels: image.PixelMap | undefined = undefined;
  let packer: image.ImagePacker | undefined = undefined;
  try {
    file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    if (!current()) { result.cancelled = true; return result; }
    const stat = await fileIo.stat(file.fd);
    if (!current()) { result.cancelled = true; return result; }
    if (!Number.isSafeInteger(stat.size) || stat.size <= 0 || stat.size > IMAGE_SOURCE_BYTES) {
      result.message = '图片为空或超过本机32MB读取上限'; return result;
    }
    const bytes: Uint8Array = new Uint8Array(stat.size); let offset: number = 0;
    while (offset < bytes.length) {
      if (!current()) { result.cancelled = true; return result; }
      const buffer: ArrayBuffer = new ArrayBuffer(Math.min(1024 * 1024, bytes.length - offset));
      const read: number = await fileIo.read(file.fd, buffer, { length: buffer.byteLength });
      if (!current()) { result.cancelled = true; return result; }
      if (!Number.isInteger(read) || read <= 0 || read > buffer.byteLength) { result.message = '图片读取不完整'; return result; }
      bytes.set(new Uint8Array(buffer, 0, read), offset); offset += read;
    }
    const after = await fileIo.stat(file.fd);
    if (!current()) { result.cancelled = true; return result; }
    if (after.size !== bytes.length) { result.message = '图片在读取时发生变化，请重新选择'; return result; }
    source = image.createImageSource(bytes.buffer as ArrayBuffer);
    const info = await source.getImageInfo();
    if (!current()) { result.cancelled = true; return result; }
    const size = prepareImageSize(info.size.width, info.size.height);
    if (size === undefined) { result.message = '图片尺寸无效或超过本机解码上限'; return result; }
    const frames: number = await source.getFrameCount();
    if (!current()) { result.cancelled = true; return result; }
    if (!Number.isInteger(frames) || frames < 1) { result.message = '图片帧数未确认'; return result; }
    const input: ImageUploadInput = new ImageUploadInput(); input.forumName = forumName.trim();
    if (frames > 1 || info.mimeType === 'image/gif') {
      if (info.mimeType !== 'image/gif' && info.mimeType !== 'image/png') { result.message = '该动图格式暂未支持'; return result; }
      if (bytes.length > IMAGE_UPLOAD_BYTES || size.width !== info.size.width || size.height !== info.size.height) {
        result.message = '动图超过本机8MB或2048像素上限，未改变原始帧'; return result;
      }
      input.bytes = bytes; input.width = info.size.width; input.height = info.size.height;
    } else {
      pixels = await source.createPixelMap({ desiredSize: { width: size.width, height: size.height } });
      if (!current()) { result.cancelled = true; return result; }
      const decoded = await pixels.getImageInfo();
      if (!current()) { result.cancelled = true; return result; }
      const actual = prepareImageSize(decoded.size.width, decoded.size.height);
      if (actual === undefined || actual.width !== decoded.size.width || actual.height !== decoded.size.height) {
        result.message = '图片解码尺寸未满足本机上限'; return result;
      }
      packer = image.createImagePacker();
      const packed: ArrayBuffer = await packer.packing(pixels,
        { format: info.mimeType === 'image/jpeg' ? 'image/jpeg' : 'image/png', quality: 90 });
      if (!current()) { result.cancelled = true; return result; }
      if (packed.byteLength === 0 || packed.byteLength > IMAGE_UPLOAD_BYTES) { result.message = '处理后的图片超过本机8MB上限或为空'; return result; }
      input.bytes = new Uint8Array(packed); input.width = decoded.size.width; input.height = decoded.size.height;
    }
    result.input = input;
  } catch (err) { result.message = '图片读取或处理失败，请重新选择'; }
  finally {
    let failed: boolean = false;
    if (packer !== undefined) { try { await packer.release(); } catch (err) { failed = true; } }
    if (pixels !== undefined) { try { await pixels.release(); } catch (err) { failed = true; } }
    if (source !== undefined) { try { await source.release(); } catch (err) { failed = true; } }
    if (file !== undefined) { try { await fileIo.close(file); } catch (err) { failed = true; } }
    if (!current()) { result.cancelled = true; result.input = undefined; }
    if (failed) { result.input = undefined; result.message = '图片处理资源释放失败，请重试'; }
  }
  return result;
}
