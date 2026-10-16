
import { ContentKind, ContentPiece, linkLabel, webLinkUrl } from '../model/ThreadDetail';
import { emojiSrc } from '../common/emoji/EmojiSrc';
import { DetailTheme } from '../theme/Theme';

interface PostContentInlineParams {
  pieces: ContentPiece[];
  emojiSize: number;
  textColor: ResourceColor;
  accentColor: ResourceColor;
  onActivate: (piece: ContentPiece) => void;
}

@Builder
export function PostContentInline($$: PostContentInlineParams) {
  ForEach($$.pieces, (piece: ContentPiece, index: number) => {
    if (piece.kind === ContentKind.EMOJI && piece.emojiUrl.length > 0) {
      ImageSpan(emojiSrc(piece.emojiUrl))
        .width($$.emojiSize)
        .height($$.emojiSize)
        .verticalAlign(ImageSpanAlignment.CENTER)
        .objectFit(ImageFit.Contain)
    } else if (piece.kind === ContentKind.TOPIC || piece.kind === ContentKind.LINK) {
      if (piece.kind === ContentKind.LINK && webLinkUrl(piece.link).length > 0) {
        SymbolSpan($r('sys.symbol.link'))
          .fontColor([$$.accentColor])
        Span('\u00A0')
      }
      Span(piece.kind === ContentKind.TOPIC ? piece.text : linkLabel(piece.link, piece.text))
        .fontColor(piece.kind === ContentKind.TOPIC || webLinkUrl(piece.link).length > 0
          ? $$.accentColor : $$.textColor)
        .onClick(() => { $$.onActivate(piece); })
    } else if (piece.kind === ContentKind.REPLY_TARGET) {
      Span(piece.text)
        .fontColor(DetailTheme.COMMENT_ACTION)
    } else if (piece.kind !== ContentKind.IMAGE) {
      Span(piece.text)
        .fontColor($$.textColor)
    }
  }, (piece: ContentPiece, index: number) => `${index}`)
}
