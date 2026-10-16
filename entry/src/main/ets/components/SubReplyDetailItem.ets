/**
 * 回复详情面板里的**一条楼中楼回复**（完整样式）。
 *
 * 与 `SubReplyPreviewItem`（灰块预览）刻意做成两种密度：
 *   预览：无头像、单行流式、"谁回复谁 + 内容"，只为让人扫一眼；
 *   面板：头像 + 昵称/身份、时间、正文及操作，接近正式评论区。
 *
 * 头像右侧内容整体缩进，保证多行正文与昵称左边缘对齐。
 */

import { SubPostItem } from '../model/ThreadDetail';
import { AgreeState } from '../viewmodel/ThreadDetailVM';
import { DetailTheme } from '../theme/Theme';
import { COMMENT_NICKNAME_SIZE } from '../common/appearance/PostTypography';
import { AvatarComponent } from './AvatarComponent';
import { ThreadAuthorBadge } from './ThreadAuthorBadge';
import { CommentActionHost } from './CommentActionHost';
import { CommentMetadata } from './CommentMetadata';
import { ReplyMetaBar } from './ReplyMetaBar';
import { subCommentTarget } from '../model/CommentAction';

@ComponentV2
export struct SubReplyDetailItem {
  @Param tid: number = 0;
  @Param parentPid: number = 0;
  @Param threadTitle: string = '';
  @Event onOpenAuthor: () => void = (): void => {};
  @Require @Param sub: SubPostItem;
  @Require @Param agreeState: AgreeState;
  /** 本条作者是否是当前父评论作者 */
  @Param isFloorAuthor: boolean = false;
  /** 正文（富文本），由页面提供，保证与主列表同一套渲染 */
  @BuilderParam bodyBuilder: () => void = this.emptyBody;
  /** 回复点击由调用方选择实际支持的发送目标 */
  @Event onReply: () => void = (): void => {};
  @Event onToggleLike: () => void = (): void => {};
  /** 正文里的图片点击 */
  @Event onViewImage: (url: string) => void = (): void => {};

  @Builder
  emptyBody() {
  }

  build() {
    CommentActionHost({ target: subCommentTarget(this.sub, this.tid, this.parentPid, this.threadTitle),
      content: (): void => { this.ReplyContent(); } })
  }

  @Builder
  ReplyContent() {
    Row({ space: 10 }) {
      AvatarComponent({ url: this.sub.author.portraitUrl, avatarSize: 32, fallbackName: this.sub.author.displayName })
        .onClick(() => { this.onOpenAuthor(); })

      Column() {
        Row({ space: 6 }) {
          Text(this.sub.author.displayName)
            .fontSize(COMMENT_NICKNAME_SIZE)
            .flexShrink(1)
            .fontColor(DetailTheme.SUB_REPLY_NAME)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .onClick(() => { this.onOpenAuthor(); })

          if (this.isFloorAuthor) {
            Text('层主')
              .fontSize(10)
              .fontColor(DetailTheme.ACCENT_DARK)
              .backgroundColor(DetailTheme.ACCENT_LIGHT)
              .borderRadius(4)
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
          }

          if (this.sub.isThreadAuthor) {
            ThreadAuthorBadge();
          }
          if (this.sub.author.isBawu) {
            Text('吧务')
              .fontSize(10)
              .fontColor(DetailTheme.ACCENT_DARK)
              .backgroundColor(DetailTheme.ACCENT_LIGHT)
              .borderRadius(4)
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
          }

        }
        .width('100%')

        CommentMetadata({ timeText: this.sub.timeText, ipLocation: this.sub.author.ipLocation })
          .margin({ top: 2 })

        Column() {
          this.bodyBuilder();
        }
        .width('100%')
        .margin({ top: 8 })

        ReplyMetaBar({
          detailLayout: true,
          agreeState: this.agreeState,
          onReply: this.onReply,
          onToggleLike: this.onToggleLike
        })
          .margin({ top: 8 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}
