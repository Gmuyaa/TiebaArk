import { UIContext } from '@kit.ArkUI';
import { MotionEffect } from '../common/appearance/MotionConfig';
import { motionStore } from '../common/appearance/MotionStore';
import { ImageTransitionCrop } from '../model/ImageTransitionCrop';

let nextSource: number = 0;
let pending: ImageTransitionSeed | undefined = undefined;
let active: ImageTransitionSeed | undefined = undefined;
let activeReturn: ImageTransitionReturnRegistration | undefined = undefined;

/** 一处实际显示的缩略图；回调在准备返回时读取加载、可见性和组件身份。 */
export class ImageTransitionTarget {
  source: ImageTransitionSource;
  preview: string;
  origin: string;
  sourceIndex: number;
  crop: ImageTransitionCrop | undefined;
  onExpanded: ((expanded: boolean) => void) | undefined;
  onReleased: (() => void) | undefined;

  constructor(source: ImageTransitionSource, preview: string = '', origin: string = '', sourceIndex: number = 0,
    crop?: ImageTransitionCrop, onExpanded?: (expanded: boolean) => void, onReleased?: () => void) {
    this.source = source;
    this.preview = preview;
    this.origin = origin;
    this.sourceIndex = sourceIndex;
    this.crop = crop;
    this.onExpanded = onExpanded;
    this.onReleased = onReleased;
  }
}

class ImageTransitionGalleryEntry {
  origin: string;
  prepare: () => ImageTransitionTarget | undefined;

  constructor(origin: string, prepare: () => ImageTransitionTarget | undefined) {
    this.origin = origin;
    this.prepare = prepare;
  }
}

/** 每个实际呈现的图集独享一份注册表；相同 URL 的不同出现位置仍按下标区分。 */
export class ImageTransitionGallery {
  private entries: Map<number, ImageTransitionGalleryEntry> = new Map<number, ImageTransitionGalleryEntry>();

  register(viewerIndex: number, origin: string, prepare: () => ImageTransitionTarget | undefined): () => void {
    if (!Number.isInteger(viewerIndex) || viewerIndex < 0 || origin.length === 0) { return (): void => {}; }
    const entry: ImageTransitionGalleryEntry = new ImageTransitionGalleryEntry(origin, prepare);
    this.entries.set(viewerIndex, entry);
    return (): void => {
      // 旧组件晚到的离树回调不能注销同一位置后来注册的新组件。
      if (this.entries.get(viewerIndex) === entry) { this.entries.delete(viewerIndex); }
    };
  }

  prepare(viewerIndex: number, origin: string): ImageTransitionTarget | undefined {
    if (!Number.isInteger(viewerIndex) || viewerIndex < 0 || origin.length === 0) { return undefined; }
    const entry: ImageTransitionGalleryEntry | undefined = this.entries.get(viewerIndex);
    if (entry === undefined || entry.origin !== origin) { return undefined; }
    const target: ImageTransitionTarget | undefined = entry.prepare();
    if (target === undefined) { return undefined; }
    // 准备回调可能触发组件重用；再次确认仍是同一个位置、同一原图的注册。
    if (this.entries.get(viewerIndex) !== entry || target.origin !== origin || target.preview.length === 0 ||
      !Number.isInteger(target.sourceIndex) || target.sourceIndex < 0 ||
      (target.crop !== undefined && !target.crop.usable)) {
      target.onReleased?.();
      return undefined;
    }
    return target;
  }

  /** 离树清空旧成员；组件重新出现时可以重新注册。 */
  dispose(): void { this.entries.clear(); }
}

/** 返回解析属于 Viewer，会比最初点击的那一张缩略图活得更久。 */
class ImageTransitionReturnRegistration {
  opening: ImageTransitionSeed;
  prepare: () => ImageTransitionSeed | undefined;
  settleBeforeReturn: ((ready: () => void) => void) | undefined;
  returning: ImageTransitionSeed | undefined = undefined;
  live: boolean = true;
  closing: boolean = false;
  animationStarted: boolean = false;
  completed: boolean = false;

  constructor(opening: ImageTransitionSeed, prepare: () => ImageTransitionSeed | undefined,
    settleBeforeReturn?: (ready: () => void) => void) {
    this.opening = opening;
    this.prepare = prepare;
    this.settleBeforeReturn = settleBeforeReturn;
  }
}

/** 一次性桥接点击源与浮层；不按 URL 全局配对，重复图片仍各有独立返回位置。 */
export class ImageTransitionSeed {
  id: string;
  preview: string;
  origin: string;
  readonly crop: ImageTransitionCrop | undefined;
  readonly gallery: ImageTransitionGallery | undefined;
  readonly galleryIndex: number;
  private openingFinished: boolean = false;
  private closing: boolean = false;
  private finished: boolean = false;
  private returnEnabled: boolean = true;
  private returnDetached: boolean = false;
  private sourceExpanded: boolean = false;
  private nextListener: number = 0;
  private openingListeners: Map<number, () => void> = new Map<number, () => void>();
  private finishedListeners: Map<number, () => void> = new Map<number, () => void>();
  private onSourceExpanded: ((expanded: boolean) => void) | undefined;
  private onSourceReleased: (() => void) | undefined;
  private onSourceDetached: (() => void) | undefined;

  constructor(id: string = '', preview: string = '', origin: string = '',
    crop?: ImageTransitionCrop, onSourceExpanded?: (expanded: boolean) => void,
    onSourceReleased?: () => void, onSourceDetached?: () => void,
    gallery?: ImageTransitionGallery, galleryIndex: number = -1) {
    this.id = id;
    this.preview = preview;
    this.origin = origin;
    this.gallery = gallery;
    this.galleryIndex = Number.isInteger(galleryIndex) && galleryIndex >= 0 ? galleryIndex : -1;
    // 退出期间仍会读取此快照；源组件更新、复用或释放不能把它改掉。
    if (crop !== undefined) {
      const snapshot: ImageTransitionCrop = new ImageTransitionCrop();
      snapshot.scale = crop.scale;
      snapshot.centerX = crop.centerX;
      snapshot.centerY = crop.centerY;
      snapshot.usable = crop.usable;
      // 只有完整图片的单位变换才可按内容矩形共享；裁切预览保留旧框体语义。
      snapshot.contentAspectRatio = crop.usable && crop.scale === 1 &&
        Number.isFinite(crop.contentAspectRatio) && crop.contentAspectRatio > 0 ? crop.contentAspectRatio : 0;
      this.crop = snapshot;
    } else {
      this.crop = undefined;
    }
    this.onSourceExpanded = onSourceExpanded;
    this.onSourceReleased = onSourceReleased;
    this.onSourceDetached = onSourceDetached;
  }

  isOpening(): boolean {
    return this.crop !== undefined && !this.openingFinished && !this.closing && !this.finished;
  }

  bindOpeningFinished(listener: () => void): () => void {
    const key: number = ++this.nextListener;
    if (!this.finished && !this.closing) {
      // 动效为 0 或组件较晚挂载时，onFinish 可能早于订阅；完成状态必须保留。
      if (this.isOpening()) { this.openingListeners.set(key, listener); } else { listener(); }
    }
    return (): void => { this.openingListeners.delete(key); };
  }

  /** 源被取消后通知仍存活的 Viewer 改走淡化；正常关闭不提前撤掉共享配对。 */
  bindFinished(listener: () => void): () => void {
    const key: number = ++this.nextListener;
    if (!this.closing) {
      if (this.finished) { listener(); } else { this.finishedListeners.set(key, listener); }
    }
    return (): void => { this.finishedListeners.delete(key); };
  }

  setReturnEnabled(enabled: boolean): void {
    if (this.finished || this.closing || this.returnDetached || this.returnEnabled === enabled) { return; }
    this.returnEnabled = enabled;
    if (enabled) { this.expandSource(); } else { this.restoreSource(); }
  }

  /** 横向翻页后不再沿用初始缩略图配对；保留图片租约直到退场结束。 */
  detachSharedReturn(): void {
    if (this.finished || this.closing || this.returnDetached) { return; }
    this.returnDetached = true;
    this.returnEnabled = false;
    try { this.onSourceDetached?.(); } finally { this.restoreSource(); }
  }

  isReturnDetached(): boolean { return this.returnDetached; }

  /** Viewer 离树先撤监听；正常退场的源快照由动画完成回调再释放。 */
  release(): void {
    this.openingListeners.clear();
    this.finishedListeners.clear();
    this.clearRegistration();
    if (!this.closing) { this.finish(); }
  }

  /** 以下方法仅供本模块的源组件及动画协调器调用。 */
  expandSource(): void {
    if (this.finished || this.closing || !this.returnEnabled || this.crop === undefined || this.sourceExpanded) { return; }
    this.sourceExpanded = true;
    this.onSourceExpanded?.(true);
  }

  finishOpening(): void {
    if (this.finished || this.closing || this.openingFinished) { return; }
    this.openingFinished = true;
    const listeners: (() => void)[] = Array.from(this.openingListeners.values());
    this.openingListeners.clear();
    for (const listener of listeners) {
      if (this.finished || this.closing) { break; }
      listener();
    }
  }

  beginClosing(): boolean {
    if (this.finished || this.closing) { return false; }
    this.freezeReturnPreparation();
    return true;
  }

  /** 解析当前页前同步冻结 Viewer；原始源已失效时仍必须拦住迟到的翻页/解码回调。 */
  freezeReturnPreparation(): void {
    this.closing = true;
    this.openingListeners.clear();
    this.finishedListeners.clear();
  }

  restoreSource(): void {
    if (!this.sourceExpanded) { return; }
    this.sourceExpanded = false;
    this.onSourceExpanded?.(false);
  }

  finishClosing(): void { this.finish(); }

  /** 源身份失效时结束仍在等待的预览交接，再取消租约；已关闭或解绑的监听不会被唤回。 */
  cancel(): void {
    try { this.finishOpening(); } finally { this.finish(); }
  }

  isClosing(): boolean { return this.closing; }

  hasFinished(): boolean { return this.finished; }

  private clearRegistration(): void {
    if (pending === this) { pending = undefined; }
    if (active === this) { active = undefined; }
  }

  private finish(): void {
    if (this.finished) { return; }
    this.finished = true;
    this.openingListeners.clear();
    const listeners: (() => void)[] = Array.from(this.finishedListeners.values());
    this.finishedListeners.clear();
    this.clearRegistration();
    // 先标记结束和清除引用，再通知源，避免回调重入误清后来打开的会话。
    const expanded: boolean = this.sourceExpanded;
    this.sourceExpanded = false;
    const onExpanded: ((expanded: boolean) => void) | undefined = this.onSourceExpanded;
    const onReleased: (() => void) | undefined = this.onSourceReleased;
    this.onSourceExpanded = undefined;
    this.onSourceReleased = undefined;
    this.onSourceDetached = undefined;
    try {
      for (const listener of listeners) { listener(); }
    } finally {
      try { if (expanded) { onExpanded?.(false); } }
      finally { onReleased?.(); }
    }
  }
}

export class ImageTransitionSource {
  private prefix: string = `image-transition-${++nextSource}`;
  private lease: number = 0;
  private seed: ImageTransitionSeed | undefined = undefined;
  private sharedEnabled: boolean = true;
  private onSharedChanged: ((enabled: boolean) => void) | undefined;

  constructor(onSharedChanged?: (enabled: boolean) => void) {
    this.onSharedChanged = onSharedChanged;
  }

  private setSharedEnabled(enabled: boolean): void {
    if (this.sharedEnabled === enabled) { return; }
    this.sharedEnabled = enabled;
    this.onSharedChanged?.(enabled);
  }

  /** 新点击的资格不受上一场尚在退场的临时解绑影响。 */
  canOpenShared(): boolean { return motionStore.isOn(MotionEffect.SHARED_ELEMENT); }

  id(url: string, index: number = 0): string {
    if (!this.sharedEnabled || !this.canOpenShared()) { return ''; }
    // URL 参与身份：列表组件复用后不能把旧图收回到新图的位置。
    return `${this.prefix}:${index}:${url}`;
  }

  open(context: UIContext, preview: string, origin: string, action: () => void,
    index: number = 0, showPreview: boolean = true, crop?: ImageTransitionCrop,
    onSourceExpanded?: (expanded: boolean) => void, onSourceReleased?: () => void,
    gallery?: ImageTransitionGallery, galleryIndex: number = -1): void {
    this.invalidate();
    // 未被 Viewer 消费的旧点击也必须归还其源组件，但不碰其他已激活会话。
    pending?.cancel();
    const lease: number = ++this.lease;
    this.setSharedEnabled(true);
    const shared: boolean = showPreview && this.canOpenShared();
    const usableCrop: ImageTransitionCrop | undefined = shared && crop?.usable ? crop : undefined;
    const id: string = shared && (crop === undefined || crop.usable) ? this.id(preview, index) : '';
    const seed: ImageTransitionSeed = new ImageTransitionSeed(id, showPreview ? preview : '', origin,
      usableCrop, onSourceExpanded, (): void => {
        try {
          if (this.lease === lease) {
            this.seed = undefined;
            this.setSharedEnabled(true);
          }
        } finally { onSourceReleased?.(); }
      }, (): void => {
        if (this.lease === lease) { this.setSharedEnabled(false); }
      }, gallery, galleryIndex);
    this.seed = seed;
    pending = seed;
    try {
      context.animateTo({ duration: imageSharedDuration(), curve: Curve.Friction,
        onFinish: (): void => {
          if (!seed.hasFinished()) { context.runScopedTask((): void => { seed.finishOpening(); }); }
        } }, (): void => {
        seed.expandSource();
        action();
      });
    } catch (error) {
      seed.cancel();
      throw new Error(String(error));
    }
  }

  /** 只获取返回源租约；不创建 pending、不打开 Viewer，也不启动一次新的入场动画。 */
  prepareReturn(target: ImageTransitionTarget): ImageTransitionSeed {
    if (target.source !== this) { return new ImageTransitionSeed(); }
    this.invalidate();
    const lease: number = ++this.lease;
    this.setSharedEnabled(true);
    const shared: boolean = this.canOpenShared() && target.preview.length > 0 &&
      Number.isInteger(target.sourceIndex) && target.sourceIndex >= 0;
    const crop: ImageTransitionCrop | undefined = shared && target.crop?.usable ? target.crop : undefined;
    const id: string = shared && (target.crop === undefined || target.crop.usable)
      ? this.id(target.preview, target.sourceIndex) : '';
    const seed: ImageTransitionSeed = new ImageTransitionSeed(id, target.preview, target.origin, crop,
      (expanded: boolean): void => {
        if (this.lease === lease) { target.onExpanded?.(expanded); }
      }, (): void => {
        try {
          if (this.lease === lease) {
            this.seed = undefined;
            this.setSharedEnabled(true);
          }
        } finally { target.onReleased?.(); }
      }, (): void => {
        if (this.lease === lease) { this.setSharedEnabled(false); }
      });
    this.seed = seed;
    return seed;
  }

  invalidate(): void {
    const seed: ImageTransitionSeed | undefined = this.seed;
    this.seed = undefined;
    seed?.cancel();
  }
}

export function takeImageTransition(origin: string): ImageTransitionSeed {
  const candidate: ImageTransitionSeed | undefined = pending;
  pending = undefined;
  let seed: ImageTransitionSeed;
  if (candidate !== undefined && candidate.origin === origin && !candidate.hasFinished()) {
    seed = candidate;
  } else {
    candidate?.cancel();
    seed = new ImageTransitionSeed();
  }
  // 新的普通 Viewer 也必须接管返回解析；不能继承上一处相同 URL 的图集注册表。
  if (activeReturn !== undefined && activeReturn.opening !== seed) { retireReturnRegistration(activeReturn); }
  // 无源预览的普通 Viewer 也接管会话，不能让其关闭误操作旧 Viewer 的裁切源。
  // 新 Viewer 接管后，旧 Viewer 的迟到 release/onFinish 只能清其自己的引用。
  if (active !== seed) { active?.release(); }
  active = seed;
  return seed;
}

/** 注册当前 Viewer 的返回解析；初始源取消、离屏或复用不会提前销毁这个解析器。 */
export function bindImageTransitionReturn(opening: ImageTransitionSeed,
  prepare: () => ImageTransitionSeed | undefined,
  settleBeforeReturn?: (ready: () => void) => void): () => void {
  if (activeReturn !== undefined) { retireReturnRegistration(activeReturn); }
  const registration: ImageTransitionReturnRegistration =
    new ImageTransitionReturnRegistration(opening, prepare, settleBeforeReturn);
  activeReturn = registration;
  return (): void => { retireReturnRegistration(registration); };
}

function finishRegisteredReturn(registration: ImageTransitionReturnRegistration): void {
  if (registration.completed) { return; }
  registration.completed = true;
  registration.live = false;
  if (activeReturn === registration) { activeReturn = undefined; }
  // 清全局引用在回调之前，旧释放回调若重开 Viewer，不能覆盖后来会话。
  const returning: ImageTransitionSeed | undefined = registration.returning;
  registration.returning = undefined;
  try { returning?.finishClosing(); }
  finally {
    if (returning !== registration.opening) { registration.opening.finishClosing(); }
  }
}

function retireReturnRegistration(registration: ImageTransitionReturnRegistration): void {
  registration.live = false;
  if (activeReturn === registration) { activeReturn = undefined; }
  // 等待 Swiper 时还没有退场完成回调；离树/重开必须主动归还已冻结的旧源。
  if (registration.closing && !registration.animationStarted) { finishRegisteredReturn(registration); }
}

function animateRegisteredReturn(context: UIContext, registration: ImageTransitionReturnRegistration,
  action: () => void, beforeClose?: () => void): void {
  // 同步 prepare 内也可能刷新原生布局并重入离树；先保留租约，拿到返回值后再统一释放。
  registration.animationStarted = true;
  try {
    // prepare 在动画事务外同步提交新 ID/crop 和源展开状态；随后 animateTo 会先刷新布局。
    let returning: ImageTransitionSeed | undefined = registration.prepare();
    registration.returning = returning;
    if (!registration.live || registration.completed || activeReturn !== registration) {
      finishRegisteredReturn(registration);
      return;
    }
    if (returning !== undefined && returning !== registration.opening && !returning.beginClosing()) {
      returning = undefined;
    }
    const shared: boolean = returning !== undefined && !returning.hasFinished() &&
      returning.id.length > 0 && !returning.isReturnDetached();
    beforeClose?.();
    if (!registration.live || registration.completed || activeReturn !== registration) {
      finishRegisteredReturn(registration);
      return;
    }
    const closing: ImageTransitionSeed | undefined = returning;
    context.animateTo({ duration: shared ? imageSharedDuration() : imageFadeDuration(),
      curve: shared ? Curve.Friction : Curve.EaseOut,
      onFinish: (): void => {
        context.runScopedTask((): void => { finishRegisteredReturn(registration); });
      } }, (): void => {
      // 初始源可能仍保留图片；只在此处恢复，不抢先释放退场所需的像素。
      if (closing !== registration.opening) { registration.opening.restoreSource(); }
      closing?.restoreSource();
      action();
    });
  } catch (error) {
    finishRegisteredReturn(registration);
    throw new Error(String(error));
  }
}

function closeRegisteredReturn(context: UIContext, registration: ImageTransitionReturnRegistration,
  action: () => void, beforeClose?: () => void): void {
  if (!registration.live || registration.closing) { return; }
  registration.closing = true;
  registration.opening.freezeReturnPreparation();
  let consumed: boolean = false;
  const ready: () => void = (): void => {
    if (consumed) { return; }
    consumed = true;
    // finishAnimation 可以异步回调；旧 Viewer 已离树或被替换时不能再移除后来页面。
    if (!registration.live || registration.completed || activeReturn !== registration) { return; }
    animateRegisteredReturn(context, registration, action, beforeClose);
  };
  try {
    if (registration.settleBeforeReturn === undefined) { ready(); }
    else { registration.settleBeforeReturn(ready); }
  } catch (error) {
    finishRegisteredReturn(registration);
    throw new Error(String(error));
  }
}

export function imageSharedDuration(): number {
  return motionStore.isOn(MotionEffect.SHARED_ELEMENT) ? 300 : 0;
}

export function animateImageTransition(context: UIContext, action: () => void): void {
  context.animateTo({ duration: imageSharedDuration(), curve: Curve.Friction }, action);
}

/** 仅图片 Viewer 的关闭入口使用；普通浮层的 animateImageTransition 不改变源会话。 */
export function closeImageTransition(context: UIContext, action: () => void,
  beforeClose?: () => void): void {
  const registration: ImageTransitionReturnRegistration | undefined = activeReturn;
  if (registration !== undefined) {
    closeRegisteredReturn(context, registration, action, beforeClose);
    return;
  }
  const seed: ImageTransitionSeed | undefined = active;
  if (seed === undefined) {
    beforeClose?.();
    animateImageTransition(context, action);
    return;
  }
  if (!seed.beginClosing()) { return; }
  try {
    beforeClose?.();
    context.animateTo({ duration: seed.isReturnDetached() ? imageFadeDuration() : imageSharedDuration(),
      curve: seed.isReturnDetached() ? Curve.EaseOut : Curve.Friction,
      onFinish: (): void => {
        if (!seed.hasFinished()) { context.runScopedTask((): void => { seed.finishClosing(); }); }
      } }, (): void => {
      seed.restoreSource();
      action();
    });
  } catch (error) {
    seed.cancel();
    throw new Error(String(error));
  }
}

/** 遮罩与共享几何分开计时，关闭共享元素时仍保留用户开启的淡化。 */
export function imageFadeDuration(): number {
  return motionStore.isOn(MotionEffect.FADE) ? 300 : 0;
}

/** 保留查看器的原生退场子树，避免照片尚在缩回时上层容器已被立即移除。 */
export function imageLayerRetentionTransition(): TransitionEffect {
  const duration: number = Math.max(imageSharedDuration(), imageFadeDuration());
  if (duration === 0) { return TransitionEffect.IDENTITY; }
  // IDENTITY 和 opacity(1) 都不会产生实际动画；与 1 保持足够差值，避免被浮点近似跳过。
  // 只让容器变化 0.2% 的透明度来保持存续，真正的淡出由独立黑底和非共享图片负责。
  return TransitionEffect.opacity(0.998).animation({ duration: duration, curve: Curve.Linear });
}

export function imageFadeTransition(): TransitionEffect {
  return TransitionEffect.OPACITY.animation({ duration: imageFadeDuration(), curve: Curve.EaseOut });
}
