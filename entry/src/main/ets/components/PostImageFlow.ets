import { display, FrameCallback } from '@kit.ArkUI';
import { ContentImage } from '../model/ThreadDetail';
import { BODY_RADIUS, FeedImageBox, FeedImageInfo, feedImageInfo,
  rememberMeasuredImage } from '../model/HomeFeedPresentation';
import { POST_IMAGE_PREVIEW_MAX_HEIGHT, ReadingDecodeSize, commentImageBox, hasReadingImageSize, readingDecodeSize,
  readingImageBox, readingImageInfo } from '../model/PostImageLayout';
import { FeedImageTransform } from '../model/FeedImageLayout';
import { ImageTransitionCrop, imageTransitionCrop } from '../model/ImageTransitionCrop';
import { LowFlowStore, lowFlowStore } from '../common/appearance/LowFlowStore';
import { AppTheme } from '../theme/Theme';
import { ImageTransitionGallery, ImageTransitionSource, ImageTransitionTarget } from './ImageTransition';

interface ReadingImageComplete {
  width: number;
  height: number;
  loadingStatus: number;
}

/** 退场先恢复原生共享节点，布局/绘制后再决定是否释放离屏的正文图片。 */
class PostImageReleaseFrame extends FrameCallback {
  private ready: () => void;
  constructor(ready: () => void) { super(); this.ready = ready; }
  onIdle(_timeLeft: number): void { this.ready(); }
}

/** 完整纵向图片；正文长图展开阅读，评论使用更紧凑的等比预览。 */
@ComponentV2
struct PostFlowImage {
  @Require @Param image: ContentImage;
  @Param imageIndex: number = 0;
  @Param viewerIndex: number = -1;
  @Param transitionGallery: ImageTransitionGallery | undefined = undefined;
  @Param contentWidth: number = 320;
  @Param density: number = 1;
  @Param commentPreview: boolean = false;
  @Event onOpen: () => void = (): void => {};
  @Local visible: boolean = false;
  @Local loadedUrl: string = '';
  @Local failedUrl: string = '';
  @Local actualUrl: string = '';
  @Local actual: FeedImageInfo = new FeedImageInfo();
  @Local flow: LowFlowStore = lowFlowStore;
  @Local private originalPreferred: boolean = false;
  @Local private transitionRetained: boolean = false;
  @Local private sharedBindingEnabled: boolean = true;
  private imageTransition: ImageTransitionSource = new ImageTransitionSource((enabled: boolean): void => {
    this.sharedBindingEnabled = enabled;
  });
  private alive: boolean = false;
  private imageKey: string = '';
  private sourceIdentity: string = '';
  private imagePosition: number = 0;
  private requestEpoch: number = 0;
  private transitionEpoch: number = 0;
  private unregisterReturn: () => void = (): void => {};

  aboutToAppear(): void {
    this.alive = true;
    this.invalidateRequest();
    const sameSource: boolean = this.imageKey === this.currentImageKey();
    this.originalPreferred = (sameSource && this.originalPreferred) || this.knownLongImage();
    this.imageKey = this.currentImageKey();
    this.sourceIdentity = this.sourceUrl();
    this.imagePosition = this.imageIndex;
    this.registerReturnSource();
  }

  private currentImageKey(): string {
    return `${this.image.imageUrl}\n${this.image.originImageUrl}`;
  }

  private invalidateTransition(): void {
    ++this.transitionEpoch;
    this.transitionRetained = false;
    this.imageTransition.invalidate();
  }

  private invalidateRequest(): void {
    this.invalidateTransition();
    ++this.requestEpoch;
    this.loadedUrl = '';
    this.failedUrl = '';
  }

  @Monitor('image', 'imageIndex')
  onImageChanged(): void {
    // 同 URL 补齐声明尺寸也需要判长；相同资源不能因对象/序号变化被清成加载中。
    const sameSource: boolean = this.imageKey === this.currentImageKey();
    if (sameSource && this.imagePosition === this.imageIndex) {
      this.promoteOriginalIfLong();
      return;
    }
    const previousUrl: string = this.sourceIdentity;
    this.imageKey = this.currentImageKey();
    this.imagePosition = this.imageIndex;
    this.invalidateTransition();
    if (!sameSource) { this.originalPreferred = this.knownLongImage(); }
    this.sourceIdentity = this.sourceUrl();
    if (previousUrl !== this.sourceIdentity) {
      this.invalidateRequest();
      this.actualUrl = '';
      this.actual = new FeedImageInfo();
    } else if (!this.visible) {
      // 身份变化取消了离屏保留，Image 随之离树；它的旧加载回调不能继续生效。
      this.invalidateRequest();
    } else {
      // 原图地址或序号变化，但当前仍用同一缩略资源时，不依赖不会到来的第二次加载回调。
      this.promoteOriginalIfLong();
    }
    this.registerReturnSource();
  }

  @Monitor('viewerIndex', 'transitionGallery')
  onReturnGalleryChanged(): void {
    this.invalidateTransition();
    if (!this.visible) { this.invalidateRequest(); }
    this.registerReturnSource();
  }

  /** 注册的是整段富文本里的出现序号；相同地址在不同位置仍是不同目标。 */
  private registerReturnSource(): void {
    this.unregisterReturn();
    this.unregisterReturn = (): void => {};
    if (!this.alive || this.transitionGallery === undefined || this.viewerIndex < 0) { return; }
    const key: string = this.currentImageKey();
    const index: number = this.imageIndex;
    const viewerIndex: number = this.viewerIndex;
    const origin: string = this.image.originImageUrl || this.image.imageUrl;
    this.unregisterReturn = this.transitionGallery.register(viewerIndex, origin,
      (): ImageTransitionTarget | undefined => {
        if (!this.alive || !this.visible || this.flow.enabled || !this.isLoaded() ||
          key !== this.currentImageKey() || index !== this.imageIndex || viewerIndex !== this.viewerIndex) {
          return undefined;
        }
        const url: string = this.sourceUrl();
        const crop: ImageTransitionCrop = this.drawingCrop();
        if (!crop.usable || !this.imageTransition.canOpenShared()) { return undefined; }
        // prepareReturn 随后会换掉旧源租约；先换代，旧 release 不能卸掉本次目标。
        const transition: number = ++this.transitionEpoch;
        this.transitionRetained = true;
        return new ImageTransitionTarget(this.imageTransition, url, origin, index, crop, undefined,
          (): void => { this.releaseTransition(url, index, transition); });
      });
  }

  @Monitor('flow.enabled')
  onLowFlowChanged(): void {
    this.invalidateRequest();
  }

  aboutToDisappear(): void {
    this.unregisterReturn();
    this.unregisterReturn = (): void => {};
    this.alive = false;
    this.visible = false;
    this.invalidateRequest();
  }

  private sourceUrl(): string {
    return (this.originalPreferred || this.image.imageUrl.length === 0) && this.image.originImageUrl.length > 0
      ? this.image.originImageUrl : this.image.imageUrl;
  }

  private isLoaded(): boolean { return this.sourceUrl().length > 0 && this.loadedUrl === this.sourceUrl(); }

  private declaredInfo(): FeedImageInfo {
    const declared: FeedImageInfo = new FeedImageInfo();
    declared.width = this.image.width;
    declared.height = this.image.height;
    declared.origin = this.image.originImageUrl;
    return declared;
  }

  /** 直接读取声明和缓存，避免与 sourceInfo/sourceUrl 形成循环。 */
  private knownLongImage(): boolean {
    const declared: FeedImageInfo = this.declaredInfo();
    return readingImageInfo(declared, feedImageInfo(this.image.imageUrl)).long ||
      readingImageInfo(declared, feedImageInfo(this.image.originImageUrl)).long;
  }

  /** 取源只升级一次；仅实际换 URL 才清除加载状态并使旧回调失效。 */
  private promoteOriginalIfLong(): boolean {
    if (this.originalPreferred || !(this.knownLongImage() || this.sourceInfo().long)) { return false; }
    const previousUrl: string = this.sourceUrl();
    this.originalPreferred = true;
    this.sourceIdentity = this.sourceUrl();
    if (previousUrl === this.sourceIdentity) {
      this.invalidateTransition();
      if (!this.visible) { this.invalidateRequest(); }
      return false;
    }
    this.invalidateRequest();
    this.actualUrl = '';
    this.actual = new FeedImageInfo();
    return true;
  }

  private sourceInfo(): FeedImageInfo {
    const declared: FeedImageInfo = this.declaredInfo();
    // 保留已确认的长图语义，不因原图尚无尺寸或暂缺标记而降回缩略图。
    declared.long = this.originalPreferred;
    const url: string = this.sourceUrl();
    if (this.actualUrl === url && hasReadingImageSize(this.actual)) {
      return readingImageInfo(declared, this.actual);
    }
    let remembered: FeedImageInfo = feedImageInfo(url);
    if (!hasReadingImageSize(remembered) && !hasReadingImageSize(declared) && this.originalPreferred &&
      url === this.image.originImageUrl) {
      // 仅用于原图尚未显示时估算占位；原图回调后以其自身实际尺寸为准，不写入原图缓存。
      remembered = feedImageInfo(this.image.imageUrl);
    }
    return readingImageInfo(declared, remembered);
  }

  private frame(): FeedImageBox {
    if (this.commentPreview) {
      return commentImageBox(this.sourceInfo(), this.contentWidth, this.density, this.flow.enabled);
    }
    // 正常阅读直接完整显示；低流量只保留有界占位，不撑出整张长图的空白高度。
    return readingImageBox(this.sourceInfo(), this.contentWidth, this.density, !this.flow.enabled);
  }

  /** 完整图片只需单位变换，仍用 crop 会话保持同源预览交接及返回保护。 */
  private drawingCrop(): ImageTransitionCrop {
    const crop: ImageTransitionCrop = imageTransitionCrop(new FeedImageTransform());
    const info: FeedImageInfo = this.sourceInfo();
    if (hasReadingImageSize(info)) { crop.contentAspectRatio = info.width / info.height; }
    return crop;
  }

  private retentionIsCurrent(url: string, index: number, epoch: number): boolean {
    return this.alive && !this.flow.enabled && this.transitionRetained && epoch === this.transitionEpoch &&
      url === this.sourceUrl() && index === this.imageIndex;
  }

  private releaseTransition(url: string, index: number, epoch: number, attempt: number = 0): void {
    if (!this.retentionIsCurrent(url, index, epoch)) { return; }
    const context: UIContext = this.getUIContext();
    try {
      context.postFrameCallback(new PostImageReleaseFrame((): void => {
        if (!this.retentionIsCurrent(url, index, epoch)) { return; }
        context.runScopedTask((): void => {
          if (!this.retentionIsCurrent(url, index, epoch)) { return; }
          // 共享几何结束先留一次可见性更新；仍为 false 时再等一帧，不在退场同帧卸图。
          if (!this.visible && attempt === 0) { this.releaseTransition(url, index, epoch, 1); return; }
          this.transitionRetained = false;
          if (!this.visible) { this.invalidateRequest(); }
        });
      }));
    } catch (_) {
      // UIContext 已不可用时不继续占用原图；正常路径统一等原生布局后的帧回调。
      if (!this.retentionIsCurrent(url, index, epoch)) { return; }
      this.transitionRetained = false;
      if (!this.visible) { this.invalidateRequest(); }
    }
  }

  private openImage(): void {
    const url: string = this.sourceUrl();
    if (url.length === 0) { return; }
    const request: number = this.requestEpoch;
    const index: number = this.imageIndex;
    const ready: boolean = this.acceptsRequest(url, request) && this.isLoaded();
    const crop: ImageTransitionCrop | undefined = ready && this.imageTransition.canOpenShared()
      ? this.drawingCrop() : undefined;
    const transition: number = ++this.transitionEpoch;
    // 只保留当前参与共享的一张已加载源图，不把所有看过的长图常驻在页面里。
    this.transitionRetained = crop !== undefined && crop.usable;
    this.imageTransition.open(this.getUIContext(), url,
      this.image.originImageUrl || this.image.imageUrl, this.onOpen, index, ready, crop, undefined,
      (): void => { this.releaseTransition(url, index, transition); }, this.transitionGallery, this.viewerIndex);
  }

  private decodeSize(): ImageSourceSize | undefined {
    const pixels: ReadingDecodeSize | undefined = readingDecodeSize(this.sourceInfo(), this.frame().width, this.density);
    if (pixels === undefined) { return undefined; }
    // 当前 ImageSourceSize 文档的数值单位为 vp；源尺寸/像素预算为 px，交给 UIContext 转换。
    const ui: UIContext = this.getUIContext();
    return { width: ui.px2vp(pixels.width), height: ui.px2vp(pixels.height) };
  }

  private acceptsRequest(url: string, epoch: number): boolean {
    return this.alive && (this.visible || this.transitionRetained) && !this.flow.enabled && url.length > 0 &&
      epoch === this.requestEpoch && url === this.sourceUrl();
  }

  private completeHandler(url: string, epoch: number): (event?: ReadingImageComplete) => void {
    return (event?: ReadingImageComplete): void => {
      if (!this.acceptsRequest(url, epoch) || event === undefined ||
        (event.loadingStatus !== 0 && event.loadingStatus !== 1) ||
        !Number.isFinite(event.width) || !Number.isFinite(event.height) ||
        !(event.width > 0) || !(event.height > 0)) { return; }
      const width: number = event.width;
      const height: number = event.height;
      const status: number = event.loadingStatus;
      // 缓存命中可能在渲染中同步回调；离开当前调用栈再写 @Local，并重新核对加载代次。
      Promise.resolve().then((): void => { this.applyComplete(url, epoch, width, height, status); });
    };
  }

  private applyComplete(url: string, epoch: number, width: number, height: number, status: number): void {
    if (!this.acceptsRequest(url, epoch)) { return; }
    this.getUIContext().runScopedTask((): void => {
      if (!this.acceptsRequest(url, epoch)) { return; }
      // status 0 给出数据源尺寸，先校正比例与解码目标；成功显示仍等 status 1。
      if ((status === 0 || this.actualUrl !== url) &&
        (this.actualUrl !== url || this.actual.width !== width || this.actual.height !== height)) {
        const info: FeedImageInfo = new FeedImageInfo();
        info.width = width;
        info.height = height;
        info.long = feedImageInfo(url).long;
        info.origin = this.image.originImageUrl;
        this.actualUrl = url;
        this.actual = info;
        rememberMeasuredImage(url, width, height, this.sourceInfo().long, info.origin);
      }
      // 未知尺寸缩略图确认成长图后，先切原图；该次缩略图成功不能标记新资源已加载。
      if (this.promoteOriginalIfLong()) { return; }
      if (status === 1) { this.loadedUrl = url; this.failedUrl = ''; }
    });
  }

  private errorHandler(url: string, epoch: number): () => void {
    return (): void => {
      Promise.resolve().then((): void => {
        if (!this.acceptsRequest(url, epoch)) { return; }
        this.getUIContext().runScopedTask((): void => {
          if (this.acceptsRequest(url, epoch)) {
            this.invalidateTransition();
            this.failedUrl = url;
            this.loadedUrl = '';
          }
        });
      });
    };
  }

  private visibilityChanged(visible: boolean): void {
    if (this.visible === visible) { return; }
    this.visible = visible;
    // 原生共享几何期间的短暂不可见不能删掉源图，也不能提前解除查看器的预览交接。
    if (!visible && !this.transitionRetained) { this.invalidateRequest(); }
  }

  @Builder
  Picture() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.flow.enabled) {
        Text('低流量模式 · 点按查看').fontSize(12).fontColor(AppTheme.TEXT_SUB)
          .width('100%').height('100%').textAlign(TextAlign.Center)
      } else {
        if (!this.isLoaded()) {
          Text(this.sourceUrl().length === 0 ? '图片地址不可用' :
            this.failedUrl === this.sourceUrl() ? '图片加载失败 · 点按查看' : '图片加载中…')
            .fontSize(12).fontColor(AppTheme.TEXT_SUB)
            .width('100%').height(Math.min(this.frame().height, POST_IMAGE_PREVIEW_MAX_HEIGHT))
            .textAlign(TextAlign.Center)
        }
        // 首次只加载可见图；共享会话期间保留同一节点，连续多图不会一次下载全部原图。
        if ((this.visible || this.transitionRetained) && this.sourceUrl().length > 0) {
          Image(this.sourceUrl())
            .width('100%').height('100%')
            .position({ x: 0, y: 0 })
            .objectFit(ImageFit.Contain)
            .objectRepeat(ImageRepeat.NoRepeat)
            .autoResize(true)
            .sourceSize(this.decodeSize())
            .opacity(this.isLoaded() ? 1 : 0)
            .onComplete(this.completeHandler(this.sourceUrl(), this.requestEpoch))
            .onError(this.errorHandler(this.sourceUrl(), this.requestEpoch))
        }
      }
    }
    .width(this.frame().width).height(this.frame().height)
    .backgroundColor(this.isLoaded() ? Color.Transparent : AppTheme.SURFACE_MUTED)
    .borderRadius(BODY_RADIUS).clip(true)
    .geometryTransition(this.sharedBindingEnabled
      ? this.imageTransition.id(this.sourceUrl(), this.imageIndex) : '', { follow: true })
    .transition(TransitionEffect.IDENTITY)
    .renderFit(RenderFit.RESIZE_FILL)
    .onClick((): void => { this.openImage(); })
  }

  build() {
    Column() {
      this.Picture()
    }.width('100%').alignItems(HorizontalAlign.Start)
      // follow 只搬动 Picture；可见性以原阅读位置的稳定父容器为准。
      .onVisibleAreaChange([0], (visible: boolean): void => { this.visibilityChanged(visible); })
  }
}

/** 连续图片按顺序纵排，点击仍回传整篇内容中的原始下标。 */
@ComponentV2
export struct PostImageFlow {
  @Require @Param images: ContentImage[];
  @Param startIndex: number = 0;
  @Param viewerIndices: number[] = [];
  @Param transitionGallery: ImageTransitionGallery | undefined = undefined;
  @Param commentPreview: boolean = false;
  @Event onOpenImage: (index: number) => void = (): void => {};
  @Local contentWidth: number = 320;
  private density: number = 1;

  aboutToAppear(): void {
    try {
      const screen: display.Display = display.getDefaultDisplaySync();
      this.density = screen.densityPixels;
      this.contentWidth = screen.width / screen.densityPixels - 32;
    } catch (_) { /* onAreaChange 提供实际内容宽度。 */ }
  }

  build() {
    Column({ space: 9 }) {
      ForEach(this.images, (image: ContentImage, index: number): void => {
        PostFlowImage({ image: image, contentWidth: this.contentWidth,
          imageIndex: this.startIndex + index, density: this.density,
          viewerIndex: this.viewerIndices[index] ?? -1, transitionGallery: this.transitionGallery,
          commentPreview: this.commentPreview,
          onOpen: (): void => { this.onOpenImage(this.startIndex + index); } })
      }, (image: ContentImage, index: number): string => `${index}:${image.imageUrl}`)
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .onAreaChange((_old: Area, area: Area): void => {
      const width: number = Number(area.width);
      if (width > 0 && Math.abs(width - this.contentWidth) > 0.5) { this.contentWidth = width; }
    })
  }
}
