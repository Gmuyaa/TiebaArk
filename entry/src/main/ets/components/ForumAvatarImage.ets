/** 吧头像组件：优先显示图片，加载失败时回退到文字头像。 */
import { AppTheme } from '../theme/Theme';

export function forumAvatarRadius(size: number): number {
  return size * 14 / 64;
}

@ComponentV2
export struct ForumAvatarImage {
  /** 服务端给的完整吧头像地址；空串走文字兜底 */
  @Param url: string = '';
  /** 元数据补取完成后只重试失败图片，成功的同地址图片继续复用。 */
  @Param retryRevision: number = 0;
  /** 兜底文字取它的首字；空串时兜底为「吧」 */
  @Param forumName: string = '';
  @Param avatarSize: number = 18;
  @Param radius: number = 4;
  /** 兜底字号；0 = 按 `avatarSize` 的 0.6 倍（不小于 9） */
  @Param fontSize: number = 0;
  /** 非空时用它当兜底文字（详情页传「吧」），忽略 `forumName` 首字 */
  @Param glyphText: string = '';
  /** 深色 Hero（吧页渐变 / 迷你吧名栏）上的白字形态 */
  @Param onHero: boolean = false;
  /** 图片加载中/失败时的底色；默认透明 */
  @Param bgColor: ResourceColor = Color.Transparent;
  /**
   * 图片加载失败回调（只报"当前这张地址"的失败）。
   * 用于落盘 URL 的自愈：调用方作废该地址并重取一次，见 `MyListVM.retryAvatar`。
   */
  @Param onLoadError: (url: string) => void = (_url: string): void => {};

  /** 加载失败标记：失败后改走文字兜底，不再留空方块 */
  @Local failed: boolean = false;

  /** URL 变化 = 换了一次地址（反查回填 / 刷新），重试标记必须复位 */
  @Monitor('url', 'retryRevision')
  onUrlChanged(): void {
    this.failed = false;
  }

  private errorHandler(url: string, revision: number): () => void {
    return (): void => {
      if (url === this.url && revision === this.retryRevision) {
        this.failed = true;
        this.onLoadError(url);
      }
    };
  }

  private glyph(): string {
    if (this.glyphText.length > 0) { return this.glyphText; }
    return this.forumName.length > 0 ? this.forumName.charAt(0) : '吧';
  }

  private glyphFontSize(): number {
    if (this.fontSize > 0) { return this.fontSize; }
    return Math.max(9, Math.round(this.avatarSize * 0.6));
  }

  build() {
    Stack() {
      if (this.url.length > 0 && !this.failed) {
        Image(this.url)
          .width(this.avatarSize)
          .height(this.avatarSize)
          .borderRadius(this.radius)
          .objectFit(ImageFit.Cover)
          .backgroundColor(this.bgColor)
          .onError(this.errorHandler(this.url, this.retryRevision))
      } else {
        Text(this.glyph())
          .fontSize(this.glyphFontSize()).maxFontScale(1)
          .fontColor(this.onHero ? Color.White : AppTheme.ACCENT_DARK)
          .width(this.avatarSize)
          .height(this.avatarSize)
          .borderRadius(this.radius)
          .backgroundColor(this.onHero ? '#33FFFFFF' : AppTheme.ACCENT_LIGHT)
          .textAlign(TextAlign.Center)
      }
    }
    .width(this.avatarSize)
    .height(this.avatarSize)
    .flexShrink(0)
  }
}
