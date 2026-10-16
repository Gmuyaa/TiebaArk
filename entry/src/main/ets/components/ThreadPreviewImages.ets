import { display } from '@kit.ArkUI';
import { AppTheme } from '../theme/Theme';
import {
  FeedImageBox, FeedImageInfo, feedImageBox, feedImageInfo, feedPreviewInfo, previewRowHeight,
  rememberMeasuredImage, PREVIEW_GAP, PREVIEW_RADIUS
} from '../model/HomeFeedPresentation';
import { lowFlowStore } from '../common/appearance/LowFlowStore';

/** 首页与吧内列表共享的帖子图片预览；按图片数量选择单图或多图布局。 */

interface PreviewImageComplete {
  width: number;
  height: number;
  loadingStatus: number;
}

@ComponentV2
struct ThreadPreviewImage {
  @Require @Param url: string;
  /** 在本卡 `images` 里的下标（回报容器高度用） */
  @Param index: number = 0;
  @Param contentWidth: number = 300;
  @Param multiple: boolean = false;
  @Param density: number = 1;
  @Event onOpen: () => void = (): void => {};

  @Event onBoxHeight: (index: number, height: number) => void = (_index: number, _height: number): void => {};
  @Local loaded: boolean = false;
  @Local failed: boolean = false;
  /** 本次加载确认到的实际源尺寸；空 = 还没加载出来，用缓存/占位框 */
  @Local actual: FeedImageInfo = new FeedImageInfo();

  /**
   * URL 变了（列表项复用）＝ 换成另一张图：成功态、失败态与实测尺寸一律作废，
   * 否则上一张图的尺寸会串到新图片上。
   */
  @Monitor('url')
  onUrlChanged(): void {
    this.loaded = false;
    this.failed = false;
    this.actual = new FeedImageInfo();
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

  /** 图片本体的绘制高度：长图按真实比例可以高出预览框，超出部分由预览框裁掉 */
  private drawHeight(frame: FeedImageBox): number {
    if (frame.long && this.actual.width > 0) {
      return Math.max(1, frame.width * this.actual.height / this.actual.width);
    }
    return frame.height;
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
    return (event?: PreviewImageComplete): void => {
      if (url !== this.url) { return; }
      this.applyLoaded(event);
    };
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      /*
       * 低流量模式（A-08）：**不渲染 `Image`** —— 不发起任何图片请求，只占位。
       * 占位仍可点（外层 onClick 不变），点开查看器照常加载原图。
       */
      if (lowFlowStore.enabled) {
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
          .width(this.frame().width)
          .height(this.drawHeight(this.frame()))
          .objectFit(this.imageFit(this.frame()))
          .objectRepeat(ImageRepeat.NoRepeat)
          .opacity(this.loaded ? 1 : 0)
          .onComplete(this.completeHandler(this.url))
          .onError(() => { this.failed = true; this.loaded = false; })
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
    .onClick(() => { this.onOpen(); })

    .onAreaChange((_old: Area, area: Area) => {
      const height: number = Number(area.height);
      if (height > 0) { this.onBoxHeight(this.index, height); }
    })
  }
}

@ComponentV2
export struct ThreadPreviewImages {
  @Require @Param images: string[];
  @Require @Param scroller: ListScroller;
  @Event onOpenImage: (index: number) => void = (_index: number): void => {};
  @Local contentWidth: number = 300;
  /**
   * 每张图容器的**实测高度**（vp），由子组件回报 —— 多图整行高度取其中的最大值
   * （`previewRowHeight`）。空数组 = 一张都还没量到，用占位行高。
   */
  @Local boxHeights: number[] = [];
  private density: number = 1;

  aboutToAppear(): void {
    // 启动时的粗算；真实宽度由根节点的 onAreaChange 校正（横竖屏、分屏都会变）
    try {
      const screen: display.Display = display.getDefaultDisplaySync();
      this.density = screen.densityPixels;
      this.contentWidth = screen.width / this.density - 44;
    } catch (err) { /* 后续通过区域宽度校正。 */ }
  }

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
      if (this.images.length === 1) {
        ThreadPreviewImage({ url: this.images[0], index: 0, contentWidth: this.contentWidth,
          density: this.density,
          onBoxHeight: (index: number, height: number): void => { this.reportBoxHeight(index, height); },
          onOpen: (): void => { this.onOpenImage(0); } })
      } else if (this.images.length > 1) {
        List({ space: PREVIEW_GAP, scroller: this.scroller }) {
          ForEach(this.images, (url: string, index: number) => {
            ListItem() {
              ThreadPreviewImage({ url: url, index: index, contentWidth: this.contentWidth,
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
