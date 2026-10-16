import { AppTheme } from '../theme/Theme';

@ComponentV2
export struct ForumExperience {
  @Param currentScore: number = -1;
  @Param nextScore: number = -1;
  @Param onHero: boolean = false;

  build() {
    Column({ space: 3 }) {
      if (this.currentScore >= 0 && this.nextScore > 0) {
        Progress({ value: Math.min(this.currentScore, this.nextScore), total: this.nextScore,
          type: ProgressType.Linear })
          .width('100%').color(this.onHero ? '#DCE7FA' : AppTheme.ACCENT_DARK)
          .backgroundColor(this.onHero ? '#40FFFFFF' : AppTheme.ACCENT_LIGHT)
          .style({ strokeWidth: 3 })
        Text(`${this.currentScore}/${this.nextScore}`)
          .fontSize(10).fontColor(this.onHero ? '#CCD6E8' : AppTheme.TEXT_SUB)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      } else {
        Text(this.currentScore >= 0 ? `经验 ${this.currentScore}` : '经验未读取')
          .fontSize(10).fontColor(this.onHero ? '#CCD6E8' : AppTheme.TEXT_SUB)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
