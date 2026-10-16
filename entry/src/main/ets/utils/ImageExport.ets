
import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';
import { HttpClient, HttpResult } from '../net/HttpClient';

const IMAGE_UA: string = 'bdtb for Android 12.64.1.1';

const MAX_IMAGE_BYTES: number = 24 * 1024 * 1024;

export function imageExtension(url: string): string {
  const clean: string = url.split('?')[0].toLowerCase();
  const candidates: string[] = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];
  for (let i = 0; i < candidates.length; i++) {
    if (clean.endsWith(`.${candidates[i]}`)) {
      return candidates[i] === 'jpeg' ? 'jpg' : candidates[i];
    }
  }
  return 'jpg';
}

export function imageFileName(url: string, index: number): string {
  const ext: string = imageExtension(url);
  const stamp: number = Date.now();
  return `tieba_${stamp}_${index}.${ext}`;
}

export async function fetchImageBytes(url: string): Promise<Uint8Array> {
  if (url.length === 0) {
    throw new Error('图片地址为空');
  }
  const client: HttpClient = new HttpClient();
  client.userAgent = IMAGE_UA;
  const result: HttpResult = await client.get(url);
  if (!result.ok) {
    throw new Error(result.error.length > 0 ? result.error : `下载失败（HTTP ${result.code}）`);
  }
  if (result.bytes.length === 0) {
    throw new Error('下载内容为空');
  }
  if (result.bytes.length > MAX_IMAGE_BYTES) {
    throw new Error('图片过大，暂不支持导出');
  }
  return result.bytes;
}

export function writeImageToCache(context: common.Context, bytes: Uint8Array, fileName: string): string {
  const dir: string = `${context.cacheDir}/export`;
  if (!fileIo.accessSync(dir)) {
    fileIo.mkdirSync(dir, true);
  }
  const filePath: string = `${dir}/${fileName}`;
  const file = fileIo.openSync(filePath,
    fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  try {

    const exact: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
    fileIo.writeSync(file.fd, exact);
  } finally {
    fileIo.closeSync(file);
  }
  return fileUri.getUriFromPath(filePath);
}

export async function saveImageToGallery(context: common.Context, fileUri: string): Promise<void> {
  const helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
  const request: photoAccessHelper.MediaAssetChangeRequest =
    photoAccessHelper.MediaAssetChangeRequest.createImageAssetRequest(context, fileUri);
  await helper.applyChanges(request);
}

export async function copyImageToPasteboard(bytes: Uint8Array): Promise<void> {
  const exact: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
  const source: image.ImageSource = image.createImageSource(exact);
  try {
    const pixelMap: image.PixelMap = await source.createPixelMap();
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_PIXELMAP, pixelMap);
    await pasteboard.getSystemPasteboard().setData(data);
  } finally {
    source.release();
  }
}

export async function shareImageFile(context: common.UIAbilityContext, fileUri: string,
  title: string): Promise<void> {
  const record: systemShare.SharedRecord = {
    utd: uniformTypeDescriptor.UniformDataType.IMAGE,
    uri: fileUri,
    title: title
  };
  const data: systemShare.SharedData = new systemShare.SharedData(record);
  const controller: systemShare.ShareController = new systemShare.ShareController(data);
  await controller.show(context, {});
}
