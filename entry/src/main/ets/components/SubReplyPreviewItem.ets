/**
 * 楼中楼预览里的**一条**：`昵称[楼主]：正文` 或 `昵称 回复 某人[楼主]：正文`。
 *
 * 为什么不用完整的楼中楼行（头像 + 时间 + 富文本）：预览块要的是密度，
 * 一行能读完的"谁回复谁"，不是又一张作者卡片。所以这里：
 *   - 不显示头像
 *   - 不显示时间（默认不展示）
 *   - 正文里的图片退化成"查看图片"链接，不撑开高度
 *
 * 发言者用沉蓝色，回复对象和连接词用辅助灰，正文保留清楚的深字。
 */

import { ContentPiece, SubPostItem, collectPreviewImageUrls } from '../model/ThreadDetail';
import { PostContentInline } from './PostContentInline';
import { openContentPiece } from '../navigation/ContentNavigation';
import { DetailTheme } from '../theme/Theme';
import { SUB_REPLY_BODY_SIZE, SUB_REPLY_LINE_HEIGHT } from '../common/appearance/PostTypography';
import {
  ThreadAuthorBadge, ThreadAuthorBadgeImage, ThreadAuthorBadgeInline, loadThreadAuthorBadgeImage
} from './ThreadAuthorBadge';
import { FontSizeScaleStore, fontScaleStore } from '../common/appearance/FontSizeScaleStore';
import { fontSizeScaleOf } from '../common/appearance/FontSizeScale';
import { ThemeModeStore, themeModeStore } from '../common/appearance/ThemeModeStore';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 预览里最多渲染多少张图；楼中楼预览只提示有图，不展开 */
const PREVIEW_IMAGE_HINT: string = '查看图片';

/**
 * 行内表情边长（vp）：正文 14fp／行高 21vp，表情 18vp 不撑行。
 */
const PREVIEW_EMOJI_SIZE: number = 18;

@ComponentV2
export struct SubReplyPreviewItem {
  @Local badge: ThreadAuthorBadgeImage | undefined = undefined;
  @Local fontSettings: FontSizeScaleStore = fontScaleStore;
  @Local themeSettings: ThemeModeStore = themeModeStore;
  private badgeSeq: number = 0;
  /** 一条楼中楼 */
  @Require @Param sub: SubPostItem;
  /** 点"查看图片"时回传图片地址 */
  @Event onViewImage: (url: string) => void = (): void => {};

  aboutToAppear(): void {
    this.refreshBadge();
  }

  aboutToDisappear(): void {
    this.badgeSeq++;
  }

  @Builder
  BadgeSnapshot() {
    ThreadAuthorBadge();
  }

  @Monitor('fontSettings.pref', 'fontSettings.customSize', 'fontSettings.systemScale', 'themeSettings.isDark',
    'sub')
  refreshBadge(): void {
    if (!this.sub.isThreadAuthor && !this.sub.replyToIsThreadAuthor) {
      return;
    }
    const seq: number = ++this.badgeSeq;
    const scale: number = fontSizeScaleOf(this.fontSettings.pref, this.fontSettings.systemScale,
      this.fontSettings.customSize);
    const key: string = `${this.themeSettings.isDark}:${scale}`;
    loadThreadAuthorBadgeImage(this.getUIContext(), key, (): void => {
      this.BadgeSnapshot();
    }).then((badge: ThreadAuthorBadgeImage) => {
      if (seq === this.badgeSeq) {
        this.badge = badge;
      }
    }).catch((err: Error) => {
      hilog.warn(0x0, 'ThreadAuthorBadge', 'inline badge render failed: %{public}s', String(err));
    });
  }

  /** 正文里第一张可用图片；没有则空串 */
  private firstImageUrl(): string {
    const urls: string[] = collectPreviewImageUrls(this.sub.contents);
    return urls.length > 0 ? urls[0] : '';
  }

  build() {
    Text() {
      Span(this.sub.author.displayName)
        .fontColor(DetailTheme.SUB_REPLY_NAME)
      if (this.sub.isThreadAuthor) {
        ThreadAuthorBadgeInline({ badge: this.badge });
      }
      if (this.sub.replyToName.length > 0) {
        Span(' 回复')
          .fontColor(DetailTheme.COMMENT_ACTION)
        Span(this.sub.replyToName)
          .fontColor(DetailTheme.COMMENT_ACTION)
        if (this.sub.replyToIsThreadAuthor) {
          ThreadAuthorBadgeInline({ badge: this.badge });
        }
      }
      Span('：')
        .fontColor(DetailTheme.COMMENT_ACTION)

      PostContentInline({
        pieces: this.sub.contents,
        emojiSize: PREVIEW_EMOJI_SIZE,
        textColor: DetailTheme.SUB_REPLY_BODY,
        accentColor: DetailTheme.ACCENT_DARK,
        onActivate: (piece: ContentPiece): void => { openContentPiece(piece, this.getUIContext()); }
      })

      if (this.firstImageUrl().length > 0) {
        Span(PREVIEW_IMAGE_HINT)
          .fontColor(DetailTheme.ACCENT_DARK)
          .onClick(() => {
            this.onViewImage(this.firstImageUrl());
          })
      }
    }
    .fontSize(SUB_REPLY_BODY_SIZE)
    .lineHeight(SUB_REPLY_LINE_HEIGHT)
    .width('100%')
  }
}
