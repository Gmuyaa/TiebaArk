

import { display } from '@kit.ArkUI';
import { AppTheme } from '../theme/Theme';
import { ContentImage, galleryAspectRatio } from '../model/ThreadDetail';
import {
  BODY_RADIUS, FeedImageBox, FeedImageInfo, bodySingleImageBox, feedImageInfo, rememberMeasuredImage
} from '../model/HomeFeedPresentation';
import { lowFlowStore } from '../common/appearance/LowFlowStore';

const PAGE_SIDE_PADDING: number = 32;

const PAGE_GAP: number = 8;

const IMAGE_LOADING: number = 0;
const IMAGE_LOADED: number = 1;
const IMAGE_FAILED: number = 2;

interface GalleryImageComplete {
  width: number;
  height: number;
  loadingStatus: number;
}

function estimateGalleryWidth(): number {
  try {
    const info: display.Display = display.getDefaultDisplaySync();
    const width: number = info.width / info.densityPixels - PAGE_SIDE_PADDING;
    return width > 0 ? width : 240;
  } catch (err) {

    return 240;
  }
}

@ComponentV2
export struct PostImageGallery {

  @Require @Param images: ContentImage[];

  @Param startIndex: number = 0;

  @Event onOpenImage: (globalIndex: number) => void = (): void => {};

  @Local page: number = 0;

  @Local boxWidth: number = estimateGalleryWidth();

  @Local actual: FeedImageInfo = new FeedImageInfo();

  @Local actualUrl: string = '';

  @Local states: number[] = [];

  @Local stateUrls: string[] = [];

  private density: number = 1;

  aboutToAppear(): void {
    try {
      this.density = display.getDefaultDisplaySync().densityPixels;
    } catch (err) {

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

  private frame(): FeedImageBox {
    const url: string = this.urlOf(0);
    const source: FeedImageInfo =
      (this.actualUrl === url && this.actual.width > 0) ? this.actual : this.sourceInfo();
    return bodySingleImageBox(source, this.boxWidth, this.density);
  }

  private issuedHeight(): number {
    if (this.images.length === 1) { return this.frame().height; }
    return this.boxWidth > 0 ? this.boxWidth / galleryAspectRatio(this.images) : 240;
  }

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

      rememberMeasuredImage(url, event.width, event.height, false, origin);
    };
  }

  @Builder
  SingleImage(img: ContentImage) {
    Stack({ alignContent: Alignment.TopStart }) {
      if (lowFlowStore.enabled) {

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

    .width(this.frame().width)
    .height(this.frame().height)
    .backgroundColor(this.stateOf(0) === IMAGE_LOADED ? Color.Transparent : AppTheme.SURFACE_MUTED)
    .borderRadius(BODY_RADIUS)
    .clip(true)
    .onClick(() => {
      this.onOpenImage(this.startIndex);
    })
  }

  @Builder
  GalleryPage(img: ContentImage, index: number) {
    Stack() {
      if (lowFlowStore.enabled) {
        Text('低流量模式 · 点按查看')
          .fontSize(12).fontColor(AppTheme.TEXT_SUB)
          .width('100%').height('100%').textAlign(TextAlign.Center)
      } else {

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

      .backgroundColor(this.stateOf(index) === IMAGE_LOADED ? Color.Transparent : AppTheme.SURFACE_MUTED)
      .borderRadius(BODY_RADIUS)
      .clip(true)
      .flexShrink(0)
      .onClick(() => {
        this.onOpenImage(this.startIndex + index);
      })
  }

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

    Stack({ alignContent: this.images.length > 1 ? Alignment.BottomEnd : Alignment.TopStart }) {
      Column() {
        if (this.images.length > 1) {

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

          this.SingleImage(this.images[0])
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)

      this.PageBadge()
    }

    .borderRadius(BODY_RADIUS)
    .clip(true)
    .width('100%')
    .height(this.issuedHeight())
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const width: number = Number(newArea.width);

      if (width > 0 && Math.abs(width - this.boxWidth) > 0.5) {
        this.boxWidth = width;
      }
    })
  }
}
