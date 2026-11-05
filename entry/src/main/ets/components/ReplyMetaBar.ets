/** 评论下方的楼层、楼主回复提示与点赞操作行；详情模式保留左侧文字回复入口。 */

import { AgreeState } from '../viewmodel/ThreadDetailVM';
import { DetailTheme } from '../theme/Theme';

@ComponentV2
export struct ReplyMetaBar {
  /** 完整回复详情：32vp 视觉操作行，点击区向上下各延伸 6vp。 */
  @Param detailLayout: boolean = false;
  /** 一级评论楼层号；缺失时不补占位。 */
  @Param floor: number = 0;
  /** 楼中楼里是否出现过楼主回复 */
  @Param hasAuthorReply: boolean = false;

  @Require @Param agreeState: AgreeState;
  /** 点赞点击 */
  @Event onToggleLike: () => void = (): void => {};
  /** 详情模式的文字入口回复当前评论，由调用方区分父楼层与子评论。 */
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
    .constraintSize({ minWidth: this.detailLayout ? 44 : 40, minHeight: this.detailLayout ? 32 : 0 })
    .justifyContent(FlexAlign.Center)
    .responseRegion(this.detailLayout
      ? [{ x: 0, y: 0, width: '100%', height: '100%' }, { x: 0, y: -6, width: '100%', height: 44 }]
      : { x: 0, y: 0, width: '100%', height: '100%' })
    .borderRadius(8)
    .accessibilityGroup(true)
    .accessibilityText(this.agreeState.liked() ? '取消点赞' : '点赞')
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
          .constraintSize({ minWidth: 48, minHeight: 32 })
          .textAlign(TextAlign.Start)
          .responseRegion([{ x: 0, y: 0, width: '100%', height: '100%' },
            { x: 0, y: -6, width: '100%', height: 44 }])
          .borderRadius(8)
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

      this.LikeEntry()
    }
    // 外层保持内容高度，详情点击区扩展不撑大视觉行。
    .width('100%')
  }
}
