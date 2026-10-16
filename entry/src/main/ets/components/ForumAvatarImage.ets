
import { AppTheme } from '../theme/Theme';

export function forumAvatarRadius(size: number): number {
  return size * 14 / 64;
}

@ComponentV2
export struct ForumAvatarImage {

  @Param url: string = '';

  @Param forumName: string = '';
  @Param avatarSize: number = 18;
  @Param radius: number = 4;

  @Param fontSize: number = 0;

  @Param glyphText: string = '';

  @Param onHero: boolean = false;

  @Param bgColor: ResourceColor = Color.Transparent;

  @Local failed: boolean = false;

  @Monitor('url')
  onUrlChanged(): void {
    this.failed = false;
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
          .onError((): void => {
            this.failed = true;
          })
      } else {
        Text(this.glyph())
          .fontSize(this.glyphFontSize())
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
