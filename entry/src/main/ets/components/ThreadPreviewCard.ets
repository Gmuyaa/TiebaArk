import { visualThemeStore } from '../common/appearance/VisualThemeStore';
import { ThreadCardActionState } from '../viewmodel/ThreadCardActionsVM';
import { AppTheme } from '../theme/Theme';
import { ThreadCardLayout } from '../common/appearance/ThreadCardLayout';
import { PaperLayout } from '../common/appearance/VisualTheme';
import { ContentPiece } from '../model/ThreadDetail';
import { ThreadPreviewImages } from './ThreadPreviewImages';
import { ForumAvatarImage, forumAvatarRadius } from './ForumAvatarImage';
import { AvatarComponent } from './AvatarComponent';
import { PostContentInline } from './PostContentInline';
import { TaggedThreadText } from './TaggedThreadText';
import { materialManager } from '../common/material/MaterialManager';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { popupMotion } from '../common/appearance/MotionPolicy';

/** 标准帖子卡：页面传入展示值与动作，组件不发请求、不执行导航。 */
@ComponentV2
export struct ThreadPreviewCard {
  @Param authorName: string = '';
  @Param authorAvatar: string = '';
  @Param forumName: string = '';
  @Param forumAvatar: string = '';
  @Param forumAvatarRevision: number = 0;
  /** 我的帖子复用吧内卡片布局，以吧身份替代作者身份。 */
  @Param forumIdentity: boolean = false;
  @Param headerStatus: string = '';
  @Param menuBusy: boolean = false;
  /** 仅传已确认的发帖日期；不要将最后回复时间填到作者信息中。 */
  @Param postedTime: string = '';
  @Param title: string = '';
  @Param summary: string = '';
  @Param contentPieces: ContentPiece[] = [];
  @Event onActivateContent: (piece: ContentPiece) => void = (_piece: ContentPiece): void => {};
  @Param images: string[] = [];
  @Param originImages: string[] = [];
  /** 图片排布偏好仅由指定的信息流入口启用。 */
  @Param useImageLayoutPreference: boolean = false;
  @Param isTop: boolean = false;
  @Param isGood: boolean = false;
  @Param isHelp: boolean = false;
  @Local actionState: ThreadCardActionState = new ThreadCardActionState();
  @Event onToggleLike: (state: ThreadCardActionState) => void = (_state: ThreadCardActionState): void => {};
  @Event onOpenComments: () => void = (): void => {};
  @Event onShare: () => void = (): void => {};
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

  private titleLabels(): string[] {
    const labels: string[] = [];
    if (this.isTop) { labels.push('置顶'); }
    if (this.isGood) { labels.push('精华'); }
    if (this.isHelp) { labels.push('求助'); }
    return labels;
  }

  private metricCount(label: string): number {
    if (label === '赞') { return this.actionState?.count(this.agreeCount) ?? this.agreeCount; }
    return label === '评论' ? this.replyCount : this.shareCount;
  }

  private activateMetric(label: string): void {
    if (label === '赞') {
      if (!this.actionState?.isPreparing()) { this.onToggleLike(this.actionState); }
    } else if (label === '评论') { this.onOpenComments(); }
    else { this.onShare(); }
  }

  private metricColor(label: string): ResourceColor {
    const liked: boolean = label === '赞' && (this.actionState?.liked() ?? false);
    if (!visualThemeStore.isPaper) { return liked ? AppTheme.ACCENT : AppTheme.TEXT_SUB; }
    if (liked) { return AppTheme.EMPHASIS; }
    return AppTheme.TEXT_SUB;
  }

  /** 独立动作读取稳定观察态，避免在列表复用时捕获旧计数。 */
  @Builder
  Metric(icon: Resource, label: string) {
    Row({ space: ThreadCardLayout.METRIC_ITEM_GAP }) {
      if (label === '赞' && this.actionState?.isPreparing()) {
        LoadingProgress().width(ThreadCardLayout.METRIC_ICON_SIZE).height(ThreadCardLayout.METRIC_ICON_SIZE)
      } else {
        SymbolGlyph(label === '赞' && this.actionState?.liked() ? $r('sys.symbol.hand_thumbsup_fill') : icon)
          .fontSize(ThreadCardLayout.METRIC_ICON_SIZE).maxFontScale(1)
          .fontColor([this.metricColor(label)])
      }
      Text(this.metricCount(label) < 0 ? '—' : `${this.metricCount(label)}`).fontSize(ThreadCardLayout.METRIC_TEXT_SIZE)
        .fontColor(this.metricColor(label))
    }
    .layoutWeight(1).justifyContent(FlexAlign.Center)
    .accessibilityGroup(true)
    .constraintSize({ minHeight: 32 })
    // 紧凑排布与点击范围分开；保留完整行热区，极大字号撑高时也不会裁掉响应范围。
    .responseRegion([
      { x: 0, y: 0, width: '100%', height: '100%' },
      { x: 0, y: -8, width: '100%', height: 48 }
    ])
    .borderRadius(12)
    .id(label === '赞' ? 'thread-card-like' : (label === '评论' ? 'thread-card-comment' : 'thread-card-share'))
    .accessibilityText(`${label === '赞' && this.actionState?.liked() ? '取消点赞' : label} ${this.metricCount(label) < 0 ? '数量未知' : this.metricCount(label)}`)
    .onClick(() => { this.activateMetric(label); })
  }

  private openAuthor(): void {
    if (this.canOpenAuthor) { this.onOpenAuthor(); } else { this.onOpenThread(); }
  }
  private openForum(): void {
    if (this.canOpenForum) { this.onOpenForum(); } else { this.onOpenThread(); }
  }

  @Builder
  HeaderMenu() {
    if (this.headerStatus.length > 0 || this.menu.length > 0) {
      Row({ space: 6 }) {
        if (this.headerStatus.length > 0) {
          Text(this.headerStatus).fontSize(11).fontColor(AppTheme.TEXT_SUB)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor(AppTheme.BG).borderRadius(4)
            .maxLines(1).flexShrink(0).id('thread-card-header-status')
        }
        if (this.menu.length > 0) {
          if (this.menuBusy) {
            LoadingProgress().width(32).height(24).accessibilityText('正在处理帖子')
          } else {
            // SDK没有裸横向三点符号，复用官方圆点组合，避免文字字体的基线偏移。
            Row() {
              ForEach([0, 1, 2], (_index: number) => {
                SymbolGlyph($r('sys.symbol.dot')).fontSize(8).maxFontScale(1).fontColor([AppTheme.TEXT_SUB])
              })
            }.width(32).height(24).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
              .responseRegion({ x: -8, y: -12, width: 48, height: 48 })
              .id('thread-card-more').accessibilityGroup(true).accessibilityText('更多').bindMenu(this.menu, {
                systemMaterial: materialManager.officialOf(MaterialSlot.SHEET), transition: popupMotion()
              })
          }
        }
      }.alignItems(VerticalAlign.Center).flexShrink(0)
    }
  }

  @Builder
  IdentityHeader() {
    if (this.forumName.length > 0 && !this.forumIdentity) {
      Row({ space: ThreadCardLayout.SECTION_GAP }) {
        ForumAvatarImage({ url: this.forumAvatar, forumName: this.forumName, retryRevision: this.forumAvatarRevision,
          avatarSize: ThreadCardLayout.AVATAR_SIZE, radius: forumAvatarRadius(ThreadCardLayout.AVATAR_SIZE) })
          .id('thread-card-forum-avatar').flexShrink(0).onClick(() => { this.openForum(); })
        Column({ space: 2 }) {
          Row({ space: 6 }) {
            Text(this.forumName.endsWith('吧') ? this.forumName : `${this.forumName}吧`)
              .fontSize(ThreadCardLayout.AUTHOR_SIZE).fontWeight(FontWeight.Medium)
              .fontColor(visualThemeStore.isPaper ? AppTheme.ACCENT_DARK : AppTheme.TEXT_MAIN)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
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
        if (this.forumIdentity) {
          ForumAvatarImage({ url: this.forumAvatar, forumName: this.forumName, retryRevision: this.forumAvatarRevision,
            avatarSize: ThreadCardLayout.AVATAR_SIZE, radius: forumAvatarRadius(ThreadCardLayout.AVATAR_SIZE) })
            .id('thread-card-primary-forum-avatar').onClick(() => { this.openForum(); })
        } else {
          AvatarComponent({ url: this.authorAvatar, avatarSize: ThreadCardLayout.AVATAR_SIZE,
            fallbackName: this.authorName }).id('thread-card-primary-author-avatar')
            .onClick(() => { this.openAuthor(); })
        }
        Column({ space: 5 }) {
          Text(this.forumIdentity ? (this.forumName.length > 0
            ? (this.forumName.endsWith('吧') ? this.forumName : `${this.forumName}吧`) : '贴吧')
            : (this.authorName.length > 0 ? this.authorName : '贴吧用户'))
            .fontSize(ThreadCardLayout.AUTHOR_SIZE).fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT_MAIN).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .id('thread-card-primary-author-name').width('100%').onClick(() => {
              if (this.forumIdentity) { this.openForum(); } else { this.openAuthor(); }
            })
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

  /** 空阅读组不参与排布，纯图卡只产生一次身份到图片的间距。 */
  private hasReadingContent(): boolean {
    return this.title.length > 0 || this.isTop || this.isGood || this.isHelp ||
      ((this.summary.length > 0 || this.contentPieces.length > 0) && this.summary !== this.title);
  }

  @Builder
  ReadingContent() {
    Column({ space: visualThemeStore.isPaper ? PaperLayout.CARD_TEXT_GAP : ThreadCardLayout.TITLE_BODY_GAP }) {
      if (this.title.length > 0 || this.isTop || this.isGood || this.isHelp) {
        TaggedThreadText({ text: this.title, labels: this.titleLabels(),
          textColor: AppTheme.TEXT_MAIN,
          textSize: visualThemeStore.isPaper ? PaperLayout.CARD_TITLE_SIZE : ThreadCardLayout.TITLE_SIZE,
          lineSize: visualThemeStore.isPaper ? PaperLayout.CARD_TITLE_LINE : ThreadCardLayout.TITLE_LINE })
      }
      if ((this.summary.length > 0 || this.contentPieces.length > 0) && this.summary !== this.title) {
        Text() {
          if (this.contentPieces.length > 0) {
            PostContentInline({ pieces: this.contentPieces, emojiSize: 20, textColor: AppTheme.TEXT_MAIN,
              accentColor: AppTheme.ACCENT_DARK,
              onActivate: (piece: ContentPiece): void => { this.onActivateContent(piece); } })
          } else {
            // 仅返回摘要字符串的接口仍需解析官方表情；渲染与正文使用同一组件。
            PostContentInline({ pieces: this.summaryPieces(), emojiSize: 20, textColor: AppTheme.TEXT_MAIN,
              accentColor: AppTheme.ACCENT_DARK,
              onActivate: (piece: ContentPiece): void => { this.onActivateContent(piece); } })
          }
        }.fontSize(ThreadCardLayout.BODY_SIZE).fontColor(AppTheme.TEXT_MAIN)
          .fontWeight(FontWeight.Normal)
          .lineHeight(ThreadCardLayout.LINE_HEIGHT).maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  Content() {
    Column({ space: visualThemeStore.isPaper ? PaperLayout.CARD_CONTENT_GAP : ThreadCardLayout.SECTION_GAP }) {
      this.IdentityHeader()
      if (this.hasReadingContent()) {
        this.ReadingContent()
      }
      if (this.images.length > 0) {
        ThreadPreviewImages({ images: this.images, originImages: this.originImages, scroller: this.imageScroller,
          useImageLayoutPreference: this.useImageLayoutPreference,
          onOpenImage: (index: number): void => { this.onOpenImage(index); } })
      }

    }.width('100%').alignItems(HorizontalAlign.Start)
      .padding({ left: ThreadCardLayout.SIDE_PADDING, right: ThreadCardLayout.SIDE_PADDING })
      .onClick(() => { this.onOpenThread(); })
  }

  build() {
    Column({ space: ThreadCardLayout.SECTION_GAP }) {
      this.Content()
      Row() {
        this.Metric($r('sys.symbol.hand_thumbsup'), '赞')
        this.Metric($r('sys.symbol.message'), '评论')
        this.Metric($r('sys.symbol.share'), '分享')
      }.width('100%')
        .padding({ left: ThreadCardLayout.METRIC_SIDE_PADDING, right: ThreadCardLayout.METRIC_SIDE_PADDING })
        .id('thread-card-metrics')
    }.width('100%').alignItems(HorizontalAlign.Start)
      .padding({ top: ThreadCardLayout.TOP_PADDING, bottom: ThreadCardLayout.BOTTOM_PADDING })
      .borderRadius(ThreadCardLayout.RADIUS).backgroundColor(AppTheme.CARD)
      .border({ width: { bottom: visualThemeStore.isPaper ? 0.5 : 0 }, color: AppTheme.DIVIDER })
  }
}
