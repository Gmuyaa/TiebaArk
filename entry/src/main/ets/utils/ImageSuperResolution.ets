/** 图像超分平台服务：能力检查、解码、增强与编码。同一进程串行调用能力；SDK 无取消接口，界面取消后仍须等待底层任务结束再启动下一次。失败向上抛出错误。 */

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

/** 通过系统能力检查设备支持情况，不支持时禁用入口。 */
export function srDeviceSupported(): boolean {
  try {
    return canIUse('SystemCapability.AI.Vision.VisionBase');
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'canIUse threw, treat as unsupported');
    return false;
  }
}

/** 错误码（拿不到记 0），日志与归因都要它 */
export function srErrorCode(err: Object): number {
  const e: BusinessError = err as BusinessError;
  return e.code === undefined ? 0 : e.code;
}

/** 错误原文（拿不到就用 String(err)） */
export function srErrorMessage(err: Object): string {
  const e: BusinessError = err as BusinessError;
  return e.message === undefined || e.message.length === 0 ? String(err) : e.message;
}

/** 解码好的原图（送进超分之前的形态）。**调用方必须 `release()`** */
export class SrDecodedImage {
  pixelMap: image.PixelMap | null = null;
  width: number = 0;
  height: number = 0;
  /** 1 = 静态图；>1 = 动图（第一版不处理） */
  frames: number = 0;
  /** 原图是否带透明通道（决定增强图导出编码 PNG 还是 JPEG） */
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

/** 解码 + 可用性判定的结果：`decoded` 为 null 即不可用，`eligibility.reason` 是原话 */
export class SrPrepared {
  eligibility: SrEligibility = new SrEligibility();
  decoded: SrDecodedImage | null = null;
  /** 已消耗的解码字节（宽×高×4），用于缓存预算计量 */
  bytes: number = 0;
}

/** 字节 → `ArrayBuffer` 的精确切片（`HttpClient` 返回的是视图，不能直接把 .buffer 交出去） */
function exactBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
}

/**
 * 处理前的读图：拿到**格式、帧数、解码尺寸**，先判能不能超分，再决定要不要真的解码。
 *
 * 顺序很重要：`getImageInfo()` 只读头部（代价低），不合规的图在这里就被挡掉，
 * **不做"先解码再发现超大"的浪费**，也不把大图缩小后再超分（那会改变结论）。
 * 无论成败，`ImageSource` 都会释放；只有判定通过时才会创建 PixelMap。
 */
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
      // 读不到帧数就**不猜**：动图截首帧冒充处理结果是被明确禁止的
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

/**
 * 超分引擎（**模块级单例**）。
 *
 * 为什么必须是单例："同一进程不得并发调用同一能力" —— 如果每个查看器会话各持一个，
 * 用户退出后立刻重进就能造出两个实例，而旧会话的 `process()` 可能还在飞（SDK 没有取消接口）。
 * 单例 + 忙标志把"并发"这件事在进程维度堵死，同时省掉每次开图重新 `create()` 的开销。
 */
export class SrEngine {
  private static instance: SrEngine | null = null;

  private analyzer: imageSuperResolution.ImageSRAnalyzer | null = null;
  private busy: boolean = false;
  /** 退出查看器时若还有任务在飞，先记下来，等它 settle 再释放分析器 */
  private destroyWhenIdle: boolean = false;
  private creating: Promise<void> | null = null;

  static shared(): SrEngine {
    if (SrEngine.instance === null) {
      SrEngine.instance = new SrEngine();
    }
    return SrEngine.instance;
  }

  /** 底层是否正忙（UI 侧的单飞判断以会话 VM 为准，这里只防"绕过 VM 直接调"） */
  isBusy(): boolean {
    return this.busy;
  }

  hasAnalyzer(): boolean {
    return this.analyzer !== null;
  }

  /** 惰性创建分析器；并发调用共享同一次 create（不会造出两个实例） */
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

  /**
   * 跑一次超分。调用方保证串行；若真被并发调用，这里**直接抛**而不是排队 ——
   * 排队会掩盖"上层单飞逻辑坏了"这件事。
   */
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

  /**
   * 释放分析器。**忙的时候不释放**（会把在飞的 process 打断），
   * 改为记一笔，等任务 settle 后在 `superResolve` 的 finally 里释放。
   */
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

/** 把增强图编码成字节（导出用）。格式取 `srExportFormat()`：带透明通道 PNG，否则 JPEG。 */
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
