

import { promptAction, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { KeyCode } from '@ohos.multimodalInput.keyCode';
import {
  copyImageToPasteboard,
  fetchImageBytes,
  imageFileName,
  saveImageToGallery,
  shareImageFile,
  writeImageToCache
} from '../utils/ImageExport';
import { srEncodePixelMap } from '../utils/ImageSuperResolution';
import { superResolutionStore } from '../common/appearance/SuperResolutionStore';
import {
  SR_BUTTON_BASE,
  SR_BUTTON_ICON,
  SR_BUTTON_INSET,
  SR_BUTTON_MARGIN,
  SR_BUTTON_TOUCH,
  SrButtonBox,
  SrStatus,
  srButtonPosition,
  srExportFileName,
  srExportFormat,
  srFormatExtension
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

const EXPORT_DOMAIN: number = 0x0;
const EXPORT_TAG: string = 'ImageViewerExport';

class ImageSize {
  width: number = 0;
  height: number = 0;
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

@Component
struct ZoomableImagePage {
  imageUrl: string = '';

  onTapImage: () => void = (): void => {};

  onLongPressImage: () => void = (): void => {};

  @State private zoomScale: number = MIN_SCALE;
  @State private panX: number = 0;
  @State private panY: number = 0;
  @State private containerWidth: number = 0;
  @State private containerHeight: number = 0;
  @State private sourceWidth: number = 0;
  @State private sourceHeight: number = 0;
  @State private loadState: ImageLoadState = ImageLoadState.LOADING;
  @State private retryCount: number = 0;

  @State private topSafeVp: number = 0;

  index: number = 0;

  onSuperResolutionToggle: (index: number) => void = (): void => {};

  onImageDecoded: (index: number, width: number, height: number) => void = (): void => {};

  @ObjectLink sr: PageSuperResolutionState;

  private srTouchActive: boolean = false;
  private srGuardUntil: number = 0;

  private pinchBase: number = MIN_SCALE;
  private panBaseX: number = 0;
  private panBaseY: number = 0;

  aboutToAppear(): void {
    this.resetImageState();
    this.readWindowSize();
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
    try {
      const context = this.getUIContext().getHostContext();
      window.getLastWindow(context).then((win: window.Window) => {
        const rect = win.getWindowProperties().windowRect;
        this.containerWidth = rect.width > 0 ? px2vp(rect.width) : this.containerWidth;
        this.containerHeight = rect.height > 0 ? px2vp(rect.height) : this.containerHeight;

        const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        this.topSafeVp = px2vp(area.topRect.height);
      }).catch(() => {

      });
    } catch (err) {

    }
  }

  private sourceForLoad(): string {
    if (this.retryCount <= 0) {
      return this.imageUrl;
    }
    const separator: string = this.imageUrl.indexOf('?') >= 0 ? '&' : '?';
    return `${this.imageUrl}${separator}preview_retry=${this.retryCount}`;
  }

  private showingEnhanced(): boolean {
    return this.sr.status === SrStatus.ON && this.sr.pixelMap !== null;
  }

  private displaySource(): image.PixelMap | string {
    const enhanced: image.PixelMap | null = this.sr.pixelMap;
    if (this.sr.status === SrStatus.ON && enhanced !== null) {
      return enhanced;
    }
    return this.sourceForLoad();
  }

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

  private srBlocked(): boolean {
    return this.srTouchActive || Date.now() < this.srGuardUntil;
  }

  private srIconColor(): ResourceColor {
    if (this.sr.status === SrStatus.UNAVAILABLE) {
      return '#80FFFFFF';
    }
    return Color.White;
  }

  private srBaseColor(): ResourceColor {
    if (this.sr.status === SrStatus.UNAVAILABLE) {
      return '#33000000';
    }
    if (this.sr.status === SrStatus.ON) {

      return '#CC0A59F7';
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
  }

  private sourceImageSize(): ImageSize {
    const result: ImageSize = new ImageSize();
    const widthPx: number = this.displayedSourceWidth();
    const heightPx: number = this.displayedSourceHeight();
    if (widthPx <= 0 || heightPx <= 0) {
      result.width = this.containerWidth;
      result.height = this.containerHeight;
      return result;
    }
    const imageWidth: number = px2vp(widthPx);
    const imageHeight: number = px2vp(heightPx);
    if (this.containerWidth <= 0 || this.containerHeight <= 0) {
      result.width = imageWidth;
      result.height = imageHeight;
      return result;
    }
    const fitScale: number = Math.min(this.containerWidth / imageWidth, this.containerHeight / imageHeight);
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
    const next: number = Math.max(MIN_SCALE, Math.min(MAX_SCALE, value));
    this.zoomScale = next;
    if (next === MIN_SCALE) {
      this.panX = 0;
      this.panY = 0;
    } else {
      this.clampOffsets();
    }
  }

  private settleScale(): void {
    const target: number = Math.max(MIN_SCALE, Math.min(MAX_SCALE, this.zoomScale));
    animateTo({ duration: ANIMATION_DURATION }, () => {
      this.setScale(target);
      if (target === MIN_SCALE) {
        this.panX = 0;
        this.panY = 0;
      }
    });
  }

  private toggleDoubleTapZoom(): void {
    animateTo({ duration: ANIMATION_DURATION }, () => {
      if (this.zoomScale > MIN_SCALE) {
        this.setScale(MIN_SCALE);
      } else {
        this.setScale(DOUBLE_TAP_SCALE);
      }
    });
  }

  private retry(): void {
    this.retryCount += 1;
    this.loadState = ImageLoadState.LOADING;
    this.sourceWidth = 0;
    this.sourceHeight = 0;
  }

  @Builder
  private PreviewImage() {
    Image(this.displaySource())
      .objectFit(ImageFit.Contain)

      .interpolation(this.zoomScale > MIN_SCALE ? ImageInterpolation.High : ImageInterpolation.Medium)
      .width('100%')
      .height('100%')
      .scale({ x: this.zoomScale, y: this.zoomScale })
      .translate({ x: this.panX, y: this.panY })
      .onComplete((event?: ImageCompleteInfo) => {

        if (event === undefined || event.loadingStatus !== 1) { return; }

        if (!this.showingEnhanced()) {
          this.sourceWidth = event.width;
          this.sourceHeight = event.height;
          this.onImageDecoded(this.index, event.width, event.height);
        }
        this.loadState = ImageLoadState.SUCCESS;
        this.clampOffsets();
      })
      .onError(() => {
        this.loadState = ImageLoadState.ERROR;
      })
  }

  @Builder
  private ZoomedImage() {
    Stack() {
      this.PreviewImage()
    }
    .width('100%')
    .height('100%')
      .gesture(
        PanGesture({ fingers: 1, distance: 5 })
          .onActionStart(() => {
            this.panBaseX = this.panX;
            this.panBaseY = this.panY;
          })
          .onActionUpdate((event: GestureEvent) => {
            this.panX = this.panBaseX + event.offsetX;
            this.panY = this.panBaseY + event.offsetY;
            this.clampOffsets();
          })
          .onActionEnd(() => {
            this.clampOffsets();
          })
      )
  }

  @Builder
  private LoadOverlay() {
    if (this.loadState === ImageLoadState.LOADING) {
      Progress({ value: 0, total: 100, type: ProgressType.Ring })
        .width(34)
        .height(34)
        .color(Color.White)
    } else if (this.loadState === ImageLoadState.ERROR) {
      Column({ space: 10 }) {
        Text('图片加载失败')
          .fontSize(15)
          .fontColor(Color.White)
        Text('点击重试')
          .fontSize(14)
          .fontColor('#B8D8FF')
          .onClick(() => {
            this.retry();
          })
      }
      .padding({ left: 18, right: 18, top: 14, bottom: 14 })
      .borderRadius(10)
      .backgroundColor('#99000000')
    }
  }

  build() {
    Stack() {

      Stack() {
        if (this.zoomScale > MIN_SCALE) {
          this.ZoomedImage()
        } else {
          this.PreviewImage()
        }
        this.LoadOverlay()
      }
      .width('100%')
      .height('100%')
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.containerWidth = newValue.width as number;
        this.containerHeight = newValue.height as number;
        this.clampOffsets();
      })
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          PinchGesture({ fingers: 2 })
            .onActionStart(() => {
              this.pinchBase = this.zoomScale;
            })
            .onActionUpdate((event: GestureEvent) => {
              this.setScale(this.pinchBase * event.scale);
            })
            .onActionEnd(() => {
              this.settleScale();
            }),
          TapGesture({ count: 2 })
            .onAction(() => {
              if (this.srBlocked()) {
                return;
              }
              this.toggleDoubleTapZoom();
            }),
          TapGesture({ count: 1 })
            .onAction(() => {
              if (this.srBlocked()) {
                return;
              }
              this.onTapImage();
            })
        )
      )

      .parallelGesture(
        LongPressGesture({ repeat: false, duration: 400 })
          .onAction(() => {
            if (this.srBlocked()) {
              return;
            }
            hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'gesture longpress fired');
            this.onLongPressImage();
          })
      )

      if (superResolutionStore.enabled) {
        this.SuperResolutionButton()
      }
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct ImageViewer {
  imageUrl: string = '';
  imageUrls: string[] = [];
  initialIndex: number = 0;
  onClose: () => void = (): void => {};

  @State private currentIndex: number = 0;

  @State private bottomSafeVp: number = 0;

  @State private exportOpen: boolean = false;

  @State private exportState: number = 0;

  @State private exportError: string = '';

  @State private exportBusy: string = '';

  @State private srTick: number = 0;

  private exportBytes: Uint8Array | null = null;
  private exportUri: string = '';

  private suppressCloseUntil: number = 0;

  private srSession: ImageSuperResolutionSession = new ImageSuperResolutionSession();

  private srStates: PageSuperResolutionState[] = [];

  aboutToAppear(): void {
    const urls: string[] = this.effectiveImageUrls();
    this.currentIndex = this.clampedIndex(this.initialIndex, urls.length);
    this.buildSrStates(urls);
    this.readSafeArea();
    this.hideSystemStatusBar();
  }

  aboutToDisappear(): void {

    this.srSession.close();
    this.restoreSystemStatusBar();
  }

  private viewerWindow: window.Window | null = null;

  private statusWasVisible: boolean = true;

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

        });
      }).catch(() => {

      });
    } catch (err) {

    }
  }

  private restoreSystemStatusBar(): void {
    if (!this.statusHiddenByViewer || this.viewerWindow === null) {
      return;
    }
    this.statusHiddenByViewer = false;
    this.viewerWindow.setSpecificSystemBarEnabled('status', this.statusWasVisible, true)
      .catch(() => {

      });
  }

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

  private srStateAt(index: number, url: string): PageSuperResolutionState {
    if (index >= 0 && index < this.srStates.length) {
      return this.srStates[index];
    }
    return this.srSession.stateFor(url);
  }

  private syncSrCurrent(index: number): void {
    const urls: string[] = this.effectiveImageUrls();
    if (index < 0 || index >= urls.length) {
      return;
    }
    this.srSession.setCurrentKey(urls[index]);
    this.srTick += 1;
  }

  private noteDecoded(index: number, width: number, height: number): void {
    const urls: string[] = this.effectiveImageUrls();
    if (index < 0 || index >= urls.length) {
      return;
    }
    this.srSession.noteDecodedSize(urls[index], width, height);
  }

  private async toggleSuperResolution(index: number): Promise<void> {
    const urls: string[] = this.effectiveImageUrls();
    if (index < 0 || index >= urls.length) {
      return;
    }
    hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'sr toggle index=%{public}d url=%{public}s',
      index, urls[index].slice(0, 60));
    const outcome: SrToggleResult = await this.srSession.toggle(urls[index]);
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

      });
    } catch (err) {

    }
  }

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
    }
  }

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

  private openExport(): void {
    hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'openExport index=%{public}d url=%{public}s',
      this.currentIndex, this.currentUrl().slice(0, 60));
    this.suppressCloseUntil = Date.now() + 700;
    this.exportOpen = true;
    this.exportError = '';
    this.exportBytes = null;
    this.exportUri = '';
    this.exportState = 1;
    this.prepareExport();
  }

  private async prepareExport(): Promise<void> {
    const url: string = this.currentUrl();
    try {
      const bytes: Uint8Array = await fetchImageBytes(url);
      const name: string = imageFileName(url, this.currentIndex);
      const uri: string = writeImageToCache(this.hostContext(), bytes, name);
      this.exportBytes = bytes;
      this.exportUri = uri;
      this.exportState = 2;
      hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'prepare ok bytes=%{public}d', bytes.length);
    } catch (err) {
      this.exportState = 3;
      this.exportError = err instanceof Error ? err.message : String(err);
      hilog.error(EXPORT_DOMAIN, EXPORT_TAG, 'prepare failed: %{public}s', this.exportError);
    }
  }

  private closeExport(): void {
    this.exportOpen = false;
    this.exportState = 0;
    this.exportError = '';
    this.exportBusy = '';
    this.exportBytes = null;
    this.exportUri = '';
  }

  private toast(message: string): void {
    promptAction.showToast({ message: message, duration: 2000 });
  }

  private async saveToGallery(): Promise<void> {
    if (this.exportState !== 2 || this.exportUri.length === 0) {
      hilog.warn(EXPORT_DOMAIN, EXPORT_TAG, 'save skipped state=%{public}d uri=%{public}d',
        this.exportState, this.exportUri.length);
      this.toast('图片还没准备好');
      return;
    }
    this.exportBusy = 'save';
    try {
      await saveImageToGallery(this.hostContext(), this.exportUri);
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

  private async copyImage(): Promise<void> {
    if (this.exportBytes === null || this.exportState !== 2) {
      hilog.warn(EXPORT_DOMAIN, EXPORT_TAG, 'copy skipped state=%{public}d bytes=%{public}d',
        this.exportState, this.exportBytes === null ? -1 : this.exportBytes.length);
      this.toast('图片还没准备好');
      return;
    }
    this.exportBusy = 'copy';
    try {
      await copyImageToPasteboard(this.exportBytes);
      hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'copy ok');
      this.toast('已复制图片');
      this.closeExport();
    } catch (err) {
      hilog.error(EXPORT_DOMAIN, EXPORT_TAG, 'copy failed: %{public}s',
        err instanceof Error ? err.message : String(err));
      this.toast(`复制失败：${err instanceof Error ? err.message : String(err)}`);
    } finally {
      this.exportBusy = '';
    }
  }

  private async shareImage(): Promise<void> {
    if (this.exportState !== 2 || this.exportUri.length === 0) {
      hilog.warn(EXPORT_DOMAIN, EXPORT_TAG, 'share skipped state=%{public}d uri=%{public}d',
        this.exportState, this.exportUri.length);
      this.toast('图片还没准备好');
      return;
    }
    this.exportBusy = 'share';
    try {
      await shareImageFile(this.hostContext(), this.exportUri, '贴吧图片');
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

  @Builder
  private ExportSectionLabel(label: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor('#B3FFFFFF')
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 10, bottom: 2 })
  }

  @Builder
  private SaveToGalleryButton(kind: number) {
    SaveButton({ icon: SaveIconStyle.FULL_FILLED, text: SaveDescription.SAVE_IMAGE })
      .iconSize(22)
      .fontSize(16)
      .fontColor(Color.White)
      .backgroundColor(Color.Transparent)
      .width('100%')
      .height(52)
      .padding({ left: 12 })
      .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
        if (result !== SaveButtonOnClickResult.SUCCESS) {
          hilog.warn(EXPORT_DOMAIN, EXPORT_TAG, 'save not authorized result=%{public}d', result);
          this.toast('未获得保存授权');
          return;
        }
        if (kind === 5) {
          this.exportEnhanced(false);
        } else {
          this.saveToGallery();
        }
      })
  }

  @Builder
  private ExportRow(icon: Resource, label: string, kind: number) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([this.exportRowColor(kind)])
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

  private exportRowEnabled(kind: number): boolean {
    if (kind === 0 || kind === 1) {
      return this.exportState === 2;
    }
    if (kind === 5) {
      return this.enhancedReady();
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
    if (kind === 0) {
      this.copyImage();
    } else if (kind === 1) {
      this.shareImage();
    } else if (kind === 5) {
      this.exportEnhanced(true);
    } else if (kind === 2) {
      this.exportState = 1;
      this.exportError = '';
      this.prepareExport();
    } else {
      this.closeExport();
    }
  }

  private currentSrState(): PageSuperResolutionState | null {
    const index: number = this.currentIndex;
    if (index < 0 || index >= this.srStates.length) {
      return null;
    }
    return this.srStates[index];
  }

  private enhancedReady(): boolean {
    const state: PageSuperResolutionState | null = this.currentSrState();
    return state !== null && state.hasResult && state.pixelMap !== null
      && state.status !== SrStatus.PROCESSING;
  }

  private showEnhancedSection(): boolean {
    return this.srTick >= 0 && this.enhancedReady();
  }

  private async exportEnhanced(share: boolean): Promise<void> {
    const state: PageSuperResolutionState | null = this.currentSrState();
    const held: image.PixelMap | null = state === null ? null : state.pixelMap;
    if (state === null || held === null || !this.enhancedReady()) {
      this.toast('增强图还没准备好');
      return;
    }
    const pinnedKey: string = state.key;
    const pinnedVersion: number = state.resultVersion;
    const format: string = srExportFormat(state.resultHasAlpha);
    const extension: string = srFormatExtension(format);
    hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'enhanced export start share=%{public}s ver=%{public}d',
      String(share), pinnedVersion);
    this.exportBusy = share ? 'share-sr' : 'save-sr';
    this.srSession.setExportPin(pinnedKey);
    try {
      const encoded: ArrayBuffer = await srEncodePixelMap(held, format, 100);
      if (state.resultVersion !== pinnedVersion || state.pixelMap === null) {
        hilog.warn(EXPORT_DOMAIN, EXPORT_TAG, 'enhanced export aborted: result changed');
        this.toast('增强图已更新，请重新导出');
        return;
      }
      const uri: string = writeImageToCache(this.hostContext(), new Uint8Array(encoded),
        srExportFileName(this.currentIndex, Date.now(), extension));
      if (share) {
        await shareImageFile(this.hostContext(), uri, '贴吧图片（超分）');
        hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'enhanced share panel shown');
        this.toast('已打开分享面板');
      } else {
        await saveImageToGallery(this.hostContext(), uri);
        hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'enhanced save ok');
        this.toast('已保存增强图到相册');
      }
      this.closeExport();
    } catch (err) {
      const message: string = err instanceof Error ? err.message : String(err);
      hilog.error(EXPORT_DOMAIN, EXPORT_TAG, 'enhanced export failed: %{public}s', message);
      this.toast(`${share ? '分享' : '保存'}失败：${message}`);
    } finally {
      this.srSession.clearExportPin();
      this.exportBusy = '';
    }
  }

  @Builder
  private ExportSheet() {
    Column() {

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

          this.ExportSectionLabel('原图')
          this.SaveToGalleryButton(4)

          this.ExportRow($r('sys.symbol.doc_text_on_doc_text'), '复制图片', 0)

          this.ExportRow($r('sys.symbol.arrow_up_right'), '分享图片', 1)

          if (this.showEnhancedSection()) {
            this.ExportSectionLabel('增强图（图像超分结果）')
            this.SaveToGalleryButton(5)
            this.ExportRow($r('sys.symbol.arrow_up_right'), '分享增强图', 5)
          }
        }

        Divider().color('#33FFFFFF').margin({ top: 4 })
        this.ExportRow($r('sys.symbol.xmark'), '取消', 3)
      }
      .width('100%')
      .backgroundColor('#E61C1C1E')
      .borderRadius({ topLeft: 18, topRight: 18 })

      .padding({ bottom: Math.max(this.bottomSafeVp, 12) + 8 })
    }
    .width('100%')
    .height('100%')
  }

  build() {

    Stack({ alignContent: Alignment.Bottom }) {
      if (this.effectiveImageUrls().length > 0) {
        Swiper() {
          ForEach(this.effectiveImageUrls(), (url: string, index: number) => {
            ZoomableImagePage({
              imageUrl: url,
              index: index,
              sr: this.srStateAt(index, url),
              onSuperResolutionToggle: (tapped: number): void => {
                this.toggleSuperResolution(tapped);
              },
              onImageDecoded: (decoded: number, width: number, height: number): void => {
                this.noteDecoded(decoded, width, height);
              },
              onTapImage: (): void => {

                if (this.exportOpen || Date.now() < this.suppressCloseUntil) {
                  return;
                }
                this.onClose();
              },
              onLongPressImage: (): void => {

                this.currentIndex = index;
                this.syncSrCurrent(index);
                this.openExport();
              }
            })
          },

          (url: string, index: number) => `${index}:${url}`)
        }
        .index(this.currentIndex)
        .indicator(false)
        .loop(false)
        .onChange((index: number) => {
          this.currentIndex = index;

          this.syncSrCurrent(index);
        })
        .width('100%')
        .height('100%')
      }
      if (!this.exportOpen) {
        this.PageBadge(this.effectiveImageUrls().length)
      }

      if (this.exportOpen) {
        this.ExportSheet()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onKeyEvent((event: KeyEvent): boolean => {

      if (event.keyCode === KeyCode.KEYCODE_BACK) {
        this.onClose();
        return true;
      }
      return false;
    })
  }
}
