/** 圆形头像组件，支持加载占位、失败回退与头像点击。 */
import { AppTheme } from '../theme/Theme';
import { authSession } from '../auth/AuthSession';
import { avatarTrace, avatarImageLoadFor, AvatarImageLoad } from '../utils/AvatarTrace';

@ComponentV2
export struct AvatarComponent {
  @Param url: string = '';
  @Param avatarSize: number = 40;
  @Param fallbackName: string = '';
  @Param bgColor: ResourceColor = $r('app.color.app_avatar_bg');
  /**
   * 仅本人头像传非空（如 `self`）：把图片加载结果打进头像时间线。
   * 默认空串 —— 列表里成百上千个头像不产生任何日志。
   */
  @Param traceTag: string = '';

  @Local imageFailed: boolean = false;
  /** 当前展示图在这次加载启动时的归属（捕获后不再跟随全局状态）。 */
  @Local displayLoad: AvatarImageLoad = new AvatarImageLoad();

  @Monitor('url')
  onUrlChanged(): void {
    this.imageFailed = false;
    this.displayLoad = avatarImageLoadFor(this.url, 0, authSession.avatarRevision);
  }

  aboutToAppear(): void {
    // 首帧的 url 不会触发 @Monitor：这里补一次捕获，
    // 否则最初的 image-loaded 会报出 0 版本，看不出 URL 究竟有没有变过。
    this.onUrlChanged();
  }

  /** 只记阶段与捕获到的归属；不写 URL、图片内容或账号标识。 */
  private traceLoad(stage: string, load: AvatarImageLoad): void {
    if (this.traceTag.length === 0) { return; }
    avatarTrace(stage, load.traceId, `tag=${this.traceTag} src=${load.source} rev=${load.revision}`);
  }

  /** 回调闭包持有发起加载时的地址和归属；旧请求不能误报新图加载完成。 */
  private completeHandler(url: string, load: AvatarImageLoad): () => void {
    return (): void => {
      if (url !== this.url || load !== this.displayLoad) { return; }
      this.traceLoad('image-loaded', load);
    };
  }

  /** 旧图加载失败时不能隐藏当前的新图。 */
  private errorHandler(url: string, load: AvatarImageLoad): () => void {
    return (): void => {
      if (url !== this.url || load !== this.displayLoad) { return; }
      this.imageFailed = true;
      this.traceLoad('image-error', load);
    };
  }

  build() {
    Stack() {
      /* 背景圆底 */
      Circle()
        .width(this.avatarSize)
        .height(this.avatarSize)
        .fill(this.bgColor)

      /* 文字回退：URL 为空 或 图片加载失败时显示 */
      if (this.url.length === 0 || this.imageFailed) {
        Text(this.fallbackName.length > 0 ? this.fallbackName.charAt(0) : '?')
          .fontSize(this.avatarSize * 0.42).maxFontScale(1)
          .fontColor(AppTheme.TEXT_MAIN)
          .textAlign(TextAlign.Center)
          .width(this.avatarSize)
          .height(this.avatarSize)
      }

      /* 头像图片：URL 非空且未失败时叠加显示 */
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
    .flexShrink(0)
  }
}
