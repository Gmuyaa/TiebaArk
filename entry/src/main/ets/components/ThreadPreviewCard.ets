import { LengthMetrics } from '@kit.ArkUI';
import { AppTheme } from '../theme/Theme';
import { ThreadCardLayout } from '../common/appearance/ThreadCardLayout';
import { ContentKind, ContentPiece } from '../model/ThreadDetail';
import { emojiSrc } from '../common/emoji/EmojiSrc';
import { ThreadPreviewImages } from './ThreadPreviewImages';
import { ForumAvatarImage, forumAvatarRadius } from './ForumAvatarImage';
import { AvatarComponent } from './AvatarComponent';

/** 标准帖子卡：页面传入展示值与动作，组件不发请求、不执行导航。 */
@ComponentV2
export struct ThreadPreviewCard {
  @Param authorName: string = '';
  @Param authorAvatar: string = '';
  @Param forumName: string = '';
  @Param forumAvatar: string = '';
  /** 仅传已确认的发帖日期；不要将最后回复时间填到作者信息中。 */
  @Param postedTime: string = '';
  @Param title: string = '';
  @Param summary: string = '';
  @Param images: string[] = [];
  @Param isTop: boolean = false;
  @Param isGood: boolean = false;
  @Param agreeCount: number = 0;
  @Param replyCount: number = 0;
  @Param shareCount: number = 0;
  @Param menu: MenuElement[] = [];
  @Param canOpenAuthor: boolean = false;
  @Param canOpenForum: boolean = false;
  @Require @Param imageScroller: ListScroller;
  @Event onOpenAuthor: () => void = (): void => {};
  @Event onOpenForum: () => void = (): void => {};
  @Event onOpenThread: () => void = (): void => {};
  @Event onOpenImage: (index: number) => void = (_index: number): void => {};

  /** 复用正文解析器识别列表摘要里的官方表情编码。 */
  private summaryPieces(): ContentPiece[] {
    return ContentPiece.listFromRaw([{ type: 0, text: this.summary }]);
  }

  @Builder
  Tag(label: string, filled: boolean) {
    Text(label).fontSize(10)
      .fontColor(filled ? Color.White : AppTheme.ACCENT_DARK)
      .backgroundColor(filled ? AppTheme.ACCENT : AppTheme.ACCENT_LIGHT)
      .borderRadius(4).padding({ left: 5, right: 5, top: 2, bottom: 2 })
  }

  @Builder
  Metric(icon: Resource, label: string, count: number) {
    Row({ space: 4 }) {
      SymbolGlyph(icon).fontSize(ThreadCardLayout.METRIC_ICON_SIZE).maxFontScale(1).fontColor([AppTheme.TEXT_SUB])
      Text(`${count}`).fontSize(ThreadCardLayout.META_SIZE).fontColor(AppTheme.TEXT_SUB)
    }
    .accessibilityGroup(true)
    .accessibilityText(`${label} ${count}，只读统计`)
  }

  private openAuthor(): void {
    if (this.canOpenAuthor) { this.onOpenAuthor(); } else { this.onOpenThread(); }
  }
  private openForum(): void {
    if (this.canOpenForum) { this.onOpenForum(); } else { this.onOpenThread(); }
  }

  @Builder
  HeaderMenu() {
    if (this.menu.length > 0) {
      Text('⋯').fontSize(20).maxFontScale(1).fontColor(AppTheme.TEXT_SUB).width(32).height(24)
        .responseRegion({ x: -4, y: -8, width: 40, height: 40 })
        .textAlign(TextAlign.Center).accessibilityText('更多').bindMenu(this.menu)
    }
  }

  @Builder
  IdentityHeader() {
    if (this.forumName.length > 0) {
      Row({ space: ThreadCardLayout.SECTION_GAP }) {
        ForumAvatarImage({ url: this.forumAvatar, forumName: this.forumName,
          avatarSize: ThreadCardLayout.AVATAR_SIZE, radius: forumAvatarRadius(ThreadCardLayout.AVATAR_SIZE) })
          .id('thread-card-forum-avatar').flexShrink(0).onClick(() => { this.openForum(); })
        Column({ space: 2 }) {
          Row({ space: 6 }) {
            Text(this.forumName.endsWith('吧') ? this.forumName : `${this.forumName}吧`)
              .fontSize(ThreadCardLayout.AUTHOR_SIZE).fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.TEXT_MAIN).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .flexShrink(1).constraintSize({ maxWidth: '45%' })
              .id('thread-card-forum-name').onClick(() => { this.openForum(); })
            Row().width(1).height(12).backgroundColor(AppTheme.TEXT_SUB).opacity(0.45).flexShrink(0)
            Row({ space: 4 }) {
              AvatarComponent({ url: this.authorAvatar, avatarSize: 18, fallbackName: this.authorName })
                .id('thread-card-author-avatar').flexShrink(0)
              Text(this.authorName.length > 0 ? this.authorName : '贴吧用户')
                .fontSize(ThreadCardLayout.META_SIZE).fontColor(AppTheme.META_TEXT)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
                .id('thread-card-author-name')
            }.flexShrink(1).alignItems(VerticalAlign.Center).onClick(() => { this.openAuthor(); })
          }.width('100%').alignItems(VerticalAlign.Center)
          if (this.postedTime.length > 0) {
            Text(this.postedTime).fontSize(ThreadCardLayout.META_SIZE)
              .fontColor(AppTheme.TEXT_SUB).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .accessibilityText(`发帖日期 ${this.postedTime}`)
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        this.HeaderMenu()
      }.width('100%').alignItems(VerticalAlign.Top)
    } else {
      Row({ space: ThreadCardLayout.SECTION_GAP }) {
        AvatarComponent({ url: this.authorAvatar, avatarSize: ThreadCardLayout.AVATAR_SIZE,
          fallbackName: this.authorName }).id('thread-card-primary-author-avatar')
          .onClick(() => { this.openAuthor(); })
        Column({ space: 5 }) {
          Text(this.authorName.length > 0 ? this.authorName : '贴吧用户')
            .fontSize(ThreadCardLayout.AUTHOR_SIZE).fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT_MAIN).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .id('thread-card-primary-author-name').width('100%').onClick(() => { this.openAuthor(); })
          if (this.postedTime.length > 0) {
            Text(this.postedTime).fontSize(ThreadCardLayout.META_SIZE)
              .fontColor(AppTheme.TEXT_SUB).maxLines(1).accessibilityText(`发帖日期 ${this.postedTime}`)
          }
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1)
        this.HeaderMenu()
      }.width('100%').alignItems(VerticalAlign.Top)
    }
  }

  build() {
    Column({ space: ThreadCardLayout.SECTION_GAP }) {
      this.IdentityHeader()

      if (this.title.length > 0 || this.isTop || this.isGood) {
        Column({ space: 5 }) {
          if (this.isTop || this.isGood) {
            Row({ space: 4 }) {
              if (this.isTop) { this.Tag('置顶', true) }
              if (this.isGood) { this.Tag('精品', false) }
            }
          }
          if (this.title.length > 0) {
            Text(this.title).fontSize(ThreadCardLayout.BODY_SIZE).fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.TEXT_MAIN).lineHeight(ThreadCardLayout.LINE_HEIGHT)
              .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }
      if (this.summary.length > 0 && this.summary !== this.title) {
        Text() {
          ForEach(this.summaryPieces(), (piece: ContentPiece, index: number) => {
            if (piece.kind === ContentKind.EMOJI && piece.emojiUrl.length > 0) {
              ImageSpan(emojiSrc(piece.emojiUrl)).width(20).height(20)
                .verticalAlign(ImageSpanAlignment.CENTER).objectFit(ImageFit.Contain)
            } else {
              Span(piece.text)
            }
          }, (piece: ContentPiece, index: number) => `${index}:${piece.text}:${piece.emojiUrl}`)
        }.fontSize(ThreadCardLayout.BODY_SIZE).fontColor(AppTheme.TEXT_MAIN)
          .fontWeight(FontWeight.Normal)
          .lineHeight(ThreadCardLayout.LINE_HEIGHT).maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }
      if (this.images.length > 0) {
        ThreadPreviewImages({ images: this.images, scroller: this.imageScroller,
          onOpenImage: (index: number): void => { this.onOpenImage(index); } })
      }

      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(ThreadCardLayout.METRIC_GAP),
        cross: LengthMetrics.vp(6) } }) {
        this.Metric($r('sys.symbol.hand_thumbsup'), '赞', this.agreeCount)
        this.Metric($r('sys.symbol.message'), '评论', this.replyCount)
        this.Metric($r('sys.symbol.share'), '分享', this.shareCount)
        if (this.images.length > 1) {
          Text(`共 ${this.images.length} 张`).fontSize(ThreadCardLayout.META_SIZE).fontColor(AppTheme.TEXT_SUB)
        }
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
      .padding({ left: ThreadCardLayout.SIDE_PADDING, right: ThreadCardLayout.SIDE_PADDING,
        top: ThreadCardLayout.TOP_PADDING, bottom: ThreadCardLayout.BOTTOM_PADDING })
      .borderRadius(AppTheme.CARD_RADIUS).backgroundColor(AppTheme.CARD)
      .onClick(() => { this.onOpenThread(); })
  }
}
