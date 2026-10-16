

import { image } from '@kit.ImageKit';
import { imageSuperResolution, visionBase } from '@kit.CoreVisionKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  SrEligibility,
  srEligibility
} from '../model/ImageSuperResolution';

const DOMAIN: number = 0x0000;
const TAG: string = 'ImageSuperResolution';

export function srDeviceSupported(): boolean {
  try {
    return canIUse('SystemCapability.AI.Vision.VisionBase');
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'canIUse threw, treat as unsupported');
    return false;
  }
}

export function srErrorCode(err: Object): number {
  const e: BusinessError = err as BusinessError;
  return e.code === undefined ? 0 : e.code;
}

export function srErrorMessage(err: Object): string {
  const e: BusinessError = err as BusinessError;
  return e.message === undefined || e.message.length === 0 ? String(err) : e.message;
}

export class SrDecodedImage {
  pixelMap: image.PixelMap | null = null;
  width: number = 0;
  height: number = 0;

  frames: number = 0;

  hasAlpha: boolean = false;

  async release(): Promise<void> {
    const held: image.PixelMap | null = this.pixelMap;
    this.pixelMap = null;
    if (held !== null) {
      try {
        await held.release();
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'release decoded pixelMap failed');
      }
    }
  }
}

export class SrPrepared {
  eligibility: SrEligibility = new SrEligibility();
  decoded: SrDecodedImage | null = null;

  bytes: number = 0;
}

function exactBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
}

export async function srPrepareFromBytes(bytes: Uint8Array): Promise<SrPrepared> {
  const prepared: SrPrepared = new SrPrepared();
  if (bytes.length === 0) {
    prepared.eligibility.ok = false;
    prepared.eligibility.reason = '图片内容为空，无法超分';
    return prepared;
  }
  const source: image.ImageSource = image.createImageSource(exactBuffer(bytes));
  try {
    const info: image.ImageInfo = await source.getImageInfo();
    const width: number = info.size.width;
    const height: number = info.size.height;
    let frames: number = 0;
    try {
      frames = await source.getFrameCount();
    } catch (err) {

      hilog.warn(DOMAIN, TAG, 'getFrameCount failed code=%{public}d', srErrorCode(err as Object));
      frames = 0;
    }
    prepared.eligibility = srEligibility(width, height, frames);
    if (!prepared.eligibility.ok) {
      hilog.info(DOMAIN, TAG, 'prepare rejected: %{public}s (%{public}dx%{public}d frames=%{public}d)',
        prepared.eligibility.reason, width, height, frames);
      return prepared;
    }
    const decoded: SrDecodedImage = new SrDecodedImage();
    decoded.width = width;
    decoded.height = height;
    decoded.frames = frames;
    decoded.hasAlpha = info.alphaType !== image.AlphaType.OPAQUE;
    decoded.pixelMap = await source.createPixelMap();
    prepared.decoded = decoded;
    prepared.bytes = width * height * 4;
    hilog.info(DOMAIN, TAG, 'prepare ok %{public}dx%{public}d frames=%{public}d alpha=%{public}s kb=%{public}d',
      width, height, frames, String(decoded.hasAlpha), Math.round(prepared.bytes / 1024));
    return prepared;
  } finally {
    await source.release();
  }
}

export class SrEngine {
  private static instance: SrEngine | null = null;

  private analyzer: imageSuperResolution.ImageSRAnalyzer | null = null;
  private busy: boolean = false;

  private destroyWhenIdle: boolean = false;
  private creating: Promise<void> | null = null;

  static shared(): SrEngine {
    if (SrEngine.instance === null) {
      SrEngine.instance = new SrEngine();
    }
    return SrEngine.instance;
  }

  isBusy(): boolean {
    return this.busy;
  }

  hasAnalyzer(): boolean {
    return this.analyzer !== null;
  }

  async ensure(): Promise<void> {
    if (this.analyzer !== null) {
      return;
    }
    if (this.creating !== null) {
      await this.creating;
      return;
    }
    const started: number = Date.now();
    this.creating = (async (): Promise<void> => {
      this.analyzer = await imageSuperResolution.ImageSRAnalyzer.create();
      hilog.info(DOMAIN, TAG, 'analyzer created in %{public}dms', Date.now() - started);
    })();
    try {
      await this.creating;
    } finally {
      this.creating = null;
    }
  }

  async superResolve(input: image.PixelMap): Promise<image.PixelMap> {
    if (this.busy) {
      throw new Error('图像超分已有任务在处理中');
    }
    await this.ensure();
    const analyzer: imageSuperResolution.ImageSRAnalyzer | null = this.analyzer;
    if (analyzer === null) {
      throw new Error('图像超分服务未就绪');
    }
    this.busy = true;
    const started: number = Date.now();
    try {
      const request: visionBase.Request = { inputData: { pixelMap: input } };
      const response: imageSuperResolution.ISPResponse = await analyzer.process(request);
      const output: image.PixelMap = response.pixelMap;
      hilog.info(DOMAIN, TAG, 'process ok in %{public}dms', Date.now() - started);
      return output;
    } finally {
      this.busy = false;
      if (this.destroyWhenIdle) {
        this.destroyWhenIdle = false;
        await this.destroy();
      }
    }
  }

  async destroy(): Promise<void> {
    if (this.busy || this.creating !== null) {
      this.destroyWhenIdle = true;
      return;
    }
    const held: imageSuperResolution.ImageSRAnalyzer | null = this.analyzer;
    this.analyzer = null;
    if (held === null) {
      return;
    }
    try {
      await held.destroy();
      hilog.info(DOMAIN, TAG, 'analyzer destroyed');
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'analyzer destroy failed code=%{public}d', srErrorCode(err as Object));
    }
  }
}

export async function srEncodePixelMap(pixelMap: image.PixelMap, format: string,
  quality: number): Promise<ArrayBuffer> {
  const packer: image.ImagePacker = image.createImagePacker();
  try {
    const option: image.PackingOption = { format: format, quality: quality };
    return await packer.packing(pixelMap, option);
  } finally {
    await packer.release();
  }
}
