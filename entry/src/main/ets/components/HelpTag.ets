import { AppTheme } from '../theme/Theme';

/** 求助、回答与精华共用标签几何；精华沿用回答配色。 */
@ComponentV2
export struct HelpTag {
  @Param label: string = '求助';
  @Param emphasized: boolean = false;
  @Param answerStyle: boolean = false;
  @Param filled: boolean = false;
  @Param fontRatio: number = 1;
  @Param tagHeight: number = 12;
  build() {
    Text(this.label).fontSize(9).fontWeight(FontWeight.Normal)
      .fontColor(this.filled ? AppTheme.ON_EMPHASIS : (this.emphasized ? AppTheme.DANGER_TEXT :
        (this.answerStyle || this.label === '回答' ? AppTheme.HELP_ANSWER : AppTheme.ACCENT_DARK)))
      .width((this.label.length * 9 + 8) * this.fontRatio).height(this.tagHeight * this.fontRatio)
      .maxLines(1)
      .lineHeight(`${10 * this.fontRatio}vp`).textAlign(TextAlign.Center)
      .padding({ left: 3 * this.fontRatio, right: 3 * this.fontRatio })
      .backgroundColor(this.filled ? AppTheme.EMPHASIS : (this.label === '置顶' ? AppTheme.ACCENT_LIGHT : Color.Transparent))
      .border({ width: 0.5, color: this.filled ? AppTheme.EMPHASIS : (this.emphasized ? AppTheme.DANGER_TEXT :
        (this.answerStyle || this.label === '回答' ? AppTheme.HELP_ANSWER : AppTheme.ACCENT_DARK)) }).borderRadius(2.5)
      .flexShrink(0).accessibilityText(`${this.label}标签`)
  }
}
