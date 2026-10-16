import { AppTheme } from '../theme/Theme';

/** 吧头经验：细进度条在上，等级称号与真实经验在下，不用等级推算经验。 */
@ComponentV2
export struct ForumExperience {
  @Param currentScore: number = -1;
  @Param nextScore: number = -1;
  @Param level: number = -1;
  @Param levelName: string = '';
  @Param onHero: boolean = false;

  build() {
    Column({ space: 5 }) {
      if (this.currentScore >= 0 && this.nextScore > 0) {
        Progress({ value: Math.min(this.currentScore, this.nextScore), total: this.nextScore,
          type: ProgressType.Linear })
          .width('100%').color(this.onHero ? Color.White : AppTheme.ACCENT_DARK)
          .backgroundColor(this.onHero ? '#40FFFFFF' : AppTheme.ACCENT_LIGHT)
          .style({ strokeWidth: 2 })
      }
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
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
