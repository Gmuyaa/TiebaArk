import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { AvatarCrop, AvatarUploadInput, avatarCropRegion, avatarUploadInputError } from '../model/AvatarUpload';
import { IMAGE_SOURCE_BYTES } from '../model/ImagePrepare';
export class AvatarPrepareResult {
  cancelled: boolean = false;
  message: string = '';
  input: AvatarUploadInput | undefined = undefined;
  crop: AvatarCrop | undefined = undefined;
  uri: string = '';
  sourceWidth: number = 0;
  sourceHeight: number = 0;
}

export async function pickAvatarImage(current: () => boolean): Promise<AvatarPrepareResult> {
  const result: AvatarPrepareResult = new AvatarPrepareResult();
  if (!current()) { result.cancelled = true; return result; }
  try {
    const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
    const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    options.isEditSupported = false;
    const selected = await picker.select(options);
    if (!current() || selected.photoUris.length === 0) { result.cancelled = true; return result; }
    if (selected.photoUris.length !== 1) { result.message = '请每次选择一张头像图片'; return result; }
    return await prepareAvatarImage(selected.photoUris[0], current);
  } catch (err) { if (!current()) { result.cancelled = true; } else { result.message = '选图失败，请重试'; } return result; }
}
/** 原图坐标裁剪→960方图→JPEG80；动图不静默取首帧。每个异步边界检查current。 */
export async function prepareAvatarImage(uri: string, current: () => boolean, requested?: AvatarCrop): Promise<AvatarPrepareResult> {
  const result: AvatarPrepareResult = new AvatarPrepareResult();
  if (!current()) { result.cancelled = true; return result; }
  if (!uri.startsWith('file://')) { result.message = '所选头像图片无效'; return result; }
  let cropSnapshot: AvatarCrop | undefined = undefined;
  if (requested !== undefined) {
    cropSnapshot = new AvatarCrop(); cropSnapshot.left = requested.left; cropSnapshot.top = requested.top; cropSnapshot.edge = requested.edge;
  }
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
      result.message = '头像图片为空或超过本机32MB读取上限'; return result;
    }
    const bytes: Uint8Array = new Uint8Array(stat.size); let offset: number = 0;
    while (offset < bytes.length) {
      if (!current()) { result.cancelled = true; return result; }
      const buffer: ArrayBuffer = new ArrayBuffer(Math.min(1024 * 1024, bytes.length - offset));
      const read: number = await fileIo.read(file.fd, buffer, { length: buffer.byteLength });
      if (!current()) { result.cancelled = true; return result; }
      if (!Number.isInteger(read) || read <= 0 || read > buffer.byteLength) { result.message = '头像图片读取不完整'; return result; }
      bytes.set(new Uint8Array(buffer, 0, read), offset); offset += read;
    }
    const after = await fileIo.stat(file.fd);
    if (!current()) { result.cancelled = true; return result; }
    if (after.size !== bytes.length) { result.message = '头像图片在读取时发生变化'; return result; }
    source = image.createImageSource(bytes.buffer as ArrayBuffer);
    const info = await source.getImageInfo();
    if (!current()) { result.cancelled = true; return result; }
    const crop: AvatarCrop | undefined = avatarCropRegion(info.size.width, info.size.height, cropSnapshot);
    if (crop === undefined) { result.message = '头像裁剪区域无效或超过本机解码上限'; return result; }
    const frames: number = await source.getFrameCount();
    if (!current()) { result.cancelled = true; return result; }
    if (frames !== 1 || info.mimeType === 'image/gif') { result.message = '请选择静态头像图片，未改变动图帧'; return result; }
    pixels = await source.createPixelMap({ desiredRegion: { x: crop.left, y: crop.top, size: { width: crop.edge, height: crop.edge } },
      desiredSize: { width: 960, height: 960 }, cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST });
    if (!current()) { result.cancelled = true; return result; }
    const decoded = await pixels.getImageInfo();
    if (!current()) { result.cancelled = true; return result; }
    if (decoded.size.width !== 960 || decoded.size.height !== 960) { result.message = '头像裁剪解码尺寸未确认'; return result; }
    packer = image.createImagePacker();
    const packed: ArrayBuffer = await packer.packing(pixels, { format: 'image/jpeg', quality: 80 });
    if (!current()) { result.cancelled = true; return result; }
    const input: AvatarUploadInput = new AvatarUploadInput();
    input.bytes = new Uint8Array(packed); input.width = decoded.size.width; input.height = decoded.size.height;
    const invalid: string = avatarUploadInputError(input);
    if (invalid.length > 0) { result.message = invalid; return result; }
    result.input = input; result.crop = crop; result.uri = uri;
    result.sourceWidth = info.size.width; result.sourceHeight = info.size.height;
  } catch (err) { result.message = '头像图片读取或处理失败，请重新选择'; }
  finally {
    let failed: boolean = false;
    if (packer !== undefined) { try { await packer.release(); } catch (err) { failed = true; } }
    if (pixels !== undefined) { try { await pixels.release(); } catch (err) { failed = true; } }
    if (source !== undefined) { try { await source.release(); } catch (err) { failed = true; } }
    if (file !== undefined) { try { await fileIo.close(file); } catch (err) { failed = true; } }
    if (!current()) { result.cancelled = true; result.input = undefined; result.crop = undefined; }
    if (result.input === undefined || failed) { result.uri = ''; result.sourceWidth = 0; result.sourceHeight = 0; }
    if (failed) { result.input = undefined; result.crop = undefined; result.message = '头像处理资源释放失败，请重试'; }
  }
  return result;
}
