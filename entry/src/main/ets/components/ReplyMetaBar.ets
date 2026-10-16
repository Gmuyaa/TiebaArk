

import { AgreeState } from '../viewmodel/ThreadDetailVM';
import { DetailTheme } from '../theme/Theme';

@ComponentV2
export struct ReplyMetaBar {

  @Param detailLayout: boolean = false;

  @Param hasAuthorReply: boolean = false;

  @Require @Param agreeState: AgreeState;

  @Param subReplyCount: number = 0;

  @Event onToggleLike: () => void = (): void => {};

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
    Row({ space: 4 }) {

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
      Text('回复')
        .fontSize(12)
        .fontColor(DetailTheme.COMMENT_ACTION)
        .constraintSize({ minWidth: this.detailLayout ? 48 : 40, minHeight: this.detailLayout ? 44 : 0 })
        .textAlign(TextAlign.Start)
        .onClick(() => { this.onReply(); })
      if (this.hasAuthorReply) {
        this.AuthorReplyPill();
      }
      Blank()
        .layoutWeight(1)

      Row({ space: 0 }) {
        this.LikeEntry()
        if (!this.detailLayout) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.message'))
              .fontSize(15)
              .fontColor([DetailTheme.COMMENT_ACTION])
            if (this.subReplyCount > 0) {
              Text(`${this.subReplyCount}`)
                .fontSize(12)
                .fontColor(DetailTheme.COMMENT_ACTION)
            }
          }

          .padding({ right: 15 })
          .margin({ right: -15 })
          .onClick(() => {
            this.onReply();
          })
        }
      }
    }

    .width('100%')
  }
}
