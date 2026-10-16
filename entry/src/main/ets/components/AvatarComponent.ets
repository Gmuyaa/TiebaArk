
import { authSession } from '../auth/AuthSession';
import { avatarTrace, avatarImageLoadFor, AvatarImageLoad } from '../utils/AvatarTrace';

@ComponentV2
export struct AvatarComponent {
  @Param url: string = '';
  @Param avatarSize: number = 40;
  @Param fallbackName: string = '';
  @Param bgColor: ResourceColor = $r('app.color.app_avatar_bg');

  @Param traceTag: string = '';

  @Local imageFailed: boolean = false;

  @Local displayLoad: AvatarImageLoad = new AvatarImageLoad();

  @Monitor('url')
  onUrlChanged(): void {
    this.imageFailed = false;
    this.displayLoad = avatarImageLoadFor(this.url, 0, authSession.avatarRevision);
  }

  aboutToAppear(): void {

    this.onUrlChanged();
  }

  private traceLoad(stage: string, load: AvatarImageLoad): void {
    if (this.traceTag.length === 0) { return; }
    avatarTrace(stage, load.traceId, `tag=${this.traceTag} src=${load.source} rev=${load.revision}`);
  }

  private completeHandler(url: string, load: AvatarImageLoad): () => void {
    return (): void => {
      if (url !== this.url || load !== this.displayLoad) { return; }
      this.traceLoad('image-loaded', load);
    };
  }

  private errorHandler(url: string, load: AvatarImageLoad): () => void {
    return (): void => {
      if (url !== this.url || load !== this.displayLoad) { return; }
      this.imageFailed = true;
      this.traceLoad('image-error', load);
    };
  }

  build() {
    Stack() {

      Circle()
        .width(this.avatarSize)
        .height(this.avatarSize)
        .fill(this.bgColor)

      if (this.url.length === 0 || this.imageFailed) {
        Text(this.fallbackName.length > 0 ? this.fallbackName.charAt(0) : '?')
          .fontSize(this.avatarSize * 0.42)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .width(this.avatarSize)
          .height(this.avatarSize)
      }

      if (this.url.length > 0 && !this.imageFailed) {
        Image(this.url)
          .width(this.avatarSize)
          .height(this.avatarSize)
          .borderRadius(this.avatarSize / 2)
          .objectFit(ImageFit.Cover)
          .onComplete(this.completeHandler(this.url, this.displayLoad))
          .onError(this.errorHandler(this.url, this.displayLoad))
      }
    }
    .width(this.avatarSize)
    .height(this.avatarSize)
    .borderRadius(this.avatarSize / 2)
  }
}
