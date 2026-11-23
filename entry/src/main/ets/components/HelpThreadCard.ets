import { ThreadBrief } from '../model/ThreadList';
import { formatTimeText } from '../model/TimeText';
import { AppTheme } from '../theme/Theme';
import { visualThemeStore } from '../common/appearance/VisualThemeStore';
import { AvatarComponent } from './AvatarComponent';
import { TaggedThreadText } from './TaggedThreadText';
import { imageLoadStore } from '../common/appearance/ImageLoadStore';
import { feedPreviewSource, isGifFeedImage } from '../model/ImageLoadPolicy';
import { ThreadCardLayout } from '../common/appearance/ThreadCardLayout';
import { feedImageInfo } from '../model/HomeFeedPresentation';
import { ImageTransitionSource } from './ImageTransition';

/** 互助卡片只展示服务端返回的回答，不把主帖摘要当作回答。 */
@ComponentV2
export struct HelpThreadCard {
  private imageTransition: ImageTransitionSource = new ImageTransitionSource();
  @Require @Param item: ThreadBrief;
  @Event onOpenThread: () => void = (): void => {};
  @Event onOpenAnswer: () => void = (): void => {};
  @Event onOpenImage: () => void = (): void => {};
  @Local textHeight: number = 80;

  /** 时间与全站一致（`model/TimeText`），不要另写一套相对时间口径。 */
  private coverPreviewUrl(): string {
    return feedPreviewSource(feedImageInfo(this.item.coverImage), this.item.coverImage, imageLoadStore.currentPolicy());
  }

  private timeText(): string {
    return formatTimeText(this.item.lastTimeMs, Date.now());
  }

  @Builder
  PreviewText(text: string, answer: boolean) {
    TaggedThreadText({ text,
      labels: answer ? [this.item.answerIsHighQuality ? '高赞回答' : '回答'] : (this.item.isHelp ? ['求助'] : []),
      textSize: answer ? 14 : 16, lineSize: answer ? 23 : 25, weight: answer ? FontWeight.Normal : FontWeight.Bold,
      textColor: answer ? AppTheme.TEXT_SUB : AppTheme.TEXT_MAIN, lines: 2 })
  }

  build() {
    Row({ space: 12 }) {
      Column() {
        Column({ space: 6 }) {
          this.PreviewText(this.item.title, false)
          if (this.item.answerPreview.length > 0) {
            Column() { this.PreviewText(this.item.answerPreview, true) }
              .width('100%').onClick(() => { this.onOpenAnswer(); })
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      Row({ space: 7 }) {
        if (this.item.answerAvatars.length > 0) {
          Row({ space: -5 }) {
            ForEach(this.item.answerAvatars, (url: string, index: number) => {
              AvatarComponent({ url, avatarSize: 16 }).border({ width: 1, color: AppTheme.CARD }).borderRadius(8)
            }, (url: string, index: number) => `${index}:${url}`)
          }.flexShrink(0)
        }
        Text(this.item.replyCount >= 0 ? `${this.item.replyCount}个回答` : '回答数未知')
          .fontSize(11).fontColor(AppTheme.TEXT_MUTED)
        if (this.item.lastTimeMs > 0) {
          Text(`· ${this.timeText()}`).fontSize(11).fontColor(AppTheme.TEXT_MUTED)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
        }
      }.width('100%').margin({ top: 10 })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.SpaceBetween)
        .constraintSize({ minHeight: this.item.coverImage.length > 0 ? 80 : 0 })
        .onAreaChange((_old: Area, area: Area) => {
          const height: number = Number(area.height);
          if (height >= 80 && Math.abs(height - this.textHeight) > 0.5) { this.textHeight = height; }
        })
      if (this.item.coverImage.length > 0) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          if (imageLoadStore.isAutoLoadOff()) {
            Text('查看图片').fontSize(12).fontColor(AppTheme.ACCENT)
              .width('100%').height('100%').textAlign(TextAlign.Center)
          } else if (this.coverPreviewUrl().length > 0) {
            ForEach([this.coverPreviewUrl()], (src: string) => {
              Image(src).width('100%').height('100%').objectFit(ImageFit.Contain).borderRadius(9)
            }, (src: string) => src)
            if (isGifFeedImage(feedImageInfo(this.item.coverImage), this.item.coverImage)) {
              Text('GIF').fontSize(10).fontColor(Color.White)
                .backgroundColor('#88000000').borderRadius(4)
                .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                .margin({ right: 4, bottom: 4 })
                .hitTestBehavior(HitTestMode.None)
            }
          }
        }.width(80).height(this.textHeight)
          .geometryTransition(this.coverPreviewUrl().length > 0
            ? this.imageTransition.id(this.coverPreviewUrl()) : '', { follow: true })
          .renderFit(RenderFit.RESIZE_FILL)
          .onClick(() => {
            const preview: string = this.coverPreviewUrl();
            this.imageTransition.open(this.getUIContext(), preview,
              feedImageInfo(this.item.coverImage).origin || this.item.coverImage,
              (): void => { this.onOpenImage(); }, 0, preview.length > 0);
          })
      }
    }.width('100%').alignItems(VerticalAlign.Top).padding(10)
      .backgroundColor(AppTheme.CARD).borderRadius(ThreadCardLayout.RADIUS)
      .border({ width: { bottom: visualThemeStore.isPaper ? 0.5 : 0 }, color: AppTheme.DIVIDER })
      .onClick(() => { this.onOpenThread(); })
  }
}
