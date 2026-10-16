import { AtCandidate, AtEditorMention, prepareAtMention } from './AtCandidates';
import { emojiTokenFromUrl } from './ThreadDetail';

/** 仅记录显式选人的编辑区间；修改名字后不再推断为已确认提及。 */
export class ReplyMentionRange {
  start: number = 0; end: number = 0;
  mention: AtEditorMention | undefined = undefined;
}
export class ReplyMentionBook {
  private entries: ReplyMentionRange[] = [];
  clear(): void { this.entries = []; }
  ranges(): ReplyMentionRange[] {
    return this.entries.map((entry: ReplyMentionRange) => {
      const copy: ReplyMentionRange = new ReplyMentionRange();
      copy.start = entry.start; copy.end = entry.end; copy.mention = entry.mention; return copy;
    });
  }
  add(start: number, candidate: AtCandidate): boolean {
    const mention: AtEditorMention | undefined = prepareAtMention(candidate);
    if (!Number.isSafeInteger(start) || start < 0 || mention === undefined) { return false; }
    const end: number = start + mention.displayText.length;
    if (!Number.isSafeInteger(end) || this.entries.some((entry: ReplyMentionRange) => start < entry.end && end > entry.start)) { return false; }
    const ids: Set<string> = new Set<string>();
    for (const entry of this.entries) { if (entry.mention !== undefined) { ids.add(entry.mention.id); } }
    ids.add(mention.id); if (ids.size > 5) { return false; }
    const entry: ReplyMentionRange = new ReplyMentionRange(); entry.start = start; entry.end = end; entry.mention = mention;
    this.entries.push(entry); this.entries.sort((a: ReplyMentionRange, b: ReplyMentionRange) => a.start - b.start); return true;
  }
  /** 对应SDK onDidChange：两个范围同起点，索引均为编辑器UTF-16位置。 */
  changed(beforeStart: number, beforeEnd: number, afterStart: number, afterEnd: number): void {
    if (![beforeStart,beforeEnd,afterStart,afterEnd].every((n: number) => Number.isSafeInteger(n) && n >= 0) ||
      beforeEnd < beforeStart || afterEnd < afterStart || beforeStart !== afterStart) { this.clear(); return; }
    const delta: number = afterEnd - beforeEnd;
    const next: ReplyMentionRange[] = [];
    for (const entry of this.entries) {
      // 插入于起点属于前方；末端插入不扩张已确认名字。
      if (beforeEnd <= entry.start) { entry.start += delta; entry.end += delta; next.push(entry); }
      else if (beforeStart >= entry.end) { next.push(entry); }
      // 覆盖或在名字内部插入：取消语义；不认定修改后的昵称仍是原用户。
    }
    this.entries = next;
  }
  reconcile(editorText: string): void {
    this.entries = this.entries.filter((entry: ReplyMentionRange) => entry.mention !== undefined &&
      editorText.substring(entry.start, entry.end) === entry.mention.displayText);
  }
  /** 相邻文字span先合并；不能跨图片或只凭键入的同名文字推断提及。 */
  text(text: string, start: number): string {
    let output: string = ''; let cursor: number = 0;
    for (const entry of this.entries) {
      const mention: AtEditorMention | undefined = entry.mention;
      const offset: number = entry.start - start;
      if (mention === undefined || offset < cursor || entry.end > start + text.length ||
        text.substring(offset, entry.end - start) !== mention.displayText) { continue; }
      output += text.substring(cursor, offset) + mention.serverText; cursor = entry.end - start;
    }
    return output + text.substring(cursor);
  }
}
/** 平台span适配后的纯输入；图片内容只从已确认映射表序列化。 */
export class ReplyEditorSpan { text: string = ''; imageSource: string = ''; editorLength: number = 1; }
export class ReplyEditorContent {
  text: string = '';
  imageCounts: Map<string, number> = new Map<string, number>();
}
export function serializeReplyEditor(spans: ReplyEditorSpan[], memeTokens: Map<string, string>,
  imageTokens: Map<string, string>, mentions?: ReplyMentionBook): ReplyEditorContent {
  const result: ReplyEditorContent = new ReplyEditorContent();
  let editorOffset: number = 0; let words: string = ''; let wordsStart: number = 0;
  for (const span of spans) {
    if (span.text.length > 0) {
      if (words.length === 0) { wordsStart = editorOffset; }
      words += span.text; editorOffset += span.text.length; continue;
    }
    result.text += mentions !== undefined ? mentions.text(words, wordsStart) : words; words = '';
    // 平台适配提供真实span长度；不能把协议token长度当作编辑位置。
    if (!Number.isSafeInteger(span.editorLength) || span.editorLength <= 0) { mentions?.clear(); }
    else { editorOffset += span.editorLength; }
    const image: string | undefined = imageTokens.get(span.imageSource);
    if (image !== undefined && image.length > 0) {
      result.text += image; result.imageCounts.set(image, (result.imageCounts.get(image) ?? 0) + 1);
    } else {
      const meme: string | undefined = memeTokens.get(span.imageSource);
      result.text += meme !== undefined && meme.length > 0 ? meme : emojiTokenFromUrl(span.imageSource);
    }
  }
  result.text += mentions !== undefined ? mentions.text(words, wordsStart) : words;
  return result;
}
