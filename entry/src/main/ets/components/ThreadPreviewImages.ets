import { display } from '@kit.ArkUI';
import { AppTheme } from '../theme/Theme';
import {
  FeedImageBox, FeedImageInfo, feedImageBox, feedImageInfo, feedPreviewInfo, previewRowHeight,
  rememberMeasuredImage, PREVIEW_GAP, PREVIEW_RADIUS
} from '../model/HomeFeedPresentation';
import { lowFlowStore } from '../common/appearance/LowFlowStore';

interface PreviewImageComplete {
  width: number;
  height: number;
  loadingStatus: number;
}

@ComponentV2
struct ThreadPreviewImage {
  @Require @Param url: string;

  @Param index: number = 0;
  @Param contentWidth: number = 300;
  @Param multiple: boolean = false;
  @Param density: number = 1;
  @Event onOpen: () => void = (): void => {};

  @Event onBoxHeight: (index: number, height: number) => void = (_index: number, _height: number): void => {};
  @Local loaded: boolean = false;
  @Local failed: boolean = false;

  @Local actual: FeedImageInfo = new FeedImageInfo();

  @Monitor('url')
  onUrlChanged(): void {
    this.loaded = false;
    this.failed = false;
    this.actual = new FeedImageInfo();
  }

  private frame(): FeedImageBox {
    return feedImageBox(feedPreviewInfo(this.url), this.contentWidth, this.multiple, this.density);
  }

  private imageFit(frame: FeedImageBox): ImageFit {
    if (frame.long) { return ImageFit.Cover; }
    const drawn: FeedImageInfo = this.actual;
    if (!(drawn.width > 0) || !(drawn.height > 0)) { return ImageFit.Contain; }
    const boxRatio: number = frame.width / frame.height;
    const srcRatio: number = drawn.width / drawn.height;
    const drift: number = Math.abs(boxRatio - srcRatio) / Math.max(boxRatio, srcRatio);
    return drift > 0.05 ? ImageFit.Cover : ImageFit.Contain;
  }

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

    rememberMeasuredImage(this.url, event.width, event.height, measured.long, measured.origin);
  }

  private completeHandler(url: string): (event?: PreviewImageComplete) => void {
    return (event?: PreviewImageComplete): void => {
      if (url !== this.url) { return; }
      this.applyLoaded(event);
    };
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {

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

  @Local boxHeights: number[] = [];
  private density: number = 1;

  aboutToAppear(): void {

    try {
      const screen: display.Display = display.getDefaultDisplaySync();
      this.density = screen.densityPixels;
      this.contentWidth = screen.width / this.density - 44;
    } catch (err) {  }
  }

  private rowHeight(): number {
    return previewRowHeight(this.boxHeights);
  }

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
