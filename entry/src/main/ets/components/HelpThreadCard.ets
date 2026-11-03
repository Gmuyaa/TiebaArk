import { ThreadBrief } from '../model/ThreadList';
import { formatPostTime } from '../model/ThreadDetail';
import { AppTheme } from '../theme/Theme';
import { visualThemeStore } from '../common/appearance/VisualThemeStore';
import { AvatarComponent } from './AvatarComponent';
import { TaggedThreadText } from './TaggedThreadText';
import { lowFlowStore } from '../common/appearance/LowFlowStore';
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

  private timeText(): string {
    const minutes: number = Math.max(0, Math.floor((Date.now() - this.item.lastTimeMs) / 60000));
    if (minutes === 0) { return '刚刚'; }
    if (minutes < 60) { return `${minutes}分钟前`; }
    if (minutes < 1440) { return `${Math.floor(minutes / 60)}小时前`; }
    return formatPostTime(this.item.lastTimeMs, Date.now());
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
        Column() {
          if (lowFlowStore.enabled) {
            Text('查看图片').fontSize(12).fontColor(AppTheme.ACCENT)
          } else {
            Image(this.item.coverImage).width('100%').height('100%').objectFit(ImageFit.Contain).borderRadius(9)
          }
        }.width(80).height(this.textHeight).justifyContent(FlexAlign.Center)
          .geometryTransition(this.imageTransition.id(this.item.coverImage), { follow: true })
          .renderFit(RenderFit.RESIZE_FILL)
          .onClick(() => {
            this.imageTransition.open(this.getUIContext(), this.item.coverImage,
              feedImageInfo(this.item.coverImage).origin || this.item.coverImage,
              (): void => { this.onOpenImage(); }, 0, !lowFlowStore.enabled);
          })
      }
    }.width('100%').alignItems(VerticalAlign.Top).padding(10)
      .backgroundColor(AppTheme.CARD).borderRadius(ThreadCardLayout.RADIUS)
      .border({ width: { bottom: visualThemeStore.isPaper ? 0.5 : 0 }, color: AppTheme.DIVIDER })
      .onClick(() => { this.onOpenThread(); })
  }
}
