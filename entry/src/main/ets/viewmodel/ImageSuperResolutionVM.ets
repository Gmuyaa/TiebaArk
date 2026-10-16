

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

const RELEASE_DELAY_MS: number = 200;

@Observed
export class PageSuperResolutionState {

  key: string = '';

  status: number = SrStatus.OFF;

  reason: string = '';

  hasResult: boolean = false;
  resultWidth: number = 0;
  resultHeight: number = 0;

  resultBytes: number = 0;

  resultHasAlpha: boolean = false;

  resultVersion: number = 0;

  pixelMap: image.PixelMap | null = null;
}

export class SrToggleResult {
  message: string = '';
  changed: boolean = false;
}

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

export class ImageSuperResolutionSession {
  private states: Map<string, PageSuperResolutionState> = new Map<string, PageSuperResolutionState>();

  private order: string[] = [];

  private epoch: number = 0;

  private currentJob: SrJob | null = null;
  private currentKey: string = '';

  private exportPinnedKey: string = '';
  private deviceSupported: boolean = true;
  private closed: boolean = false;

  constructor() {
    this.deviceSupported = srDeviceSupported();
    hilog.info(DOMAIN, TAG, 'session opened, deviceSupported=%{public}s', String(this.deviceSupported));
  }

  isDeviceSupported(): boolean {
    return this.deviceSupported;
  }

  isBusy(): boolean {
    return this.currentJob !== null;
  }

  setExportPin(key: string): void {
    this.exportPinnedKey = key;
  }

  clearExportPin(): void {
    this.exportPinnedKey = '';
  }

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

  private cancelJob(job: SrJob, why: string): void {
    job.cancelled = true;
    const state: PageSuperResolutionState | undefined = this.states.get(job.key);
    if (state !== undefined && state.status === SrStatus.PROCESSING) {
      state.status = SrStatus.OFF;
    }
    hilog.info(DOMAIN, TAG, 'job for %{public}s invalidated (%{public}s)', job.key.slice(0, 40), why);
  }

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

    if (this.currentJob !== null) {
      result.message = this.currentJob.key === key
        ? '图像超分正在处理中，请稍候'
        : '正在处理上一张图片，请稍候';
      return result;
    }

    if (state.status === SrStatus.ON) {
      state.status = SrStatus.OFF;
      result.changed = true;
      return result;
    }

    if (state.hasResult && state.pixelMap !== null) {
      state.status = SrStatus.ON;
      result.changed = true;
      this.touch(key);
      return result;
    }

    if (state.status === SrStatus.UNAVAILABLE) {
      result.message = state.reason.length > 0 ? state.reason : '这张图暂不支持超分';
      return result;
    }

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

  private jobAlive(job: SrJob): boolean {
    return !this.closed && !job.cancelled && job.epoch === this.epoch;
  }

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

      job.cancelled = true;
      state.status = SrStatus.ERROR;
      state.reason = srFailureText(SrFailure.TIMEOUT, '');
      hilog.warn(DOMAIN, TAG, 'job timeout after %{public}dms', SR_TIMEOUT_MS);
    }
  }

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

        await releaseQuietly(output, 'stale result');
        return;
      }
      await this.adoptResult(job, state, output, decoded.hasAlpha,
        srPredictedOutputBytes(decoded.width, decoded.height));
    } finally {

      if (prepared !== null && prepared.decoded !== null) {
        await prepared.decoded.release();
      }
    }
  }

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

    state.status = SrStatus.ERROR;
    state.reason = srFailureText(SrFailure.UNKNOWN, message);
  }

  private touch(key: string): void {
    const index: number = this.order.indexOf(key);
    if (index >= 0) {
      this.order.splice(index, 1);
    }
    this.order.push(key);
  }

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

    void SrEngine.shared().destroy();
  }
}
