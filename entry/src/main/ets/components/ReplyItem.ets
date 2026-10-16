/** 一级回复组件。点赞使用可观察状态对象，正文与楼中楼入口共用回复目标。 */

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

/** 头像边长 */
const AVATAR_SIZE: number = 36;
/** 头像与右栏的横向间距；右栏缩进全靠它，不要再给右栏加 padding-left */
const AVATAR_GAP: number = 12;

/** 时间／IP 行 → 正文第一行。 */
const NAME_BODY_GAP: number = 8;
/** 正文 → 操作行。 */
const BODY_META_GAP: number = 10;
/** 操作行 → 楼中楼预览灰块。 */
const SUB_BOX_GAP: number = 10;

@ComponentV2
export struct ReplyItem {
  @Param tid: number = 0;
  @Param threadTitle: string = '';
  /** 一级回复 */
  @Require @Param item: PostItem;
  /** 作者是否是楼主 */
  @Param isThreadAuthor: boolean = false;

  @Require @Param agreeState: AgreeState;
  /** 已加载的楼中楼预览数据 */
  @Param subPosts: SubPostItem[] = [];
  /** 该楼层的楼中楼总数 */
  @Param subTotalCount: number = 0;
  /** 楼中楼是否正在加载 */
  @Param subLoading: boolean = false;
  /** 楼中楼首页失败提示 */
  @Param subErrorText: string = '';
  /** 楼中楼里是否出现过楼主回复 */
  @Param hasAuthorReply: boolean = false;
  /** 一级回复正文（富文本），由页面提供 */
  @BuilderParam bodyBuilder: () => void = this.emptyBody;

  /** 点赞点击（本地乐观更新） */
  @Event onToggleLike: () => void = (): void => {};
  /** 单击正文或气泡图标打开当前楼层的回复框 */
  @Event onReply: () => void = (): void => {};
  /** 打开完整楼中楼 */
  @Event onOpenSubDetail: () => void = (): void => {};
  /** 楼中楼预览加载失败后重试 */
  @Event onRetrySubPosts: () => void = (): void => {};
  /** 楼中楼预览里的图片点击 */
  @Event onViewImage: (url: string) => void = (): void => {};

  @Builder
  emptyBody() {
  }

  /** 有楼中楼数据、正在加载或失败时都显示灰块，避免"有没有楼中楼"在视觉上闪烁 */
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
    // 左右双栏：左栏只有头像；右栏是「用户名行 → 正文 → 底部行 → 灰块」整列。
    // 正文起点由右列决定，头像不会把昵称行撑高。
    Row({ space: AVATAR_GAP }) {
      AvatarComponent({ url: this.item.author.portraitUrl, avatarSize: AVATAR_SIZE, fallbackName: this.item.author.displayName })
        .onClick(() => { openUserByIdentity(this.item.author.id, this.item.author.portraitUrl, this.item.author.displayName, this.getUIContext()); })

      // 不用 Column 的 space：三段纵向间距不相等，逐段用 margin 显式给（见常量区）
      Column() {
        // 顶部：作者（用户名 + 身份徽章）。
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

        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        CommentMetadata({ timeText: this.item.timeText, ipLocation: this.item.author.ipLocation })
          .margin({ top: 2 })

        // 时间与 IP 下方接正文，保留紧凑间距（NAME_BODY_GAP）。
        Column() {
          this.bodyBuilder();
        }
        .width('100%')
        .margin({ top: NAME_BODY_GAP })
        .onClick(() => { this.onReply(); })

        // 底部：楼层靠左，楼主回复标签接在右侧，点赞和回复图标靠右。
        // （不加右内边距：图标组右缘保持在 16vp 版心线）
        ReplyMetaBar({
          floor: this.item.floor,
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
    // 组间停顿只由上一条 bottom 提供：灰框或操作行底部到下一条头像顶为 28vp。
    .padding({ left: 16, right: 16, bottom: 28 })
  }
}
