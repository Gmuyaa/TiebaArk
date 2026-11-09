import { display } from '@kit.ArkUI';
import { AppTheme } from '../theme/Theme';
import {
  FeedImageBox, FeedImageInfo, feedImageBox, feedImageInfo, feedPreviewInfo, previewRowHeight,
  rememberMeasuredImage, PREVIEW_GAP, PREVIEW_RADIUS
} from '../model/HomeFeedPresentation';
import { LowFlowStore, lowFlowStore } from '../common/appearance/LowFlowStore';
import { ImageTransitionGallery, ImageTransitionSource, ImageTransitionTarget } from './ImageTransition';
import { ImageTransitionCrop, imageTransitionCrop } from '../model/ImageTransitionCrop';
import { ImageLayoutMode } from '../model/ImageLayout';
import { ReadingDecodeSize, readingImageInfo } from '../model/PostImageLayout';
import { ImageLayoutStore, imageLayoutStore } from '../common/appearance/ImageLayoutStore';
import {
  FeedImageTransform, modernFeedDecodeSize, modernFeedImageBox, modernFeedImageBoxForColumns,
  modernFeedImageGap, modernFeedImageTransform, modernFeedPreviewIndices, modernFeedTotalLabel
} from '../model/FeedImageLayout';

/** 首页与吧内列表共享的帖子图片预览；按图片数量选择单图或多图布局。 */

interface PreviewImageComplete {
  width: number;
  height: number;
  loadingStatus: number;
}

@ComponentV2
struct ThreadPreviewImage {
  @Local private sharedBindingEnabled: boolean = true;
  private imageTransition: ImageTransitionSource = new ImageTransitionSource((enabled: boolean): void => {
    this.sharedBindingEnabled = enabled;
  });
  @Require @Param url: string;
  @Param origin: string = '';
  /** 在本卡 `images` 里的下标（回报容器高度用） */
  @Param index: number = 0;
  @Param transitionGallery: ImageTransitionGallery | undefined = undefined;
  @Param contentWidth: number = 300;
  @Param multiple: boolean = false;
  @Param density: number = 1;
  @Event onOpen: () => void = (): void => {};

  @Event onBoxHeight: (index: number, height: number) => void = (_index: number, _height: number): void => {};
  @Local flow: LowFlowStore = lowFlowStore;
  @Local loaded: boolean = false;
  @Local failed: boolean = false;
  /** 本次加载确认到的实际源尺寸；空 = 还没加载出来，用缓存/占位框 */
  @Local actual: FeedImageInfo = new FeedImageInfo();
  private alive: boolean = false;
  private visible: boolean = false;
  private requestEpoch: number = 0;
  private unregisterReturn: () => void = (): void => {};

  aboutToAppear(): void {
    this.alive = true;
    this.invalidateRequest();
    this.registerReturnSource();
  }

  private invalidateRequest(): void {
    ++this.requestEpoch;
    this.imageTransition.invalidate();
    this.loaded = false;
    this.failed = false;
  }

  private originUrl(): string { return this.origin || feedImageInfo(this.url).origin || this.url; }

  private registerReturnSource(): void {
    this.unregisterReturn();
    this.unregisterReturn = (): void => {};
    if (!this.alive || this.transitionGallery === undefined) { return; }
    const url: string = this.url;
    const origin: string = this.originUrl();
    const index: number = this.index;
    this.unregisterReturn = this.transitionGallery.register(index, origin,
      (): ImageTransitionTarget | undefined => {
        if (!this.alive || !this.visible || this.flow.enabled || !this.loaded ||
          url !== this.url || origin !== this.originUrl() || index !== this.index ||
          !this.imageTransition.canOpenShared()) { return undefined; }
        return new ImageTransitionTarget(this.imageTransition, url, origin, 0);
      });
  }

  @Monitor('transitionGallery')
  onReturnGalleryChanged(): void {
    this.imageTransition.invalidate();
    this.registerReturnSource();
  }

  @Monitor('flow.enabled')
  onLowFlowChanged(): void { this.invalidateRequest(); }

  /**
   * URL 变了（列表项复用）＝ 换成另一张图：成功态、失败态与实测尺寸一律作废，
   * 否则上一张图的尺寸会串到新图片上。
   */
  @Monitor('url')
  onUrlChanged(): void {
    this.invalidateRequest();
    this.actual = new FeedImageInfo();
    this.registerReturnSource();
  }

  @Monitor('origin', 'index')
  onTransitionIdentityChanged(): void {
    this.imageTransition.invalidate();
    this.registerReturnSource();
  }

  aboutToDisappear(): void {
    this.unregisterReturn();
    this.unregisterReturn = (): void => {};
    this.alive = false;
    this.visible = false;
    this.invalidateRequest();
  }

  private frame(): FeedImageBox {
    return feedImageBox(feedPreviewInfo(this.url), this.contentWidth, this.multiple, this.density);
  }

  /**
   * 绘制方式：容器比例与**本次实际绘制的资源**比例不一致时 `Cover` 裁切填满，
   * 一致时沿用 `Contain`（此时两者等价，不会裁掉内容）。长图沿用既有 `Cover`。
   */
  private imageFit(frame: FeedImageBox): ImageFit {
    if (frame.long) { return ImageFit.Cover; }
    const drawn: FeedImageInfo = this.actual;
    if (!(drawn.width > 0) || !(drawn.height > 0)) { return ImageFit.Contain; }
    const boxRatio: number = frame.width / frame.height;
    const srcRatio: number = drawn.width / drawn.height;
    const drift: number = Math.abs(boxRatio - srcRatio) / Math.max(boxRatio, srcRatio);
    return drift > 0.05 ? ImageFit.Cover : ImageFit.Contain;
  }

  private applyLoaded(event: PreviewImageComplete | undefined): void {
    if (event === undefined || event.loadingStatus !== 1) { return; }
    if (!(event.width > 0) || !(event.height > 0)) { return; }
    const known: FeedImageInfo = feedImageInfo(this.url);
    const measured: FeedImageInfo = new FeedImageInfo();
    measured.width = event.width;
    measured.height = event.height;
    measured.long = known.long;
    measured.origin = known.origin;
    this.actual = measured;
    this.loaded = true;
    this.failed = false;
    // 复用已确认的尺寸：滚出再滚入直接从真实尺寸开始，不再从占位框起步
    rememberMeasuredImage(this.url, event.width, event.height, measured.long, measured.origin);
  }

  /**
   * 绑定这次加载的回调：只有**发起加载时的那条 URL 仍是当前 URL** 时才生效 ——
   * 列表项复用后旧图的迟到回调不能把尺寸/成功态写到新图上。
   */
  private completeHandler(url: string): (event?: PreviewImageComplete) => void {
    const request: number = this.requestEpoch;
    return (event?: PreviewImageComplete): void => {
      if (!this.alive || this.flow.enabled || request !== this.requestEpoch || url !== this.url) { return; }
      this.applyLoaded(event);
      this.registerReturnSource();
    };
  }

  private errorHandler(url: string): () => void {
    const request: number = this.requestEpoch;
    return (): void => {
      if (!this.alive || this.flow.enabled || request !== this.requestEpoch || url !== this.url) { return; }
      this.imageTransition.invalidate();
      this.failed = true;
      this.loaded = false;
    };
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        /*
         * 低流量模式（A-08）：**不渲染 `Image`** —— 不发起任何图片请求，只占位。
         * 占位仍可点（外层 onClick 不变），点开查看器照常加载原图。
         */
        if (this.flow.enabled) {
          Text('低流量模式 · 点按查看')
            .fontSize(12).fontColor(AppTheme.TEXT_SUB)
            .width('100%').height('100%').textAlign(TextAlign.Center)
        } else {
          if (!this.loaded) {
            Text(this.failed ? '图片加载失败' : '图片加载中…')
              .fontSize(12).fontColor(AppTheme.TEXT_SUB)
              .width('100%').height('100%').textAlign(TextAlign.Center)
          }
          Image(this.url)
            // 共享转场临时改变外框尺寸时，内容必须跟随外框；固定vp会留下向左上角漂移的小图。
            .width('100%')
            .height('100%')
            .objectFit(this.imageFit(this.frame()))
            .objectRepeat(ImageRepeat.NoRepeat)
            .opacity(this.loaded ? 1 : 0)
            .onComplete(this.completeHandler(this.url))
            .onError(this.errorHandler(this.url))
        }
        if (this.frame().long) {
          Text('长图').fontSize(11).fontColor(Color.White)
            .backgroundColor('#88000000').borderRadius(5).padding(4).margin(8)
        }
      }
      // 外框与内部图片取同一份布局结果：图片多高，占位就多高，不留失效的占位高度
      .width(this.frame().width)
      .height(this.frame().height)
      .backgroundColor(this.loaded ? Color.Transparent : AppTheme.SURFACE_MUTED)
      .borderRadius(PREVIEW_RADIUS).clip(true)
      .geometryTransition(this.sharedBindingEnabled ? this.imageTransition.id(this.url) : '', { follow: true })
      .renderFit(RenderFit.RESIZE_FILL)
      .onClick(() => {
        this.imageTransition.open(this.getUIContext(), this.url,
          this.originUrl(), (): void => { this.onOpen(); }, 0,
          !this.flow.enabled && this.loaded, undefined, undefined, undefined,
          this.transitionGallery, this.index);
      })
    }.width(this.frame().width).height(this.frame().height)
      // 父容器不参加共享几何，返回资格始终按原卡片位置判断。
      .onVisibleAreaChange([0], (visible: boolean): void => { this.visible = visible; })
      .onAreaChange((_old: Area, area: Area): void => {
        const height: number = Number(area.height);
        if (height > 0) { this.onBoxHeight(this.index, height); }
      })
  }
}

/** 仅新版使用独立渲染器，旧版尺寸、横向滚动与回调保持原样。 */
/** 首页方阵瓦片：等大方格 + 共享转场；评论多图也复用这套，见 ThreadDetail。 */
@ComponentV2
export struct ModernThreadPreviewImage {
  @Local private sharedBindingEnabled: boolean = true;
  private imageTransition: ImageTransitionSource = new ImageTransitionSource((enabled: boolean): void => {
    this.sharedBindingEnabled = enabled;
  });
  @Require @Param url: string;
  @Param origin: string = '';
  @Param index: number = 0;
  @Param transitionGallery: ImageTransitionGallery | undefined = undefined;
  @Param total: number = 1;
  /** 显式列数；0 = 按预览张数推导。正文方阵铺开全部图片时由调用方给出（4 张两列）。 */
  @Param columns: number = 0;
  @Param contentWidth: number = 300;
  @Param density: number = 1;
  /** 全部图片已经铺开时不必再用「共 N 张」收口（正文方格全量模式） */
  @Param showTotalLabel: boolean = true;
  @Event onOpen: () => void = (): void => {};
  @Local flow: LowFlowStore = lowFlowStore;
  @Local loaded: boolean = false;
  @Local failed: boolean = false;
  @Local actual: FeedImageInfo = new FeedImageInfo();
  private alive: boolean = false;
  private visible: boolean = false;
  private unregisterReturn: () => void = (): void => {};
  private requestEpoch: number = 0;
  @Local private sharedExpanded: boolean = false;
  @Local private sharedCrop: ImageTransitionCrop | undefined = undefined;
  private transitionEpoch: number = 0;

  aboutToAppear(): void {
    this.alive = true;
    this.invalidateRequest();
    this.registerReturnSource();
  }

  aboutToDisappear(): void {
    this.unregisterReturn();
    this.unregisterReturn = (): void => {};
    this.visible = false;
    this.alive = false;
    ++this.requestEpoch;
    this.resetSharedCrop();
  }

  private invalidateRequest(): void {
    this.resetSharedCrop();
    ++this.requestEpoch;
    this.loaded = false;
    this.failed = false;
  }

  @Monitor('url')
  onUrlChanged(): void {
    this.invalidateRequest();
    this.actual = new FeedImageInfo();
    this.registerReturnSource();
  }

  @Monitor('origin', 'index')
  onTransitionIdentityChanged(): void {
    this.resetSharedCrop();
    this.registerReturnSource();
  }

  @Monitor('transitionGallery')
  onReturnGalleryChanged(): void {
    this.resetSharedCrop();
    this.registerReturnSource();
  }

  private originUrl(): string { return this.origin || feedImageInfo(this.url).origin || this.url; }

  private registerReturnSource(): void {
    this.unregisterReturn();
    this.unregisterReturn = (): void => {};
    if (!this.alive || this.transitionGallery === undefined) { return; }
    const url: string = this.url;
    const origin: string = this.originUrl();
    const index: number = this.index;
    this.unregisterReturn = this.transitionGallery.register(index, origin,
      (): ImageTransitionTarget | undefined => { return this.prepareReturnTarget(url, origin, index); });
  }

  private prepareReturnTarget(url: string, origin: string, index: number): ImageTransitionTarget | undefined {
    if (!this.alive || !this.visible || this.flow.enabled || !this.loaded || url !== this.url ||
      origin !== this.originUrl() || index !== this.index || !this.imageTransition.canOpenShared()) { return undefined; }
    const crop: ImageTransitionCrop | undefined = this.usesCropTransition()
      ? imageTransitionCrop(this.drawing()) : undefined;
    if (crop !== undefined && !crop.usable) { return undefined; }
    const request: number = this.requestEpoch;
    // 换代后，起始图的旧 release 回调不能清掉此返回目标的裁切快照。
    const token: number = ++this.transitionEpoch;
    this.sharedExpanded = false;
    this.sharedCrop = crop;
    return new ImageTransitionTarget(this.imageTransition, url, origin, index, crop,
      (expanded: boolean): void => {
        if (token !== this.transitionEpoch || index !== this.index || !this.acceptsRequest(url, request)) { return; }
        this.sharedExpanded = expanded;
      }, (): void => {
        if (token !== this.transitionEpoch || !this.alive) { return; }
        this.sharedExpanded = false;
        this.sharedCrop = undefined;
      });
  }

  @Monitor('flow.enabled')
  onLowFlowChanged(): void {
    // 移除/重建 Image 都使旧请求失效；保留已知尺寸，不保留旧请求的成功或失败态。
    this.invalidateRequest();
  }

  private acceptsRequest(url: string, epoch: number): boolean {
    return this.alive && !this.flow.enabled && url.length > 0 && url === this.url && epoch === this.requestEpoch;
  }

  private afterRender(url: string, epoch: number, apply: () => void): void {
    // 缓存命中时 Image 回调可能同步发生在构建中；状态更新必须离开当前渲染栈。
    void Promise.resolve().then((): void => {
      if (!this.acceptsRequest(url, epoch)) { return; }
      this.getUIContext().runScopedTask((): void => {
        if (this.acceptsRequest(url, epoch)) { apply(); }
      });
    });
  }

  private info(): FeedImageInfo {
    const actual: FeedImageInfo = this.actual.width > 0 && this.actual.height > 0 ? this.actual : feedImageInfo(this.url);
    return readingImageInfo(feedPreviewInfo(this.url), actual);
  }

  private frame(): FeedImageBox {
    if (this.columns > 0) {
      return modernFeedImageBoxForColumns(this.info(), this.contentWidth, this.columns, this.density);
    }
    return modernFeedImageBox(this.info(), this.contentWidth, this.total, this.density);
  }

  private drawing(): FeedImageTransform {
    // 单图外框已是完整图片比例；明确使用单位变换，避免浮点微小偏移使共享配对失效。
    if (this.total < 2) { return new FeedImageTransform(); }
    return modernFeedImageTransform(this.info(), this.frame(), this.density);
  }

  private resetSharedCrop(): void {
    ++this.transitionEpoch;
    this.imageTransition.invalidate();
    this.sharedExpanded = false;
    this.sharedCrop = undefined;
  }

  /** 多图同步裁切；单张长图以单位变换保留同源预览交接，实际只有共享缩放。 */
  private usesCropTransition(): boolean {
    return this.total > 1 || this.frame().long;
  }

  private cropForDrawing(): ImageTransitionCrop | undefined {
    if (!this.usesCropTransition()) { return undefined; }
    return this.sharedCrop !== undefined ? this.sharedCrop : imageTransitionCrop(this.drawing());
  }

  /** 裁切改写成单锚点等比缩放；静态预览像素位置与原 scale + translate 等价。 */
  private imageScale(): ScaleOptions {
    const crop: ImageTransitionCrop | undefined = this.cropForDrawing();
    if (crop !== undefined && crop.usable) {
      const scale: number = this.sharedExpanded ? 1 : crop.scale;
      return { x: scale, y: scale, centerX: crop.centerX, centerY: crop.centerY };
    }
    const drawing: FeedImageTransform = this.drawing();
    return { x: drawing.scale, y: drawing.scale, centerX: 0, centerY: 0 };
  }

  private imageTranslation(): TranslateOptions {
    const crop: ImageTransitionCrop | undefined = this.cropForDrawing();
    if (crop !== undefined && crop.usable) { return { x: 0, y: 0 }; }
    return { x: this.imageX(), y: this.imageY() };
  }

  private openImage(): void {
    const ready: boolean = !this.flow.enabled && this.loaded;
    const crop: ImageTransitionCrop | undefined = ready && this.usesCropTransition()
      ? imageTransitionCrop(this.drawing()) : undefined;
    const url: string = this.url;
    const index: number = this.index;
    const request: number = this.requestEpoch;
    const token: number = ++this.transitionEpoch;
    this.sharedExpanded = false;
    this.sharedCrop = crop !== undefined && crop.usable ? crop : undefined;
    this.imageTransition.open(this.getUIContext(), url,
      this.originUrl(), (): void => { this.onOpen(); }, index, ready, crop,
      (expanded: boolean): void => {
        if (token !== this.transitionEpoch || index !== this.index || !this.acceptsRequest(url, request)) { return; }
        this.sharedExpanded = expanded;
      }, (): void => {
        if (token !== this.transitionEpoch || !this.alive) { return; }
        this.sharedExpanded = false;
        this.sharedCrop = undefined;
      }, this.transitionGallery, index);
  }

  // 完整单图与无法安全转为单锚点的极端参数，沿比例一致的绘制方式。
  private imageX(): string { return `${this.drawing().xPercent}%`; }
  private imageY(): string { return `${this.drawing().yPercent}%`; }

  private decodeSize(): ImageSourceSize | undefined {
    const pixels: ReadingDecodeSize | undefined = modernFeedDecodeSize(this.info(), this.frame(), this.density);
    if (pixels === undefined) { return undefined; }
    const ui: UIContext = this.getUIContext();
    // ImageSourceSize 的数值单位为 vp；模型的源尺寸和解码预算统一使用 px。
    return { width: ui.px2vp(pixels.width), height: ui.px2vp(pixels.height) };
  }

  private completeHandler(url: string, epoch: number): (event?: PreviewImageComplete) => void {
    return (event?: PreviewImageComplete): void => {
      if (!this.acceptsRequest(url, epoch) || event === undefined ||
        (event.loadingStatus !== 0 && event.loadingStatus !== 1) ||
        !Number.isFinite(event.width) || !Number.isFinite(event.height) || event.width <= 0 || event.height <= 0) { return; }
      const width: number = event.width;
      const height: number = event.height;
      const status: number = event.loadingStatus;
      this.afterRender(url, epoch, (): void => {
        // 数据加载时先校正源比例和解码目标；后续解码回调不覆盖已确认的源尺寸。
        if (status === 0 || this.actual.width <= 0 || this.actual.height <= 0) {
          const known: FeedImageInfo = feedImageInfo(url);
          const measured: FeedImageInfo = new FeedImageInfo();
          measured.width = width;
          measured.height = height;
          measured.long = known.long;
          measured.origin = known.origin;
          this.actual = measured;
          rememberMeasuredImage(url, measured.width, measured.height, measured.long, measured.origin);
        }
        if (status === 1) {
          this.loaded = true;
          this.failed = false;
          this.registerReturnSource();
        }
      });
    };
  }

  private errorHandler(url: string, epoch: number): () => void {
    return (): void => {
      if (!this.acceptsRequest(url, epoch)) { return; }
      this.afterRender(url, epoch, (): void => {
        this.resetSharedCrop();
        this.failed = true;
        this.loaded = false;
      });
    };
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.flow.enabled) {
          Text('低流量模式 · 点按查看')
            .fontSize(12).fontColor(AppTheme.TEXT_SUB)
            .width('100%').height('100%').textAlign(TextAlign.Center)
        } else {
          if (!this.loaded) {
            Text(this.failed ? '图片加载失败' : '图片加载中…')
              .fontSize(12).fontColor(AppTheme.TEXT_SUB)
              .width('100%').height('100%').textAlign(TextAlign.Center)
          }
          Image(this.url)
            .width('100%').height('100%')
            .objectFit(ImageFit.Contain).objectRepeat(ImageRepeat.NoRepeat)
            .autoResize(true)
            .sourceSize(this.decodeSize())
            .scale(this.imageScale())
            .translate(this.imageTranslation())
            .hitTestBehavior(HitTestMode.None)
            .opacity(this.loaded ? 1 : 0)
            .onComplete(this.completeHandler(this.url, this.requestEpoch))
            .onError(this.errorHandler(this.url, this.requestEpoch))
        }
        // 极长单图完整缩小后可能很窄，角标放不下时省略，避免被裁成半个字。
        if (this.frame().long && (this.total > 1 || this.frame().width >= 56)) {
          Text('长图').fontSize(11).fontColor(Color.White)
            .backgroundColor('#88000000').borderRadius(5).padding(4).margin(8)
        }
        if (this.showTotalLabel && modernFeedTotalLabel(this.total, this.index).length > 0) {
          Row() {
            Text(modernFeedTotalLabel(this.total, this.index)).fontSize(11).fontColor(Color.White)
              .backgroundColor('#88000000').borderRadius(5).padding(4)
          }.width('100%').height('100%').justifyContent(FlexAlign.End)
            .alignItems(VerticalAlign.Bottom).padding(8)
        }
      }
      .width(this.frame().width).height(this.frame().height)
      // 已加载的共享节点保持透明，避免占位底随转场放大到查看器留白。
      .backgroundColor(this.loaded ? Color.Transparent : AppTheme.SURFACE_MUTED)
      .borderRadius(PREVIEW_RADIUS).clip(true)
      .geometryTransition(this.sharedBindingEnabled ? this.imageTransition.id(this.url, this.index) : '', { follow: true })
      .renderFit(RenderFit.RESIZE_FILL)
      .accessibilityText(`${this.frame().long ? '长图，' : ''}第 ${this.index + 1} 张图片，共 ${this.total} 张`)
      .onClick(() => { this.openImage(); })
    }.width(this.frame().width).height(this.frame().height)
      .onVisibleAreaChange([0], (visible: boolean): void => { this.visible = visible; })
  }
}

@ComponentV2
export struct ThreadPreviewImages {
  @Require @Param images: string[];
  /** 个人主页等入口直接提供的原图序列；其余入口沿用现有图片元数据。 */
  @Param originImages: string[] = [];
  /** 只由首页与吧内列表开启；其他复用入口继续使用旧版。 */
  @Param useImageLayoutPreference: boolean = false;
  @Local imageLayout: ImageLayoutStore = imageLayoutStore;
  @Require @Param scroller: ListScroller;
  @Event onOpenImage: (index: number) => void = (_index: number): void => {};
  @Local contentWidth: number = 300;
  /**
   * 每张图容器的**实测高度**（vp），由子组件回报 —— 多图整行高度取其中的最大值
   * （`previewRowHeight`）。空数组 = 一张都还没量到，用占位行高。
   */
  @Local boxHeights: number[] = [];
  private density: number = 1;
  private transitionGallery: ImageTransitionGallery = new ImageTransitionGallery();

  aboutToAppear(): void {
    // 启动时的粗算；真实宽度由根节点的 onAreaChange 校正（横竖屏、分屏都会变）
    try {
      const screen: display.Display = display.getDefaultDisplaySync();
      this.density = screen.densityPixels;
      this.contentWidth = screen.width / this.density - 44;
    } catch (err) { /* 后续通过区域宽度校正。 */ }
  }

  aboutToDisappear(): void { this.transitionGallery.dispose(); }

  /** 多图整行高度：贴合内容（上限 PREVIEW_ROW_H），见 `previewRowHeight` */
  private rowHeight(): number {
    return previewRowHeight(this.boxHeights);
  }

  /**
   * 子组件回报容器高度。**只在真的变了才写状态**（半 vp 容差）——
   * 否则每次布局都触发一轮父组件重绘。
   */
  private reportBoxHeight(index: number, height: number): void {
    if (index < 0 || index >= this.images.length) { return; }
    const next: number[] = this.boxHeights.slice();
    while (next.length < this.images.length) { next.push(0); }
    if (Math.abs(next[index] - height) < 0.5) { return; }
    next[index] = height;
    this.boxHeights = next;
  }

  build() {
    Column() {
      if (this.useImageLayoutPreference && this.imageLayout.mode === ImageLayoutMode.MODERN) {
        Row({ space: modernFeedImageGap(this.contentWidth, this.images.length) }) {
          ForEach(modernFeedPreviewIndices(this.images.length), (index: number) => {
            ModernThreadPreviewImage({ url: this.images[index], origin: this.originImages[index] || '',
              index: index, total: this.images.length, contentWidth: this.contentWidth, density: this.density,
              transitionGallery: this.transitionGallery,
              onOpen: (): void => { this.onOpenImage(index); } })
          }, (index: number) => `${index}:${this.images[index]}`)
        }.width('100%').alignItems(VerticalAlign.Top)
      } else if (this.images.length === 1) {
        ThreadPreviewImage({ url: this.images[0], index: 0, contentWidth: this.contentWidth,
          transitionGallery: this.transitionGallery,
          origin: this.originImages[0] || '',
          density: this.density,
          onBoxHeight: (index: number, height: number): void => { this.reportBoxHeight(index, height); },
          onOpen: (): void => { this.onOpenImage(0); } })
      } else if (this.images.length > 1) {
        List({ space: PREVIEW_GAP, scroller: this.scroller }) {
          ForEach(this.images, (url: string, index: number) => {
            ListItem() {
              ThreadPreviewImage({ url: url, index: index, contentWidth: this.contentWidth,
                transitionGallery: this.transitionGallery,
                origin: this.originImages[index] || '',
                density: this.density, multiple: true,
                onBoxHeight: (i: number, height: number): void => { this.reportBoxHeight(i, height); },
                onOpen: (): void => { this.onOpenImage(index); } })
            }.height(this.rowHeight())
          }, (url: string, index: number) => `${index}:${url}`)
        }
        .listDirection(Axis.Horizontal).scrollBar(BarState.Off)
        .scrollSnapAlign(ScrollSnapAlign.START).edgeEffect(EdgeEffect.None)
        .width('100%').height(this.rowHeight())
        .alignListItem(ListItemAlign.Start)
        .nestedScroll({ scrollForward: NestedScrollMode.SELF_ONLY, scrollBackward: NestedScrollMode.SELF_ONLY })
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .onAreaChange((_old: Area, area: Area) => {
      const width: number = Number(area.width);
      if (width > 0 && Math.abs(width - this.contentWidth) > 0.5) { this.contentWidth = width; }
    })
  }
}
