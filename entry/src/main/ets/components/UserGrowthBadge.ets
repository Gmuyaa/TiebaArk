import { DetailTheme } from '../theme/Theme';

/** 个人成长等级；吧内等级使用ForumLevelBadge，缺失值不展示。 */
@ComponentV2
export struct UserGrowthBadge {
  @Param level: number = -1;

  build() {
    if (this.level >= 0) {
      Text(`Lv.${this.level}`).fontSize(10).fontWeight(FontWeight.Medium)
        .fontColor(DetailTheme.ACCENT_DARK).borderRadius(4)
        .padding({ left: 4, right: 4, top: 1, bottom: 1 })
        .border({ width: 0.5, color: DetailTheme.ACCENT })
        .flexShrink(0).accessibilityText(`个人等级 ${this.level}`)
    }
  }
}
