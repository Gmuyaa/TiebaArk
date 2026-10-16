/** 一级回复下方的时间、回复入口与点赞操作行。 */

import { AgreeState } from '../viewmodel/ThreadDetailVM';
import { DetailTheme } from '../theme/Theme';

@ComponentV2
export struct ReplyMetaBar {
  /** 完整回复详情：只保留回复和点赞，操作行直接容纳 44vp 点击区。 */
  @Param detailLayout: boolean = false;
  /** 一级评论楼层号；缺失时不补占位。 */
  @Param floor: number = 0;
  /** 楼中楼里是否出现过楼主回复 */
  @Param hasAuthorReply: boolean = false;

  @Require @Param agreeState: AgreeState;
  /** 该父评论下的楼中楼数量；没有回复时只显示气泡。 */
  @Param subReplyCount: number = 0;
  /** 点赞点击 */
  @Event onToggleLike: () => void = (): void => {};
  /** 气泡图标（详情模式另有文字入口）打开当前父楼层的回复框 */
  @Event onReply: () => void = (): void => {};

  @Builder
  AuthorReplyPill() {
    Text('楼主回复了')
      .fontSize(12)
      .fontColor(DetailTheme.AUTHOR_BADGE_TEXT)
      .height(20)
      .padding({ left: 7, right: 7 })
      .borderRadius(9)
      .backgroundColor(DetailTheme.AUTHOR_BADGE_BACKGROUND)
  }

  @Builder
  LikeEntry() {
    Row({ space: 2 }) {

      SymbolGlyph(this.agreeState.liked() ? $r('sys.symbol.hand_thumbsup_fill')
        : $r('sys.symbol.hand_thumbsup'))
        .fontSize(15)
        .fontColor([this.agreeState.liked() ? DetailTheme.ACCENT : DetailTheme.COMMENT_ACTION])
      if (this.agreeState.displayCount() > 0) {
        Text(`${this.agreeState.displayCount()}`)
          .fontSize(12)
          .fontColor(this.agreeState.liked() ? DetailTheme.ACCENT : DetailTheme.COMMENT_ACTION)
      }
    }
    .constraintSize({ minWidth: this.detailLayout ? 44 : 40, minHeight: this.detailLayout ? 44 : 0 })
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.onToggleLike();
    })
  }

  build() {
    Row({ space: 8 }) {
      if (this.detailLayout) {
        Text('回复')
          .fontSize(12)
          .fontColor(DetailTheme.COMMENT_ACTION)
          .constraintSize({ minWidth: 48, minHeight: 44 })
          .textAlign(TextAlign.Start)
          .onClick(() => { this.onReply(); })
      }
      if (this.floor > 0) {
        Text(`${this.floor}楼`)
          .fontSize(12)
          .fontColor(DetailTheme.COMMENT_META)
      }
      if (this.hasAuthorReply) {
        this.AuthorReplyPill();
      }
      Blank()
        .layoutWeight(1)

      Row({ space: 8 }) {
        this.LikeEntry()
        if (!this.detailLayout) {
          Row({ space: 2 }) {
            SymbolGlyph($r('sys.symbol.message'))
              .fontSize(15)
              .fontColor([DetailTheme.COMMENT_ACTION])
            if (this.subReplyCount > 0) {
              Text(`${this.subReplyCount}`)
                .fontSize(12)
                .fontColor(DetailTheme.COMMENT_ACTION)
            }
          }
          // 触控区向右延伸 15vp 进页边距（负 margin 不占布局宽），互动组右缘正好
          // 落在 16vp 版心线上；图标与数字间距 2vp，两组之间间距 8vp。
          .padding({ right: 15 })
          .margin({ right: -15 })
          .onClick(() => {
            this.onReply();
          })
        }
      }
    }
    // 外层保持内容高度；详情模式由 44vp 点击区撑开，不额外叠加上下内边距。
    .width('100%')
  }
}
