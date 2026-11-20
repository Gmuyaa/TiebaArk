/** 图片字节下载：导出与超分共用的唯一取图入口，UA 与大小上限在此收口。 */
import { HttpClient, HttpResult } from './HttpClient';

/** 贴吧图片 CDN 与主站同一套 UA 约定（空 UA 会被拦） */
const IMAGE_UA: string = 'bdtb for Android 12.64.1.1';
const MAX_IMAGE_BYTES: number = 24 * 1024 * 1024;

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
