import { DetailTheme } from '../theme/Theme';

/** 昵称下方的评论时间与 IP；缺失字段不补占位内容。 */
@ComponentV2
export struct CommentMetadata {
  @Param timeText: string = '';
  @Param ipLocation: string = '';

  private text(): string {
    if (this.timeText.length === 0) { return this.ipLocation; }
    return this.ipLocation.length > 0 ? `${this.timeText} · ${this.ipLocation}` : this.timeText;
  }

  build() {
    if (this.text().length > 0) {
      Text(this.text())
        .fontSize(12)
        .fontColor(DetailTheme.COMMENT_META)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
  }
}
