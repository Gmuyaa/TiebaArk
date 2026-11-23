/** 关闭动图自动播放时将 GIF 源解码为静态首帧 PixelMap（百度 CDN 部分 `g=0` 通道仍返回完整 GIF89a）。 */
import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';

const inFlight: Map<string, Promise<ArrayBuffer | undefined>> = new Map();

function fetchBytes(url: string): Promise<ArrayBuffer | undefined> {
  const existing: Promise<ArrayBuffer | undefined> | undefined = inFlight.get(url);
  if (existing !== undefined) {
    return existing;
  }
  const task: Promise<ArrayBuffer | undefined> = (async (): Promise<ArrayBuffer | undefined> => {
    const req: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 10000,
        readTimeout: 15000
      });
      if (resp.responseCode !== 200 || !(resp.result instanceof ArrayBuffer) || resp.result.byteLength === 0) {
        return undefined;
      }
      return resp.result;
    } catch (_) {
      return undefined;
    } finally {
      req.destroy();
      inFlight.delete(url);
    }
  })();
  inFlight.set(url, task);
  return task;
}

export interface StaticGifFrameResult {
  frame: image.PixelMap | undefined;
  isGif: boolean;
}

function hasGifHeader(buffer: ArrayBuffer): boolean {
  if (buffer.byteLength < 6) {
    return false;
  }
  const bytes: Uint8Array = new Uint8Array(buffer, 0, 6);
  // 'G'(71) 'I'(73) 'F'(70) '8'(56) ('7'(55)|'9'(57)) 'a'(97)
  return bytes[0] === 71 && bytes[1] === 73 && bytes[2] === 70 &&
    bytes[3] === 56 && (bytes[4] === 55 || bytes[4] === 57) && bytes[5] === 97;
}

/** 每次返回独立 PixelMap 及实际文件头是否为 GIF，由调用方在离树或换源时释放。 */
export async function loadStaticGifFrameWithMeta(url: string): Promise<StaticGifFrameResult> {
  if (url.length === 0) {
    return { frame: undefined, isGif: false };
  }
  const buffer: ArrayBuffer | undefined = await fetchBytes(url);
  if (buffer === undefined || buffer.byteLength === 0) {
    return { frame: undefined, isGif: false };
  }
  const isGif: boolean = hasGifHeader(buffer);
  let source: image.ImageSource | undefined = undefined;
  try {
    source = image.createImageSource(buffer);
    const frame: image.PixelMap = await source.createPixelMap({ index: 0 });
    return { frame, isGif };
  } catch (_) {
    return { frame: undefined, isGif };
  } finally {
    if (source !== undefined) {
      try { await source.release(); } catch (_) {}
    }
  }
}

/** 每次返回独立 PixelMap，由调用方在离树或换源时调用 `releaseStaticGifFrame` 释放。 */
export async function loadStaticGifFrame(url: string): Promise<image.PixelMap | undefined> {
  const result: StaticGifFrameResult = await loadStaticGifFrameWithMeta(url);
  return result.frame;
}

export function releaseStaticGifFrame(frame: image.PixelMap | undefined): void {
  if (frame === undefined) {
    return;
  }
  void frame.release().catch((): void => {});
}
