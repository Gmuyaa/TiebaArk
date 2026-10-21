import { ThreadBrief } from '../model/ThreadList';
import { ContentKind, ContentPiece, formatPostTime } from '../model/ThreadDetail';
import { AppTheme } from '../theme/Theme';
import { visualThemeStore } from '../common/appearance/VisualThemeStore';
import { emojiSrc } from '../common/emoji/EmojiSrc';
import { AvatarComponent } from './AvatarComponent';
import { HelpTag } from './HelpTag';
import { lowFlowStore } from '../common/appearance/LowFlowStore';

/** 互助卡片只展示服务端返回的回答，不把主帖摘要当作回答。 */
@ComponentV2
export struct HelpThreadCard {
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
    Stack({ alignContent: Alignment.TopStart }) {
    Text() {
      // 首行预留标签宽度，后续行仍从段落左边缘排版；标签层不参与行高。
      if (answer || this.item.isHelp) {
        Span('　'.repeat(answer && this.item.answerIsHighQuality ? 4 : 2)).fontSize(9).fontWeight(FontWeight.Normal)
        Span('　').fontSize(11).fontWeight(FontWeight.Normal)
      }
      ForEach(ContentPiece.listFromRaw([{ type: 0, text }]), (piece: ContentPiece, index: number) => {
        if (piece.kind === ContentKind.EMOJI && piece.emojiUrl.length > 0) {
          ImageSpan(emojiSrc(piece.emojiUrl)).width(18).height(18)
            .verticalAlign(ImageSpanAlignment.CENTER).objectFit(ImageFit.Contain)
        } else { Span(piece.text) }
      }, (piece: ContentPiece, index: number) => `${index}:${piece.text}:${piece.emojiUrl}`)
    }.fontSize(answer ? 14 : 16).fontWeight(answer ? FontWeight.Normal : FontWeight.Bold)
      .fontColor(answer ? AppTheme.TEXT_SUB : AppTheme.TEXT_MAIN).lineHeight(answer ? 23 : 25)
      .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      .accessibilityText(`${answer ? (this.item.answerIsHighQuality ? '高赞回答' : '回答') : (this.item.isHelp ? '求助' : '')} ${text}`)
      if (answer || this.item.isHelp) {
        HelpTag({ label: answer ? (this.item.answerIsHighQuality ? '高赞回答' : '回答') : '求助',
          emphasized: answer && this.item.answerIsHighQuality })
          .margin({ top: answer ? 4.5 : 5.5 }).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      }
    }.width('100%')
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
            Image(this.item.coverImage).width('100%').height('100%').objectFit(ImageFit.Contain).borderRadius(8)
          }
        }.width(80).height(this.textHeight).justifyContent(FlexAlign.Center)
          .onClick(() => { this.onOpenImage(); })
      }
    }.width('100%').alignItems(VerticalAlign.Top).padding(10)
      .backgroundColor(AppTheme.CARD).borderRadius(visualThemeStore.isPaper ? 0 : AppTheme.CARD_RADIUS)
      .border({ width: { bottom: visualThemeStore.isPaper ? 0.5 : 0 }, color: AppTheme.DIVIDER })
      .onClick(() => { this.onOpenThread(); })
  }
}
