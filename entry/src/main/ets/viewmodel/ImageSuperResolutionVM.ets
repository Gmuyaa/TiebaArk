/** 查看器会话状态按图片 URL 关联。一次仅允许一个底层任务；切图使结果失效但不取消底层任务，迟到结果只释放。缓存按实际解码字节计量，当前图不淘汰。 */

import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fetchImageBytes } from '../utils/ImageExport';
import {
  SrDecodedImage,
  SrEngine,
  SrPrepared,
  srDeviceSupported,
  srErrorMessage,
  srPrepareFromBytes
} from '../utils/ImageSuperResolution';
import {
  SR_CACHE_BUDGET_BYTES,
  SR_TIMEOUT_MS,
  SrCacheEntry,
  SrFailure,
  SrStatus,
  srEvictionPlan,
  srFailureText,
  srPredictedOutputBytes,
  srSizeEligibility
} from '../model/ImageSuperResolution';

const DOMAIN: number = 0x0000;
const TAG: string = 'ImageSuperResolutionVM';

/** 退出查看器后延迟这么久再释放增强图：确保 ArkUI 不会再拿它渲染当前帧 */
const RELEASE_DELAY_MS: number = 200;

/**
 * 一张图的超分状态。**`@Observed`**：页组件以 `@ObjectLink` 接住它，
 * 于是本类（而不是页组件自己）也能把状态推到界面上。
 *
 * `hasResult` 与 `status` **分开记**：前者是"结果还在缓存里"，后者是"当前正在显示增强图"。
 * 关掉开关只改 `status`，`hasResult` 保持 —— 再打开不需要重算。
 */
@Observed
export class PageSuperResolutionState {
  /** 图片身份（URL），不随页码变 */
  key: string = '';
  /** `SrStatus` */
  status: number = SrStatus.OFF;
  /** 不可用 / 失败的原话 */
  reason: string = '';
  /** 增强图是否还在缓存里 */
  hasResult: boolean = false;
  resultWidth: number = 0;
  resultHeight: number = 0;
  /** 增强图的实测字节数（`getPixelBytesNumber()`），缓存预算按它算 */
  resultBytes: number = 0;
  /** 原图是否带透明通道（决定导出编码） */
  resultHasAlpha: boolean = false;
  /** 结果版本：每次结果落地/丢弃自增，导出时用它钉住"开始导出时那一版" */
  resultVersion: number = 0;
  /** 增强图本体；`hasResult=false` 时必须为 null */
  pixelMap: image.PixelMap | null = null;
}

/** `toggle()` 的返回值：`message` 非空即由界面原话提示（VM 不碰 UI） */
export class SrToggleResult {
  message: string = '';
  changed: boolean = false;
}

/** 一次在飞的任务。`cancelled` 由切图/关闭置位；结果迟到时按它决定"丢弃" */
class SrJob {
  key: string = '';
  epoch: number = 0;
  cancelled: boolean = false;

  constructor(key: string, epoch: number) {
    this.key = key;
    this.epoch = epoch;
  }
}

function srSleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, ms);
  });
}

/** 实测字节数；读不到就退回预测值（预算宁可估大不估小） */
function pixelBytesOf(pixelMap: image.PixelMap, fallback: number): number {
  try {
    return pixelMap.getPixelBytesNumber();
  } catch (err) {
    return fallback;
  }
}

async function releaseQuietly(pixelMap: image.PixelMap | null, why: string): Promise<void> {
  if (pixelMap === null) {
    return;
  }
  try {
    await pixelMap.release();
    hilog.info(DOMAIN, TAG, 'released enhanced pixelMap (%{public}s)', why);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'release enhanced pixelMap failed (%{public}s)', why);
  }
}

/**
 * 一次看图会话的超分状态机。**生命周期与 `ImageViewer` 一致**：打开时建，关闭时 `close()`。
 */
export class ImageSuperResolutionSession {
  private states: Map<string, PageSuperResolutionState> = new Map<string, PageSuperResolutionState>();
  /** 缓存条目的使用顺序（旧 → 新），淘汰从头部开始 */
  private order: string[] = [];
  /** 会话纪元：`close()` 自增，用来判定迟到结果是否属于"上一辈子" */
  private epoch: number = 0;
  /** 在飞的任务；非 null 即"忙"（含已失效但底层还没结束的） */
  private currentJob: SrJob | null = null;
  private currentKey: string = '';
  /** 正在导出的那一张：异步编码期间不允许被淘汰掉脚下的 PixelMap */
  private exportPinnedKey: string = '';
  private deviceSupported: boolean = true;
  private closed: boolean = false;

  constructor() {
    this.deviceSupported = srDeviceSupported();
    hilog.info(DOMAIN, TAG, 'session opened, deviceSupported=%{public}s', String(this.deviceSupported));
  }

  /** 设备是否具备这套能力（按钮灰显的第一判据） */
  isDeviceSupported(): boolean {
    return this.deviceSupported;
  }

  isBusy(): boolean {
    return this.currentJob !== null;
  }

  /**
   * 导出开始/结束时钉住某张图：编码是异步的，中途若正好有别的结果落地触发淘汰，
   * 被钉住的那张不许释放（否则会编出坏文件）。传空串即解除。
   */
  setExportPin(key: string): void {
    this.exportPinnedKey = key;
  }

  clearExportPin(): void {
    this.exportPinnedKey = '';
  }

  /** 取（必要时创建）某张图的状态对象。**同一 URL 永远拿到同一个对象**，`@ObjectLink` 才稳 */
  stateFor(key: string): PageSuperResolutionState {
    const existing: PageSuperResolutionState | undefined = this.states.get(key);
    if (existing !== undefined) {
      return existing;
    }
    const created: PageSuperResolutionState = new PageSuperResolutionState();
    created.key = key;
    if (!this.deviceSupported) {
      created.status = SrStatus.UNAVAILABLE;
      created.reason = srFailureText(SrFailure.DEVICE_UNSUPPORTED, '');
    }
    this.states.set(key, created);
    this.order.push(key);
    return created;
  }

  /**
   * 页面报告"这张图解码出来的真实尺寸"（`Image.onComplete`）。
   *
   * 只用来做**尺寸/内存**层面的提前灰显：尺寸不合规的图在点击前就说明原因。
   * 不假设帧数（只有真去读文件才知道），因此不会在这里判"动图"。
   */
  noteDecodedSize(key: string, width: number, height: number): void {
    if (this.closed || !this.deviceSupported) {
      return;
    }
    const state: PageSuperResolutionState = this.stateFor(key);
    if (state.status !== SrStatus.OFF) {
      return;
    }
    const verdict = srSizeEligibility(width, height);
    if (!verdict.ok) {
      state.status = SrStatus.UNAVAILABLE;
      state.reason = verdict.reason;
      hilog.info(DOMAIN, TAG, 'size-ineligible %{public}s', verdict.reason);
    }
  }

  /** 当前显示的是哪张图。**切走时使在飞任务失效**（结果作废，底层仍会跑完） */
  setCurrentKey(key: string): void {
    if (this.closed || key === this.currentKey) {
      return;
    }
    this.currentKey = key;
    const job: SrJob | null = this.currentJob;
    if (job !== null && job.key !== key) {
      this.cancelJob(job, 'switched away');
    }
  }

  /** 关掉开关 / 失败后放弃：状态回到原图，缓存保留（`hasResult` 不动） */
  private cancelJob(job: SrJob, why: string): void {
    job.cancelled = true;
    const state: PageSuperResolutionState | undefined = this.states.get(job.key);
    if (state !== undefined && state.status === SrStatus.PROCESSING) {
      state.status = SrStatus.OFF;
    }
    hilog.info(DOMAIN, TAG, 'job for %{public}s invalidated (%{public}s)', job.key.slice(0, 40), why);
  }

  /**
   * 点一次超分按钮。返回"要不要提示、提示什么"，由界面原话展示。
   *
   * 分支顺序按用户体验排：先挡重复提交（处理中），再判开关状态，再看缓存，最后才起任务。
   */
  async toggle(key: string): Promise<SrToggleResult> {
    const result: SrToggleResult = new SrToggleResult();
    if (this.closed) {
      return result;
    }
    const state: PageSuperResolutionState = this.stateFor(key);
    if (!this.deviceSupported) {
      result.message = srFailureText(SrFailure.DEVICE_UNSUPPORTED, '');
      return result;
    }
    // ① 忙：SDK 没有取消接口，旧任务没 settle 之前绝不并发
    if (this.currentJob !== null) {
      result.message = this.currentJob.key === key
        ? '图像超分正在处理中，请稍候'
        : '正在处理上一张图片，请稍候';
      return result;
    }
    // ② 已经是开启态：立即恢复原图（保留缓存与缩放，界面侧不动缩放状态）
    if (state.status === SrStatus.ON) {
      state.status = SrStatus.OFF;
      result.changed = true;
      return result;
    }
    // ③ 缓存命中：直接显示，不重算
    if (state.hasResult && state.pixelMap !== null) {
      state.status = SrStatus.ON;
      result.changed = true;
      this.touch(key);
      return result;
    }
    // ④ 已知不可用：只解释原因
    if (state.status === SrStatus.UNAVAILABLE) {
      result.message = state.reason.length > 0 ? state.reason : '这张图暂不支持超分';
      return result;
    }
    // ⑤ 真起任务
    state.status = SrStatus.PROCESSING;
    state.reason = '';
    result.changed = true;
    await this.runJob(state);
    if (state.status === SrStatus.ON) {
      result.message = '已应用图像超分';
    } else if (state.status === SrStatus.ERROR || state.status === SrStatus.UNAVAILABLE) {
      result.message = state.reason;
    }
    return result;
  }

  /** 任务落地与否只看"任务没被取消 + 纪元没变 + 会话还活着" */
  private jobAlive(job: SrJob): boolean {
    return !this.closed && !job.cancelled && job.epoch === this.epoch;
  }

  /** 起任务并等到"界面该恢复"为止。超时只恢复 UI，底层任务继续跟踪到 settle */
  private async runJob(state: PageSuperResolutionState): Promise<void> {
    const job: SrJob = new SrJob(state.key, this.epoch);
    this.currentJob = job;
    hilog.info(DOMAIN, TAG, 'job start %{public}s', job.key.slice(0, 60));
    const body: Promise<void> = this.jobBody(job, state)
      .catch((err: Object): void => {
        this.failJob(job, state, err);
      })
      .then((): void => {
        if (this.currentJob === job) {
          this.currentJob = null;
          hilog.info(DOMAIN, TAG, 'job settled %{public}s', job.key.slice(0, 60));
        }
      });
    await Promise.race([body, srSleep(SR_TIMEOUT_MS)]);
    if (this.currentJob === job) {
      // 超时：先恢复可用 UI；底层还在跑，`currentJob` 留着挡并发，结果到达时只释放
      job.cancelled = true;
      state.status = SrStatus.ERROR;
      state.reason = srFailureText(SrFailure.TIMEOUT, '');
      hilog.warn(DOMAIN, TAG, 'job timeout after %{public}dms', SR_TIMEOUT_MS);
    }
  }

  /** 真正的活儿：下载原图 → 解码判合规 → 超分 → 落地（或按失效丢弃） */
  private async jobBody(job: SrJob, state: PageSuperResolutionState): Promise<void> {
    let prepared: SrPrepared | null = null;
    try {
      const bytes: Uint8Array = await fetchImageBytes(job.key);
      if (!this.jobAlive(job)) {
        return;
      }
      prepared = await srPrepareFromBytes(bytes);
      if (!this.jobAlive(job)) {
        return;
      }
      if (!prepared.eligibility.ok) {
        state.status = SrStatus.UNAVAILABLE;
        state.reason = prepared.eligibility.reason;
        return;
      }
      const decoded: SrDecodedImage | null = prepared.decoded;
      if (decoded === null || decoded.pixelMap === null) {
        state.status = SrStatus.ERROR;
        state.reason = srFailureText(SrFailure.DECODE_FAILED, '');
        return;
      }
      const engine: SrEngine = SrEngine.shared();
      const output: image.PixelMap = await engine.superResolve(decoded.pixelMap);
      if (!this.jobAlive(job)) {
        // 失效任务迟到返回：只释放，不自动开启效果、不覆盖当前页
        await releaseQuietly(output, 'stale result');
        return;
      }
      await this.adoptResult(job, state, output, decoded.hasAlpha,
        srPredictedOutputBytes(decoded.width, decoded.height));
    } finally {
      // 输入永远单独释放：它只服务于这一次超分
      if (prepared !== null && prepared.decoded !== null) {
        await prepared.decoded.release();
      }
    }
  }

  /** 结果落地：记字节、记版本、点亮开关，然后按预算淘汰别人 */
  private async adoptResult(job: SrJob, state: PageSuperResolutionState, output: image.PixelMap,
    hasAlpha: boolean, predictedBytes: number): Promise<void> {
    const bytes: number = pixelBytesOf(output, predictedBytes);
    let width: number = 0;
    let height: number = 0;
    try {
      const info: image.ImageInfo = await output.getImageInfo();
      width = info.size.width;
      height = info.size.height;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'output size unreadable');
    }
    // getImageInfo 是异步的：等回来时任务可能已经失效，再确认一次
    if (!this.jobAlive(job)) {
      await releaseQuietly(output, 'stale after info');
      return;
    }
    this.dropResult(job.key);
    state.pixelMap = output;
    state.hasResult = true;
    state.resultWidth = width;
    state.resultHeight = height;
    state.resultBytes = bytes;
    state.resultHasAlpha = hasAlpha;
    state.resultVersion += 1;
    state.status = SrStatus.ON;
    state.reason = '';
    this.touch(job.key);
    hilog.info(DOMAIN, TAG, 'result ready %{public}dx%{public}d kb=%{public}d',
      width, height, Math.round(bytes / 1024));
    this.evictFor(job.key);
  }

  private failJob(job: SrJob, state: PageSuperResolutionState, err: Object): void {
    const message: string = srErrorMessage(err);
    hilog.error(DOMAIN, TAG, 'job failed %{public}s', message);
    if (!this.jobAlive(job)) {
      return;
    }
    // 失败保留原图，允许重试：状态记为 ERROR，reason 是原话
    state.status = SrStatus.ERROR;
    state.reason = srFailureText(SrFailure.UNKNOWN, message);
  }

  /** 把某个 key 挪到使用顺序末尾（最近使用） */
  private touch(key: string): void {
    const index: number = this.order.indexOf(key);
    if (index >= 0) {
      this.order.splice(index, 1);
    }
    this.order.push(key);
  }

  /** 丢掉某张图的结果（释放 PixelMap），状态回到关闭 */
  private dropResult(key: string): void {
    const state: PageSuperResolutionState | undefined = this.states.get(key);
    if (state === undefined) {
      return;
    }
    const held: image.PixelMap | null = state.pixelMap;
    const had: boolean = state.hasResult || held !== null;
    state.pixelMap = null;
    state.hasResult = false;
    state.resultBytes = 0;
    if (had) {
      state.resultVersion += 1;
    }
    if (state.status === SrStatus.ON) {
      state.status = SrStatus.OFF;
    }
    if (held !== null) {
      void releaseQuietly(held, 'dropped');
    }
  }

  /** 按预算淘汰：当前图永不淘汰，被淘汰的图再次开启会重新处理 */
  private evictFor(currentKey: string): void {
    const entries: SrCacheEntry[] = [];
    for (let i: number = 0; i < this.order.length; i++) {
      const key: string = this.order[i];
      const state: PageSuperResolutionState | undefined = this.states.get(key);
      if (state !== undefined && state.hasResult) {
        const entry: SrCacheEntry = new SrCacheEntry();
        entry.key = key;
        entry.bytes = state.resultBytes;
        entries.push(entry);
      }
    }
    const doomed: string[] = srEvictionPlan(entries, currentKey, SR_CACHE_BUDGET_BYTES,
      this.exportPinnedKey);
    for (let i: number = 0; i < doomed.length; i++) {
      hilog.info(DOMAIN, TAG, 'evict cached result %{public}s', doomed[i].slice(0, 40));
      this.dropResult(doomed[i]);
    }
  }

  /**
   * 退出查看器：使在飞任务失效、清空缓存、在安全时机释放分析器。
   *
   * 增强图**延迟 `RELEASE_DELAY_MS` 释放**：本函数在 `aboutToDisappear` 里调用，
   * 此刻 ArkUI 可能还在用这张 PixelMap 收尾当前帧；立即释放会出现"渲染已释放对象"。
   * 引用先摘掉（本会话不再持有），真正的释放推后，且不影响下一次会话。
   */
  close(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    this.epoch += 1;
    const job: SrJob | null = this.currentJob;
    if (job !== null) {
      job.cancelled = true;
    }
    const doomed: image.PixelMap[] = [];
    const keys: string[] = [];
    this.states.forEach((state: PageSuperResolutionState, key: string): void => {
      if (state.pixelMap !== null) {
        doomed.push(state.pixelMap);
        state.pixelMap = null;
      }
      keys.push(key);
    });
    this.states.clear();
    this.order = [];
    hilog.info(DOMAIN, TAG, 'session closing: %{public}d enhanced pixelMap(s) to release', doomed.length);
    if (doomed.length > 0) {
      setTimeout((): void => {
        for (let i: number = 0; i < doomed.length; i++) {
          void releaseQuietly(doomed[i], 'session closed');
        }
      }, RELEASE_DELAY_MS);
    }
    // 分析器：有任务在飞时不释放（会把 process 打断），由引擎自己等它 settle 后再销毁
    void SrEngine.shared().destroy();
  }
}
