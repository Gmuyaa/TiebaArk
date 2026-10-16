/**
 * 回复详情面板顶部的**锚点回复卡**：完整展示被展开的那条一级回复。
 *
 * 它的作用不是"缩略预览"，而是给下面那串回复提供上下文——
 * 所以正文用与主列表同一套富文本渲染（由页面以 `bodyBuilder` 传入），
 * 图片、长正文都完整展示，不截断、不折叠。
 *
 * 组件自身不碰网络：点赞与回复都只把点击意图抛给页面。
 */

import { PostItem } from '../model/ThreadDetail';
import { AgreeState } from '../viewmodel/ThreadDetailVM';
import { DetailTheme } from '../theme/Theme';
import { COMMENT_NICKNAME_SIZE } from '../common/appearance/PostTypography';
import { AvatarComponent } from './AvatarComponent';
import { ThreadAuthorBadge } from './ThreadAuthorBadge';
import { ReplyMetaBar } from './ReplyMetaBar';
import { CommentMetadata } from './CommentMetadata';
import { CommentActionHost } from './CommentActionHost';
import { postCommentTarget } from '../model/CommentAction';

@ComponentV2
export struct AnchorReplyCard {
  @Param tid: number = 0;
  @Param threadTitle: string = '';
  @Event onOpenAuthor: () => void = (): void => {};
  @Require @Param item: PostItem;
  /** 作者是否是楼主 */
  @Param isThreadAuthor: boolean = false;

  @Require @Param agreeState: AgreeState;
  /** 一级回复正文（富文本），由页面提供 */
  @BuilderParam bodyBuilder: () => void = this.emptyBody;
  /** 点赞点击 */
  @Event onToggleLike: () => void = (): void => {};
  /** 回复点击：调用方打开本层的回复框 */
  @Event onReply: () => void = (): void => {};

  @Builder
  emptyBody() {
  }

  @Builder
  Badge(text: string, filled: boolean) {
    Text(text)
      .fontSize(10)
      .fontColor(filled ? '#FFFFFF' : DetailTheme.ACCENT_DARK)
      .backgroundColor(filled ? DetailTheme.ACCENT : DetailTheme.ACCENT_LIGHT)
      .borderRadius(4)
      .padding({ left: 5, right: 5, top: 2, bottom: 2 })
  }

  build() {
    CommentActionHost({ target: postCommentTarget(this.item, this.tid, this.threadTitle),
      content: (): void => { this.ReplyContent(); } })
  }

  @Builder
  ReplyContent() {
    Row({ space: 12 }) {
      AvatarComponent({ url: this.item.author.portraitUrl, avatarSize: 36, fallbackName: this.item.author.displayName })
        .onClick(() => { this.onOpenAuthor(); })

      Column() {
        Row({ space: 10 }) {
          Row({ space: 6 }) {
            Text(this.item.author.displayName)
              .onClick(() => { this.onOpenAuthor(); })
              .fontSize(COMMENT_NICKNAME_SIZE)
              .flexShrink(1)
              .fontColor(DetailTheme.COMMENT_NICKNAME)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.isThreadAuthor) {
              ThreadAuthorBadge();
            }
            if (this.item.author.isBawu) {
              this.Badge('吧务', false);
            }
          }
          .layoutWeight(1)

          if (this.item.floor > 0) {
            Text(`${this.item.floor}楼`)
              .fontSize(12)
              .fontColor(DetailTheme.COMMENT_META)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        CommentMetadata({ timeText: this.item.timeText, ipLocation: this.item.author.ipLocation })
          .margin({ top: 2 })

        Column() {
          this.bodyBuilder();
        }
        .width('100%')
        .margin({ top: 8 })

        ReplyMetaBar({
          detailLayout: true,
          agreeState: this.agreeState,
          onToggleLike: this.onToggleLike,
          onReply: this.onReply
        })
          .margin({ top: 8 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: 16, right: 16, top: 14, bottom: 8 })
  }
}
