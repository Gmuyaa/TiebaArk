import { AppTheme } from '../theme/Theme';
import { ForumLevelBadge } from './ForumLevelBadge';

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
      Column({ space: 5 }) {
        Row({ space: 8 }) {
          Text(this.currentScore >= 0 && this.nextScore > 0 ? `${this.currentScore}/${this.nextScore}` :
            this.currentScore >= 0 ? `经验 ${this.currentScore}` : '经验未读取')
            .fontSize(11).fontColor(AppTheme.TEXT_SUB).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          ForumLevelBadge({ level: this.level, levelName: this.levelName, forceOfficial: true })
            .id('forum-identity-level')
        }.width('100%').alignItems(VerticalAlign.Center)
        if (this.currentScore >= 0 && this.nextScore > 0) {
          Progress({ value: Math.min(this.currentScore, this.nextScore), total: this.nextScore,
            type: ProgressType.Linear })
            .width('100%').color(AppTheme.ACCENT_DARK).backgroundColor(AppTheme.ACCENT_LIGHT)
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
