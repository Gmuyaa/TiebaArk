/** 圆形头像组件，支持加载占位、失败回退与头像点击。 */
import { AppTheme } from '../theme/Theme';
import { authSession } from '../auth/AuthSession';
import { avatarTrace, avatarImageLoadFor, AvatarImageLoad } from '../utils/AvatarTrace';
import { ImageLoadStore, imageLoadStore } from '../common/appearance/ImageLoadStore';
import { ImageQuality, avatarVariant, avatarVariantForQuality } from '../model/ImageLoadPolicy';

@ComponentV2
export struct AvatarComponent {
  @Param url: string = '';
  @Param avatarSize: number = 40;
  @Param fallbackName: string = '';
  @Param bgColor: ResourceColor | undefined = undefined;
  /**
   * 仅本人头像传非空（如 `self`）：把图片加载结果打进头像时间线。
   * 默认空串 —— 列表里成百上千个头像不产生任何日志。
   */
  @Param traceTag: string = '';

  @Local imageLoad: ImageLoadStore = imageLoadStore;
  @Local imageFailed: boolean = false;
  @Local private quality: ImageQuality = imageLoadStore.currentPolicy().quality;
  @Local private fallbackToNormal: boolean = false;
  /** 当前展示图在这次加载启动时的归属（捕获后不再跟随全局状态）。 */
  @Local displayLoad: AvatarImageLoad = new AvatarImageLoad();
  /** 最近一张已加载完成的头像地址：换地址加载期间作底图承接，避免重建 Image 露出占位圆。 */
  @Local private loadedUrl: string = '';
  private lastUrl: string = '';
  private lastResolved: string = '';
  private lastFallbackName: string = '';

  @Monitor('url', 'fallbackName', 'imageLoad.revision')
  onUrlChanged(): void {
    const urlChanged: boolean = this.url !== this.lastUrl;
    const ownerChanged: boolean = this.lastFallbackName.length > 0 && this.fallbackName !== this.lastFallbackName;
    const nextQuality: ImageQuality = this.imageLoad.currentPolicy().quality;
    if (urlChanged || nextQuality !== this.quality) {
      this.quality = nextQuality;
      this.fallbackToNormal = false;
    }
    const nextResolved: string = this.resolvedUrl();
    if (nextResolved.length === 0 || ownerChanged) {
      this.loadedUrl = '';
    }
    if (urlChanged || nextResolved !== this.lastResolved || this.imageFailed) {
      this.imageFailed = false;
      this.displayLoad = avatarImageLoadFor(this.url, 0, authSession.avatarRevision);
    }
    this.lastUrl = this.url;
    this.lastResolved = nextResolved;
    this.lastFallbackName = this.fallbackName;
  }

  aboutToAppear(): void {
    // 首帧的 url 不会触发 @Monitor：这里补一次捕获，
    // 否则最初的 image-loaded 会报出 0 版本，看不出 URL 究竟有没有变过。
    this.lastUrl = '\u0000';
    this.onUrlChanged();
  }

  private resolvedUrl(): string {
    if (this.quality === ImageQuality.OFF || this.url.length === 0) {
      return '';
    }
    if (this.fallbackToNormal) {
      return avatarVariant(this.url, false);
    }
    return avatarVariantForQuality(this.url, this.quality);
  }

  /** 只记阶段与捕获到的归属；不写 URL、图片内容或账号标识。 */
  private traceLoad(stage: string, load: AvatarImageLoad): void {
    if (this.traceTag.length === 0) { return; }
    avatarTrace(stage, load.traceId, `tag=${this.traceTag} src=${load.source} rev=${load.revision}`);
  }

  /** 回调闭包持有发起加载时的地址和归属；旧请求不能误报新图加载完成。 */
  private completeHandler(resolved: string, load: AvatarImageLoad): () => void {
    return (): void => {
      if (resolved !== this.resolvedUrl() || load !== this.displayLoad) { return; }
      this.loadedUrl = resolved;
      this.traceLoad('image-loaded', load);
    };
  }

  /** 高清/极小头像失败时自动回退普通地址一次；旧图加载失败不能隐藏当前的新图。 */
  private errorHandler(resolved: string, load: AvatarImageLoad): () => void {
    return (): void => {
      if (resolved !== this.resolvedUrl() || load !== this.displayLoad) { return; }
      const normal: string = avatarVariant(this.url, false);
      if (!this.fallbackToNormal && resolved !== normal) {
        this.fallbackToNormal = true;
        return;
      }
      this.imageFailed = true;
      this.loadedUrl = '';
      this.traceLoad('image-error', load);
    };
  }

  build() {
    Stack() {
      Circle()
        .width(this.avatarSize)
        .height(this.avatarSize)
        .fill(this.bgColor ?? AppTheme.AVATAR_BG)

      // 文字回退：URL 为空、关闭自动加载或图片加载失败时显示
      if (this.resolvedUrl().length === 0 || this.imageFailed) {
        Text(this.fallbackName.length > 0 ? this.fallbackName.charAt(0) : '?')
          .fontSize(this.avatarSize * 0.42).maxFontScale(1)
          .fontColor(AppTheme.TEXT_MAIN)
          .textAlign(TextAlign.Center)
          .width(this.avatarSize)
          .height(this.avatarSize)
      }

      // 换地址加载期间保留最近一张已完成的图片（已命中缓存，syncLoad 避免过渡帧露底圆）。
      if (this.loadedUrl.length > 0 && this.loadedUrl !== this.resolvedUrl() &&
        this.resolvedUrl().length > 0 && !this.imageFailed) {
        Image(this.loadedUrl)
          .width(this.avatarSize)
          .height(this.avatarSize)
          .borderRadius(this.avatarSize / 2)
          .objectFit(ImageFit.Cover)
          .syncLoad(true)
      }

      // 头像图片：解析地址非空且未失败时叠加显示；按实际地址做 key 保证切档立刻替换。
      if (this.resolvedUrl().length > 0 && !this.imageFailed) {
        ForEach([this.resolvedUrl()], (src: string) => {
          Image(src)
            .width(this.avatarSize)
            .height(this.avatarSize)
            .borderRadius(this.avatarSize / 2)
            .objectFit(ImageFit.Cover)
            .onComplete(this.completeHandler(src, this.displayLoad))
            .onError(this.errorHandler(src, this.displayLoad))
        }, (src: string) => src)
      }
    }
    .width(this.avatarSize)
    .height(this.avatarSize)
    .borderRadius(this.avatarSize / 2)
    .flexShrink(0)
  }
}
