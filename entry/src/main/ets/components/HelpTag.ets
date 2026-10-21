import { AppTheme } from '../theme/Theme';

/** 求助与回答标记统一尺寸；标签内容由服务端确认的帖子类型/回答字段决定。 */
@ComponentV2
export struct HelpTag {
  @Param label: string = '求助';
  @Param emphasized: boolean = false;
  build() {
    Text(this.label).fontSize(9).fontWeight(FontWeight.Normal)
      .fontColor(this.emphasized ? AppTheme.DANGER_TEXT : (this.label === '回答' ? AppTheme.HELP_ANSWER : AppTheme.ACCENT_DARK))
      .height(14).lineHeight(12).textAlign(TextAlign.Center)
      .padding({ left: 3, right: 3 })
      .border({ width: 0.5, color: this.emphasized ? AppTheme.DANGER_TEXT :
        (this.label === '回答' ? AppTheme.HELP_ANSWER : AppTheme.ACCENT_DARK) }).borderRadius(2.5)
      .flexShrink(0).accessibilityText(`${this.label}标签`)
  }
}
