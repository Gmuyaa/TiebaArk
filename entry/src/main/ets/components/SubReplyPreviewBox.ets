/**
 * 一级回复下方的**楼中楼预览灰块**。
 *
 * 全页只有这一块用浅灰底：主帖与一级回复都保持页面底色，
 * 靠"灰块"这一个视觉信号把"主回复"和"讨论串"分成两层。
 * 灰块不带阴影、不带边框，圆角 10；左右内边距 12，上下 10。
 *
 * 内容只给前若干条（默认 3 条）；总回复数至少 5 条时显示"查看 X 条回复 ›"。
 * 点击灰块任意位置与点击底部入口是**同一个动作**——从底部弹出回复详情面板
 * （`SubReplyDetailSheet`），不再跳独立页面。
 */

import { SubPostItem } from '../model/ThreadDetail';
import { DetailTheme } from '../theme/Theme';
import { SUB_REPLY_BODY_SIZE, SUB_REPLY_LINE_HEIGHT } from '../common/appearance/PostTypography';
import { SubReplyPreviewItem } from './SubReplyPreviewItem';
import { CommentActionHost } from './CommentActionHost';
import { subCommentTarget } from '../model/CommentAction';

/** 灰块里最多展示几条楼中楼。多了就不是预览了 */
const PREVIEW_LIMIT: number = 3;

@ComponentV2
export struct SubReplyPreviewBox {
  @Param tid: number = 0;
  @Param parentPid: number = 0;
  @Param threadTitle: string = '';
  /** 已加载的楼中楼（调用方负责只传需要的数量来源，这里再截断一次） */
  @Require @Param subPosts: SubPostItem[];
  /** 该楼层的回复总数，用于"查看 X 条回复 ›" */
  @Param totalCount: number = 0;
  /** 是否正在加载第一页 */
  @Param loading: boolean = false;
  /** 首页加载失败提示；为空表示没有失败 */
  @Param errorText: string = '';
  /** 打开回复详情面板 */
  @Event onOpenDetail: () => void = (): void => {};
  /** 首页失败后重试 */
  @Event onRetry: () => void = (): void => {};
  /** 预览里的图片点击 */
  @Event onViewImage: (url: string) => void = (): void => {};

  /** 预览条数：不超过上限，也不超过已加载条数 */
  private previewItems(): SubPostItem[] {
    const loaded: number = this.subPosts.length;
    const limit: number = loaded < PREVIEW_LIMIT ? loaded : PREVIEW_LIMIT;
    return this.subPosts.slice(0, limit);
  }

  /** 底部入口显示的条数：服务端总数优先，缺失时用已加载条数 */
  private totalForEntry(): number {
    return this.totalCount > 0 ? this.totalCount : this.subPosts.length;
  }

  /** 5 条起显示底部入口；不足 5 条仍可点击整个灰块打开详情。 */
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
            // 根列已有 8vp 间隔，额外 2vp 合成最后一条到入口的 10vp。
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
