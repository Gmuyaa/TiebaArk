/** 正文图片按连续区段组成横向图集。单图按实际宽高比展示，多图共享图集状态。 */

import { display } from '@kit.ArkUI';
import { AppTheme } from '../theme/Theme';
import { ContentImage, galleryAspectRatio } from '../model/ThreadDetail';
import {
  BODY_RADIUS, FeedImageBox, FeedImageInfo, bodySingleImageBox, feedImageInfo, rememberMeasuredImage
} from '../model/HomeFeedPresentation';
import { lowFlowStore } from '../common/appearance/LowFlowStore';

/** 详情页内容区左右各留 16vp */
const PAGE_SIDE_PADDING: number = 32;

/** 图集内两张图之间的间距（vp） */
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
 * 首帧的图集宽度估计（vp）：屏宽 - 页面左右留白。
 *
 * 为什么需要它：`@Local boxWidth` 要靠 `onAreaChange` 才能拿到实测宽度，
 * 而 `List` 回收复用会让组件重建、宽度回到初始值——若初值是随便给的常数，
 * 每次滚过图集都要"先塌后撑"跳一下。用屏宽推算后首帧就落在正确值上。
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
  /** 本图集的图片，至少 1 张 */
  @Require @Param images: ContentImage[];
  /** 本图集第一张图在整篇内容图片序列里的下标，用来换算全屏查看器的初始页 */
  @Param startIndex: number = 0;
  /** 点击某张图：回传它在整篇内容图片序列里的下标 */
  @Event onOpenImage: (globalIndex: number) => void = (): void => {};

  /** 当前页。多个图集之间必须各自独立，所以放在组件内部而不是页面级 */
  @Local page: number = 0;
  /**
   * 本图集实测宽度（vp）。宽度来自 `onAreaChange`，用来把高度算成 `宽 ÷ 比例`。
   *
   * 不用 `.width('100%') + 平台自适应` 的原因：在这条容器链路（`List` item →
   * `Column` → 图集）里，"父宽定子高"的推导不可靠，显式算出来才可控。
   * 初值用屏宽推算，避免 `List` 回收复用重建时先塌后撑跳一下。
   */
  @Local boxWidth: number = estimateGalleryWidth();
  /**
   * 单图本次加载确认到的实际尺寸（px）。**只给单图用**，理由见文件头：
   * 多图若把实测值并进组平均比例，翻页时高度会跟着变。
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
    try {
      this.density = display.getDefaultDisplaySync().densityPixels;
    } catch (err) {
      // 拿不到密度就用 1：小图限制放宽，但不会让容器算不出来
    }
  }

  private urlOf(index: number): string {
    return index >= 0 && index < this.images.length ? this.images[index].imageUrl : '';
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
   * 单图的尺寸真值：已确认的实际尺寸 > 服务端声明尺寸 > 空。
   *
   * 实际尺寸优先是刻意的：**屏幕上画的就是实际加载到的那份资源**，服务端声明
   * （`ContentImage.width/height`）描述的是原图，两者比例不一致时按声明值排版会留白。
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
   * 容器高度（vp）。单图 = 贴合图片的容器高度；多图 = 实测宽 ÷ 组内平均比例。
   *
   * 多图直接用即可，**不需要任何"上方内容高度"补偿**：早先那套补偿是 `Swiper` 时代的
   * 误判（当时确实量到"下发 379vp 只剩 140vp"），换成横向 `List` 后实测
   * 下发给 `.height()` 多少就渲染多少（下发 379vp → 像素实测 1327px = 379.1vp），
   * 补偿量一旦加上反而把图集撑高、把内容顶到屏幕外。
   */
  private issuedHeight(): number {
    if (this.images.length === 1) { return this.frame().height; }
    return this.boxWidth > 0 ? this.boxWidth / galleryAspectRatio(this.images) : 240;
  }

  /**
   * 绑定这次加载的回调：只有**发起加载时的那条 URL 仍是那张图**时才生效 ——
   * 列表项复用后旧图的迟到回调不能把尺寸/成功态写到新图上。
   */
  private completeHandler(index: number, url: string): (event?: GalleryImageComplete) => void {
    return (event?: GalleryImageComplete): void => {
      if (url.length === 0 || url !== this.urlOf(index)) { return; }
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

  /**
   * 正文单图：容器贴合图片最终显示尺寸，不用模糊背景撑满一个偏大的框。
   * 长图不裁切，靠 `bodySingleImageBox` 的高度上限等比收缩。
   */
  @Builder
  SingleImage(img: ContentImage) {
    Stack({ alignContent: Alignment.TopStart }) {
      if (lowFlowStore.enabled) {
        // 低流量模式：**不渲染 `Image`** —— 不发起任何图片请求，只占位。
        // 占位仍可点，点开查看器照常加载原图。
        Text('低流量模式 · 点按查看')
          .fontSize(12).fontColor(AppTheme.TEXT_SUB)
          .width('100%').height('100%').textAlign(TextAlign.Center)
      } else {
        if (this.stateOf(0) !== IMAGE_LOADED) {
          Text(this.stateOf(0) === IMAGE_FAILED ? '图片加载失败' : '图片加载中…')
            .fontSize(12).fontColor(AppTheme.TEXT_SUB)
            .width('100%').height('100%').textAlign(TextAlign.Center)
        }
        Image(img.imageUrl)
          .width(this.frame().width)
          .height(this.frame().height)
          .objectFit(ImageFit.Contain)
          .objectRepeat(ImageRepeat.NoRepeat)
          .opacity(this.stateOf(0) === IMAGE_LOADED ? 1 : 0)
          .onComplete(this.completeHandler(0, img.imageUrl))
          .onError(() => { this.markState(0, IMAGE_FAILED); })
      }
    }
    // 外框与内部图片取同一份布局结果：图片多高，容器就多高，不留失效的占位高度
    .width(this.frame().width)
    .height(this.frame().height)
    .backgroundColor(this.stateOf(0) === IMAGE_LOADED ? Color.Transparent : AppTheme.SURFACE_MUTED)
    .borderRadius(BODY_RADIUS)
    .clip(true)
    .onClick(() => {
      this.onOpenImage(this.startIndex);
    })
  }

  /**
   * 图集里的一页：一屏一张，宽度取实测内容宽，高度由 `aspectRatio(组比例)` 自己撑开。
   * 图集高度为保证翻页稳定而按整组平均比例固定。单张比例不同时保持 `Contain`，
   * 不能为填满容器裁掉正文图片；底层用同图 `Cover` + 模糊延展，视觉上没有黑/灰留边。
   *
   * **必须 `flexShrink(0)`**：缩放祖先里有 `List`/`Row` 时子项会被压缩，
   * 实测（`Scroll + Row` 版）每页被挤到 539 / 637px 且 `aspectRatio` 一起被破坏，
   * 一屏并排露出两张图。加上它每页才稳定是 `344×379vp`。
   */
  @Builder
  GalleryPage(img: ContentImage, index: number) {
    Stack() {
      if (lowFlowStore.enabled) {
        Text('低流量模式 · 点按查看')
          .fontSize(12).fontColor(AppTheme.TEXT_SUB)
          .width('100%').height('100%').textAlign(TextAlign.Center)
      } else {
        // 只是补满比例差的背景，不影响前景原图的完整展示。
        Image(img.imageUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(24)
          .opacity(0.72)
        Image(img.imageUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .onComplete(this.completeHandler(index, img.imageUrl))
          .onError(() => { this.markState(index, IMAGE_FAILED); })
        if (this.stateOf(index) === IMAGE_FAILED) {
          Text('图片加载失败')
            .fontSize(12).fontColor(AppTheme.TEXT_SUB)
            .width('100%').height('100%').textAlign(TextAlign.Center)
        }
      }
    }
      .width(this.boxWidth)
      .aspectRatio(galleryAspectRatio(this.images))
      // 加载完成前铺一层底色，免得图集位置是一块透明洞；加载后透明，观感与改动前一致
      .backgroundColor(this.stateOf(index) === IMAGE_LOADED ? Color.Transparent : AppTheme.SURFACE_MUTED)
      .borderRadius(BODY_RADIUS)
      .clip(true)
      .flexShrink(0)
      .onClick(() => {
        this.onOpenImage(this.startIndex + index);
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
          // 横向 `List`（每页一个 `ListItem`），**不用 `Swiper`、也不用 `Scroll + Row`**。
          //
          // 为什么不用 `Swiper`：实测同一份内容放进 `Swiper` 后图集高度被压到 140vp
          // （要求 379 / 600vp 都一样，两次都恰好少 239vp —— 同列上方文字的高度），
          // 换成纯色块也照样被压，所以与图片无关，是 Swiper 那条测量链路的问题。
          //
          // 为什么不用 `Scroll + Row`：`Row` 会把超出容器的子项**压缩**——
          // 实测每页被挤到 539 / 637px 且 `aspectRatio` 被破坏，一屏并排显示两张图。
          // 加 `flexShrink(0)` 能修，但 `Scroll.onScroll(xOffset)` 在此结构下拿不到真实偏移
          // （整段滑动过程中实测上限只有 2），页码无法同步。
          // `List.onScrollIndex` 直接回传**首个可见项下标**，无单位换算、无歧义。
          List({ space: PAGE_GAP }) {
            ForEach(this.images, (img: ContentImage, index: number) => {
              ListItem() {
                this.GalleryPage(img, index)
              }
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
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const width: number = Number(newArea.width);
      // 只在宽度真的变了才写回，避免"改高度 → 再触发 onAreaChange"的自激
      if (width > 0 && Math.abs(width - this.boxWidth) > 0.5) {
        this.boxWidth = width;
      }
    })
  }
}
