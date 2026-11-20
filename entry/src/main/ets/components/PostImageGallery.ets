/** 正文图片按连续区段组成横向图集。单图按实际宽高比展示，多图共享图集状态。 */

import { display } from '@kit.ArkUI';
import { AppTheme } from '../theme/Theme';
import { ContentImage, galleryAspectRatio } from '../model/ThreadDetail';
import {
  BODY_RADIUS, FeedImageBox, FeedImageInfo, bodySingleImageBox, feedImageInfo, rememberMeasuredImage
} from '../model/HomeFeedPresentation';
import { ImageLoadStore, imageLoadStore } from '../common/appearance/ImageLoadStore';
import { ImageLoadPolicy, ImageQuality, bodyImageSource, bodyTransitionKey } from '../model/ImageLoadPolicy';
import { ImageTransitionGallery, ImageTransitionSource, ImageTransitionTarget } from './ImageTransition';

/** 详情页内容区左右各留 16vp */
const PAGE_SIDE_PADDING: number = 32;

const PAGE_GAP: number = 8;

/** 单张图的加载态；0 也用于"这张图还没轮到加载" */
const IMAGE_LOADING: number = 0;
const IMAGE_LOADED: number = 1;
const IMAGE_FAILED: number = 2;

/** `Image.onComplete` 里我们用到的那部分（与图片预览组件同一口径） */
interface GalleryImageComplete {
  width: number;
  height: number;
  loadingStatus: number;
}

/**
 * 首帧的图集宽度估计（vp）：屏宽 − 页面左右留白。`boxWidth` 要靠 `onAreaChange` 才拿到实测宽度，
 * 而 `List` 回收复用会让组件重建、宽度回到初值 —— 初值给常数的话每次滚过图集都要"先塌后撑"跳一下。
 */
function estimateGalleryWidth(): number {
  try {
    const info: display.Display = display.getDefaultDisplaySync();
    const width: number = info.width / info.densityPixels - PAGE_SIDE_PADDING;
    return width > 0 ? width : 240;
  } catch (err) {
    // 拿不到屏幕信息不该让图集渲染失败，退回固定值由 onAreaChange 校正
    return 240;
  }
}

@ComponentV2
export struct PostImageGallery {
  @Local private sharedBindingEnabled: boolean = true;
  private imageTransition: ImageTransitionSource = new ImageTransitionSource((enabled: boolean): void => {
    this.sharedBindingEnabled = enabled;
  });
  private transitionIdentity: string = '';
  private alive: boolean = false;
  private visible: boolean = false;
  private visiblePages: Set<number> = new Set<number>();
  private unregisterReturns: (() => void)[] = [];
  private requestEpoch: number = 0;
  @Local imageLoad: ImageLoadStore = imageLoadStore;
  @Local private policy: ImageLoadPolicy = imageLoadStore.currentPolicy();
  /** 本图集的图片，至少 1 张 */
  @Require @Param images: ContentImage[];
  /** 本图集第一张图在整篇内容图片序列里的下标，用来换算全屏查看器的初始页 */
  @Param startIndex: number = 0;
  @Param viewerIndices: number[] = [];
  @Param transitionGallery: ImageTransitionGallery | undefined = undefined;
  /** 懒加载组件重建时恢复的图集页码，仅初次布局使用。 */
  @Param initialPage: number = 0;
  /**
   * 调用方已知的可用宽度（vp）。>0 时用它作首帧宽度：评论正文左侧有头像列，按屏宽算会宽出 48vp，
   * 首帧撑高、`onAreaChange` 修正后塌回去，列表就"跳一下"。0 = 调用方不知道，沿用估算。
   */
  @Param widthHint: number = 0;
  @Event onPageChange: (page: number) => void = (): void => {};
  /** 点击某张图：回传它在整篇内容图片序列里的下标 */
  @Event onOpenImage: (globalIndex: number) => void = (): void => {};

  /** 当前显示页；父页面仅保存离屏重建所需的页码，不参与逐帧滚动。 */
  @Local page: number = 0;
  /**
   * 本图集实测宽度（vp），用来把高度算成 `宽 ÷ 比例`。不用 `.width('100%') + 平台自适应`：
   * 在这条容器链路（`List` item → `Column` → 图集）里"父宽定子高"不可靠，显式算才可控。初值用屏宽推算。
   */
  @Local boxWidth: number = estimateGalleryWidth();
  /**
   * 单图本次加载确认到的实际尺寸（px）。只给单图用：多图若把实测值并进组平均比例，翻页时高度会跟着变。
   */
  @Local actual: FeedImageInfo = new FeedImageInfo();
  /** 与 `actual` 配对的 URL；对不上说明这张图已经换了，尺寸作废（列表项复用防护） */
  @Local actualUrl: string = '';
  /** 每一页的加载态，与 `stateUrls` 一一对应 */
  @Local states: number[] = [];
  /** `states` 对应的 URL；对不上按"未加载"处理，旧图的迟到回调不会把新图标成已加载 */
  @Local stateUrls: string[] = [];

  /** 小图放大限制要按屏幕密度换算原像素 → vp */
  private density: number = 1;

  aboutToAppear(): void {
    this.alive = true;
    this.policy = this.imageLoad.currentPolicy();
    // 调用方给的宽度比按屏宽估算更准，先落位，避免首帧"先撑高再塌回"
    if (this.widthHint > 0) { this.boxWidth = this.widthHint; }
    this.invalidateRequest();
    this.transitionIdentity = this.currentTransitionIdentity();
    this.page = this.boundedInitialPage();
    try {
      this.density = display.getDefaultDisplaySync().densityPixels;
    } catch (err) {
      // 拿不到密度就用 1：小图限制放宽，但不会让容器算不出来
    }
    this.registerReturnSources();
  }

  private isOff(): boolean { return this.policy.quality === ImageQuality.OFF; }

  aboutToDisappear(): void {
    this.clearReturnSources();
    this.alive = false;
    this.visible = false;
    this.visiblePages.clear();
    this.invalidateRequest();
  }

  private invalidateRequest(): void {
    ++this.requestEpoch;
    this.states = [];
    this.stateUrls = [];
    this.imageTransition.invalidate();
  }

  @Monitor('imageLoad.revision')
  onPolicyChanged(): void {
    const prevOff: boolean = this.isOff();
    const prevUrls: string[] = [];
    for (let i: number = 0; i < this.images.length; i++) {
      prevUrls.push(this.urlOf(i));
    }
    this.policy = this.imageLoad.currentPolicy();
    let changed: boolean = prevOff !== this.isOff();
    if (!changed) {
      for (let i: number = 0; i < this.images.length; i++) {
        if (prevUrls[i] !== this.urlOf(i)) {
          changed = true;
          break;
        }
      }
    }
    if (changed) {
      this.invalidateRequest();
      this.registerReturnSources();
    }
  }

  private currentTransitionIdentity(): string {
    const urls: string[] = [];
    for (const img of this.images) { urls.push(img.imageUrl, img.originImageUrl); }
    return `${this.startIndex}:${JSON.stringify(urls)}:${JSON.stringify(this.viewerIndices)}`;
  }

  @Monitor('images', 'startIndex', 'viewerIndices')
  onTransitionIdentityChanged(): void {
    const identity: string = this.currentTransitionIdentity();
    if (identity === this.transitionIdentity) { return; }
    this.transitionIdentity = identity;
    this.imageTransition.invalidate();
    this.registerReturnSources();
  }

  @Monitor('transitionGallery')
  onReturnGalleryChanged(): void {
    this.imageTransition.invalidate();
    this.registerReturnSources();
  }

  private clearReturnSources(): void {
    for (const unregister of this.unregisterReturns) { unregister(); }
    this.unregisterReturns = [];
  }

  private registerReturnSources(): void {
    this.clearReturnSources();
    if (!this.alive || this.transitionGallery === undefined) { return; }
    const identity: string = this.currentTransitionIdentity();
    for (let index: number = 0; index < this.images.length; index++) {
      const viewerIndex: number = this.viewerIndices[index] ?? -1;
      if (viewerIndex < 0) { continue; }
      const preview: string = this.urlOf(index);
      const origin: string = bodyTransitionKey(this.images[index]);
      this.unregisterReturns.push(this.transitionGallery.register(viewerIndex, origin,
        (): ImageTransitionTarget | undefined => {
          if (!this.alive || !this.visible || this.isOff() ||
            identity !== this.currentTransitionIdentity() || this.stateOf(index) !== IMAGE_LOADED ||
            (this.images.length > 1 && !this.visiblePages.has(index)) || !this.imageTransition.canOpenShared()) {
            return undefined;
          }
          return new ImageTransitionTarget(this.imageTransition, preview, origin, index);
        }));
    }
  }

  private pageVisibilityChanged(index: number, visible: boolean): void {
    if (visible) { this.visiblePages.add(index); } else { this.visiblePages.delete(index); }
  }

  private boundedInitialPage(): number {
    if (!Number.isFinite(this.initialPage)) { return 0; }
    return Math.max(0, Math.min(this.images.length - 1, Math.floor(this.initialPage)));
  }

  private urlOf(index: number): string {
    return index >= 0 && index < this.images.length ? bodyImageSource(this.images[index], false, this.policy) : '';
  }

  private stateOf(index: number): number {
    if (index < 0 || index >= this.states.length || index >= this.stateUrls.length) {
      return IMAGE_LOADING;
    }
    return this.stateUrls[index] === this.urlOf(index) ? this.states[index] : IMAGE_LOADING;
  }

  /** 记一页的加载态。数组整体替换，V2 才能观察到变化 */
  private markState(index: number, state: number): void {
    const urls: string[] = this.stateUrls.slice();
    const states: number[] = this.states.slice();
    while (urls.length <= index) {
      urls.push('');
      states.push(IMAGE_LOADING);
    }
    urls[index] = this.urlOf(index);
    states[index] = state;
    this.stateUrls = urls;
    this.states = states;
  }

  /**
   * 单图的尺寸真值：已确认的实际尺寸 > 服务端声明尺寸 > 空。实际尺寸优先是刻意的 ——
   * 屏幕上画的就是实际加载到的那份资源，服务端 `ContentImage.width/height` 描述的是原图，比例不一致时按声明排版会留白。
   */
  private sourceInfo(): FeedImageInfo {
    if (this.images.length === 0) { return new FeedImageInfo(); }
    const img: ContentImage = this.images[0];
    const remembered: FeedImageInfo = feedImageInfo(img.imageUrl);
    if (remembered.width > 0 && remembered.height > 0) { return remembered; }
    const declared: FeedImageInfo = new FeedImageInfo();
    declared.width = img.width;
    declared.height = img.height;
    declared.origin = img.originImageUrl;
    return declared;
  }

  /** 正文单图的容器：外框与里面的图片**只从这一份结果取值** */
  private frame(): FeedImageBox {
    const url: string = this.urlOf(0);
    const source: FeedImageInfo =
      (this.actualUrl === url && this.actual.width > 0) ? this.actual : this.sourceInfo();
    return bodySingleImageBox(source, this.boxWidth, this.density);
  }

  /**
   * 容器高度（vp）：单图 = 贴合图片的容器高度，多图 = 实测宽 ÷ 组内平均比例。
   * 多图不需要任何"上方内容高度"补偿 —— 那套补偿是 `Swiper` 时代的误判，换成横向 `List` 后下发多少就渲染多少，
   * 加上反而把图集撑高、把内容顶到屏幕外。
   */
  private issuedHeight(): number {
    if (this.images.length === 1) { return this.frame().height; }
    return this.boxWidth > 0 ? this.boxWidth / galleryAspectRatio(this.images) : 240;
  }

  /**
   * 绑定这次加载的回调：只有发起加载时那条 URL 仍是那张图时才生效 —— 列表项复用后旧图的迟到回调不能写到新图上。
   */
  private completeHandler(index: number, url: string): (event?: GalleryImageComplete) => void {
    const request: number = this.requestEpoch;
    return (event?: GalleryImageComplete): void => {
      if (!this.alive || this.isOff() || request !== this.requestEpoch ||
        url.length === 0 || url !== this.urlOf(index)) { return; }
      if (event === undefined || event.loadingStatus !== 1) { return; }
      if (!(event.width > 0) || !(event.height > 0)) { return; }
      const origin: string = this.sourceInfo().origin;
      if (this.images.length === 1) {
        const measured: FeedImageInfo = new FeedImageInfo();
        measured.width = event.width;
        measured.height = event.height;
        measured.origin = origin;
        this.actual = measured;
        this.actualUrl = url;
      }
      this.markState(index, IMAGE_LOADED);
      // 与列表预览共用同一个按 URL 键控的缓存：滚出再滚入、或正文与列表出现同一张图时
      // 都直接从确认过的尺寸开始，不再从占位框起步
      rememberMeasuredImage(url, event.width, event.height, false, origin);
    };
  }

  private errorHandler(index: number, url: string): () => void {
    const request: number = this.requestEpoch;
    return (): void => {
      if (!this.alive || this.isOff() || request !== this.requestEpoch || url !== this.urlOf(index)) { return; }
      this.markState(index, IMAGE_FAILED);
    };
  }

  /**
   * 正文单图：容器贴合图片最终显示尺寸，不用模糊背景撑满一个偏大的框。
   * 长图不裁切，靠 `bodySingleImageBox` 的高度上限等比收缩。
   */
  @Builder
  SingleImage(img: ContentImage) {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.isOff()) {
        Text('点按查看图片')
          .fontSize(12).fontColor(AppTheme.TEXT_SUB)
          .width('100%').height('100%').textAlign(TextAlign.Center)
      } else {
        if (this.stateOf(0) !== IMAGE_LOADED) {
          Text(this.stateOf(0) === IMAGE_FAILED ? '图片加载失败' : '图片加载中…')
            .fontSize(12).fontColor(AppTheme.TEXT_SUB)
            .width('100%').height('100%').textAlign(TextAlign.Center)
        }
        if (this.urlOf(0).length > 0) {
          ForEach([this.urlOf(0)], (src: string) => {
            Image(src)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
              .objectRepeat(ImageRepeat.NoRepeat)
              .opacity(this.stateOf(0) === IMAGE_LOADED ? 1 : 0)
              .onComplete(this.completeHandler(0, src))
              .onError(this.errorHandler(0, src))
          }, (src: string) => src)
        }
      }
    }
    // 外框与内部图片取同一份布局结果：图片多高，容器就多高，不留失效的占位高度
    .width(this.frame().width)
    .height(this.frame().height)
    .backgroundColor(this.stateOf(0) === IMAGE_LOADED ? Color.Transparent : AppTheme.SURFACE_MUTED)
    .borderRadius(BODY_RADIUS)
    .clip(true)
    .geometryTransition(this.sharedBindingEnabled && this.urlOf(0).length > 0
      ? this.imageTransition.id(this.urlOf(0)) : '', { follow: true })
    .renderFit(RenderFit.RESIZE_FILL)
    .onClick(() => {
      this.imageTransition.open(this.getUIContext(), this.urlOf(0), bodyTransitionKey(img),
        (): void => { this.onOpenImage(this.startIndex); }, 0,
        !this.isOff() && this.stateOf(0) === IMAGE_LOADED, undefined, undefined, undefined,
        this.transitionGallery, this.viewerIndices[0] ?? -1);
    })
  }

  /**
   * 图集里的一页：一屏一张，宽度取实测内容宽，高度由 `aspectRatio(组比例)` 自己撑开；单张比例不同时保持 `Contain`，
   * 不能为填满容器裁掉正文图片（底层用同图 `Cover` + 模糊延展补边）。
   *
   * 必须 `flexShrink(0)`：缩放祖先里有 `List`/`Row` 时子项会被压缩，`aspectRatio` 一起失效、一屏露出两张图。
   */
  @Builder
  GalleryPage(img: ContentImage, index: number) {
    Stack() {
      if (this.isOff()) {
        Text('点按查看图片')
          .fontSize(12).fontColor(AppTheme.TEXT_SUB)
          .width('100%').height('100%').textAlign(TextAlign.Center)
      } else {
        if (this.urlOf(index).length > 0) {
          ForEach([this.urlOf(index)], (src: string) => {
            Stack() {
              // 只是补满比例差的背景，不影响前景原图的完整展示。
              Image(src)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
                .blur(24)
                .opacity(0.72)
              Image(src)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Contain)
                .onComplete(this.completeHandler(index, src))
                .onError(this.errorHandler(index, src))
            }.width('100%').height('100%')
          }, (src: string) => src)
        }
        if (this.stateOf(index) === IMAGE_FAILED) {
          Text('图片加载失败')
            .fontSize(12).fontColor(AppTheme.TEXT_SUB)
            .width('100%').height('100%').textAlign(TextAlign.Center)
        }
      }
    }
      .width(this.boxWidth)
      .aspectRatio(galleryAspectRatio(this.images))
      // 加载完成前铺一层底色，免得图集位置是透明洞；加载后转透明。
      .backgroundColor(this.stateOf(index) === IMAGE_LOADED ? Color.Transparent : AppTheme.SURFACE_MUTED)
      .borderRadius(BODY_RADIUS)
      .clip(true)
      .flexShrink(0)
      .geometryTransition(this.sharedBindingEnabled && this.urlOf(index).length > 0
        ? this.imageTransition.id(this.urlOf(index), index) : '', { follow: true })
      .renderFit(RenderFit.RESIZE_FILL)
      .onClick(() => {
        this.imageTransition.open(this.getUIContext(), this.urlOf(index), bodyTransitionKey(img),
          (): void => { this.onOpenImage(this.startIndex + index); }, index,
          !this.isOff() && this.stateOf(index) === IMAGE_LOADED, undefined, undefined, undefined,
          this.transitionGallery, this.viewerIndices[index] ?? -1);
      })
  }

  /** 多图时右下角显示"当前页 / 总数"，与全屏查看器的计数口径一致 */
  @Builder
  PageBadge() {
    if (this.images.length > 1) {
      Text(`${this.page + 1} / ${this.images.length}`)
        .fontSize(12)
        .fontColor(Color.White)
        .backgroundColor('#66000000')
        .borderRadius(9)
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .margin({ right: 10, bottom: 10 })
    }
  }

  build() {
    // 单图容器贴合图片、从左上角开始排；多图才需要把页码徽标钉在右下角
    Stack({ alignContent: this.images.length > 1 ? Alignment.BottomEnd : Alignment.TopStart }) {
      Column() {
        if (this.images.length > 1) {
          // 横向 `List`（每页一个 `ListItem`），不用 `Swiper` 也不用 `Scroll + Row`：
          // Swiper 会把图集高度压掉一截且与图片内容无关；`Row` 会压缩超出容器的子项、破坏 `aspectRatio`，
          // 加 `flexShrink(0)` 能修但 `Scroll.onScroll(xOffset)` 在该结构下拿不到真实偏移、页码无法同步。
          // `List.onScrollIndex` 直接回传首个可见项下标，无单位换算、无歧义。
          List({ space: PAGE_GAP, initialIndex: this.boundedInitialPage() }) {
            ForEach(this.images, (img: ContentImage, index: number) => {
              ListItem() {
                this.GalleryPage(img, index)
              }
              // ListItem 留在原列表中；共享图片自身可能被 follow 临时搬走。
              .onVisibleAreaChange([0], (visible: boolean): void => {
                this.pageVisibilityChanged(index, visible);
              })
            }, (img: ContentImage, index: number) => `${index}:${img.imageUrl}`)
          }
          .listDirection(Axis.Horizontal)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.None)
          .scrollSnapAlign(ScrollSnapAlign.START)
          .width('100%')
          .height('100%')
          .onScrollIndex((first: number) => {
            if (first >= 0 && first < this.images.length && first !== this.page) {
              this.page = first;
              this.onPageChange(first);
            }
          })
        } else if (this.images.length === 1) {
          // 单图不进滚动容器：没有可翻的页，多套一层只会白白多一层手势竞争
          this.SingleImage(this.images[0])
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)

      this.PageBadge()
    }
    // 滑动时 List 会让相邻页短暂经过矩形视口；圆角必须挂在最外层，
    // 不能只裁每张 Image，否则过渡帧四角会露成直角。
    .borderRadius(BODY_RADIUS)
    .clip(true)
    .width('100%')
    .height(this.issuedHeight())
    .onVisibleAreaChange([0], (visible: boolean): void => { this.visible = visible; })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const width: number = Number(newArea.width);
      // 只在宽度真的变了才写回，避免"改高度 → 再触发 onAreaChange"的自激
      if (width > 0 && Math.abs(width - this.boxWidth) > 0.5) {
        this.boxWidth = width;
      }
    })
  }
}
