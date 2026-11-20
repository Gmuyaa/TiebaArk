/**
 * 会话列表一行：头像 + 昵称 + 最后一条摘要 + 时间。
 *
 * 只画拿得到的字段：没有最后一条就显示"还没有聊天记录"，不编造预览。
 */

import { AvatarComponent } from './AvatarComponent';
import { ChatGroup, ChatMessage, MSG_TYPE_TEXT } from '../model/Chat';
import { ContentKind, ContentPiece, portraitUrl } from '../model/ThreadDetail';
import { emojiSrc } from '../common/emoji/EmojiSrc';
import { formatTimeText } from '../model/TimeText';
import { AppTheme } from '../theme/Theme';

@ComponentV2
export struct ChatConversationRow {
  @Param group: ChatGroup = new ChatGroup();
  @Event onTap: () => void = (): void => {};

  private preview(): string {
    const last: ChatMessage | undefined = this.group.lastMessage;
    if (last === undefined) { return '还没有聊天记录'; }
    const text: string = last.text();
    return last.fromSelf ? `我：${text}` : text;
  }

  /** 预览分片：文本消息里的 `#(xxx)` 也要显示成表情图。 */
  private previewPieces(): ContentPiece[] {
    const last: ChatMessage | undefined = this.group.lastMessage;
    if (last === undefined) { return []; }
    if (last.msgType !== MSG_TYPE_TEXT) {
      return ContentPiece.splitTextAndEmoji(last.text());
    }
    return ContentPiece.splitTextAndEmoji(last.content);
  }

  private lastFromSelf(): boolean {
    const last: ChatMessage | undefined = this.group.lastMessage;
    return last !== undefined && last.fromSelf;
  }

  private timeText(): string {
    // 用 timeKey 而不是 sortKey：sortKey 含置顶偏移，直接格式化会显示成几万年后的日期
    const ms: number = this.group.timeKey();
    return ms > 0 ? formatTimeText(ms, Date.now()) : '';
  }

  /** 未读数角标文案：超过 99 折成 99+。 */
  private unreadText(): string {
    return this.group.unread > 99 ? '99+' : String(this.group.unread);
  }

  @Builder
  Avatar() {
    Stack() {
      AvatarComponent({
        url: this.group.peer.portrait.length > 0 ? portraitUrl(this.group.peer.portrait) : '',
        avatarSize: 48,
        fallbackName: this.group.title(),
        traceTag: 'chat-row'
      });
    }.width(48).height(48).borderRadius(24).clip(true).flexShrink(0).accessibilityLevel('no')
  }

  @Builder
  PreviewText() {
    Text() {
      if (this.lastFromSelf()) { Span('我：') }
      ForEach(this.previewPieces(), (piece: ContentPiece, index: number) => {
        if (piece.kind === ContentKind.EMOJI && piece.emojiUrl.length > 0) {
          ImageSpan(emojiSrc(piece.emojiUrl))
            .width(14)
            .height(14)
            .verticalAlign(ImageSpanAlignment.CENTER)
        } else {
          Span(piece.text)
        }
      }, (piece: ContentPiece, index: number) => `${index}:${piece.kind}:${piece.text}`)
    }
    .fontSize(13)
    .fontColor(AppTheme.TEXT_SUB)
    .maxLines(1)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  build() {
    Row({ space: 12 }) {
      this.Avatar()

      Column({ space: 4 }) {
        Text(this.group.title())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_MAIN)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.group.lastMessage === undefined) {
          Text('还没有聊天记录')
            .fontSize(13)
            .fontColor(AppTheme.TEXT_SUB)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        } else {
          this.PreviewText()
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column({ space: 6 }) {
        // 置顶标记：放在右上角，和时间同一列
        if (this.group.pinned) {
          SymbolGlyph($r('sys.symbol.pin'))
            .fontSize(12)
            .fontColor([AppTheme.TEXT_SUB])
        }
        Text(this.timeText())
          .fontSize(12)
          .fontColor(AppTheme.TEXT_SUB)
          .maxLines(1)
        // 未读红点：与通知角标一致的强提醒
        if (this.group.unread > 0) {
          Text(this.unreadText())
            .fontSize(11)
            .fontColor(Color.White)
            .backgroundColor(AppTheme.DANGER_TEXT)
            .borderRadius(9)
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
            .constraintSize({ minWidth: 18 })
            .textAlign(TextAlign.Center)
        }
      }
      .alignItems(HorizontalAlign.End)
      .flexShrink(0)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .borderRadius(AppTheme.CARD_RADIUS)
    .backgroundColor(AppTheme.CARD)
    .clip(true)
    .accessibilityGroup(true)
    .accessibilityText(`${this.group.title()}，${this.preview()}`)
    .onClick((): void => { this.onTap(); })
  }
}
