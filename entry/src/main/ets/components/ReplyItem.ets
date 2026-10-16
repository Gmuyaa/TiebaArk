

import { openUserByIdentity } from '../navigation/UserNavigation';
import { PostItem, SubPostItem } from '../model/ThreadDetail';
import { AgreeState } from '../viewmodel/ThreadDetailVM';
import { DetailTheme } from '../theme/Theme';
import { COMMENT_NICKNAME_SIZE } from '../common/appearance/PostTypography';
import { AvatarComponent } from './AvatarComponent';
import { ThreadAuthorBadge } from './ThreadAuthorBadge';
import { ReplyMetaBar } from './ReplyMetaBar';
import { CommentMetadata } from './CommentMetadata';
import { SubReplyPreviewBox } from './SubReplyPreviewBox';
import { CommentActionHost } from './CommentActionHost';
import { postCommentTarget } from '../model/CommentAction';

const AVATAR_SIZE: number = 36;

const AVATAR_GAP: number = 12;

const NAME_BODY_GAP: number = 8;

const BODY_META_GAP: number = 10;

const SUB_BOX_GAP: number = 10;

@ComponentV2
export struct ReplyItem {
  @Param tid: number = 0;
  @Param threadTitle: string = '';

  @Require @Param item: PostItem;

  @Param isThreadAuthor: boolean = false;

  @Require @Param agreeState: AgreeState;

  @Param subPosts: SubPostItem[] = [];

  @Param subTotalCount: number = 0;

  @Param subLoading: boolean = false;

  @Param subErrorText: string = '';

  @Param hasAuthorReply: boolean = false;

  @BuilderParam bodyBuilder: () => void = this.emptyBody;

  @Event onToggleLike: () => void = (): void => {};

  @Event onReply: () => void = (): void => {};

  @Event onOpenSubDetail: () => void = (): void => {};

  @Event onRetrySubPosts: () => void = (): void => {};

  @Event onViewImage: (url: string) => void = (): void => {};

  @Builder
  emptyBody() {
  }

  private shouldShowSubPreview(): boolean {
    return this.subPosts.length > 0 || this.subLoading || this.subErrorText.length > 0;
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

    Row({ space: AVATAR_GAP }) {
      AvatarComponent({ url: this.item.author.portraitUrl, avatarSize: AVATAR_SIZE, fallbackName: this.item.author.displayName })
        .onClick(() => { openUserByIdentity(this.item.author.id, this.item.author.portraitUrl, this.item.author.displayName, this.getUIContext()); })

      Column() {

        Row({ space: 10 }) {
          Row({ space: 6 }) {
            Text(this.item.author.displayName)
              .fontSize(COMMENT_NICKNAME_SIZE)
              .fontColor(DetailTheme.COMMENT_NICKNAME)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick(() => { openUserByIdentity(this.item.author.id, this.item.author.portraitUrl, this.item.author.displayName, this.getUIContext()); })
            if (this.isThreadAuthor) {
              ThreadAuthorBadge();
            }
            if (this.item.author.isBawu) {
              this.Badge('吧务', false);
            }
          }
          .layoutWeight(1)
          .alignItems(VerticalAlign.Center)

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
        .margin({ top: NAME_BODY_GAP })

        ReplyMetaBar({
          hasAuthorReply: this.hasAuthorReply,
          agreeState: this.agreeState,
          subReplyCount: this.subTotalCount,
          onToggleLike: this.onToggleLike,
          onReply: this.onReply
        })
          .margin({ top: BODY_META_GAP })

        if (this.shouldShowSubPreview()) {
          SubReplyPreviewBox({
            tid: this.tid,
            parentPid: this.item.pid,
            threadTitle: this.threadTitle,
            subPosts: this.subPosts,
            totalCount: this.subTotalCount,
            loading: this.subLoading,
            errorText: this.subErrorText,
            onOpenDetail: this.onOpenSubDetail,
            onRetry: this.onRetrySubPosts,
            onViewImage: this.onViewImage
          })
            .margin({ top: SUB_BOX_GAP })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)

    .padding({ left: 16, right: 16, bottom: 28 })
  }
}
