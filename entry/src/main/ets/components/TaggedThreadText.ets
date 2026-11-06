import { ContentKind, ContentPiece } from '../model/ThreadDetail';
import { AppTheme } from '../theme/Theme';
import { emojiSrc } from '../common/emoji/EmojiSrc';
import { fontScaleStore } from '../common/appearance/FontSizeScaleStore';
import { fontSizeScaleOf } from '../common/appearance/FontSizeScale';
import { HelpTag } from './HelpTag';

/** 标签只占首行开头，不增加行高；后续行回到段落左边缘。 */
@ComponentV2
export struct TaggedThreadText {
  @Param text: string = '';
  @Param labels: string[] = [];
  @Param textSize: number = 16;
  @Param lineSize: number = 24;
  @Param weight: FontWeight = FontWeight.Bold;
  @Param textColor: ResourceColor | undefined = undefined;
  @Param lines: number = 3;
  @Param fillPinned: boolean = true;

  private fontRatio(): number {
    return fontSizeScaleOf(fontScaleStore.pref, fontScaleStore.systemScale, fontScaleStore.customSize);
  }

  private tagHeight(): number { return Math.min(12, this.textSize * 0.8); }

  private firstIndent(): number {
    let width: number = 0;
    // 含文字、左右内距、边框与像素取整余量，避免标签自身折行。
    for (const label of this.labels) { width += label.length * 9 + 8 + 4; }
    return width * this.fontRatio();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Text() {
        ForEach(ContentPiece.listFromRaw([{ type: 0, text: this.text.length > 0 ? this.text : '\u200b' }]),
          (piece: ContentPiece, index: number) => {
            if (piece.kind === ContentKind.EMOJI && piece.emojiUrl.length > 0) {
              ImageSpan(emojiSrc(piece.emojiUrl)).width(this.textSize).height(this.textSize)
                .verticalAlign(ImageSpanAlignment.CENTER).objectFit(ImageFit.Contain)
            } else { Span(piece.text) }
          }, (piece: ContentPiece, index: number) => `${index}:${piece.text}:${piece.emojiUrl}`)
      }.fontSize(this.textSize).fontWeight(this.weight)
        .fontColor(this.textColor ?? AppTheme.TEXT_MAIN).lineHeight(`${this.lineSize}fp`)
        .textIndent(`${this.firstIndent()}vp`)
        .maxLines(this.lines).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        .accessibilityText(`${this.labels.join(' ')} ${this.text}`.trim())
      if (this.labels.length > 0) {
        Row({ space: 4 * this.fontRatio() }) {
          ForEach(this.labels, (label: string) => {
            HelpTag({ label, filled: label === '置顶' && this.fillPinned, answerStyle: label === '精华',
              emphasized: label === '高赞回答', fontRatio: this.fontRatio(), tagHeight: this.tagHeight() })
          }, (label: string) => label)
        }.height(this.lineSize * this.fontRatio()).alignItems(VerticalAlign.Center)
          // 汉字墨迹中心略低于行盒中心，按字号同比修正，不按整段高度居中。
          .translate({ y: this.textSize * 0.1 * this.fontRatio() })
          .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      }
    }.width('100%')
  }
}
