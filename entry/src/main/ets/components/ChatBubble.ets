/**
 * 一条私信气泡：自己靠右、对方靠左，带头像；发送失败可点重试。
 *
 * 颜色全部走 `AppTheme`（自己 = 强调色 + ON_ACCENT，对方 = 卡片色 + 主文字），
 * 不新增自绘材质或按压效果。
 *
 * 正文走富文本：`#(酸爽)` 这类官方表情写法渲染成表情图（复用帖子正文那套解析），
 * 已读回执（type=22）与系统消息（type=10）不再画成气泡，改成居中小字。
 */

import { AvatarComponent } from './AvatarComponent';
import { ChatMessage, MSG_TYPE_READED } from '../model/Chat';
import { ContentKind, ContentPiece, portraitUrl } from '../model/ThreadDetail';
import { emojiSrc } from '../common/emoji/EmojiSrc';
import { formatTimeText } from '../model/TimeText';
import { AppTheme } from '../theme/Theme';

/** 系统消息（非聊天内容）的类型：10 = 会话状态，22 = 已读回执。 */
const MSG_TYPE_SYSTEM: number = 10;

@ComponentV2
export struct ChatBubble {
  @Param message: ChatMessage = new ChatMessage();
  /** 与上一条间隔超过阈值时在气泡上方显示时间条。 */
  @Param showTime: boolean = false;
  @Param selfPortrait: string = '';
  @Event onRetry: (message: ChatMessage) => void = (): void => {};

  private avatarUrl(): string {
    const raw: string = this.message.fromSelf ? this.selfPortrait : this.message.peer.portrait;
    return raw.length > 0 ? portraitUrl(raw) : '';
  }

  private bubbleColor(): ResourceColor {
    return this.message.fromSelf ? AppTheme.ACCENT : AppTheme.CARD;
  }

  private textColor(): ResourceColor {
    return this.message.fromSelf ? AppTheme.ON_ACCENT : AppTheme.TEXT_MAIN;
  }

  /** 已读回执与系统消息：不占气泡，居中一行小字。 */
  private isSystemNotice(): boolean {
    return this.message.msgType === MSG_TYPE_READED || this.message.msgType === MSG_TYPE_SYSTEM;
  }

  private noticeText(): string {
    if (this.message.msgType === MSG_TYPE_READED) {
      return this.message.fromSelf ? '对方已读' : '已读';
    }
    return '系统消息';
  }

  /** 正文分片：官方表情 `#(xxx)` 会拆成 EMOJI 片段，其余保持文本。 */
  private pieces(): ContentPiece[] {
    return ContentPiece.splitTextAndEmoji(this.message.content);
  }

  @Builder
  Avatar() {
    Stack() {
      AvatarComponent({
        url: this.avatarUrl(),
        avatarSize: 36,
        fallbackName: this.message.fromSelf ? '我' : this.message.peer.displayName(),
        traceTag: 'chat-bubble'
      });
    }.width(36).height(36).borderRadius(18).clip(true).flexShrink(0).accessibilityLevel('no')
  }

  /** 气泡正文：文本 + 行内表情图。 */
  @Builder
  BubbleText() {
    Text() {
      ForEach(this.pieces(), (piece: ContentPiece, index: number) => {
        if (piece.kind === ContentKind.EMOJI && piece.emojiUrl.length > 0) {
          ImageSpan(emojiSrc(piece.emojiUrl))
            .width(18)
            .height(18)
            .verticalAlign(ImageSpanAlignment.CENTER)
        } else {
          Span(piece.text)
        }
      }, (piece: ContentPiece, index: number) => `${index}:${piece.kind}:${piece.text}`)
    }
    .fontSize(15)
    .lineHeight(21)
    .fontColor(this.textColor())
    .constraintSize({ maxWidth: '100%' })
    .padding({ left: 12, right: 12, top: 9, bottom: 9 })
    .borderRadius(16)
    .backgroundColor(this.bubbleColor())
    .copyOption(CopyOptions.LocalDevice)
    .textAlign(TextAlign.Start)
  }

  build() {
    Column({ space: 6 }) {
      if (this.showTime) {
        Text(formatTimeText(this.message.createTimeMs, Date.now()))
          .fontSize(12)
          .fontColor(AppTheme.TEXT_SUB)
          .width('100%')
          .textAlign(TextAlign.Center)
      }
      if (this.isSystemNotice()) {
        Text(this.noticeText())
          .fontSize(11)
          .fontColor(AppTheme.TEXT_SUB)
          .width('100%')
          .textAlign(TextAlign.Center)
      } else {
        Row({ space: 8 }) {
          if (!this.message.fromSelf) { this.Avatar() } else { Blank() }
          Column({ space: 4 }) {
            this.BubbleText()
            if (this.message.fromSelf && (this.message.sendState === 'sending' || this.message.sendState === 'failed')) {
              Row({ space: 6 }) {
                if (this.message.sendState === 'sending') {
                  LoadingProgress().width(12).height(12).color(AppTheme.TEXT_SUB)
                  Text('发送中').fontSize(11).fontColor(AppTheme.TEXT_SUB)
                } else {
                  Text('发送失败，点击重试')
                    .fontSize(11)
                    .fontColor(AppTheme.DANGER_TEXT)
                    .onClick((): void => { this.onRetry(this.message); })
                }
              }
            }
          }
          .alignItems(this.message.fromSelf ? HorizontalAlign.End : HorizontalAlign.Start)
          .layoutWeight(1)
          if (this.message.fromSelf) { this.Avatar() } else { Blank() }
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 4 })
    .accessibilityGroup(true)
    .accessibilityText(`${this.message.fromSelf ? '我' : this.message.peer.displayName()}：${this.message.text()}`)
  }
}
