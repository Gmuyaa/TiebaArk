import { AppTheme } from '../theme/Theme';

/** 个人成长等级（填充标签：主题强调色底 + 白字）；吧内等级使用ForumLevelBadge，缺失值不展示。 */
@ComponentV2
export struct UserGrowthBadge {
  @Param level: number = -1;

  build() {
    if (this.level >= 0) {
      Text(`Lv.${this.level}`).fontSize(10).fontWeight(FontWeight.Medium)
        .fontStyle(FontStyle.Italic)
        .fontColor(AppTheme.ON_ACCENT)
        .borderRadius(4)
        .padding({ left: 3, right: 5, top: 1, bottom: 1 })
        .backgroundColor(AppTheme.ACCENT)
        .flexShrink(0).accessibilityText(`个人等级 ${this.level}`)
    }
  }
}
