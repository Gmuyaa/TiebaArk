import { forumLevelStore } from '../common/appearance/ForumLevelStore';
import { AppTheme } from '../theme/Theme';

const LEVEL_ICONS: Resource[] = [
  $r('app.media.forum_level_1'), $r('app.media.forum_level_2'), $r('app.media.forum_level_3'),
  $r('app.media.forum_level_4'), $r('app.media.forum_level_5'), $r('app.media.forum_level_6'),
  $r('app.media.forum_level_7'), $r('app.media.forum_level_8'), $r('app.media.forum_level_9'),
  $r('app.media.forum_level_10'), $r('app.media.forum_level_11'), $r('app.media.forum_level_12'),
  $r('app.media.forum_level_13'), $r('app.media.forum_level_14'), $r('app.media.forum_level_15'),
  $r('app.media.forum_level_16'), $r('app.media.forum_level_17'), $r('app.media.forum_level_18')
];

const SIMPLE_LEVEL_ICONS: Resource[] = [
  $r('app.media.forum_level_simple_1'), $r('app.media.forum_level_simple_2'), $r('app.media.forum_level_simple_3'),
  $r('app.media.forum_level_simple_4'), $r('app.media.forum_level_simple_5'), $r('app.media.forum_level_simple_6'),
  $r('app.media.forum_level_simple_7'), $r('app.media.forum_level_simple_8'), $r('app.media.forum_level_simple_9'),
  $r('app.media.forum_level_simple_10'), $r('app.media.forum_level_simple_11'), $r('app.media.forum_level_simple_12'),
  $r('app.media.forum_level_simple_13'), $r('app.media.forum_level_simple_14'), $r('app.media.forum_level_simple_15'),
  $r('app.media.forum_level_simple_16'), $r('app.media.forum_level_simple_17'), $r('app.media.forum_level_simple_18')
];

/** 官方标签使用用户指定 APK 的等级素材；称号只使用该吧服务端值。 */
@ComponentV2
export struct ForumLevelBadge {
  @Param level: number = -1;
  @Param levelName: string = '';
  @Param onHero: boolean = false;
  private preference = forumLevelStore;
  @Local titleStretchWidth: number = 0;

  /** 官方 xl7.c() 对应 CAM_X0309 / 0306 / 0305 / 0319。 */
  private titleColor(): string {
    if (this.level <= 3) { return '#24D45C'; }
    if (this.level <= 9) { return '#2B87FF'; }
    return this.level <= 15 ? '#FFA32B' : '#FF792B';
  }

  /** 原图 x=0..50 / 50..76 / 76..86；固定高13vp，仅中段横向拉伸。 */
  @Builder
  OfficialBackground() {
    Row({ space: 0 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Image(LEVEL_ICONS[this.level - 1]).width(86 / 3).height(13).objectFit(ImageFit.Fill)
      }.width(50 / 3).height(13).clip(true).flexShrink(0)
      Stack({ alignContent: Alignment.TopStart }) {
        Image(LEVEL_ICONS[this.level - 1]).width(this.titleStretchWidth * 86 / 26).height(13)
          .objectFit(ImageFit.Fill).translate({ x: -this.titleStretchWidth * 50 / 26 })
      }.height(13).layoutWeight(1).clip(true)
        .onSizeChange((_oldValue: SizeOptions, newValue: SizeOptions): void => {
          this.titleStretchWidth = Number(newValue.width);
        })
      Stack({ alignContent: Alignment.TopStart }) {
        Image(LEVEL_ICONS[this.level - 1]).width(86 / 3).height(13).objectFit(ImageFit.Fill)
          .translate({ x: -76 / 3 })
      }.width(10 / 3).height(13).clip(true).flexShrink(0)
    }.width('100%').height(13)
  }

  build() {
    if (this.preference.style === 1 && this.level >= 1 && this.level <= LEVEL_ICONS.length) {
      if (this.levelName.length > 0) {
        // 移植 TbLevelView：完整 NinePatch 背景承载称号，而非裁图＋另画底色。
        // 固定高13vp，无需纵向拉伸；图形区按86:39原比例缩放。
        Text(this.levelName).fontSize(8.7).maxFontScale(1).fontWeight(FontWeight.Bold)
          .fontColor(this.titleColor()).height(13)
          .padding({ left: 16.3, right: 3.3 })
          .background(this.OfficialBackground)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ minWidth: 86 / 3, maxWidth: 82.4 })
          .id('forum-level-badge')
          .flexShrink(0)
          .accessibilityText(`等级 ${this.level} ${this.levelName}`)
      } else {
        // 官方空称号分支使用 icon_forum_level_N，布局 tbds44×tbds39。
        Image(SIMPLE_LEVEL_ICONS[this.level - 1]).width(14.7).height(13)
          .objectFit(ImageFit.Fill).accessibilityText(`等级 ${this.level}`)
      }
    } else {
      Text(this.onHero ? `LV${this.level}${this.levelName.length > 0 ? ` ${this.levelName}` : ''}` : `Lv.${this.level}`)
        .fontSize(this.onHero ? 12 : 11).fontColor(this.onHero ? '#CCD6E8' : AppTheme.ACCENT_DARK)
        .backgroundColor(this.onHero ? Color.Transparent : AppTheme.ACCENT_LIGHT)
        .borderRadius(6).padding({ left: this.onHero ? 0 : 5, right: this.onHero ? 0 : 5, top: 1, bottom: 1 })
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }
}
