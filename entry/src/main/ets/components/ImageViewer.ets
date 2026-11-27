import { MotionEffect } from '../common/appearance/MotionConfig';
import { motionStore } from '../common/appearance/MotionStore';
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
import { DismissDragFrame, evaluateDismissDrag, shouldDismissDrag } from '../model/ImageDismissGesture';
import {
  FlingMotionState, LongMinimapLayout, VIEWER_MAX_FLING_VELOCITY, VIEWER_MIN_FLING_VELOCITY,
  VIEWER_MIN_SCALE, ViewerTransform, applyEdgeResistance, computeLongMinimap, minimapScrubPanY,
  stepFlingMotion, viewerDoubleTapScale, viewerMaxScale, viewerOffsetLimit, zoomAroundPoint
} from '../model/ImageViewerMotion';
/** 全屏图片查看器，支持缩放、滑动切换、导出与当前图片超分。 */

import { AnimatorResult, display, promptAction, UIUtils, window } from '@kit.ArkUI';
import { AppTheme } from '../theme/Theme';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { KeyCode } from '@ohos.multimodalInput.keyCode';
import {
  imageFileName,
  saveImageToGallery,
  shareImageFile,
  writeImageToCache
} from '../utils/ImageExport';
import { fetchImageBytes } from '../net/ImageDownload';
import { superResolutionStore } from '../common/appearance/SuperResolutionStore';
import { longImageMinimapStore } from '../common/appearance/LongImageMinimapStore';
import { imageLoadStore } from '../common/appearance/ImageLoadStore';
import {
  ImageLoadPolicy, ViewerImage, formatOriginBytes, viewerCanLoadOrigin, viewerSource
} from '../model/ImageLoadPolicy';
import {
  SrStatus, SR_BUTTON_BASE, SR_BUTTON_ICON, SR_BUTTON_INSET, SR_BUTTON_MARGIN, SR_BUTTON_TOUCH,
  SrButtonBox, srButtonPosition
} from '../model/ImageSuperResolution';
import {
  ImageSuperResolutionSession,
  PageSuperResolutionState,
  SrToggleResult
} from '../viewmodel/ImageSuperResolutionVM';

const MIN_SCALE: number = VIEWER_MIN_SCALE;
const ANIMATION_DURATION: number = 180;
const DOUBLE_TAP_DURATION: number = 220;
const MINIMAP_HIDE_DELAY_MS: number = 1500;
const MINIMAP_HIT_PAD: number = 8;
/** 解码尺寸可能有取整误差；明显不同的预览/原图比例不能错误共享返回。 */
const SHARED_ASPECT_TOLERANCE: number = 0.01;
/** 导出菜单日志域；只记状态与地址前 60 字符，不含凭据 */
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
 * 每页的缩放 / 位移状态就放在页内（`@State`），不再由父组件持有 `@Observed` 数组 + `@ObjectLink`：
 * 放大后 `PanGesture` 会独占横向手势，`swipe` 与 `fling` 都推不动 `Swiper`，即放大状态下根本切不了页，
 * "翻页时复位别的页"永远不会发生。新页在 `aboutToAppear` 里自然回到 1x，够用且少一层状态。
 */

@Component
struct ZoomableImagePage {
  @Prop @Watch('onImageUrlChanged') imageUrl: string = '';
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
  @Prop explicitLong: boolean = false;
  @Prop bottomSafeVp: number = 0;
  onMinimapActiveChange: (index: number, active: boolean) => void = (_index: number, _active: boolean): void => {};
  onMultiTouchChange: (active: boolean) => void = (_active: boolean): void => {};
  @Prop dismissBlocked: boolean = false;
  onDismissDragChange: (active: boolean, backdropOpacity: number, chromeOpacity: number) => void =
    (_active: boolean, _backdropOpacity: number, _chromeOpacity: number): void => {};
  onDismissCommit: (resetForShared: () => void) => void = (_resetForShared: () => void): void => {};

  @State private zoomScale: number = MIN_SCALE;
  @State private panX: number = 0;
  @State private panY: number = 0;
  @State private dismissDragActive: boolean = false;
  @State private dismissDragX: number = 0;
  @State private dismissDragY: number = 0;
  @State private dismissDragScale: number = 1;
  @State private dismissChromeOpacity: number = 1;
  private dismissAnimationEpoch: number = 0;
  /** 本次单指拖动的归属：0 未激活｜1 放大平移或长图滚动｜2 上下拖动返回 */
  private activePanMode: number = 0;
  @State private containerWidth: number = 0;
  @State private containerHeight: number = 0;
  @State private sourceWidth: number = 0;
  @State private sourceHeight: number = 0;
  @State private loadState: ImageLoadState = ImageLoadState.LOADING;
  @State private retryCount: number = 0;
  /** 切原图期间暂留已加载的大图，原图就绪后再切换，避免闪黑。 */
  @State private upgradePreview: string = '';
  private loadedImageUrl: string = '';

  @State private topSafeVp: number = 0;
  private srTouchActive: boolean = false;
  private srGuardUntil: number = 0;
  onSuperResolutionToggle: (index: number) => void = (): void => {};
  index: number = 0;
  /** 解码成功时把**真实像素尺寸**报给查看器：尺寸不合规的图在点击前就能灰显 */
  onImageDecoded: (index: number, width: number, height: number) => void = (): void => {};
  /**
   * 这一页的超分状态。必须 `@ObjectLink`：处理完成 / 被淘汰 / 失败由会话发起，
   * 只有它能推进到本页界面而不必改 `ForEach` 的 key（改 key 会重建页面、图片重新加载）。
   */
  @ObjectLink sr: PageSuperResolutionState;


  private pinchBase: number = MIN_SCALE;
  private pinchBasePanX: number = 0;
  private pinchBasePanY: number = 0;
  private pinchStartCenterX: number = 0;
  private pinchStartCenterY: number = 0;
  private pinchActive: boolean = false;
  private pinchCooldownUntil: number = 0;
  private activeTouchCount: number = 0;
  private multiTouchReported: boolean = false;
  @State private zoomAnimating: boolean = false;
  private zoomAnimationEpoch: number = 0;
  private pageActive: boolean = false;
  private imageLoadEpoch: number = 0;
  private panBaseX: number = 0;
  private panBaseY: number = 0;
  private lastPanOffsetX: number = 0;
  private lastPanOffsetY: number = 0;
  private lastPanTimeMs: number = 0;
  private trackedVelocityX: number = 0;
  private trackedVelocityY: number = 0;
  private flingAnimator: AnimatorResult | undefined = undefined;
  private flingState: FlingMotionState = new FlingMotionState();
  private flingLastMs: number = 0;
  /** 惯性滑行中落指急停；消费当次单指点按，避免误关查看器。 */
  private stoppedFlingOnDown: boolean = false;
  @State private minimapVisible: boolean = false;
  @State private minimapOpacity: number = 0;
  private minimapHideTimer: number = -1;
  private minimapFadeEpoch: number = 0;
  private minimapScrubbing: boolean = false;
  private minimapGuardUntil: number = 0;
  private minimapReportedActive: boolean = false;
  /** 用户拖过图片后，加载完成不再自动把长图拉回顶部。 */
  private panTouched: boolean = false;

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
    this.stopFlingMotion();
    this.hideMinimapImmediate();
    this.pinchActive = false;
    this.activeTouchCount = 0;
    this.syncMultiTouchState();
    this.stopReturnState();
    ++this.imageLoadEpoch;
    ++this.zoomAnimationEpoch;
    ++this.dismissAnimationEpoch;
  }

  private canUpdatePage(): boolean {
    return this.pageActive && this.canUpdateSession();
  }

  private readReturnState(): ImageReturnPageState {
    const state: ImageReturnPageState = new ImageReturnPageState();
    state.atRest = this.pageActive && this.isAtRest();
    state.ready = this.loadState === ImageLoadState.SUCCESS && this.primaryImageVisible();
    const width: number = this.displayedSourceWidth();
    const height: number = this.displayedSourceHeight();
    const ratio: number = width / height;
    state.aspectRatio = Number.isFinite(width) && Number.isFinite(height) && width > 0 && height > 0 &&
      Number.isFinite(ratio) && ratio > 0 ? ratio : 0;
    return state;
  }

  private onImageUrlChanged(): void {
    if (!this.canUpdatePage()) { return; }
    if (this.loadState === ImageLoadState.SUCCESS && this.loadedImageUrl.length > 0 &&
      this.loadedImageUrl !== this.imageUrl) {
      this.upgradePreview = this.loadedImageUrl;
    }
    ++this.imageLoadEpoch;
    this.retryCount = 0;
    this.loadState = ImageLoadState.LOADING;
  }

  private resetImageState(): void {
    this.stopFlingMotion();
    this.hideMinimapImmediate();
    this.pinchActive = false;
    this.pinchCooldownUntil = 0;
    this.activeTouchCount = 0;
    this.syncMultiTouchState();
    this.stoppedFlingOnDown = false;
    this.zoomScale = MIN_SCALE;
    this.panX = 0;
    this.panY = 0;
    this.resetDismissDragImmediate();
    this.panTouched = false;
    this.loadState = ImageLoadState.LOADING;
    this.retryCount = 0;
    this.upgradePreview = '';
    this.loadedImageUrl = '';
    this.sourceWidth = 0;
    this.sourceHeight = 0;
  }

  private readWindowSize(): void {
    // 共享目标首帧就有可用宽高；真实窗口和全屏外层 onAreaChange 随后校正。
    try {
      const screen: display.Display = display.getDefaultDisplaySync();
      if (screen.width > 0 && screen.height > 0) {
        const ui = this.getUIContext();
        this.containerWidth = ui.px2vp(screen.width);
        this.containerHeight = ui.px2vp(screen.height);
      }
    } catch (_) { /* 无同步显示信息时仍可由窗口/布局回调提供尺寸。 */ }
    const epoch: number = this.imageLoadEpoch;
    try {
      const ui = this.getUIContext();
      const context = ui.getHostContext();
      window.getLastWindow(context).then((win: window.Window) => {
        if (!this.canUpdatePage() || epoch !== this.imageLoadEpoch) { return; }
        const rect = win.getWindowProperties().windowRect;
        this.containerWidth = rect.width > 0 ? ui.px2vp(rect.width) : this.containerWidth;
        this.containerHeight = rect.height > 0 ? ui.px2vp(rect.height) : this.containerHeight;
        this.topSafeVp = ui.px2vp(win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height);
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

  private previewBackdrop(): string {
    return this.upgradePreview.length > 0 ? this.upgradePreview : this.transitionPreview;
  }

  /** 同一 URI 只使用主 Image；异源预览节点保留到本页销毁，用透明度交接。 */
  private hasSeparateTransitionPreview(): boolean {
    const backdrop: string = this.previewBackdrop();
    return backdrop.length > 0 &&
      (backdrop !== this.sourceForLoad() || this.showingEnhanced());
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
      // 整张图缩进屏幕：长图打开时先给全貌（上下留白），共享元素从正文裁切窗口"收"成整图；
      // 要读文字再双击放大，放大后才有纵向拖动。
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
    // 共享转场结束后才把长图挪到顶部，避免动画中途被平移打断。
    if (!this.holdTransitionPreview) { this.applyInitialPan(); }
    this.clampOffsets();
    this.reportReturnEligibility();
  }

  /** 手势护栏：刚碰过超分按钮或右侧定位条的一小段时间内，不认"单击关闭 / 双击放大 / 长按导出" */
  private srBlocked(): boolean {
    return this.srTouchActive || Date.now() < this.srGuardUntil || this.minimapBlocked();
  }

  private minimapBlocked(): boolean {
    return this.minimapScrubbing || Date.now() < this.minimapGuardUntil;
  }

  private pinchBlocked(): boolean {
    return this.pinchActive || this.activeTouchCount >= 2 || Date.now() < this.pinchCooldownUntil;
  }

  private syncMultiTouchState(): void {
    const active: boolean = this.pinchActive || this.activeTouchCount >= 2;
    if (this.multiTouchReported === active) { return; }
    this.multiTouchReported = active;
    this.onMultiTouchChange(active);
  }

  private updateActiveTouchCount(event: TouchEvent): void {
    let count: number = 0;
    if (event.touches !== undefined) {
      for (let i: number = 0; i < event.touches.length; i++) {
        const touch: TouchObject = event.touches[i];
        if (touch.type !== TouchType.Up && touch.type !== TouchType.Cancel) {
          count++;
        }
      }
    }
    this.activeTouchCount = count;
    if (count >= 2) {
      this.stopFlingMotion();
      this.stoppedFlingOnDown = false;
      // 第二根手指落屏瞬间立即取消由第一指误触发的下拉返回，把控制权干净交给双指缩放。
      if (this.activePanMode === 2 || this.dismissDragActive) {
        this.resetDismissDragImmediate();
        this.onDismissDragChange(false, 1, 1);
      } else if (this.activePanMode === 1) {
        this.activePanMode = 0;
      }
    }
    this.syncMultiTouchState();
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
   * 按钮落点：以图片实际显示区域的右上角为锚、内缩 12vp，再夹进可操作区域。边界（小图/长图/满屏/放大拖动出屏）
   * 由纯逻辑 `srButtonPosition()` 与 Node 侧用例钉住，这里只喂当前页的实时数值。
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
    .opacity(this.dismissChromeOpacity * (1 - this.minimapOpacity))
    .hitTestBehavior(this.minimapVisible ? HitTestMode.None : HitTestMode.Default)
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
    const ui = this.getUIContext();
    const imageWidth: number = ui.px2vp(widthPx);
    const imageHeight: number = ui.px2vp(heightPx);
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

  private effectiveMaxScale(): number {
    const size: ImageSize = this.sourceImageSize();
    return viewerMaxScale(this.containerWidth, size.width);
  }

  private offsetLimitXFor(scale: number): number {
    const size: ImageSize = this.sourceImageSize();
    return viewerOffsetLimit(this.containerWidth, size.width, scale);
  }

  private offsetLimitYFor(scale: number): number {
    const size: ImageSize = this.sourceImageSize();
    return viewerOffsetLimit(this.containerHeight, size.height, scale);
  }

  private offsetLimitX(): number {
    return this.offsetLimitXFor(this.zoomScale);
  }

  private offsetLimitY(): number {
    return this.offsetLimitYFor(this.zoomScale);
  }

  private clampOffsets(): void {
    const limitX: number = this.offsetLimitX();
    const limitY: number = this.offsetLimitY();
    this.panX = Math.max(-limitX, Math.min(limitX, this.panX));
    this.panY = Math.max(-limitY, Math.min(limitY, this.panY));
  }

  /** 仅依赖容器/原图/缩放的静态定位条外框（不读 `panY`，避免滑动时触发 `Image` 重求值）。 */
  private currentMinimapFrame(): LongMinimapLayout {
    if (!longImageMinimapStore.enabled) { return new LongMinimapLayout(); }
    const size: ImageSize = this.sourceImageSize();
    return computeLongMinimap(
      this.containerWidth, this.containerHeight,
      size.width, size.height,
      this.displayedSourceWidth(), this.displayedSourceHeight(),
      this.explicitLong, this.zoomScale, 0,
      this.topSafeVp, this.bottomSafeVp
    );
  }

  private currentMinimapLayout(): LongMinimapLayout {
    if (!longImageMinimapStore.enabled) { return new LongMinimapLayout(); }
    const size: ImageSize = this.sourceImageSize();
    return computeLongMinimap(
      this.containerWidth, this.containerHeight,
      size.width, size.height,
      this.displayedSourceWidth(), this.displayedSourceHeight(),
      this.explicitLong, this.zoomScale, this.panY,
      this.topSafeVp, this.bottomSafeVp
    );
  }

  private setMinimapReportedActive(active: boolean): void {
    if (this.minimapReportedActive === active) { return; }
    this.minimapReportedActive = active;
    this.onMinimapActiveChange(this.index, active);
  }

  private clearMinimapHideTimer(): void {
    if (this.minimapHideTimer >= 0) {
      clearTimeout(this.minimapHideTimer);
      this.minimapHideTimer = -1;
    }
  }

  private hideMinimapImmediate(): void {
    this.clearMinimapHideTimer();
    ++this.minimapFadeEpoch;
    this.minimapScrubbing = false;
    this.minimapOpacity = 0;
    this.minimapVisible = false;
    this.setMinimapReportedActive(false);
  }

  private showMinimap(scheduleHide: boolean): void {
    if (!this.canUpdatePage()) { return; }
    const layout: LongMinimapLayout = this.currentMinimapLayout();
    if (!layout.visible) {
      this.hideMinimapImmediate();
      return;
    }
    this.clearMinimapHideTimer();
    ++this.minimapFadeEpoch;
    this.setMinimapReportedActive(true);
    if (!this.minimapVisible || this.minimapOpacity < 0.99) {
      this.minimapVisible = true;
      const duration: number = motionDuration(150, MotionEffect.FADE);
      if (duration === 0) {
        this.minimapOpacity = 1;
      } else {
        this.getUIContext().animateTo({ duration: duration, curve: Curve.EaseOut }, (): void => {
          this.minimapOpacity = 1;
        });
      }
    }
    if (scheduleHide) {
      this.scheduleMinimapHide();
    }
  }

  private scheduleMinimapHide(): void {
    this.clearMinimapHideTimer();
    if (!this.minimapVisible || this.minimapScrubbing) { return; }
    const epoch: number = ++this.minimapFadeEpoch;
    this.minimapHideTimer = setTimeout((): void => {
      this.minimapHideTimer = -1;
      if (!this.canUpdatePage() || epoch !== this.minimapFadeEpoch || this.minimapScrubbing) { return; }
      this.getUIContext().runScopedTask((): void => {
        if (!this.canUpdatePage() || epoch !== this.minimapFadeEpoch || this.minimapScrubbing) { return; }
        this.setMinimapReportedActive(false);
        const duration: number = motionDuration(240, MotionEffect.FADE);
        if (duration === 0) {
          this.minimapOpacity = 0;
          this.minimapVisible = false;
          return;
        }
        this.getUIContext().animateTo({
          duration: duration,
          curve: Curve.EaseOut,
          onFinish: (): void => {
            if (!this.canUpdatePage() || epoch !== this.minimapFadeEpoch) { return; }
            this.minimapVisible = false;
          }
        }, (): void => {
          this.minimapOpacity = 0;
        });
      });
    }, MINIMAP_HIDE_DELAY_MS);
  }

  private stopFlingMotion(): void {
    if (this.flingAnimator !== undefined) {
      this.flingAnimator.cancel();
      this.flingAnimator = undefined;
    }
  }

  private startFlingMotion(vx: number, vy: number): void {
    this.stopFlingMotion();
    if (!this.canUpdatePage() || !this.panAllowed()) { return; }
    const limitX: number = this.offsetLimitX();
    const limitY: number = this.offsetLimitY();
    const overscrolled: boolean = Math.abs(this.panX) > limitX + 0.5 || Math.abs(this.panY) > limitY + 0.5;
    const moveOn: boolean = motionStore.isOn(MotionEffect.MOVE);
    const springOn: boolean = motionStore.isOn(MotionEffect.SPRING);
    const axisVx: number = moveOn && limitX > 0.5
      ? Math.max(-VIEWER_MAX_FLING_VELOCITY, Math.min(VIEWER_MAX_FLING_VELOCITY, vx)) : 0;
    const axisVy: number = moveOn && limitY > 0.5
      ? Math.max(-VIEWER_MAX_FLING_VELOCITY, Math.min(VIEWER_MAX_FLING_VELOCITY, vy)) : 0;
    const speed: number = Math.hypot(axisVx, axisVy);
    if (!overscrolled && speed < VIEWER_MIN_FLING_VELOCITY) {
      this.clampOffsets();
      this.scheduleMinimapHide();
      return;
    }
    if (!moveOn && !springOn) {
      this.clampOffsets();
      this.scheduleMinimapHide();
      return;
    }
    const state: FlingMotionState = new FlingMotionState();
    state.panX = this.panX;
    state.panY = this.panY;
    state.velocityX = axisVx;
    state.velocityY = axisVy;
    state.settled = false;
    this.flingState = state;
    this.flingLastMs = Date.now();
    this.showMinimap(false);
    const animator: AnimatorResult = this.getUIContext().createAnimator({
      duration: 10000,
      easing: 'linear',
      delay: 0,
      fill: 'none',
      direction: 'normal',
      iterations: -1,
      begin: 0,
      end: 1
    });
    this.flingAnimator = animator;
    animator.onFrame = (_progress: number): void => {
      if (!this.canUpdatePage() || this.flingAnimator !== animator) { return; }
      const now: number = Date.now();
      const dtSec: number = Math.max(0.001, Math.min(0.05, (now - this.flingLastMs) / 1000));
      this.flingLastMs = now;
      const next: FlingMotionState = stepFlingMotion(
        this.flingState, dtSec, this.offsetLimitX(), this.offsetLimitY(), springOn);
      this.flingState = next;
      this.panX = next.panX;
      this.panY = next.panY;
      if (next.settled) {
        this.stopFlingMotion();
        this.clampOffsets();
        this.scheduleMinimapHide();
      }
    };
    animator.play();
  }

  private resolveReleaseVelocity(eventVelocity: number, trackedVelocity: number, nowMs: number): number {
    // 抬手前手指短暂停顿超过 80ms 时，忽略滞后的采样速度避免误触发滑行。
    if (this.lastPanTimeMs > 0 && nowMs - this.lastPanTimeMs > 80) { return 0; }
    if (Number.isFinite(eventVelocity) && Math.abs(eventVelocity) >= VIEWER_MIN_FLING_VELOCITY) {
      return eventVelocity;
    }
    return Number.isFinite(trackedVelocity) ? trackedVelocity : 0;
  }

  private minimapDecodeSize(): ImageSourceSize | undefined {
    const frame: LongMinimapLayout = this.currentMinimapFrame();
    if (!frame.visible || frame.stripWidth <= 0 || frame.stripHeight <= 0) { return undefined; }
    return {
      width: Math.max(16, Math.round(frame.stripWidth * 1.5)),
      height: Math.max(32, Math.round(frame.stripHeight * 1.5))
    };
  }

  @Builder
  private LongMinimapOverlay() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Image(this.displaySource())
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
          .autoResize(true)
          .sourceSize(this.minimapDecodeSize())
          .hitTestBehavior(HitTestMode.None)
        Row()
          .width('100%')
          .height(this.currentMinimapLayout().topMaskHeight)
          .backgroundColor('#A6000000')
          .hitTestBehavior(HitTestMode.None)
        Row()
          .width('100%')
          .height(this.currentMinimapLayout().bottomMaskHeight)
          .position({ x: 0, y: this.currentMinimapLayout().bottomMaskTop })
          .backgroundColor('#A6000000')
          .hitTestBehavior(HitTestMode.None)
        Row()
          .width('100%')
          .height(this.currentMinimapLayout().windowHeight)
          .position({ x: 0, y: this.currentMinimapLayout().windowTop })
          .border({ width: 1.5, color: Color.White })
          .borderRadius(1)
          .hitTestBehavior(HitTestMode.None)
      }
      .width(this.currentMinimapFrame().stripWidth)
      .height(this.currentMinimapFrame().stripHeight)
      .position({ x: MINIMAP_HIT_PAD, y: MINIMAP_HIT_PAD })
      .backgroundColor('#CC000000')
      .border({ width: 0.5, color: '#33FFFFFF' })
      .borderRadius(3)
      .clip(true)
    }
    .width(this.currentMinimapFrame().stripWidth + MINIMAP_HIT_PAD * 2)
    .height(this.currentMinimapFrame().stripHeight + MINIMAP_HIT_PAD * 2)
    .position({
      x: this.currentMinimapFrame().stripX - MINIMAP_HIT_PAD,
      y: this.currentMinimapFrame().stripY - MINIMAP_HIT_PAD
    })
    .opacity(this.minimapOpacity * this.dismissChromeOpacity)
    .hitTestBehavior(this.minimapVisible ? HitTestMode.Block : HitTestMode.None)
    .onTouch((event: TouchEvent): void => {
      if (!this.minimapVisible || !this.canUpdatePage()) { return; }
      event.stopPropagation();
      this.minimapGuardUntil = Date.now() + 450;
      const hasTouch: boolean = event.touches !== undefined && event.touches.length > 0;
      const touchY: number = hasTouch ? event.touches[0].y - MINIMAP_HIT_PAD : 0;
      if (event.type === TouchType.Down) {
        this.stopFlingMotion();
        this.stoppedFlingOnDown = false;
        this.minimapScrubbing = true;
        this.panTouched = true;
        this.showMinimap(false);
        if (hasTouch) {
          const cur: LongMinimapLayout = this.currentMinimapLayout();
          if (cur.visible) {
            this.panY = minimapScrubPanY(touchY, cur.stripHeight, cur.windowHeight, this.offsetLimitY());
          }
        }
      } else if (event.type === TouchType.Move) {
        if (this.minimapScrubbing && hasTouch) {
          const cur: LongMinimapLayout = this.currentMinimapLayout();
          if (cur.visible) {
            this.panY = minimapScrubPanY(touchY, cur.stripHeight, cur.windowHeight, this.offsetLimitY());
          }
        }
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.minimapScrubbing = false;
        this.scheduleMinimapHide();
      }
    })
  }

  /** 图片比容器高：宽度拟合后纵向溢出，需要靠拖动阅读。 */
  private verticalOverflow(): boolean {
    return this.offsetLimitY() > 0.5;
  }

  /** 允许单指拖动：已放大，或者长图在 1× 下本来就比屏幕高。 */
  private panAllowed(): boolean {
    return this.zoomScale > MIN_SCALE || this.verticalOverflow();
  }

  /** 允许上下拖动返回：1× 非溢出且无其他阻塞手势或菜单。 */
  private dismissDragAllowed(): boolean {
    return this.canUpdatePage() && !this.holdTransitionPreview && !this.zoomAnimating &&
      !this.dismissBlocked && !this.srBlocked() && !this.pinchBlocked() &&
      this.zoomScale === MIN_SCALE && !this.verticalOverflow();
  }

  private resetDismissDragImmediate(): void {
    ++this.dismissAnimationEpoch;
    this.activePanMode = 0;
    this.dismissDragActive = false;
    this.dismissDragX = 0;
    this.dismissDragY = 0;
    this.dismissDragScale = 1;
    this.dismissChromeOpacity = 1;
  }

  private reboundDismissDrag(): void {
    if (!this.canUpdatePage()) { return; }
    const epoch: number = ++this.dismissAnimationEpoch;
    const duration: number = Math.max(
      motionDuration(ANIMATION_DURATION, MotionEffect.MOVE),
      motionDuration(ANIMATION_DURATION, MotionEffect.SCALE)
    );
    this.onDismissDragChange(false, 1, 1);
    if (duration === 0) {
      this.dismissDragActive = false;
      this.dismissDragX = 0;
      this.dismissDragY = 0;
      this.dismissDragScale = 1;
      this.dismissChromeOpacity = 1;
      return;
    }
    this.getUIContext().animateTo({
      duration: duration,
      curve: Curve.EaseOut,
      onFinish: (): void => {
        if (!this.canUpdatePage() || epoch !== this.dismissAnimationEpoch) { return; }
        this.dismissDragActive = false;
      }
    }, (): void => {
      this.dismissDragX = 0;
      this.dismissDragY = 0;
      this.dismissDragScale = 1;
      this.dismissChromeOpacity = 1;
    });
  }

  /** 1× 下的静息位置：长图停在顶部（图片顶对齐屏幕顶），普通图居中。 */
  private restPanY(): number {
    return this.zoomScale === MIN_SCALE && this.verticalOverflow() ? -this.offsetLimitY() : 0;
  }

  private isAtRest(): boolean {
    return !this.zoomAnimating && this.zoomScale === MIN_SCALE && this.contentAspectMatchesSource() &&
      Math.abs(this.panX) <= 1 && Math.abs(this.panY - this.restPanY()) <= 1;
  }

  /** 图片加载完、容器尺寸确定后把长图从中间拉到顶部；用户拖过就不再自动回位。 */
  private applyInitialPan(): void {
    if (this.holdTransitionPreview || this.panTouched || this.zoomScale > MIN_SCALE) { return; }
    this.panX = 0;
    this.panY = this.restPanY();
  }

  private setScale(value: number): void {
    if (!this.canUpdatePage()) { return; }
    const next: number = Math.max(MIN_SCALE, Math.min(this.effectiveMaxScale(), value));
    this.zoomScale = next;
    if (next === MIN_SCALE) {
      this.panX = 0;
      this.panY = this.restPanY();
      this.hideMinimapImmediate();
    } else {
      this.clampOffsets();
    }
    this.reportReturnEligibility();
  }

  private reportReturnEligibility(): void {
    if (this.canUpdatePage()) {
      this.onReturnEligibility(this.index, this.isAtRest());
    }
  }

  private animateZoom(action: () => void, durationMs: number = ANIMATION_DURATION): void {
    if (!this.canUpdatePage()) { return; }
    const epoch: number = ++this.zoomAnimationEpoch;
    this.zoomAnimating = true;
    this.reportReturnEligibility();
    const duration: number = motionDuration(durationMs, MotionEffect.SCALE);
    if (duration === 0) {
      action();
      this.zoomAnimating = false;
      this.reportReturnEligibility();
      return;
    }
    this.getUIContext().animateTo({ duration: duration, curve: Curve.EaseOut,
      onFinish: (): void => {
        if (!this.canUpdatePage() || epoch !== this.zoomAnimationEpoch) { return; }
        this.zoomAnimating = false;
        this.reportReturnEligibility();
      } }, action);
  }

  private settleScale(): void {
    const target: number = Math.max(MIN_SCALE, Math.min(this.effectiveMaxScale(), this.zoomScale));
    const limitX: number = this.offsetLimitXFor(target);
    const limitY: number = this.offsetLimitYFor(target);
    const needPanClamp: boolean = target === MIN_SCALE
      ? (Math.abs(this.panX) > 0.5 || Math.abs(this.panY - this.restPanY()) > 0.5)
      : (Math.abs(this.panX) > limitX + 0.5 || Math.abs(this.panY) > limitY + 0.5);
    if (Math.abs(target - this.zoomScale) < 0.001 && !needPanClamp) {
      this.zoomScale = target;
      this.zoomAnimating = false;
      this.clampOffsets();
      this.reportReturnEligibility();
      return;
    }
    this.animateZoom(() => {
      this.setScale(target);
      if (target === MIN_SCALE) {
        this.panX = 0;
        this.panY = this.restPanY();
      }
    });
  }

  /**
   * 1× 状态下退出前把长图拉回顶部以衔接共享退场；已放大时走淡出关闭，无需把画面强行拉回。
   */
  private closeWithTopReset(): void {
    if (!this.canUpdatePage()) { return; }
    this.stopFlingMotion();
    this.hideMinimapImmediate();
    if (this.zoomScale > MIN_SCALE || Math.abs(this.panY - this.restPanY()) <= 1) {
      this.onTapImage();
      return;
    }
    const epoch: number = ++this.zoomAnimationEpoch;
    this.zoomAnimating = true;
    this.reportReturnEligibility();
    this.getUIContext().animateTo({ duration: ANIMATION_DURATION,
      onFinish: (): void => {
        if (!this.canUpdatePage() || epoch !== this.zoomAnimationEpoch) { return; }
        this.zoomAnimating = false;
        this.reportReturnEligibility();
        this.onTapImage();
      } }, (): void => {
      this.panX = 0;
      this.panY = this.restPanY();
    });
  }

  private toggleDoubleTapZoom(event?: GestureEvent): void {
    if (!this.canUpdatePage()) { return; }
    this.stopFlingMotion();
    this.stoppedFlingOnDown = false;
    const fit: ImageSize = this.sourceImageSize();
    const targetScale: number = viewerDoubleTapScale(this.zoomScale, this.containerWidth, fit.width);
    let focalX: number = this.containerWidth / 2;
    let focalY: number = this.containerHeight / 2;
    if (event !== undefined && event.fingerList !== undefined && event.fingerList.length > 0) {
      const finger: FingerInfo = event.fingerList[0];
      if (Number.isFinite(finger.localX) && Number.isFinite(finger.localY)) {
        focalX = finger.localX;
        focalY = finger.localY;
      }
    }
    const target: ViewerTransform = zoomAroundPoint(
      this.containerWidth, this.containerHeight, fit.width, fit.height,
      this.zoomScale, targetScale, this.panX, this.panY, focalX, focalY);
    if (target.scale > MIN_SCALE) {
      this.panTouched = true;
    }
    this.animateZoom(() => {
      this.zoomScale = target.scale;
      this.panX = target.panX;
      this.panY = target.scale === MIN_SCALE ? this.restPanY() : target.panY;
      this.reportReturnEligibility();
    }, DOUBLE_TAP_DURATION);
    if (target.scale > MIN_SCALE) {
      this.showMinimap(true);
    } else {
      this.hideMinimapImmediate();
    }
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
            this.loadedImageUrl = source;
            this.onImageDecoded(this.index, width, height);
          }
          this.loadState = ImageLoadState.SUCCESS;
          this.applyInitialPan();
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
    if (this.contentAspectRatio() > 0) {
      // 图片节点按原图比例排（宽度撑满、高度自己长）：转场中共享框宽高各自插值，若图片固定 100%×100% 再 Contain，
      // 框变宽的那些帧会露出左右空白或拉伸画面。
      Image(this.displaySource())
        .objectFit(ImageFit.Contain)
        .interpolation(this.zoomScale > MIN_SCALE ? ImageInterpolation.High : ImageInterpolation.Medium)
        .width('100%')
        .aspectRatio(this.contentAspectRatio())
        .scale({ x: this.zoomScale, y: this.zoomScale })
        .translate({ x: this.panX, y: this.panY })
        .opacity(this.primaryImageVisible() ? 1 : 0)
        .onComplete(this.completeHandler(this.displaySource(), this.imageLoadEpoch))
        .onError(this.errorHandler(this.displaySource(), this.imageLoadEpoch))
    } else {
      Image(this.displaySource())
        .objectFit(ImageFit.Contain)
        .interpolation(this.zoomScale > MIN_SCALE ? ImageInterpolation.High : ImageInterpolation.Medium)
        .width('100%')
        .height('100%')
        .scale({ x: this.zoomScale, y: this.zoomScale })
        .translate({ x: this.panX, y: this.panY })
        .opacity(this.primaryImageVisible() ? 1 : 0)
        .onComplete(this.completeHandler(this.displaySource(), this.imageLoadEpoch))
        .onError(this.errorHandler(this.displaySource(), this.imageLoadEpoch))
    }
  }

  @Builder
  /** 缩放始终使用同一棵图片子树，跨过1倍时不销毁/重建Image。 */
  private InteractiveImage() {
    // 顶部对齐：转场中图片比共享框高时，露出的必须是图片顶部。
    Stack({ alignContent: Alignment.Top }) {
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
      Image(this.previewBackdrop()).width('100%').height('100%').objectFit(ImageFit.Contain)
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
          .translate({ x: this.dismissDragX, y: this.dismissDragY })
          .scale({ x: this.dismissDragScale, y: this.dismissDragScale })
          .geometryTransition(this.sharedGeometryId())
          // 保持比例、贴左上：共享框在转场里宽高各自插值，RESIZE_FILL 会把画面拉伸，
          // 侧边空白处就会出现"被裁过的图"，动画结束后才消失。
          .renderFit(RenderFit.TOP_LEFT)
          .clip(this.imageFrameClipped())
          .transition(this.imageContentTransition())
        }
        .width('100%').height('100%')
        // 子层只处理严格单指拖动；双指缩放走父层 parallelGesture，避免单指 Pan 抢占双指捏合。
        .onTouch((event: TouchEvent): void => {
          this.updateActiveTouchCount(event);
          if (event.type === TouchType.Down && this.activeTouchCount === 1) {
            if (this.flingAnimator !== undefined) {
              this.stopFlingMotion();
              this.stoppedFlingOnDown = true;
              this.showMinimap(true);
            } else {
              this.stoppedFlingOnDown = false;
            }
          }
        })
        .gesture(
          PanGesture({ fingers: 1, distance: this.zoomScale > MIN_SCALE ? 4 : 6,
            // 1× 下只吃纵向拖动（长图滚动或上下拖动返回），横向留给 Swiper 翻页；放大后两个方向都归图片。
            direction: this.zoomScale > MIN_SCALE ? PanDirection.All : PanDirection.Vertical })
            .tag('image-zoom-pan')
            .onActionStart((event: GestureEvent) => {
              const fingers: number = event.fingerList !== undefined ? event.fingerList.length : 1;
              if (!this.canUpdatePage() || this.minimapBlocked() || this.pinchBlocked() || fingers >= 2) {
                this.activePanMode = 0;
                return;
              }
              this.stopFlingMotion();
              this.stoppedFlingOnDown = false;
              if (this.panAllowed()) {
                this.activePanMode = 1;
                this.panTouched = true;
                this.panBaseX = this.panX;
                this.panBaseY = this.panY;
                this.lastPanOffsetX = event.offsetX;
                this.lastPanOffsetY = event.offsetY;
                this.lastPanTimeMs = Date.now();
                this.trackedVelocityX = 0;
                this.trackedVelocityY = 0;
                this.showMinimap(false);
              } else if (this.dismissDragAllowed()) {
                this.activePanMode = 2;
                ++this.dismissAnimationEpoch;
                this.dismissDragActive = true;
              } else {
                this.activePanMode = 0;
              }
            })
            .onActionUpdate((event: GestureEvent) => {
              if (!this.canUpdatePage()) { return; }
              const fingers: number = event.fingerList !== undefined ? event.fingerList.length : 1;
              if (this.pinchBlocked() || fingers >= 2) {
                if (this.activePanMode === 2 && this.dismissDragActive) {
                  this.resetDismissDragImmediate();
                  this.onDismissDragChange(false, 1, 1);
                }
                this.activePanMode = 0;
                return;
              }
              if (this.activePanMode === 1 && this.panAllowed()) {
                const nowMs: number = Date.now();
                const dtMs: number = nowMs - this.lastPanTimeMs;
                if (dtMs > 0) {
                  const instVx: number = (event.offsetX - this.lastPanOffsetX) * 1000 / dtMs;
                  const instVy: number = (event.offsetY - this.lastPanOffsetY) * 1000 / dtMs;
                  this.trackedVelocityX = this.trackedVelocityX * 0.35 + instVx * 0.65;
                  this.trackedVelocityY = this.trackedVelocityY * 0.35 + instVy * 0.65;
                }
                this.lastPanOffsetX = event.offsetX;
                this.lastPanOffsetY = event.offsetY;
                this.lastPanTimeMs = nowMs;

                const limitX: number = this.offsetLimitX();
                const limitY: number = this.offsetLimitY();
                const rawX: number = limitX > 0.5 ? this.panBaseX + event.offsetX : 0;
                const rawY: number = limitY > 0.5 ? this.panBaseY + event.offsetY : 0;
                if (motionStore.isOn(MotionEffect.SPRING)) {
                  this.panX = limitX > 0.5 ? applyEdgeResistance(rawX, limitX, this.containerWidth) : 0;
                  this.panY = limitY > 0.5 ? applyEdgeResistance(rawY, limitY, this.containerHeight) : 0;
                } else {
                  this.panX = Math.max(-limitX, Math.min(limitX, rawX));
                  this.panY = Math.max(-limitY, Math.min(limitY, rawY));
                }
                this.showMinimap(false);
              } else if (this.activePanMode === 2 && this.dismissDragActive) {
                const frame: DismissDragFrame = evaluateDismissDrag(event.offsetX, event.offsetY, this.containerHeight);
                this.dismissDragX = frame.translateX;
                this.dismissDragY = frame.translateY;
                this.dismissDragScale = frame.scale;
                this.dismissChromeOpacity = frame.chromeOpacity;
                this.onDismissDragChange(true, frame.backdropOpacity, frame.chromeOpacity);
              }
            })
            .onActionEnd((event: GestureEvent) => {
              const mode: number = this.activePanMode;
              this.activePanMode = 0;
              if (mode === 1) {
                if (this.canUpdatePage() && !this.pinchBlocked()) {
                  const nowMs: number = Date.now();
                  const vx: number = this.resolveReleaseVelocity(event.velocityX, this.trackedVelocityX, nowMs);
                  const vy: number = this.resolveReleaseVelocity(event.velocityY, this.trackedVelocityY, nowMs);
                  this.startFlingMotion(vx, vy);
                }
              } else if (mode === 2 && this.dismissDragActive) {
                if (this.canUpdatePage() && !this.pinchBlocked() &&
                  shouldDismissDrag(event.offsetY, event.velocityY, this.containerHeight)) {
                  this.onDismissCommit((): void => { this.resetDismissDragImmediate(); });
                } else {
                  this.reboundDismissDrag();
                }
              }
            })
            .onActionCancel(() => {
              const mode: number = this.activePanMode;
              this.activePanMode = 0;
              if (mode === 1) {
                if (this.canUpdatePage() && !this.pinchBlocked()) { this.startFlingMotion(0, 0); }
              } else if (mode === 2 && this.dismissDragActive) {
                this.reboundDismissDrag();
              }
            })
        )
        .onGestureJudgeBegin((info: GestureInfo, event: BaseGestureEvent): GestureJudgeResult => {
          if (info.tag !== 'image-zoom-pan') { return GestureJudgeResult.CONTINUE; }
          const multiFinger: boolean = this.pinchBlocked() ||
            (event.fingerList !== undefined && event.fingerList.length >= 2);
          return multiFinger || this.minimapBlocked() || (!this.panAllowed() && !this.dismissDragAllowed())
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
        this.applyInitialPan();
        this.clampOffsets();
      })
      .parallelGesture(
        PinchGesture({ fingers: 2, distance: 2 })
          .onActionStart((event: GestureEvent) => {
            if (!this.canUpdatePage() || this.holdTransitionPreview) { return; }
            this.stopFlingMotion();
            this.stoppedFlingOnDown = false;
            this.pinchActive = true;
            this.syncMultiTouchState();
            if (this.activePanMode === 2 || this.dismissDragActive) {
              this.resetDismissDragImmediate();
              this.onDismissDragChange(false, 1, 1);
            }
            this.activePanMode = 0;
            ++this.zoomAnimationEpoch;
            this.zoomAnimating = true;
            this.reportReturnEligibility();
            this.pinchBase = this.zoomScale;
            this.pinchBasePanX = this.panX;
            this.pinchBasePanY = this.panY;
            this.pinchStartCenterX = Number.isFinite(event.pinchCenterX) && event.pinchCenterX > 0
              ? event.pinchCenterX : this.containerWidth / 2;
            this.pinchStartCenterY = Number.isFinite(event.pinchCenterY) && event.pinchCenterY > 0
              ? event.pinchCenterY : this.containerHeight / 2;
          })
          .onActionUpdate((event: GestureEvent) => {
            if (!this.canUpdatePage() || this.holdTransitionPreview || !this.pinchActive) { return; }
            const maxScale: number = this.effectiveMaxScale();
            const rawScale: number = this.pinchBase * event.scale;
            let nextScale: number = rawScale;
            if (motionStore.isOn(MotionEffect.SPRING)) {
              if (rawScale < MIN_SCALE) {
                nextScale = Math.max(0.75, MIN_SCALE - (MIN_SCALE - rawScale) * 0.45);
              } else if (rawScale > maxScale) {
                nextScale = Math.min(maxScale * 1.18, maxScale + (rawScale - maxScale) * 0.3);
              }
            } else {
              nextScale = Math.max(MIN_SCALE, Math.min(maxScale, rawScale));
            }
            const curX: number = Number.isFinite(event.pinchCenterX) && event.pinchCenterX > 0
              ? event.pinchCenterX : this.pinchStartCenterX;
            const curY: number = Number.isFinite(event.pinchCenterY) && event.pinchCenterY > 0
              ? event.pinchCenterY : this.pinchStartCenterY;
            const ratio: number = nextScale / Math.max(0.001, this.pinchBase);
            const dx: number = this.pinchStartCenterX - this.containerWidth / 2;
            const dy: number = this.pinchStartCenterY - this.containerHeight / 2;
            const rawPanX: number = (curX - this.containerWidth / 2) - (dx - this.pinchBasePanX) * ratio;
            const rawPanY: number = (curY - this.containerHeight / 2) - (dy - this.pinchBasePanY) * ratio;
            const limitX: number = this.offsetLimitXFor(nextScale);
            const limitY: number = this.offsetLimitYFor(nextScale);
            this.zoomScale = nextScale;
            if (nextScale <= MIN_SCALE) {
              this.panX = 0;
              this.panY = 0;
              this.hideMinimapImmediate();
            } else {
              this.panX = Math.max(-limitX, Math.min(limitX, rawPanX));
              this.panY = Math.max(-limitY, Math.min(limitY, rawPanY));
              this.panTouched = true;
              this.showMinimap(false);
            }
            this.reportReturnEligibility();
          })
          .onActionEnd(() => {
            this.pinchActive = false;
            this.pinchCooldownUntil = Date.now() + 120;
            this.syncMultiTouchState();
            if (!this.holdTransitionPreview) {
              this.settleScale();
              if (this.zoomScale > MIN_SCALE) {
                this.scheduleMinimapHide();
              } else {
                this.hideMinimapImmediate();
              }
            }
          })
          .onActionCancel(() => {
            this.pinchActive = false;
            this.pinchCooldownUntil = Date.now() + 120;
            this.syncMultiTouchState();
            if (!this.holdTransitionPreview) {
              this.settleScale();
              if (this.zoomScale > MIN_SCALE) {
                this.scheduleMinimapHide();
              } else {
                this.hideMinimapImmediate();
              }
            }
          })
      )
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          LongPressGesture({ duration: 450 })
            .onAction((): void => {
              if (!this.srBlocked() && !this.pinchBlocked() && !this.dismissDragActive) { this.onLongPressImage(); }
            }),
          TapGesture({ count: 2 })
            .onAction((event: GestureEvent) => {
              if (!this.holdTransitionPreview && !this.srBlocked() && !this.pinchBlocked() && !this.dismissDragActive) {
                this.toggleDoubleTapZoom(event);
              }
            }),
          TapGesture({ count: 1 })
            .onAction(() => {
              if (this.stoppedFlingOnDown) {
                this.stoppedFlingOnDown = false;
                return;
              }
              if (!this.srBlocked() && !this.pinchBlocked() && !this.dismissDragActive) { this.closeWithTopReset(); }
            })
        )
      )
      if (this.currentMinimapFrame().visible) {
        this.LongMinimapOverlay()
      }
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
  /** 可选多档位图片序列；未传时退回 `imageUrls` / `imageUrl`。 */
  images: ViewerImage[] = [];
  initialIndex: number = 0;
  onBeforeClose: () => void = (): void => {};
  onClose: () => void = (): void => {};
  private viewerPolicy: ImageLoadPolicy = imageLoadStore.currentPolicy();
  @State private originRequestedPages: number[] = [];
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
  @State private dismissDragging: boolean = false;
  @State private multiTouchActive: boolean = false;
  @State private backdropOpacity: number = 1;
  @State private chromeOpacity: number = 1;
  @State private longMinimapActive: boolean = false;
  @State private minimapMenuOpacity: number = 1;
  private pendingDismissReset: (() => void) | null = null;
  private lastPreparedShared: boolean = false;
  /** 底部安全区（系统手势条高度，vp）：页码贴底时用它把文字顶到手势条之上 */
  @State private bottomSafeVp: number = 0;
  @State private menuHidden: boolean = false;
  @State private menuRevealed: boolean = false;
  @State private viewerWidth: number = 0;
  @State private viewerHeight: number = 0;
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
    this.viewerPolicy = imageLoadStore.currentPolicy();
    this.originRequestedPages = [];
    const items: ViewerImage[] = this.effectiveViewerImages();
    this.currentIndex = this.clampedIndex(this.initialIndex, items.length);
    this.settledIndex = this.currentIndex;
    this.imageTransition = takeImageTransition(this.transitionKeyAt(this.currentIndex));
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
    this.buildSrStates(this.effectiveImageUrls());
    this.readSafeArea();
    this.hideSystemStatusBar();
    smartReachStore.load(this.hostContext());
    void longImageMinimapStore.load(this.hostContext());
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
        this.statusWasVisible = this.getUIContext().px2vp(area.topRect.height) > 0;
        win.setSpecificSystemBarEnabled('status', false, true).then(() => {
          this.statusHiddenByViewer = true;
        }).catch(() => {
          // 隐藏失败就照旧显示：看图不受影响，不弹错（用户一眼能看出状态栏还在）。
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

  private setLongMinimapActive(active: boolean): void {
    if (!this.canUpdateViewer() || this.longMinimapActive === active) { return; }
    this.longMinimapActive = active;
    const duration: number = motionDuration(180, MotionEffect.FADE);
    if (duration === 0) {
      this.minimapMenuOpacity = active ? 0 : 1;
      return;
    }
    this.getUIContext().animateTo({ duration: duration, curve: Curve.EaseOut }, (): void => {
      this.minimapMenuOpacity = active ? 0 : 1;
    });
  }

  private setCurrentPage(index: number): void {
    if (!this.canUpdateViewer() || !Number.isInteger(index) || index < 0 ||
      index >= this.effectiveImageUrls().length || index === this.currentIndex) { return; }
    this.currentIndex = index;
    this.multiTouchActive = false;
    this.setLongMinimapActive(false);
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
      this.lastPreparedShared = opening.id.length > 0;
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
          const target: ImageTransitionTarget | undefined = opening.gallery.prepare(
            this.currentIndex, this.transitionKeyAt(this.currentIndex));
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
    const preparedSeed: ImageTransitionSeed | undefined = prepared.length > 0 ? prepared[0] : undefined;
    this.lastPreparedShared = preparedSeed !== undefined && !preparedSeed.hasFinished() &&
      preparedSeed.id.length > 0 && !preparedSeed.isReturnDetached();
    return preparedSeed;
  }

  private handleDismissDragChange(active: boolean, backdropOpacity: number, chromeOpacity: number): void {
    if (!this.canUpdateViewer()) { return; }
    if (active) {
      this.dismissDragging = true;
      this.backdropOpacity = backdropOpacity;
      this.chromeOpacity = chromeOpacity;
      return;
    }
    this.dismissDragging = false;
    const duration: number = Math.max(
      motionDuration(ANIMATION_DURATION, MotionEffect.FADE),
      motionDuration(ANIMATION_DURATION, MotionEffect.MOVE)
    );
    if (duration === 0) {
      this.backdropOpacity = 1;
      this.chromeOpacity = 1;
      return;
    }
    this.getUIContext().animateTo({ duration: duration, curve: Curve.EaseOut }, (): void => {
      this.backdropOpacity = 1;
      this.chromeOpacity = 1;
    });
  }

  private handleDismissCommit(resetForShared: () => void): void {
    if (!this.canUpdateViewer() || this.exportBusy.length > 0) { return; }
    this.dismissDragging = false;
    this.pendingDismissReset = resetForShared;
    this.lastPreparedShared = false;
    closeImageTransition(this.getUIContext(), (): void => {
      // 共享返回时在同帧动画事务内归零拖动偏移，让 geometryTransition 从当前位置直接飞回缩略图；
      // 非共享返回保持当前偏移与缩放原地淡出，不弹回中央。
      if (this.lastPreparedShared && this.pendingDismissReset !== null) {
        this.pendingDismissReset();
      }
      this.pendingDismissReset = null;
      this.onClose();
    }, (): void => {
      this.onBeforeClose();
    });
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

  private effectiveViewerImages(): ViewerImage[] {
    if (this.images.length > 0) {
      return this.images;
    }
    const urls: string[] = this.imageUrls.length > 0 ? this.imageUrls : (this.imageUrl.length > 0 ? [this.imageUrl] : []);
    const out: ViewerImage[] = [];
    for (let i: number = 0; i < urls.length; i++) {
      const img: ViewerImage = new ViewerImage();
      img.origin = urls[i];
      img.high = urls[i];
      img.thumb = urls[i];
      img.fallback = urls[i];
      out.push(img);
    }
    return out;
  }

  private transitionKeyAt(index: number): string {
    const items: ViewerImage[] = this.effectiveViewerImages();
    if (index < 0 || index >= items.length) { return ''; }
    return items[index].transitionKey();
  }

  private displayUrlAt(index: number): string {
    const items: ViewerImage[] = this.effectiveViewerImages();
    if (index < 0 || index >= items.length) { return ''; }
    return viewerSource(items[index], this.viewerPolicy, this.originRequestedPages.includes(index));
  }

  private effectiveImageUrls(): string[] {
    const items: ViewerImage[] = this.effectiveViewerImages();
    const out: string[] = [];
    for (let i: number = 0; i < items.length; i++) {
      out.push(this.displayUrlAt(i));
    }
    return out;
  }

  private requestOriginForCurrent(): void {
    const idx: number = this.currentIndex;
    if (this.originRequestedPages.includes(idx)) { return; }
    this.suppressCloseUntil = Date.now() + 700;
    this.originRequestedPages = this.originRequestedPages.concat([idx]);
    const url: string = this.displayUrlAt(idx);
    if (idx >= 0 && idx < this.srStates.length) {
      this.srStates[idx] = this.srSession.stateFor(url);
    }
    this.syncSrCurrent(idx);
    this.openExport();
  }

  private currentOriginButtonLabel(): string {
    const items: ViewerImage[] = this.effectiveViewerImages();
    if (this.currentIndex < 0 || this.currentIndex >= items.length) { return ''; }
    const item: ViewerImage = items[this.currentIndex];
    if (!viewerCanLoadOrigin(item, this.viewerPolicy, this.originRequestedPages.includes(this.currentIndex))) {
      return '';
    }
    return formatOriginBytes(item.originBytes);
  }

  private preloadAdjacentUrls(): string[] {
    const items: ViewerImage[] = this.effectiveViewerImages();
    if (items.length <= 1) { return []; }
    const candidates: number[] = [this.currentIndex + 1, this.currentIndex - 1, this.currentIndex + 2];
    const out: string[] = [];
    for (let i: number = 0; i < candidates.length && out.length < 2; i++) {
      const idx: number = candidates[i];
      if (idx < 0 || idx >= items.length) { continue; }
      const url: string = this.displayUrlAt(idx);
      if (url.length > 0 && !out.includes(url)) {
        out.push(url);
      }
    }
    return out;
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
        const ui = this.getUIContext();
        const systemBottom: number = ui.px2vp(win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).bottomRect.height);
        const navBottom: number = ui.px2vp(
          win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height);
        this.bottomSafeVp = Math.max(systemBottom, navBottom);
      }).catch(() => {
        // 没有避让区信息时保持 0，页码仍有自身视觉间距。
      });
    } catch (err) {
      // 不影响预览主体。
    }
  }

  /**
   * 底部浮层：查看原图胶囊按钮与页码提示，抬高避开底部手势区；深灰半透明底配细描边，在纯黑留白与纯白图片上均可辨。
   */
  @Builder
  private PageBadge(count: number) {
    if (count > 1 || this.currentOriginButtonLabel().length > 0) {
      Column({ space: 10 }) {
        if (this.currentOriginButtonLabel().length > 0) {
          Button({ type: ButtonType.Capsule, stateEffect: true }) {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.picture'))
                .fontSize(15)
                .fontColor([Color.White])
              Text(this.currentOriginButtonLabel())
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.White)
            }
            .padding({ left: 16, right: 16 })
          }
          .height(36)
          .backgroundColor('#CC26262A')
          .border({ width: 0.8, color: '#59FFFFFF' })
          .accessibilityText(this.currentOriginButtonLabel())
          .onTouch((event: TouchEvent): void => {
            event.stopPropagation();
            this.suppressCloseUntil = Date.now() + 700;
          })
          .onClick((): void => {
            this.requestOriginForCurrent();
          })
        }
        if (count > 1) {
          Row() {
            Text(`${this.currentIndex + 1} / ${count}`)
              .fontSize(13)
              .fontColor(Color.White)
          }
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          .borderRadius(12)
          .backgroundColor('#9926262A')
          .border({ width: 0.6, color: '#33FFFFFF' })
        }
      }
      .alignItems(HorizontalAlign.Center)
      .margin({ bottom: Math.max(this.bottomSafeVp, 28) + 28 })
      .opacity(this.chromeOpacity)
      .transition(imageFadeTransition())
    }
  }

  // ───────────────────────── 当前图片准备与导出 ─────────────────────────

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
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
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
        .opacity(this.backdropOpacity)
        .hitTestBehavior(HitTestMode.None)
        .transition(imageFadeTransition())
      if (this.effectiveViewerImages().length > 0) {
        Swiper(this.swiperController) {
          ForEach(this.effectiveViewerImages(), (item: ViewerImage, index: number) => {
            ZoomableImagePage({
              imageUrl: this.displayUrlAt(index),
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
              sr: this.srStateAt(index, this.displayUrlAt(index)),
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
              },
              dismissBlocked: this.exportBusy.length > 0 || this.menuRevealed,
              explicitLong: item.isLong,
              bottomSafeVp: this.bottomSafeVp,
              onMinimapActiveChange: (pageIndex: number, active: boolean): void => {
                if (this.canUpdateViewer() && pageIndex === this.currentIndex) {
                  this.setLongMinimapActive(active);
                }
              },
              onMultiTouchChange: (active: boolean): void => {
                if (this.canUpdateViewer()) { this.multiTouchActive = active; }
              },
              onDismissDragChange: (active: boolean, backdropOpacity: number, chromeOpacity: number): void => {
                this.handleDismissDragChange(active, backdropOpacity, chromeOpacity);
              },
              onDismissCommit: (resetForShared: () => void): void => {
                this.handleDismissCommit(resetForShared);
              }
            })
          },
          // key **不能带 `this.currentIndex` 或切换原图后的显示地址**：否则翻页或切原图会重建页面。
          (item: ViewerImage, index: number) => `${index}:${item.transitionKey()}`)
        }
        .index(this.settledIndex)
        .cachedCount(1)
        .indicator(false)
        .disableSwipe(this.exportBusy.length > 0 || this.holdTransitionPreview || this.dismissDragging || this.multiTouchActive)
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
      // 借用 ArkUI 官方图片缓存提前预取相邻 ±1/+2 张图，减少连续翻图等待；不新增独立磁盘缓存。
      ForEach(this.preloadAdjacentUrls(), (url: string) => {
        Image(url)
          .width(1)
          .height(1)
          .opacity(0)
          .hitTestBehavior(HitTestMode.None)
          .accessibilityLevel('no')
      }, (url: string): string => `preload:${url}`)
      if (!smartReachStore.imageMenuLongPress || !this.menuRevealed) {
        this.PageBadge(this.effectiveImageUrls().length)
      }
      // 常显小胶囊只接住自身触摸；长图右侧定位条显示期间自动淡出避让。
      if (this.exportOpen && !this.menuHidden && !smartReachStore.imageMenuLongPress) {
        ImageMenuPosition({ viewportWidth: this.viewerWidth, viewportHeight: this.viewerHeight,
          capsuleHeight: superResolutionStore.enabled ? 200 : 162, bottomInset: this.bottomSafeVp,
          busy: this.exportBusy.length > 0, content: (): void => { this.ExportSheet() } })
          .opacity(this.chromeOpacity * this.minimapMenuOpacity)
          .hitTestBehavior(this.longMinimapActive ? HitTestMode.None : HitTestMode.Default)
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
      // 保留但不生效：这个 `Stack` 不持有焦点、收不到按键；真正拦返回键的是宿主（查看器是页面上的浮层）。
      if (event.keyCode === KeyCode.KEYCODE_BACK) {
        closeImageTransition(this.getUIContext(), (): void => { this.onClose(); },
          (): void => { this.onBeforeClose(); });
        return true;
      }
      return false;
    })
  }
}
