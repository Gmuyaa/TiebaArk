import { MotionEffect } from '../common/appearance/MotionConfig';
import { motionDuration, motionGeometryId, motionTransition, motionSwiperCurve } from '../common/appearance/MotionPolicy';
import { ImageMenuPosition } from './ImageMenuPosition';
import { smartReachStore } from '../common/appearance/SmartReachStore';
import { MaterialTabs } from './MaterialTabs';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { SavedEmojiManagerVM } from '../viewmodel/SavedEmojiManagerVM';
import { ImageUploadInput } from '../model/ImageUpload';
import { ImageTransitionSeed, ImageTransitionTarget, bindImageTransitionReturn, takeImageTransition,
  closeImageTransition, imageFadeTransition, imageSharedDuration, imageLayerRetentionTransition } from './ImageTransition';
import { ImageTransitionCrop } from '../model/ImageTransitionCrop';
/** 全屏图片查看器，支持缩放、滑动切换、导出与当前图片超分。 */

import { display, promptAction, UIUtils, window } from '@kit.ArkUI';
import { AppTheme } from '../theme/Theme';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { KeyCode } from '@ohos.multimodalInput.keyCode';
import {
  fetchImageBytes,
  imageFileName,
  saveImageToGallery,
  shareImageFile,
  writeImageToCache
} from '../utils/ImageExport';
import { superResolutionStore } from '../common/appearance/SuperResolutionStore';
import {
  SrStatus, SR_BUTTON_BASE, SR_BUTTON_ICON, SR_BUTTON_INSET, SR_BUTTON_MARGIN, SR_BUTTON_TOUCH,
  SrButtonBox, srButtonPosition
} from '../model/ImageSuperResolution';
import {
  ImageSuperResolutionSession,
  PageSuperResolutionState,
  SrToggleResult
} from '../viewmodel/ImageSuperResolutionVM';

const MIN_SCALE: number = 1;
const MAX_SCALE: number = 4;
const DOUBLE_TAP_SCALE: number = 2;
const ANIMATION_DURATION: number = 180;
/** 解码尺寸可能有取整误差；明显不同的预览/原图比例不能错误共享返回。 */
const SHARED_ASPECT_TOLERANCE: number = 0.01;
/** 导出菜单日志（C-06／H-07 真机取证用；只记状态与地址前 60 字符，不含凭据） */
const EXPORT_DOMAIN: number = 0x0;
const EXPORT_TAG: string = 'ImageViewerExport';

class ImageSize {
  width: number = 0;
  height: number = 0;
}

/** 返回前同步读取实际当前页；不依赖上一次异步上报，也不更换图片源。 */
class ImageReturnPageState {
  atRest: boolean = false;
  ready: boolean = false;
  aspectRatio: number = 0;
}

interface ImageCompleteInfo {
  width: number;
  height: number;
  loadingStatus: number;
}

enum ImageLoadState {
  LOADING,
  SUCCESS,
  ERROR
}

/**
 * 每页的缩放 / 位移状态就放在页内（`@State`）。
 *
 * 曾经这里挂着一个 `@Observed class PageViewState` + 父组件持有数组 + `@ObjectLink`，
 * 目的是"翻页时不重建页面，同时把离开的那页缩放复位"。实测发现这条路**没有意义**：
 * 本页放大后 `PanGesture`（`InteractiveImage` 上那条，`distance: 5`）会独占横向手势，
 * `swipe` 与 `fling` 都推不动 `Swiper`（实测页码纹丝不动停在 `1 / 8`）——
 * 也就是说**放大状态下根本切不了页**，"翻页时复位别的页"永远不会发生。
 * 于是退回页内 `@State`：新页在 `aboutToAppear` 里自然回到 1x，够用且少一层状态。
 */

@Component
struct ZoomableImagePage {
  imageUrl: string = '';
  @Prop transitionId: string = '';
  @Prop returnId: string = '';
  @Prop returnCropUsable: boolean = false;
  @Prop returnCropScale: number = 1;
  @Prop returnCropCenterX: string = '50%';
  @Prop returnCropCenterY: string = '50%';
  @Prop returnContentAspectRatio: number = 0;
  canUpdateSession: () => boolean = (): boolean => true;
  onRegisterReturnState: (index: number, read: () => ImageReturnPageState) => () => void =
    (_index: number, _read: () => ImageReturnPageState): (() => void) => (): void => {};
  private stopReturnState: () => void = (): void => {};
  transitionPreview: string = '';
  transitionCrop: ImageTransitionCrop | undefined = undefined;
  @Prop @Watch('onPreviewHoldChanged') holdTransitionPreview: boolean = false;
  onReturnEligibility: (index: number, eligible: boolean) => void = (_index: number, _eligible: boolean): void => {};

  onLongPressImage: () => void = (): void => {};
  onTapImage: () => void = (): void => {};

  @State private zoomScale: number = MIN_SCALE;
  @State private panX: number = 0;
  @State private panY: number = 0;
  @State private containerWidth: number = 0;
  @State private containerHeight: number = 0;
  @State private sourceWidth: number = 0;
  @State private sourceHeight: number = 0;
  @State private loadState: ImageLoadState = ImageLoadState.LOADING;
  @State private retryCount: number = 0;

  /** 本页在图片列表里的下标（回调时原样带回，不依赖 `currentIndex` 的时序） */
  @State private topSafeVp: number = 0;
  private srTouchActive: boolean = false;
  private srGuardUntil: number = 0;
  onSuperResolutionToggle: (index: number) => void = (): void => {};
  index: number = 0;
  /** 解码成功时把**真实像素尺寸**报给查看器：尺寸不合规的图在点击前就能灰显 */
  onImageDecoded: (index: number, width: number, height: number) => void = (): void => {};
  /**
   * 这一页的超分状态。**`@ObjectLink`**：处理完成 / 被淘汰 / 失败这些变化由会话发起，
   * 只有 `@ObjectLink` 能把它们推进到本页界面，而不必改 `ForEach` 的 key
   * （改 key 会重建页面、`Image` 重新加载 —— 翻页闪一下、缩放复位的老路）。
   */
  @ObjectLink sr: PageSuperResolutionState;


  private pinchBase: number = MIN_SCALE;
  @State private zoomAnimating: boolean = false;
  private zoomAnimationEpoch: number = 0;
  private pageActive: boolean = false;
  private imageLoadEpoch: number = 0;
  private panBaseX: number = 0;
  private panBaseY: number = 0;

  aboutToAppear(): void {
    this.pageActive = true;
    ++this.imageLoadEpoch;
    ++this.zoomAnimationEpoch;
    this.zoomAnimating = false;
    this.resetImageState();
    this.readWindowSize();
    this.stopReturnState = this.onRegisterReturnState(this.index, (): ImageReturnPageState => this.readReturnState());
  }

  aboutToDisappear(): void {
    this.pageActive = false;
    this.stopReturnState();
    ++this.imageLoadEpoch;
    ++this.zoomAnimationEpoch;
  }

  private canUpdatePage(): boolean {
    return this.pageActive && this.canUpdateSession();
  }

  private readReturnState(): ImageReturnPageState {
    const state: ImageReturnPageState = new ImageReturnPageState();
    state.atRest = this.pageActive && !this.zoomAnimating && this.zoomScale === MIN_SCALE &&
      this.contentAspectMatchesSource();
    state.ready = this.loadState === ImageLoadState.SUCCESS && this.primaryImageVisible();
    const width: number = this.displayedSourceWidth();
    const height: number = this.displayedSourceHeight();
    const ratio: number = width / height;
    state.aspectRatio = Number.isFinite(width) && Number.isFinite(height) && width > 0 && height > 0 &&
      Number.isFinite(ratio) && ratio > 0 ? ratio : 0;
    return state;
  }

  private resetImageState(): void {
    this.zoomScale = MIN_SCALE;
    this.panX = 0;
    this.panY = 0;
    this.loadState = ImageLoadState.LOADING;
    this.retryCount = 0;
    this.sourceWidth = 0;
    this.sourceHeight = 0;
  }

  private readWindowSize(): void {
    // 共享目标首帧就有可用宽高；真实窗口和全屏外层 onAreaChange 随后校正。
    try {
      const screen: display.Display = display.getDefaultDisplaySync();
      if (screen.width > 0 && screen.height > 0) {
        this.containerWidth = px2vp(screen.width);
        this.containerHeight = px2vp(screen.height);
      }
    } catch (_) { /* 无同步显示信息时仍可由窗口/布局回调提供尺寸。 */ }
    const epoch: number = this.imageLoadEpoch;
    try {
      const context = this.getUIContext().getHostContext();
      window.getLastWindow(context).then((win: window.Window) => {
        if (!this.canUpdatePage() || epoch !== this.imageLoadEpoch) { return; }
        const rect = win.getWindowProperties().windowRect;
        this.containerWidth = rect.width > 0 ? px2vp(rect.width) : this.containerWidth;
        this.containerHeight = rect.height > 0 ? px2vp(rect.height) : this.containerHeight;
        this.topSafeVp = px2vp(win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height);
        this.clampOffsets();
      }).catch(() => {
        // onAreaChange 会提供更精确的组件尺寸；这里仅作为早期兜底。
      });
    } catch (err) {
      // 不影响图片加载和手势。
    }
  }

  private sourceForLoad(): string {
    if (this.retryCount <= 0) {
      return this.imageUrl;
    }
    const separator: string = this.imageUrl.indexOf('?') >= 0 ? '&' : '?';
    return `${this.imageUrl}${separator}preview_retry=${this.retryCount}`;
  }

  // ───────────────────────── 图像超分显示 ─────────────────────────

  /** 当前显示的是不是增强图。**增强图与原图各自独立引用**，原图 URL 始终留着 */
  private showingEnhanced(): boolean {
    return this.sr.status === SrStatus.ON && this.sr.pixelMap !== null;
  }

  /** 交给 `Image` 的源：开着超分用增强 PixelMap，否则用原图 URL */
  private displaySource(): image.PixelMap | string {
    const enhanced: image.PixelMap | null = this.sr.pixelMap;
    if (this.sr.status === SrStatus.ON && enhanced !== null) {
      return enhanced;
    }
    return this.sourceForLoad();
  }

  /** 当前画面的原始像素宽：增强图用结果尺寸，原图用 `onComplete` 报的尺寸 */
  private displayedSourceWidth(): number {
    if (this.showingEnhanced() && this.sr.resultWidth > 0) {
      return this.sr.resultWidth;
    }
    return this.sourceWidth;
  }

  private displayedSourceHeight(): number {
    if (this.showingEnhanced() && this.sr.resultHeight > 0) {
      return this.sr.resultHeight;
    }
    return this.sourceHeight;
  }

  /** 同一 URI 只使用主 Image；异源预览节点保留到本页销毁，用透明度交接。 */
  private hasSeparateTransitionPreview(): boolean {
    return this.transitionPreview.length > 0 &&
      (this.transitionPreview !== this.sourceForLoad() || this.showingEnhanced());
  }

  private primaryImageVisible(): boolean {
    return !this.hasSeparateTransitionPreview() ||
      (!this.holdTransitionPreview && this.loadState === ImageLoadState.SUCCESS);
  }

  private transitionPreviewVisible(): boolean {
    return this.hasSeparateTransitionPreview() && !this.primaryImageVisible();
  }

  /** 大于零的比例只由正文完整图片提供；首页和旧图集仍使用原来的全屏共享框。 */
  private sourceContentAspectRatio(): number {
    const ratio: number = this.returnId.length > 0 ? this.returnContentAspectRatio :
      (this.transitionCrop?.contentAspectRatio ?? 0);
    return Number.isFinite(ratio) && ratio > 0 ? ratio : 0;
  }

  private contentAspectRatio(): number {
    const sourceRatio: number = this.sourceContentAspectRatio();
    if (sourceRatio === 0 || this.holdTransitionPreview || this.loadState !== ImageLoadState.SUCCESS) {
      return sourceRatio;
    }
    const width: number = this.displayedSourceWidth();
    const height: number = this.displayedSourceHeight();
    const ratio: number = width / height;
    return Number.isFinite(width) && Number.isFinite(height) && width > 0 && height > 0 &&
      Number.isFinite(ratio) && ratio > 0 ? ratio : sourceRatio;
  }

  private contentAspectMatchesSource(): boolean {
    const sourceRatio: number = this.sourceContentAspectRatio();
    if (sourceRatio === 0) { return true; }
    const ratio: number = this.contentAspectRatio();
    return Math.abs(ratio - sourceRatio) / Math.max(ratio, sourceRatio) <= SHARED_ASPECT_TOLERANCE;
  }

  private imageFrameSize(): ImageSize {
    const result: ImageSize = new ImageSize();
    const width: number = this.containerWidth;
    const height: number = this.containerHeight;
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) { return result; }
    result.width = width;
    result.height = height;
    const ratio: number = this.contentAspectRatio();
    if (ratio > 0) {
      if (width / height > ratio) {
        result.width = height * ratio;
      } else {
        result.height = width / ratio;
      }
    }
    return result;
  }

  private imageFrameWidth(): number | string {
    const size: ImageSize = this.imageFrameSize();
    return this.sourceContentAspectRatio() > 0 && size.width > 0 ? size.width : '100%';
  }

  private imageFrameHeight(): number | string {
    const size: ImageSize = this.imageFrameSize();
    return this.sourceContentAspectRatio() > 0 && size.height > 0 ? size.height : '100%';
  }

  private sharedGeometryId(): string {
    if (this.zoomScale !== MIN_SCALE || this.zoomAnimating || !this.contentAspectMatchesSource()) { return ''; }
    return motionGeometryId(this.returnId.length > 0 ? this.returnId : this.transitionId);
  }

  private imageContentTransition(): TransitionEffect {
    // 共享图片需要真实退场动画才能继续绘制；回退图片仍尊重淡化设置。
    return this.sharedGeometryId().length > 0 ? imageLayerRetentionTransition() : imageFadeTransition();
  }

  private imageFrameClipped(): boolean {
    // 放大图可以越过正文的窄拟合框，但始终受外层全屏区域裁切。
    return this.sourceContentAspectRatio() === 0 ||
      (this.zoomScale === MIN_SCALE && !this.zoomAnimating);
  }

  private onPreviewHoldChanged(_propertyName: string): void {
    if (!this.canUpdatePage()) { return; }
    this.clampOffsets();
    this.reportReturnEligibility();
  }

  /** 手势护栏：刚碰过超分按钮的一小段时间内，不认"单击关闭 / 双击放大 / 长按导出" */
  private srBlocked(): boolean {
    return this.srTouchActive || Date.now() < this.srGuardUntil;
  }

  private srIconColor(): ResourceColor {
    if (this.sr.status === SrStatus.UNAVAILABLE) {
      return '#80FFFFFF';
    }
    if (this.sr.status === SrStatus.ON) {
      return AppTheme.ON_ACCENT;
    }
    return Color.White;
  }

  private srBaseColor(): ResourceColor {
    if (this.sr.status === SrStatus.UNAVAILABLE) {
      return '#33000000';
    }
    if (this.sr.status === SrStatus.ON) {
      // 开启成功使用当前主题强调色的半透明底。
      return AppTheme.SR_ACTIVE_BACKGROUND;
    }
    return '#66000000';
  }

  private srAccessibilityText(): string {
    if (this.sr.status === SrStatus.PROCESSING) {
      return '正在处理图像超分';
    }
    if (this.sr.status === SrStatus.ON) {
      return '关闭图像超分';
    }
    if (this.sr.status === SrStatus.UNAVAILABLE) {
      return '图像超分不可用';
    }
    if (this.sr.status === SrStatus.ERROR) {
      return '图像超分失败，点击重试';
    }
    return '开启图像超分';
  }

  /**
   * 按钮落点：以**图片实际显示区域的右上角**为锚、内缩 12vp，再夹进可操作区域。
   * 几何全在纯逻辑 `srButtonPosition()` 里，边界（小图/长图/满屏/放大拖动出屏）
   * 由 Node 侧用例钉住；这里只把当前页的实时数值喂进去。
   */
  private srButtonBox(): SrButtonBox {
    const fit: ImageSize = this.sourceImageSize();
    return srButtonPosition(this.containerWidth, this.containerHeight, fit.width, fit.height,
      this.zoomScale, this.panX, this.panY, SR_BUTTON_INSET, this.topSafeVp + SR_BUTTON_MARGIN);
  }

  @Builder
  private SuperResolutionButton() {
    Stack() {
      Stack() {
        if (this.sr.status === SrStatus.PROCESSING) {
          LoadingProgress()
            .width(SR_BUTTON_ICON)
            .height(SR_BUTTON_ICON)
            .color(Color.White)
        } else {
          // 两态与全站图标约定一致：未开启用线框、开启后用实心
          SymbolGlyph(this.sr.status === SrStatus.ON
            ? $r('sys.symbol.wand_and_stars_fill')
            : $r('sys.symbol.wand_and_stars'))
            .fontSize(SR_BUTTON_ICON)
            .fontColor([this.srIconColor()])
        }
      }
      .width(SR_BUTTON_BASE)
      .height(SR_BUTTON_BASE)
      .borderRadius(SR_BUTTON_BASE / 2)
      .backgroundColor(this.srBaseColor())
    }
    .width(SR_BUTTON_TOUCH)
    .height(SR_BUTTON_TOUCH)
    .position({ x: this.srButtonBox().x, y: this.srButtonBox().y })
    .accessibilityText(this.srAccessibilityText())
    .accessibilityLevel('yes')
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.srTouchActive = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.srTouchActive = false;
      }
      this.srGuardUntil = Date.now() + 400;
    })
    .onClick(() => {
      this.srGuardUntil = Date.now() + 400;
      this.onSuperResolutionToggle(this.index);
    })
    .transition(imageFadeTransition())
  }

  private sourceImageSize(): ImageSize {
    const result: ImageSize = new ImageSize();
    const frame: ImageSize = this.imageFrameSize();
    const widthPx: number = this.displayedSourceWidth();
    const heightPx: number = this.displayedSourceHeight();
    if (widthPx <= 0 || heightPx <= 0) {
      result.width = frame.width;
      result.height = frame.height;
      return result;
    }
    const imageWidth: number = px2vp(widthPx);
    const imageHeight: number = px2vp(heightPx);
    if (frame.width <= 0 || frame.height <= 0) {
      result.width = imageWidth;
      result.height = imageHeight;
      return result;
    }
    const fitScale: number = Math.min(frame.width / imageWidth, frame.height / imageHeight);
    result.width = imageWidth * fitScale;
    result.height = imageHeight * fitScale;
    return result;
  }

  private offsetLimitX(): number {
    const size = this.sourceImageSize();
    return Math.max(0, (size.width * this.zoomScale - this.containerWidth) / 2);
  }

  private offsetLimitY(): number {
    const size = this.sourceImageSize();
    return Math.max(0, (size.height * this.zoomScale - this.containerHeight) / 2);
  }

  private clampOffsets(): void {
    const limitX: number = this.offsetLimitX();
    const limitY: number = this.offsetLimitY();
    this.panX = Math.max(-limitX, Math.min(limitX, this.panX));
    this.panY = Math.max(-limitY, Math.min(limitY, this.panY));
  }

  private setScale(value: number): void {
    if (!this.canUpdatePage()) { return; }
    const next: number = Math.max(MIN_SCALE, Math.min(MAX_SCALE, value));
    this.zoomScale = next;
    if (next === MIN_SCALE) {
      this.panX = 0;
      this.panY = 0;
    } else {
      this.clampOffsets();
    }
    this.reportReturnEligibility();
  }

  private reportReturnEligibility(): void {
    if (this.canUpdatePage()) {
      this.onReturnEligibility(this.index, !this.zoomAnimating && this.zoomScale === MIN_SCALE &&
        this.contentAspectMatchesSource());
    }
  }

  private animateZoom(action: () => void): void {
    if (!this.canUpdatePage()) { return; }
    const epoch: number = ++this.zoomAnimationEpoch;
    this.zoomAnimating = true;
    this.reportReturnEligibility();
    this.getUIContext().animateTo({ duration: motionDuration(ANIMATION_DURATION, MotionEffect.SCALE),
      onFinish: (): void => {
        if (!this.canUpdatePage() || epoch !== this.zoomAnimationEpoch) { return; }
        this.zoomAnimating = false;
        this.reportReturnEligibility();
      } }, action);
  }

  private settleScale(): void {
    const target: number = Math.max(MIN_SCALE, Math.min(MAX_SCALE, this.zoomScale));
    this.animateZoom(() => {
      this.setScale(target);
      if (target === MIN_SCALE) {
        this.panX = 0;
        this.panY = 0;
      }
    });
  }

  private toggleDoubleTapZoom(): void {
    this.animateZoom(() => {
      if (this.zoomScale > MIN_SCALE) {
        this.setScale(MIN_SCALE);
      } else {
        this.setScale(DOUBLE_TAP_SCALE);
      }
    });
  }

  private retry(): void {
    if (!this.canUpdatePage()) { return; }
    ++this.imageLoadEpoch;
    this.retryCount += 1;
    this.loadState = ImageLoadState.LOADING;
    this.sourceWidth = 0;
    this.sourceHeight = 0;
    this.clampOffsets();
    this.reportReturnEligibility();
  }

  private acceptsImageCallback(source: image.PixelMap | string, epoch: number): boolean {
    return this.canUpdatePage() && epoch === this.imageLoadEpoch && source === this.displaySource();
  }

  private completeHandler(source: image.PixelMap | string, epoch: number): (event?: ImageCompleteInfo) => void {
    return (event?: ImageCompleteInfo): void => {
      if (!this.acceptsImageCallback(source, epoch) || event === undefined || event.loadingStatus !== 1 ||
        !Number.isFinite(event.width) || !Number.isFinite(event.height) || event.width <= 0 || event.height <= 0) { return; }
      const width: number = event.width;
      const height: number = event.height;
      // 缓存命中也可能同步回调；离开构建栈，再以 URI/PixelMap 身份和代次确认交接。
      void Promise.resolve().then((): void => {
        if (!this.acceptsImageCallback(source, epoch)) { return; }
        this.getUIContext().runScopedTask((): void => {
          if (!this.acceptsImageCallback(source, epoch)) { return; }
          // 增强图的尺寸不能写进原图口径。
          if (typeof source === 'string') {
            this.sourceWidth = width;
            this.sourceHeight = height;
            this.onImageDecoded(this.index, width, height);
          }
          this.loadState = ImageLoadState.SUCCESS;
          this.clampOffsets();
          this.reportReturnEligibility();
        });
      });
    };
  }

  private errorHandler(source: image.PixelMap | string, epoch: number): () => void {
    return (): void => {
      void Promise.resolve().then((): void => {
        if (!this.acceptsImageCallback(source, epoch)) { return; }
        this.getUIContext().runScopedTask((): void => {
          if (!this.acceptsImageCallback(source, epoch)) { return; }
          this.loadState = ImageLoadState.ERROR;
          this.clampOffsets();
          this.reportReturnEligibility();
        });
      });
    };
  }

  @Builder
  private PreviewImage() {
    Image(this.displaySource())
      .objectFit(ImageFit.Contain)
      // 全屏缩放优先保留边缘细节；列表缩略图继续使用默认插值以控制开销。
      .interpolation(this.zoomScale > MIN_SCALE ? ImageInterpolation.High : ImageInterpolation.Medium)
      .width('100%')
      .height('100%')
      .scale({ x: this.zoomScale, y: this.zoomScale })
      .translate({ x: this.panX, y: this.panY })
      // 同 URI 始终显示唯一图片；异 URI 等开场结束且原图成功后才交接。
      .opacity(this.primaryImageVisible() ? 1 : 0)
      .onComplete(this.completeHandler(this.displaySource(), this.imageLoadEpoch))
      .onError(this.errorHandler(this.displaySource(), this.imageLoadEpoch))
  }

  @Builder
  /** 缩放始终使用同一棵图片子树，跨过1倍时不销毁/重建Image。 */
  private InteractiveImage() {
    Stack() {
      this.PreviewImage()
    }
    .width('100%')
    .height('100%')
  }

  private sharedCropEffect(): TransitionEffect {
    if (this.sharedGeometryId().length === 0) { return TransitionEffect.IDENTITY; }
    if (this.returnId.length > 0) {
      if (!this.returnCropUsable) { return TransitionEffect.IDENTITY; }
      return TransitionEffect.scale({ x: this.returnCropScale, y: this.returnCropScale,
        centerX: this.returnCropCenterX, centerY: this.returnCropCenterY })
        .animation({ duration: imageSharedDuration(), curve: Curve.Friction });
    }
    const crop: ImageTransitionCrop | undefined = this.transitionCrop;
    if (crop === undefined || !crop.usable) { return TransitionEffect.IDENTITY; }
    // 与源图片的属性动画共用倍率、锚点、时长和曲线；不缩放加载提示或操作按钮。
    return TransitionEffect.scale({ x: crop.scale, y: crop.scale, centerX: crop.centerX, centerY: crop.centerY })
      .animation({ duration: imageSharedDuration(), curve: Curve.Friction });
  }

  @Builder
  private PictureContent() {
    if (this.hasSeparateTransitionPreview()) {
      Image(this.transitionPreview).width('100%').height('100%').objectFit(ImageFit.Contain)
        .opacity(this.transitionPreviewVisible() ? 1 : 0)
    }
    this.InteractiveImage()
  }

  @Builder
  private LoadOverlay() {
    if (this.loadState === ImageLoadState.LOADING) {
      Progress({ value: 0, total: 100, type: ProgressType.Ring })
        .width(34)
        .height(34)
        .color(Color.White)
        .transition(imageFadeTransition())
    } else if (this.loadState === ImageLoadState.ERROR) {
      Column({ space: 10 }) {
        Text('图片加载失败')
          .fontSize(15)
          .fontColor(Color.White)
        Text('点击重试')
          .fontSize(14)
          .fontColor(AppTheme.MEDIA_ACCENT)
          .onClick(() => {
            this.retry();
          })
      }
      .padding({ left: 18, right: 18, top: 14, bottom: 14 })
      .borderRadius(10)
      .backgroundColor('#99000000')
      .transition(imageFadeTransition())
    }
  }

  build() {
    Stack() {
      // 全屏负责手势、提示和视口裁切；共享节点只包图片本身。
      Stack() {
        Stack() {
          Stack() {
            // 开场和重绑定返回共用稳定子树，切换 crop 只更新参数，不重新解码图片。
            Stack() { this.PictureContent() }
              .width('100%').height('100%')
              .transition(this.sharedCropEffect())
          }
          .width(this.imageFrameWidth())
          .height(this.imageFrameHeight())
          .geometryTransition(this.sharedGeometryId())
          .renderFit(RenderFit.RESIZE_FILL)
          .clip(this.imageFrameClipped())
          .transition(this.imageContentTransition())
        }
        .width('100%').height('100%')
        // 保留原来的子层 Pan 与父层 Pinch/Tap 仲裁，触摸区不随窄图片缩小。
        .gesture(
          PanGesture({ fingers: 1, distance: 5 })
            .tag('image-zoom-pan')
            .onActionStart(() => {
              if (!this.canUpdatePage()) { return; }
              this.panBaseX = this.panX;
              this.panBaseY = this.panY;
            })
            .onActionUpdate((event: GestureEvent) => {
              if (!this.canUpdatePage() || this.zoomScale <= MIN_SCALE) { return; }
              this.panX = this.panBaseX + event.offsetX;
              this.panY = this.panBaseY + event.offsetY;
              this.clampOffsets();
            })
            .onActionEnd(() => { if (this.canUpdatePage()) { this.clampOffsets(); } })
        )
        .parallelGesture(LongPressGesture({ duration: 450 })
          .onAction((): void => { if (!this.srBlocked()) { this.onLongPressImage(); } }))
        .onGestureJudgeBegin((info: GestureInfo, _event: BaseGestureEvent): GestureJudgeResult => {
          return info.tag === 'image-zoom-pan' && this.zoomScale <= MIN_SCALE
            ? GestureJudgeResult.REJECT : GestureJudgeResult.CONTINUE;
        })
        this.LoadOverlay()
      }
      .width('100%').height('100%')
      .clip(true)
      .onAreaChange((_old: Area, area: Area): void => {
        if (!this.canUpdatePage()) { return; }
        this.containerWidth = Number(area.width);
        this.containerHeight = Number(area.height);
        this.clampOffsets();
      })
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          PinchGesture({ fingers: 2 })
            .onActionStart(() => {
              if (!this.canUpdatePage() || this.holdTransitionPreview) { return; }
              ++this.zoomAnimationEpoch;
              this.zoomAnimating = true;
              this.reportReturnEligibility();
              this.pinchBase = this.zoomScale;
            })
            .onActionUpdate((event: GestureEvent) => {
              if (!this.holdTransitionPreview) { this.setScale(this.pinchBase * event.scale); }
            })
            .onActionEnd(() => {
              if (!this.holdTransitionPreview) { this.settleScale(); }
            }),
          TapGesture({ count: 2 })
            .onAction(() => {
              if (!this.holdTransitionPreview && !this.srBlocked()) { this.toggleDoubleTapZoom(); }
            }),
          TapGesture({ count: 1 })
            .onAction(() => {
              if (!this.srBlocked()) { this.onTapImage(); }
            })
        )
      )
      if (smartReachStore.imageMenuLongPress && superResolutionStore.enabled) {
        this.SuperResolutionButton()
      }
    }
    .width('100%').height('100%')
    .transition(TransitionEffect.IDENTITY)
  }
}

@Component
export struct ImageViewer {
  imageUrl: string = '';
  imageUrls: string[] = [];
  initialIndex: number = 0;
  onBeforeClose: () => void = (): void => {};
  onClose: () => void = (): void => {};
  private imageTransition: ImageTransitionSeed = new ImageTransitionSeed();
  @State private holdTransitionPreview: boolean = false;
  @State private cropReturnEligible: boolean = true;
  @State private transitionAvailable: boolean = false;
  private transitionAlive: boolean = false;
  private stopTransitionListener: () => void = (): void => {};
  private stopTransitionFinishedListener: () => void = (): void => {};
  private stopReturnPreparation: () => void = (): void => {};
  private returnStates: Map<number, () => ImageReturnPageState> = new Map<number, () => ImageReturnPageState>();
  @State private returnTargetId: string = '';
  @State private returnTargetIndex: number = -1;
  @State private returnCropUsable: boolean = false;
  @State private returnCropScale: number = 1;
  @State private returnCropCenterX: string = '50%';
  @State private returnCropCenterY: string = '50%';
  @State private returnContentAspectRatio: number = 0;

  /** 当前选中图片：目标页确定后即同步页码、超分和导出，不等待弹簧尾段。 */
  @State private currentIndex: number = 0;
  /** 仅回写原生已落定的页，避免目标页状态在动画开始时再次驱动 Swiper。 */
  @State private settledIndex: number = 0;
  private swiperController: SwiperController = new SwiperController();
  private swipeDragging: boolean = false;
  /** 底部安全区（系统手势条高度，vp）：页码贴底时用它把文字顶到手势条之上 */
  @State private bottomSafeVp: number = 0;
  @State private menuHidden: boolean = false;
  @State private menuRevealed: boolean = false;
  @State private viewerWidth: number = 0;
  @State private viewerHeight: number = 0;
  /** 导出是否已初始化 */
  @State private exportOpen: boolean = false;
  /** 导出准备状态：0 未开始｜1 下载中｜2 图片数据就绪｜3 失败 */
  @State private exportState: number = 0;
  /** 准备失败原因（原话展示，不吞） */
  @State private exportError: string = '';
  /** 正在执行的动作名（防重复点击，仅用于提示） */
  @State private exportBusy: string = '';
  /** 推动菜单重读当前图片的超分状态。 */
  @State private srTick: number = 0;

  /** 已下载的图片字节（非状态）；只有保存、分享时才创建导出临时文件。 */
  private exportBytes: Uint8Array | null = null;
  /** 操作完成后一小段时间内忽略单击关闭 */
  private suppressCloseUntil: number = 0;
  private exportEpoch: number = 0;
  private emojiManager: SavedEmojiManagerVM = new SavedEmojiManagerVM();

  /** 本次看图会话的超分状态机（打开时建、关闭时 `close()` 释放） */
  private srSession: ImageSuperResolutionSession = new ImageSuperResolutionSession();
  /** 与图片一一对应的状态对象：**按 URL 复用**，翻页回来仍是同一个对象 */
  private srStates: PageSuperResolutionState[] = [];

  aboutToAppear(): void {
    const urls: string[] = this.effectiveImageUrls();
    this.currentIndex = this.clampedIndex(this.initialIndex, urls.length);
    this.settledIndex = this.currentIndex;
    this.imageTransition = takeImageTransition(urls[this.currentIndex] || '');
    this.transitionAlive = true;
    this.cropReturnEligible = true;
    this.transitionAvailable = this.imageTransition.id.length > 0 && !this.imageTransition.hasFinished();
    this.holdTransitionPreview = this.imageTransition.isOpening();
    const seed: ImageTransitionSeed = this.imageTransition;
    this.stopReturnPreparation = bindImageTransitionReturn(seed, (): ImageTransitionSeed | undefined =>
      this.prepareSharedReturn(), (ready: () => void): void => this.settleBeforeReturn(ready));
    this.stopTransitionListener = seed.bindOpeningFinished((): void => {
      if (!this.canUpdateViewer() || seed !== this.imageTransition) { return; }
      this.getUIContext().runScopedTask((): void => {
        if (this.canUpdateViewer() && seed === this.imageTransition) { this.holdTransitionPreview = false; }
      });
    });
    this.stopTransitionFinishedListener = seed.bindFinished((): void => {
      if (!this.canUpdateViewer() || seed !== this.imageTransition) { return; }
      this.getUIContext().runScopedTask((): void => {
        if (this.canUpdateViewer() && seed === this.imageTransition) {
          // 源更换/失效后立即撤销旧配对，退场恢复普通淡化；正常关闭先撤监听。
          this.transitionAvailable = false;
          this.holdTransitionPreview = false;
        }
      });
    });
    this.buildSrStates(urls);
    this.readSafeArea();
    this.hideSystemStatusBar();
    smartReachStore.load(this.hostContext());
    this.openExport();
  }

  aboutToDisappear(): void {
    this.transitionAlive = false;
    this.stopTransitionListener();
    this.stopTransitionFinishedListener();
    this.stopReturnPreparation();
    this.returnStates.clear();
    this.imageTransition.release();
    // 会话结束：使在飞任务失效、清空增强图缓存、在安全时机释放分析器
    this.srSession.close();
    ++this.exportEpoch;
    this.emojiManager.dispose();
    this.restoreSystemStatusBar();
  }

  /** 打开看图时抓住的窗口对象：关闭时用它还原状态栏，不再重新取一次（组件已在销毁中） */
  private viewerWindow: window.Window | null = null;
  /** 打开前状态栏是否可见 —— 还原时按这个值走，不无脑点亮 */
  private statusWasVisible: boolean = true;
  /** 本次是否真的成功隐藏过（没隐藏过就不去"还原"） */
  private statusHiddenByViewer: boolean = false;

  private hideSystemStatusBar(): void {
    try {
      const context = this.getUIContext().getHostContext();
      window.getLastWindow(context).then((win: window.Window) => {
        this.viewerWindow = win;
        const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        this.statusWasVisible = px2vp(area.topRect.height) > 0;
        win.setSpecificSystemBarEnabled('status', false, true).then(() => {
          this.statusHiddenByViewer = true;
        }).catch(() => {
          // 隐藏失败就照旧显示：看图不受影响，不弹错（用户一眼能看出状态栏还在）
        });
      }).catch(() => {
        // 拿不到窗口对象：保持原样
      });
    } catch (err) {
      // 同上：不影响图片加载与手势
    }
  }

  /** 关闭查看器：按打开时的可见性还原状态栏 */
  private restoreSystemStatusBar(): void {
    if (!this.statusHiddenByViewer || this.viewerWindow === null) {
      return;
    }
    this.statusHiddenByViewer = false;
    this.viewerWindow.setSpecificSystemBarEnabled('status', this.statusWasVisible, true)
      .catch(() => {
        // 还原失败不阻断关闭：首页下一次滚动/回到前台会按自己的状态再设一次
      });
  }

  /** 按当前图片列表准备每张图的状态对象，并把"当前是谁"告诉会话（用于切图失效判定） */
  private buildSrStates(urls: string[]): void {
    const states: PageSuperResolutionState[] = [];
    for (let i: number = 0; i < urls.length; i++) {
      states.push(this.srSession.stateFor(urls[i]));
    }
    this.srStates = states;
    if (urls.length > 0) {
      this.srSession.setCurrentKey(urls[this.clampedIndex(this.initialIndex, urls.length)]);
    }
  }

  /** 当前页状态对象（`ForEach` 里取用）。列表在打开期间固定，这里只兜住越界 */
  private srStateAt(index: number, url: string): PageSuperResolutionState {
    if (index >= 0 && index < this.srStates.length) {
      return this.srStates[index];
    }
    return this.srSession.stateFor(url);
  }

  /** 源图失效后仍可翻页；只有查看器离树或开始退场才冻结当前图片状态。 */
  private canUpdateViewer(): boolean {
    return this.transitionAlive && !this.imageTransition.isClosing();
  }

  private setCurrentPage(index: number): void {
    if (!this.canUpdateViewer() || !Number.isInteger(index) || index < 0 ||
      index >= this.effectiveImageUrls().length || index === this.currentIndex) { return; }
    this.currentIndex = index;
    this.imageTransition.setReturnEnabled(index === this.initialIndex && this.cropReturnEligible);
    this.syncSrCurrent(index);
    this.openExport();
  }

  /** 动画结束或被打断时按实际页校准；重复通知不重复预取图片。 */
  private settleCurrentPage(index: number): void {
    if (!this.canUpdateViewer() || !Number.isInteger(index) || index < 0 ||
      index >= this.effectiveImageUrls().length) { return; }
    if (index !== this.currentIndex) { this.detachSharedReturn(); }
    this.swipeDragging = false;
    this.settledIndex = index;
    this.setCurrentPage(index);
  }

  private registerReturnState(index: number, read: () => ImageReturnPageState): () => void {
    this.returnStates.set(index, read);
    return (): void => {
      if (this.returnStates.get(index) === read) { this.returnStates.delete(index); }
    };
  }

  private settleBeforeReturn(ready: () => void): void {
    if (this.swipeDragging) { ready(); return; }
    // 已选定目标页时收完真实翻页动画，再开始回缩；回调可能同步，协调器已先冻结/去重。
    this.swiperController.finishAnimation(ready);
  }

  /** 关闭协调器已冻结页码；在退出动画之前重新配对，不能在动画闭包内临时换 ID。 */
  private prepareSharedReturn(): ImageTransitionSeed | undefined {
    if (!this.transitionAlive) { return undefined; }
    const read: (() => ImageReturnPageState) | undefined = this.returnStates.get(this.currentIndex);
    const state: ImageReturnPageState | undefined = read === undefined ? undefined : read();
    const opening: ImageTransitionSeed = this.imageTransition;
    if (!this.swipeDragging && this.transitionAvailable && this.currentIndex === this.initialIndex && this.cropReturnEligible &&
      !opening.isReturnDetached() && !opening.hasFinished() && state !== undefined && state.atRest) {
      // 未切图沿用原始配对；原图仍在加载时，已显示的开场预览也能正常缩回。
      return opening;
    }
    const prepared: ImageTransitionSeed[] = [];
    try {
      this.getUIContext().runScopedTask((): void => {
        // 先注册源。原生按树深度构建，不保证一次 applySync 内源比 Viewer 先登记。
        UIUtils.applySync((): void => {
          this.transitionAvailable = false;
          this.returnTargetId = '';
          if (this.swipeDragging || state === undefined || !state.atRest || !state.ready ||
            opening.gallery === undefined) { return; }
          const target: ImageTransitionTarget | undefined = opening.gallery.prepare(this.currentIndex, this.currentUrl());
          if (target === undefined) { return; }
          const ratio: number = target.crop?.contentAspectRatio ?? 0;
          if (ratio > 0 && (state.aspectRatio <= 0 ||
            Math.abs(state.aspectRatio - ratio) / Math.max(state.aspectRatio, ratio) > SHARED_ASPECT_TOLERANCE)) {
            target.onReleased?.();
            return;
          }
          const seed: ImageTransitionSeed = target.source.prepareReturn(target);
          if (seed.id.length === 0 || seed.hasFinished()) { seed.cancel(); return; }
          prepared.push(seed);
          seed.expandSource();
        });
        if (prepared.length === 0) { return; }
        const seed: ImageTransitionSeed = prepared[0];
        // 空的零时长事务只提供同步 build/layout 边界，不等待帧、不做可见动画。
        // 先让源成为已登记端，确保后续 follow holder 留在缩略图父节点。
        this.getUIContext().animateTo({ duration: 0 }, (): void => {});
        if (seed.hasFinished()) { prepared.pop(); return; }
        UIUtils.applySync((): void => {
          this.returnTargetIndex = this.currentIndex;
          this.returnCropUsable = seed.crop?.usable ?? false;
          this.returnCropScale = seed.crop?.scale ?? 1;
          this.returnCropCenterX = seed.crop?.centerX ?? '50%';
          this.returnCropCenterY = seed.crop?.centerY ?? '50%';
          this.returnContentAspectRatio = seed.crop?.contentAspectRatio ?? 0;
          this.returnTargetId = seed.id;
        });
      });
    } catch (error) {
      for (const seed of prepared) { seed.cancel(); }
      throw new Error(String(error));
    }
    return prepared.length > 0 ? prepared[0] : undefined;
  }

  /** 浏览期间解除初始配对；关闭时再按当前页注册信息建立自己的返回配对。 */
  private detachSharedReturn(): void {
    if (!this.canUpdateViewer() || !this.transitionAvailable || this.effectiveImageUrls().length < 2) { return; }
    this.getUIContext().runScopedTask((): void => {
      // 源端是 V2 @Local；同步提交解绑，避免快速返回把旧配对带入关闭动画。
      UIUtils.applySync((): void => {
        this.transitionAvailable = false;
        this.imageTransition.detachSharedReturn();
      });
    });
  }

  /** 翻页时同步"当前图"：切走会让在飞任务的**结果作废**（底层仍会跑完） */
  private syncSrCurrent(index: number): void {
    const urls: string[] = this.effectiveImageUrls();
    if (index < 0 || index >= urls.length) {
      return;
    }
    this.srSession.setCurrentKey(urls[index]);
    this.srTick += 1;
  }

  /** 页组件上报解码尺寸：尺寸不合规的图在点击前就灰显并给出原因 */
  private noteDecoded(index: number, width: number, height: number): void {
    const urls: string[] = this.effectiveImageUrls();
    if (index < 0 || index >= urls.length) {
      return;
    }
    this.srSession.noteDecodedSize(urls[index], width, height);
  }

  /** 点击胶囊内超分图标；提示文案由会话决定，这里只负责原话展示 */
  private async toggleSuperResolution(index: number): Promise<void> {
    const urls: string[] = this.effectiveImageUrls();
    if (index < 0 || index >= urls.length) {
      return;
    }
    hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'sr toggle index=%{public}d url=%{public}s',
      index, urls[index].slice(0, 60));
    const pending: Promise<SrToggleResult> = this.srSession.toggle(urls[index]);
    this.srTick += 1;
    const outcome: SrToggleResult = await pending;
    this.srTick += 1;
    if (outcome.message.length > 0) {
      this.toast(outcome.message);
    }
  }

  private effectiveImageUrls(): string[] {
    if (this.imageUrls.length > 0) {
      return this.imageUrls;
    }
    return this.imageUrl.length > 0 ? [this.imageUrl] : [];
  }

  private clampedIndex(index: number, count: number): number {
    if (count <= 0 || index < 0) {
      return 0;
    }
    return index >= count ? count - 1 : index;
  }

  private readSafeArea(): void {
    try {
      const context = this.getUIContext().getHostContext();
      window.getLastWindow(context).then((win: window.Window) => {
        const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        this.bottomSafeVp = px2vp(area.bottomRect.height);
      }).catch(() => {
        // 没有避让区信息时保持 0，页码仍有自身视觉间距。
      });
    } catch (err) {
      // 不影响预览主体。
    }
  }

  /**
   * 页码提示：贴在**底部居中**，只显示 `n / N`，**常显**。
   *
   * 单击画面的语义已从"切换这枚页码的显隐"改为"关闭查看器"（对齐常见看图 App 的手感），
   * 于是不再有隐藏态：`count > 1` 时一直显示。单图（`count <= 1`）没有可翻的页，不显示。
   *
   * 给一层 `#66000000` 圆角药丸底：页码压在照片上，纯白字遇到浅色照片会看不见。
   */
  @Builder
  private PageBadge(count: number) {
    if (count > 1) {
      Row() {
        Text(`${this.currentIndex + 1} / ${count}`)
          .fontSize(14)
          .fontColor(Color.White)
      }
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .borderRadius(12)
      .backgroundColor('#66000000')
      .margin({ bottom: this.bottomSafeVp + 12 })
      .transition(imageFadeTransition())
    }
  }

  // ───────────────────────── 当前图片准备与导出 ─────────────────────────

  /** 当前页地址 */
  private currentUrl(): string {
    const urls: string[] = this.effectiveImageUrls();
    if (urls.length === 0) {
      return this.imageUrl;
    }
    const index: number = this.clampedIndex(this.currentIndex, urls.length);
    return urls[index];
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  /** 打开或切图只预取原图字节，普通浏览不占用导出文件的保留额度。 */
  private openExport(): void {
    hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'openExport index=%{public}d url=%{public}s',
      this.currentIndex, this.currentUrl().slice(0, 60));
    this.suppressCloseUntil = Date.now() + 700;
    this.exportOpen = true;
    this.exportError = '';
    this.exportBytes = null;
    this.exportState = 1;
    this.prepareExport();
  }

  private async prepareExport(notifyFailure: boolean = false): Promise<void> {
    const url: string = this.currentUrl();
    const mine: number = ++this.exportEpoch;
    try {
      const bytes: Uint8Array = await fetchImageBytes(url);
      if (mine !== this.exportEpoch || !this.exportOpen) { return; }
      this.exportBytes = bytes;
      this.exportState = 2;
      hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'prepare ok bytes=%{public}d', bytes.length);
    } catch (err) {
      if (mine !== this.exportEpoch || !this.exportOpen) { return; }
      this.exportState = 3;
      this.exportError = err instanceof Error ? err.message : String(err);
      // 自动预取失败留在菜单中，只有主动重试失败才弹出原因。
      if (notifyFailure) { this.toast(`图片准备失败：${this.exportError}`); }
      hilog.error(EXPORT_DOMAIN, EXPORT_TAG, 'prepare failed: %{public}s', this.exportError);
    }
  }

  private closeExport(): void {
    // 常显模式保留胶囊；长按模式完成操作后收起，下一次长按再显示。
    if (smartReachStore.imageMenuLongPress) { this.menuRevealed = false; }
    this.suppressCloseUntil = Date.now() + 400;
  }

  private toast(message: string): void {
    promptAction.showToast({ message: message, duration: 2000 });
  }

  /** 保存到相册：安全控件授权成功后直接保存到相册 */
  private async saveToGallery(): Promise<void> {
    if (this.exportBusy.length > 0) { return; }
    const bytes: Uint8Array | null = this.exportBytes;
    if (this.exportState !== 2 || bytes === null) {
      hilog.warn(EXPORT_DOMAIN, EXPORT_TAG, 'save skipped state=%{public}d', this.exportState);
      this.toast('图片还没准备好');
      return;
    }
    this.exportBusy = 'save';
    try {
      // 字节已预取；在 SaveButton 授权回调内写文件后立即提交，不等待网络。
      const context: common.UIAbilityContext = this.hostContext();
      const uri: string = writeImageToCache(context, bytes, imageFileName(this.currentUrl(), this.currentIndex));
      await saveImageToGallery(context, uri);
      hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'save ok');
      this.toast('已保存到相册');
      this.closeExport();
    } catch (err) {
      hilog.error(EXPORT_DOMAIN, EXPORT_TAG, 'save failed: %{public}s',
        err instanceof Error ? err.message : String(err));
      this.toast(`保存失败：${err instanceof Error ? err.message : String(err)}`);
    } finally {
      this.exportBusy = '';
    }
  }

  private async shareImage(): Promise<void> {
    if (this.exportBusy.length > 0) { return; }
    const bytes: Uint8Array | null = this.exportBytes;
    if (this.exportState !== 2 || bytes === null) {
      hilog.warn(EXPORT_DOMAIN, EXPORT_TAG, 'share skipped state=%{public}d', this.exportState);
      this.toast('图片还没准备好');
      return;
    }
    this.exportBusy = 'share';
    try {
      const context: common.UIAbilityContext = this.hostContext();
      const uri: string = writeImageToCache(context, bytes, imageFileName(this.currentUrl(), this.currentIndex));
      await shareImageFile(context, uri, '贴吧图片');
      hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'share panel shown');
      this.closeExport();
    } catch (err) {
      hilog.error(EXPORT_DOMAIN, EXPORT_TAG, 'share failed: %{public}s',
        err instanceof Error ? err.message : String(err));
      this.toast(`分享失败：${err instanceof Error ? err.message : String(err)}`);
    } finally {
      this.exportBusy = '';
    }
  }

  private async collectImage(): Promise<void> {
    const bytes: Uint8Array | null = this.exportBytes;
    if (this.exportBusy.length > 0 || bytes === null || this.exportState !== 2) { return; }
    this.exportBusy = 'emoji';
    let source: image.ImageSource | null = null;
    try {
      source = image.createImageSource(bytes.buffer as ArrayBuffer);
      const info: image.ImageInfo = await source.getImageInfo();
      const input: ImageUploadInput = new ImageUploadInput();
      input.bytes = bytes; input.width = info.size.width; input.height = info.size.height;
      input.forCollection = true;
      const added: boolean = await this.emojiManager.addImage(this.hostContext(), input);
      this.toast(added ? '已收藏到表情' : this.emojiManager.error || '未完成收藏，请重试');
      if (added) { this.closeExport(); }
    } catch (err) {
      this.toast('收藏失败，请重试');
    } finally {
      if (source !== null) { source.release(); }
      this.exportBusy = '';
    }
  }

  private menuReady(): boolean { return this.exportState === 2 && this.exportBusy.length === 0; }

  private retryExport(): void {
    if (this.exportState === 3 && this.exportBusy.length === 0) {
      this.exportState = 1;
      this.exportError = '';
      this.toast('正在重新准备图片');
      this.prepareExport(true);
    }
  }

  @Builder
  private MenuIcon(icon: Resource, label: string, kind: number) {
    Stack() {
      if (this.exportBusy === (kind === 0 ? 'save' : kind === 1 ? 'share' : 'emoji')) {
        LoadingProgress().width(20).height(20).color(AppTheme.TEXT_MAIN)
      } else {
        SymbolGlyph(icon).fontSize(20).fontColor([AppTheme.TEXT_MAIN])
      }
    }
    .width(36).height(36).backgroundColor(Color.Transparent)
    .opacity(this.menuReady() ? 1 : 0.45)
    .accessibilityText(label).accessibilityLevel('yes')
    .onClick((): void => {
      if (this.exportState === 3) { this.retryExport(); return; }
      if (!this.menuReady()) { this.toast(this.exportBusy ? '正在处理，请稍候' : '图片准备中'); return; }
      if (kind === 0) {
        this.saveToGallery();
      } else if (kind === 1) {
        this.shareImage();
      } else { this.collectImage(); }
    })
  }

  @Builder
  private SaveToGalleryButton() {
    Row() {
      SaveButton({ icon: SaveIconStyle.FULL_FILLED, text: SaveDescription.SAVE, buttonType: ButtonType.Normal })
        .iconSize(22)
        .fontSize(16)
        .fontColor(Color.White)
        .backgroundColor('#1C1C1E')
        .height(52)
        .padding({ left: 20, right: 20 })
        .textIconSpace(12)
        .enabled(this.menuReady())
        .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
          if (result !== SaveButtonOnClickResult.SUCCESS) {
            hilog.warn(EXPORT_DOMAIN, EXPORT_TAG, 'save not authorized result=%{public}d', result);
            this.toast('未获得保存授权');
            return;
          }
          this.saveToGallery();
        })
    }.width('100%').height(52)
  }

  @Builder
  private ExportRow(icon: Resource, label: string, kind: number) {
    Row({ space: 12 }) {
      SymbolGlyph(icon).fontSize(22).fontColor([this.exportRowColor(kind)])
      Text(label)
        .fontSize(16)
        .fontColor(this.exportRowColor(kind))
        .layoutWeight(1)
    }
    .width('100%')
    .height(52)
    .padding({ left: 20, right: 20 })
    .onClick(() => {
      this.runExportAction(kind);
    })
  }

  /** 分享与表情收藏依赖原图就绪；处理中禁止重复操作。 */
  private exportRowEnabled(kind: number): boolean {
    if (this.exportBusy.length > 0) { return false; }
    if (kind === 1 || kind === 6) {
      return this.exportState === 2;
    }
    return true;
  }

  private exportRowColor(kind: number): ResourceColor {
    return this.exportRowEnabled(kind) ? Color.White : '#66FFFFFF';
  }

  private runExportAction(kind: number): void {
    if (!this.exportRowEnabled(kind)) {
      hilog.warn(EXPORT_DOMAIN, EXPORT_TAG, 'row %{public}d ignored state=%{public}d',
        kind, this.exportState);
      this.toast('图片还没准备好');
      return;
    }
    if (kind === 1) {
      this.shareImage();
    } else if (kind === 6) {
      this.collectImage();

    } else if (kind === 2) {
      this.exportState = 1;
      this.exportError = '';
      this.prepareExport(true);
    } else {
      this.closeExport();
    }
  }

  // 当前图片的超分仅用于查看；保存、分享始终使用已下载原图。

  /** 当前页的状态对象（页码越界返回 null） */
  private currentSrState(): PageSuperResolutionState | null {
    const index: number = this.srTick >= 0 ? this.currentIndex : -1;
    if (index < 0 || index >= this.srStates.length) {
      return null;
    }
    return this.srStates[index];
  }

  @Builder
  private BottomExportSheet() {
    Column() {
      // 遮罩：点它只关菜单，不关查看器
      Column()
        .width('100%')
        .layoutWeight(1)
        .onClick(() => {
          this.closeExport();
        })

      Column({ space: 2 }) {
        Row() {
          Text('图片')
            .fontSize(14)
            .fontColor('#B3FFFFFF')
          Blank()
          if (this.exportState === 1) {
            Row({ space: 6 }) {
              LoadingProgress().width(16).height(16).color(Color.White)
              Text('准备中…').fontSize(13).fontColor('#B3FFFFFF')
            }
          } else if (this.exportState === 3) {
            Text('准备失败')
              .fontSize(13)
              .fontColor('#FF9A9A')
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 12, bottom: 6 })

        if (this.exportState === 3) {
          Text(this.exportError)
            .fontSize(13)
            .fontColor('#FF9A9A')
            .width('100%')
            .padding({ left: 20, right: 20, bottom: 8 })
          this.ExportRow($r('sys.symbol.exclamationmark_circle'), '重试', 2)
        } else {
          this.SaveToGalleryButton()
          this.ExportRow($r('sys.symbol.arrow_up_right'), '分享', 1)
          this.ExportRow($r('sys.symbol.face_smiling'), '收藏到表情', 6)
        }
      }
      .width('100%')
      .backgroundColor('#1C1C1E')
      .borderRadius({ topLeft: 18, topRight: 18 })
      // 底部留白至少 12vp：真机实测 `TYPE_SYSTEM` 避让区在查看器里可能返回 0
      .padding({ bottom: Math.max(this.bottomSafeVp, 12) + 8 })
    }
    .width('100%')
    .height('100%')
    .id('image-bottom-menu')
    .transition(motionTransition(TransitionEffect.translate({ y: 24 }), MotionEffect.MOVE)
      .combine(motionTransition(TransitionEffect.OPACITY, MotionEffect.FADE))
      .animation({ duration: Math.max(motionDuration(180, MotionEffect.MOVE), motionDuration(180, MotionEffect.FADE)),
        curve: Curve.EaseOut }))
  }

  @Builder
  private CapsuleBacking() { Row().width('100%').height('100%') }

  @Builder
  private CapsuleContent() {
    Column({ space: 2 }) {
      SaveButton({ icon: SaveIconStyle.LINES, buttonType: ButtonType.Circle })
        .iconSize(20).iconColor(AppTheme.TEXT_MAIN)
        // 安全控件背景alpha低于0x1a会强制变成不透明，使用系统允许的最低值。
        .backgroundColor('#1A000000').width(36).height(36).padding(8)
        .enabled(this.menuReady())
        .onClick((_event: ClickEvent, result: SaveButtonOnClickResult): void => {
          if (!this.menuReady()) { return; }
          if (result !== SaveButtonOnClickResult.SUCCESS) { this.toast('未获得保存授权'); return; }
          this.saveToGallery();
        })
      this.MenuIcon($r('sys.symbol.arrow_up_right'), '分享图片', 1)
      this.MenuIcon($r('sys.symbol.face_smiling'), '添加到表情收藏', 2)
      if (superResolutionStore.enabled) {
        Stack() {
          if (this.currentSrState()?.status === SrStatus.PROCESSING) {
            LoadingProgress().width(20).height(20).color(AppTheme.TEXT_MAIN)
          } else {
            SymbolGlyph(this.currentSrState()?.status === SrStatus.ON
              ? $r('sys.symbol.wand_and_stars_fill') : $r('sys.symbol.wand_and_stars'))
              .fontSize(20).fontColor([this.currentSrState()?.status === SrStatus.ON ? AppTheme.ACCENT : AppTheme.TEXT_MAIN])
          }
        }.width(36).height(36).backgroundColor(Color.Transparent)
          .opacity(this.currentSrState()?.status === SrStatus.UNAVAILABLE ? 0.45 : 1)
          .accessibilityText(this.currentSrState()?.status === SrStatus.ON ? '关闭图像超分' : '开启图像超分')
          .accessibilityLevel('yes')
          .onClick((): void => {
            if (this.exportBusy.length > 0) { this.toast('正在处理，请稍候'); return; }
            this.toggleSuperResolution(this.currentIndex);
          })
      }
      Stack() {
        SymbolGlyph($r('sys.symbol.eye_slash')).fontSize(20).fontColor([AppTheme.TEXT_MAIN])
      }.width(36).height(36).accessibilityText('本次查看隐藏菜单').accessibilityLevel('yes')
        .onClick((): void => { this.menuHidden = true; this.suppressCloseUntil = Date.now() + 400; })
    }.padding(6).width(48).height(superResolutionStore.enabled ? 200 : 162)
  }

  @Builder
  private ExportSheet() {
    Stack() {
        MaterialTabs({ slot: MaterialSlot.SHEET, barHeight: superResolutionStore.enabled ? 200 : 162, barWidth: 48,
        barContent: (): void => { this.CapsuleBacking(); } })
        .width(48).height(superResolutionStore.enabled ? 200 : 162).hitTestBehavior(HitTestMode.None)
        this.CapsuleContent()
      }
      .width(48).height(superResolutionStore.enabled ? 200 : 162).borderRadius(24).clip(false)

      .id('image-action-capsule')
  }

  build() {
    // `Bottom` 对齐：页码提示贴底。`Swiper` 自身 100%×100%，不受对齐方式影响。
    Stack({ alignContent: Alignment.Bottom }) {
      // 只淡化独立黑底；共享图片不再继承整个 Viewer 的 opacity 动画。
      Stack() {}
        .width('100%').height('100%')
        .backgroundColor(Color.Black)
        .hitTestBehavior(HitTestMode.None)
        .transition(imageFadeTransition())
      if (this.effectiveImageUrls().length > 0) {
        Swiper(this.swiperController) {
          ForEach(this.effectiveImageUrls(), (url: string, index: number) => {
            ZoomableImagePage({
              imageUrl: url,
              transitionId: this.transitionAvailable && index === this.initialIndex &&
                this.currentIndex === this.initialIndex && this.cropReturnEligible
                ? this.imageTransition.id : '',
              transitionPreview: index === this.initialIndex ? this.imageTransition.preview : '',
              returnId: index === this.returnTargetIndex ? this.returnTargetId : '',
              returnCropUsable: this.returnCropUsable,
              returnCropScale: this.returnCropScale,
              returnCropCenterX: this.returnCropCenterX,
              returnCropCenterY: this.returnCropCenterY,
              returnContentAspectRatio: this.returnContentAspectRatio,
              canUpdateSession: (): boolean => this.canUpdateViewer(),
              onRegisterReturnState: (pageIndex: number, read: () => ImageReturnPageState): (() => void) =>
                this.registerReturnState(pageIndex, read),
              transitionCrop: index === this.initialIndex ? this.imageTransition.crop : undefined,
              holdTransitionPreview: index === this.initialIndex && this.holdTransitionPreview,
              onReturnEligibility: (pageIndex: number, eligible: boolean): void => {
                if (!this.canUpdateViewer() || pageIndex !== this.initialIndex || this.imageTransition.crop === undefined) { return; }
                this.cropReturnEligible = eligible;
                this.imageTransition.setReturnEnabled(eligible && this.currentIndex === this.initialIndex);
              },
              index: index,
              sr: this.srStateAt(index, url),
              onSuperResolutionToggle: (index: number): void => {
                if (this.canUpdateViewer() && this.exportBusy.length === 0) { this.toggleSuperResolution(index); }
              },
              onImageDecoded: (decoded: number, width: number, height: number): void => {
                if (this.canUpdateViewer()) { this.noteDecoded(decoded, width, height); }
              },
              onLongPressImage: (): void => {
                if (this.canUpdateViewer() && smartReachStore.imageMenuLongPress && this.exportBusy.length === 0) {
                  this.menuRevealed = true; this.suppressCloseUntil = Date.now() + 700;
                }
              },
              onTapImage: (): void => {
                // 操作完成后的短时间内忽略冒泡单击，避免误关查看器
                if (this.exportBusy.length > 0 || Date.now() < this.suppressCloseUntil) {
                  return;
                }
                if (smartReachStore.imageMenuLongPress && this.menuRevealed) {
                  this.menuRevealed = false; return;
                }
                closeImageTransition(this.getUIContext(), (): void => { this.onClose(); },
                  (): void => { this.onBeforeClose(); });
              }
            })
          },
          // key **不能带 `this.currentIndex`**：带上的话每翻一页所有 key 都变，
          // `Swiper` 会把整批页面销毁重建、`Image` 重新加载 —— 视觉上就是翻页"闪一下"。
          // 实测：key 含 currentIndex 时打开查看器 mount 3 次、翻一页 mount 8 次；
          // 去掉后翻页只 mount 1 次，且那次是预建屏幕外的下一页。
          (url: string, index: number) => `${index}:${url}`)
        }
        .index(this.settledIndex)
        .indicator(false)
        .disableSwipe(this.exportBusy.length > 0 || this.holdTransitionPreview)
        .loop(false)
        .duration(motionDuration(400)).curve(motionSwiperCurve())
        .onGestureSwipe((_index: number, _event: SwiperAnimationEvent): void => {
          if (!this.canUpdateViewer()) { return; }
          this.swipeDragging = true;
          this.detachSharedReturn();
        })
        .onAnimationStart((index: number, targetIndex: number, _event: SwiperAnimationEvent): void => {
          if (!this.canUpdateViewer() || !Number.isInteger(targetIndex) || targetIndex < 0 ||
            targetIndex >= this.effectiveImageUrls().length) { return; }
          this.swipeDragging = false;
          if (index !== targetIndex) { this.detachSharedReturn(); }
          this.setCurrentPage(targetIndex);
        })
        .onAnimationEnd((index: number, _event: SwiperAnimationEvent): void => {
          this.settleCurrentPage(index);
        })
        .onChange((index: number) => {
          // 无动画切页也走同一入口；关闭时的迟到回调不再改退场画面。
          this.settleCurrentPage(index);
        })
        .width('100%')
        .height('100%')
        .transition(TransitionEffect.IDENTITY)
      }
      if (!smartReachStore.imageMenuLongPress || !this.menuRevealed) {
        this.PageBadge(this.effectiveImageUrls().length)
      }
      // 常显小胶囊只接住自身触摸；图片仍可缩放、翻页和单击关闭。
      if (this.exportOpen && !this.menuHidden && !smartReachStore.imageMenuLongPress) {
        ImageMenuPosition({ viewportWidth: this.viewerWidth, viewportHeight: this.viewerHeight,
          capsuleHeight: superResolutionStore.enabled ? 200 : 162, bottomInset: this.bottomSafeVp,
          busy: this.exportBusy.length > 0, content: (): void => { this.ExportSheet() } })
          .transition(imageFadeTransition())
      }
      if (smartReachStore.imageMenuLongPress && this.menuRevealed) {
        this.BottomExportSheet()
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_old: Area, area: Area): void => {
      if (!this.canUpdateViewer()) { return; }
      this.viewerWidth = Number(area.width); this.viewerHeight = Number(area.height);
    })
    // 留住整棵退场子树直到共享几何与黑底淡化结束，避免只剩下列表内的源图在缩回。
    .transition(imageLayerRetentionTransition())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onKeyEvent((event: KeyEvent): boolean => {
      // 保留但**不生效**：这个 `Stack` 不持有焦点，收不到按键。真正拦返回键的是
      // 宿主 Index / ThreadDetailPage 的 onBackPress（查看器是页面上的浮层）。
      if (event.keyCode === KeyCode.KEYCODE_BACK) {
        closeImageTransition(this.getUIContext(), (): void => { this.onClose(); },
          (): void => { this.onBeforeClose(); });
        return true;
      }
      return false;
    })
  }
}
