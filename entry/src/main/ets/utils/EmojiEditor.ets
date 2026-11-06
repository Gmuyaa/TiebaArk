import { emojiSrc } from '../common/emoji/EmojiSrc';
import { emojiCodeFromReplyToken, emojiImageUrl } from '../model/ThreadDetail';
import { ReplyEditorContent, ReplyEditorSpan, serializeReplyEditor } from '../model/ReplyEditor';

/** 换肤只更新文字颜色，不重建 spans，不改变草稿、图片、选区或光标。 */
export function updateEmojiEditorTextColor(controller: RichEditorController, textColor: ResourceColor): void {
  const spans: Array<RichEditorImageSpanResult | RichEditorTextSpanResult> = controller.getSpans();
  for (const span of spans) {
    const text: RichEditorTextSpanResult = span as RichEditorTextSpanResult;
    if (typeof text.value === 'string' && text.value.length > 0) {
      controller.updateSpanStyle({ start: span.spanPosition.spanRange[0], end: span.spanPosition.spanRange[1],
        textStyle: { fontColor: textColor } });
    }
  }
}

/** 评论和发帖统一从实际 spans 提取正文，图片显示与协议 token 分开。 */
export function readEmojiEditor(controller: RichEditorController,
  memeTokens: Map<string, string>, imageTokens: Map<string, string>): ReplyEditorContent {
  const adapted: ReplyEditorSpan[] = [];
  const spans: Array<RichEditorImageSpanResult | RichEditorTextSpanResult> = controller.getSpans();
  for (const span of spans) {
    const item: ReplyEditorSpan = new ReplyEditorSpan();
    item.text = (span as RichEditorTextSpanResult).value ?? '';
    item.imageSource = String((span as RichEditorImageSpanResult).valueResourceStr ?? '');
    item.editorLength = span.spanPosition.spanRange[1] - span.spanPosition.spanRange[0];
    adapted.push(item);
  }
  return serializeReplyEditor(adapted, memeTokens, imageTokens);
}

/** 仅还原已确认的内置/收藏 token，未知内容继续作为文字保留。 */
export function restoreEmojiEditor(controller: RichEditorController, text: string,
  memeTokens: Map<string, string>, textColor: ResourceColor): void {
  controller.deleteSpans();
  let start: number = 0;
  let cursor: number = 0;
  while (cursor < text.length) {
    const open: number = text.indexOf('#(', cursor);
    if (open < 0) { break; }
    const close: number = text.indexOf(')', open + 2);
    if (close < 0) { break; }
    const token: string = text.substring(open, close + 1);
    const code: string = emojiCodeFromReplyToken(token);
    let url: string = code.length > 0 ? emojiImageUrl(code) : '';
    if (url.length === 0) {
      memeTokens.forEach((value: string, key: string): void => { if (value === token) { url = key; } });
    }
    if (url.length > 0) {
      if (open > start) { controller.addTextSpan(text.substring(start, open), { style: { fontSize: 16, fontColor: textColor } }); }
      controller.addImageSpan(emojiSrc(url), { imageStyle: { size: [22, 22] } });
      start = close + 1;
    }
    cursor = close + 1;
  }
  if (start < text.length) { controller.addTextSpan(text.substring(start), { style: { fontSize: 16, fontColor: textColor } }); }
}
