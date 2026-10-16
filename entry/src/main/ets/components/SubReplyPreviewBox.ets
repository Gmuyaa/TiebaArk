

import { SubPostItem } from '../model/ThreadDetail';
import { DetailTheme } from '../theme/Theme';
import { SUB_REPLY_BODY_SIZE, SUB_REPLY_LINE_HEIGHT } from '../common/appearance/PostTypography';
import { SubReplyPreviewItem } from './SubReplyPreviewItem';
import { CommentActionHost } from './CommentActionHost';
import { subCommentTarget } from '../model/CommentAction';

const PREVIEW_LIMIT: number = 3;

@ComponentV2
export struct SubReplyPreviewBox {
  @Param tid: number = 0;
  @Param parentPid: number = 0;
  @Param threadTitle: string = '';

  @Require @Param subPosts: SubPostItem[];

  @Param totalCount: number = 0;

  @Param loading: boolean = false;

  @Param errorText: string = '';

  @Event onOpenDetail: () => void = (): void => {};

  @Event onRetry: () => void = (): void => {};

  @Event onViewImage: (url: string) => void = (): void => {};

  private previewItems(): SubPostItem[] {
    const loaded: number = this.subPosts.length;
    const limit: number = loaded < PREVIEW_LIMIT ? loaded : PREVIEW_LIMIT;
    return this.subPosts.slice(0, limit);
  }

  private totalForEntry(): number {
    return this.totalCount > 0 ? this.totalCount : this.subPosts.length;
  }

  private shouldShowEntry(): boolean {
    return this.totalForEntry() >= 5;
  }

  @Builder
  PreviewContent(sub: SubPostItem) {
    SubReplyPreviewItem({ sub: sub, onViewImage: this.onViewImage })
  }

  build() {
    Column({ space: 8 }) {
      if (this.loading && this.subPosts.length === 0) {
        Text('正在加载回复…')
          .fontSize(13)
          .fontColor(DetailTheme.TEXT_SUB)
          .width('100%')
      } else if (this.errorText.length > 0 && this.subPosts.length === 0) {
        Text(this.errorText)
          .fontSize(12)
          .fontColor(DetailTheme.ERROR)
          .width('100%')
        Text('重试')
          .fontSize(13)
          .fontColor(DetailTheme.ACCENT_DARK)
          .onClick(() => {
            this.onRetry();
          })
      } else {
        Column({ space: 8 }) {
          ForEach(this.previewItems(), (sub: SubPostItem) => {
            CommentActionHost({ target: subCommentTarget(sub, this.tid, this.parentPid, this.threadTitle),
              content: (): void => { this.PreviewContent(sub); } })
          }, (sub: SubPostItem) => `${sub.pid}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        if (this.shouldShowEntry()) {
          Text(`查看 ${this.totalForEntry()} 条回复 ›`)
            .fontSize(SUB_REPLY_BODY_SIZE)
            .lineHeight(SUB_REPLY_LINE_HEIGHT)
            .fontColor(DetailTheme.SUB_REPLY_NAME)
            .width('100%')

            .margin({ top: 2 })
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(10)
    .backgroundColor(DetailTheme.SUB_REPLY_BACKGROUND)
    .onClick(() => {
      this.onOpenDetail();
    })
  }
}
