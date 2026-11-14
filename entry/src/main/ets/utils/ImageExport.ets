/** 图片导出：按权限与目标位置保存，完成后释放临时资源。 */
import { common } from '@kit.AbilityKit';
import { cacheMaintenance } from './ApplicationCache';
import { trimExportCache } from './ExportCachePolicy';
import { isCacheEntryName } from '../model/CachePolicy';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';

/** 从 URL 推断扩展名；未知按 jpg（贴吧图床绝大多数是 jpg） */
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

/** 生成安全的文件名：不含路径分隔符与查询串 */
export function imageFileName(url: string, index: number): string {
  const ext: string = imageExtension(url);
  const stamp: number = Date.now();
  return `tieba_${stamp}_${index}.${ext}`;
}

export function writeImageToCache(context: common.Context, bytes: Uint8Array, fileName: string): string {
  if (cacheMaintenance.busy) { throw new Error('正在清理缓存，请稍后重试'); }
  if (!isCacheEntryName(fileName)) { throw new Error('导出文件名无效'); }
  trimExportCache(context, bytes.length, fileName);
  const dir: string = `${context.cacheDir}/export`;
  if (!fileIo.accessSync(dir)) {
    fileIo.mkdirSync(dir, true);
  }
  const filePath: string = `${dir}/${fileName}`;
  if (fileIo.accessSync(filePath) && fileIo.lstatSync(filePath).isSymbolicLink()) {
    throw new Error('导出缓存文件异常');
  }
  const file = fileIo.openSync(filePath,
    fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  try {
    // 用切片保证 buffer 与视图一致（HttpClient 返回的是独立数组，这里仍按防御性写法处理）
    const exact: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
    fileIo.writeSync(file.fd, exact);
  } finally {
    fileIo.closeSync(file);
  }
  return fileUri.getUriFromPath(filePath);
}

/**
 * 保存到相册（媒体库）。
 * **必须在 `SaveButton` 的 `onClick` 里调用**：安全控件点击后系统才临时授权写入。
 */
export async function saveImageToGallery(context: common.Context, fileUri: string): Promise<void> {
  const helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
  const request: photoAccessHelper.MediaAssetChangeRequest =
    photoAccessHelper.MediaAssetChangeRequest.createImageAssetRequest(context, fileUri);
  await helper.applyChanges(request);
}

/** 复制图片到剪贴板（按 PixelMap 记录，接收方粘贴的是图片本体） */
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

/** 分享图片文件本身（Share Kit 官方面板；`uri` 是应用沙箱文件） */
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
