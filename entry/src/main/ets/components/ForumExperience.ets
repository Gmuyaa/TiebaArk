import { AppTheme } from '../theme/Theme';
import { ForumLevelBadge } from './ForumLevelBadge';

/** 紧凑行里等级徽章相对数字行的上抬量（vp）。纯渲染位移，不参与布局。 */
const FORUM_EXP_BADGE_LIFT: number = 2;

/** 吧头经验：紧凑行供身份摘要使用，默认布局保留等级和完整进度。 */
@ComponentV2
export struct ForumExperience {
  @Param currentScore: number = -1;
  @Param nextScore: number = -1;
  @Param level: number = -1;
  @Param levelName: string = '';
  @Param onHero: boolean = false;
  @Param compact: boolean = false;

  build() {
    if (this.compact) {
      // 2026-11-11：紧凑版要放进吧头「头像框 − 20vp」的 52vp 里（名称行 32 + 本条约 19），
      // 行距收到 1；浮在图上时数字/进度条换浅色，否则压在照片上看不清。
      Column({ space: 1 }) {
        Row({ space: 8 }) {
          // 2026-11-11 持有者定：等级在左、经验值在右，比原来「数值左 / 徽章右」看着不那么挤；
          // 徽章再单独上抬 2vp，视觉上不跟右侧数字贴同一条基线。
          ForumLevelBadge({ level: this.level, levelName: this.levelName, forceOfficial: true })
            .translate({ y: -FORUM_EXP_BADGE_LIFT })
            .id('forum-identity-level')
          Text(this.currentScore >= 0 && this.nextScore > 0 ? `${this.currentScore}/${this.nextScore}` :
            this.currentScore >= 0 ? `经验 ${this.currentScore}` : '经验未读取')
            .fontSize(11).fontColor(this.onHero ? '#E6FFFFFF' : AppTheme.TEXT_SUB).maxLines(1)
            .textAlign(TextAlign.End)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        }.width('100%').alignItems(VerticalAlign.Center)
        if (this.currentScore >= 0 && this.nextScore > 0) {
          Progress({ value: Math.min(this.currentScore, this.nextScore), total: this.nextScore,
            type: ProgressType.Linear })
            .width('100%')
            .color(this.onHero ? Color.White : AppTheme.ACCENT_DARK)
            .backgroundColor(this.onHero ? '#40FFFFFF' : AppTheme.ACCENT_LIGHT)
            .style({ strokeWidth: 2 }).id('forum-experience-progress')
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
    } else {
      Column({ space: 5 }) {
        Row({ space: 4 }) {
          if (this.level >= 0) {
            Text(`LV${this.level}${this.levelName.length > 0 ? ' ' + this.levelName : ''}`)
              .fontSize(12).fontColor(this.onHero ? '#CCD6E8' : AppTheme.TEXT_SUB)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          } else {
            Blank().layoutWeight(1)
          }
          if (this.currentScore >= 0 && this.nextScore > 0) {
            Text(`${this.currentScore}/${this.nextScore}`)
              .fontSize(12).fontColor(this.onHero ? '#CCD6E8' : AppTheme.TEXT_SUB)
              .maxLines(1)
          } else {
            Text(this.currentScore >= 0 ? `经验 ${this.currentScore}` : '经验未读取')
              .fontSize(12).fontColor(this.onHero ? '#CCD6E8' : AppTheme.TEXT_SUB)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(12).fontColor([this.onHero ? '#CCD6E8' : AppTheme.TEXT_SUB])
        }
        .width('100%').alignItems(VerticalAlign.Center)
        if (this.currentScore >= 0 && this.nextScore > 0) {
          Progress({ value: Math.min(this.currentScore, this.nextScore), total: this.nextScore,
            type: ProgressType.Linear })
            .width('100%').color(this.onHero ? Color.White : AppTheme.ACCENT_DARK)
            .backgroundColor(this.onHero ? '#40FFFFFF' : AppTheme.ACCENT_LIGHT)
            .style({ strokeWidth: 2 })
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
  }
}
