/** 图片加载档位与地址选择策略（纯逻辑，不依赖平台）。地址语义见 `docs/协议/协议证据-图片尺寸与动图.md`。 */
import { FeedImageInfo, feedImageInfo } from './HomeFeedPresentation';

export enum ImageQuality {
  ORIGINAL = 0,
  HIGH = 1,
  THUMB = 2,
  OFF = 3
}

export const ALL_IMAGE_QUALITIES: ImageQuality[] = [
  ImageQuality.ORIGINAL,
  ImageQuality.HIGH,
  ImageQuality.THUMB,
  ImageQuality.OFF
];

export enum GifAutoPlay {
  WIFI = 0,
  ALWAYS = 1,
  NEVER = 2
}

export const ALL_GIF_AUTO_PLAYS: GifAutoPlay[] = [
  GifAutoPlay.WIFI,
  GifAutoPlay.ALWAYS,
  GifAutoPlay.NEVER
];

/** 未知网络统一归入 MOBILE，避免读取失败时误按 Wi-Fi 消耗流量。 */
export enum NetworkKind {
  WIFI = 0,
  MOBILE = 1
}

export const DEFAULT_WIFI_QUALITY: ImageQuality = ImageQuality.ORIGINAL;
export const DEFAULT_MOBILE_QUALITY: ImageQuality = ImageQuality.HIGH;
export const DEFAULT_GIF_AUTO_PLAY: GifAutoPlay = GifAutoPlay.WIFI;

export function imageQualityLabel(value: number): string {
  switch (value) {
    case ImageQuality.ORIGINAL:
      return '原图';
    case ImageQuality.HIGH:
      return '高清';
    case ImageQuality.THUMB:
      return '缩略图';
    case ImageQuality.OFF:
      return '不自动加载';
    default:
      return '高清';
  }
}

export function parseImageQuality(value: number, fallback: ImageQuality): ImageQuality {
  if (value === ImageQuality.ORIGINAL || value === ImageQuality.HIGH ||
    value === ImageQuality.THUMB || value === ImageQuality.OFF) {
    return value as ImageQuality;
  }
  return fallback;
}

export function gifAutoPlayLabel(value: number): string {
  switch (value) {
    case GifAutoPlay.WIFI:
      return '仅 Wi-Fi';
    case GifAutoPlay.ALWAYS:
      return '始终';
    case GifAutoPlay.NEVER:
      return '从不';
    default:
      return '仅 Wi-Fi';
  }
}

export function parseGifAutoPlay(value: number, fallback: GifAutoPlay): GifAutoPlay {
  if (value === GifAutoPlay.WIFI || value === GifAutoPlay.ALWAYS || value === GifAutoPlay.NEVER) {
    return value as GifAutoPlay;
  }
  return fallback;
}

export class ImageLoadPolicy {
  quality: ImageQuality = DEFAULT_MOBILE_QUALITY;
  gifPlays: boolean = false;
  highAvatar: boolean = false;
}

export function imageLoadPolicy(
  wifi: ImageQuality,
  mobile: ImageQuality,
  gif: GifAutoPlay,
  net: NetworkKind
): ImageLoadPolicy {
  const policy: ImageLoadPolicy = new ImageLoadPolicy();
  const isWifi: boolean = net === NetworkKind.WIFI;
  policy.quality = isWifi ? wifi : mobile;
  policy.gifPlays = gif === GifAutoPlay.ALWAYS || (gif === GifAutoPlay.WIFI && isWifi);
  policy.highAvatar = policy.quality === ImageQuality.ORIGINAL;
  return policy;
}

export interface BodyImageSource {
  imageUrl: string;
  /** 带 `g=0` 的静态首帧通道（`cdn_src`） */
  staticUrl: string;
  /** 960 宽高清通道（`big_cdn_src`） */
  bigImageUrl: string;
  originImageUrl: string;
  /** 原图字节数 */
  originBytes: number;
  isGif?: boolean;
}

/** 依据扩展名与贴吧列表 CDN 实测形态（`frs` `src_pic` GIF 为 `w=1920`）识别动图。 */
export function isGifImageUrl(url: string, highUrl: string = ''): boolean {
  if (/\.gif(?:[?#]|$)/i.test(url) || /\.gif(?:[?#]|$)/i.test(highUrl)) {
    return true;
  }
  const candidate: string = highUrl.length > 0 ? highUrl : url;
  return /\/forum\/[^/]*(?:w%3D1920|w=1920)(?:%3B|;|\/|$)/i.test(candidate);
}

/** 正文/评论 GIF 判定：实测 `pb/page` 真 GIF 的 `big_cdn_src` 与 `cdn_src_active` 一致（静态图为 `w=960`/`w=1920`）。 */
export function isGifBodyImage(image: BodyImageSource): boolean {
  if (image.isGif === true) {
    return true;
  }
  if (/\.gif(?:[?#]|$)/i.test(image.originImageUrl) ||
    /\.gif(?:[?#]|$)/i.test(image.imageUrl) ||
    /\.gif(?:[?#]|$)/i.test(image.bigImageUrl)) {
    return true;
  }
  return image.bigImageUrl.length > 0 && image.imageUrl.length > 0 &&
    image.bigImageUrl === image.imageUrl && image.bigImageUrl !== image.staticUrl;
}

export function isGifFeedImage(info: FeedImageInfo, key: string = ''): boolean {
  return info.gif || isGifImageUrl(info.origin || key, info.high);
}

export class ViewerImage {
  /** 缩略图档优先加载的地址 */
  thumb: string = '';
  /** 高清档优先加载的大图地址 */
  high: string = '';
  /** 原图地址 */
  origin: string = '';
  /** 原图字节数；0 表示服务端未返回 */
  originBytes: number = 0;
  /** 兜底展示地址 */
  fallback: string = '';

  /** 与 `ImageTransition` 共享转场配对键一致（原图优先，缺失退展示图）。 */
  transitionKey(): string {
    return this.origin || this.high || this.thumb || this.fallback;
  }
}

export function bodyTransitionKey(image: BodyImageSource): string {
  return image.originImageUrl || image.bigImageUrl || image.imageUrl || image.staticUrl;
}

export function shouldPromoteLongToOrigin(policy: ImageLoadPolicy): boolean {
  return policy.quality === ImageQuality.ORIGINAL || policy.quality === ImageQuality.HIGH;
}

/** 列表预览图实际请求地址；`OFF` 返回空串表示仅渲染占位，关闭动图自动播放时优先走静态首帧通道。 */
export function feedPreviewSource(info: FeedImageInfo, key: string, policy: ImageLoadPolicy): string {
  if (policy.quality === ImageQuality.OFF) {
    return '';
  }
  if (!policy.gifPlays) {
    return info.staticUrl || info.thumb || key || info.high || info.origin;
  }
  if (policy.quality === ImageQuality.ORIGINAL) {
    return info.origin || info.high || key || info.staticUrl || info.thumb;
  }
  if (policy.quality === ImageQuality.THUMB) {
    return info.thumb || key || info.staticUrl || info.high || info.origin;
  }
  return info.high || key || info.staticUrl || info.thumb || info.origin;
}

/** 正文/评论图实际请求地址；关闭动图自动播放时优先走带 `g=0` 的静态首帧通道，开启时按清晰度档位选择。 */
export function bodyImageSource(image: BodyImageSource, isLong: boolean, policy: ImageLoadPolicy): string {
  if (policy.quality === ImageQuality.OFF) {
    return '';
  }
  if (!policy.gifPlays && image.staticUrl.length > 0) {
    return image.staticUrl;
  }
  if (policy.quality === ImageQuality.ORIGINAL) {
    return image.originImageUrl || image.bigImageUrl || image.imageUrl || image.staticUrl;
  }
  if (isLong && shouldPromoteLongToOrigin(policy) && image.originImageUrl.length > 0) {
    return image.originImageUrl;
  }
  if (policy.quality === ImageQuality.HIGH) {
    return image.bigImageUrl || image.imageUrl || image.staticUrl || image.originImageUrl;
  }
  return image.imageUrl || image.staticUrl || image.bigImageUrl || image.originImageUrl;
}

/** 全屏查看器实际加载地址；`ORIGINAL` 或已点击「查看原图」取原图，`THUMB` 先取缩略图，其余先取高清大图。 */
export function viewerSource(image: ViewerImage, policy: ImageLoadPolicy, originRequested: boolean): string {
  if ((policy.quality === ImageQuality.ORIGINAL || originRequested) && image.origin.length > 0) {
    return image.origin;
  }
  if (policy.quality === ImageQuality.THUMB) {
    return image.thumb || image.high || image.fallback || image.origin;
  }
  return image.high || image.thumb || image.fallback || image.origin;
}

/** 是否应在全屏查看器底部显示「查看原图」按钮。 */
export function viewerCanLoadOrigin(image: ViewerImage, policy: ImageLoadPolicy, originRequested: boolean): boolean {
  if (originRequested || policy.quality === ImageQuality.ORIGINAL || image.origin.length === 0) {
    return false;
  }
  return viewerSource(image, policy, false) !== image.origin;
}

/** 从列表预览键构建查看器序列（自动读取 `rememberFeedImage` 登记的缩略/高清/原图/字节数）。 */
export function viewerImagesForFeed(keys: string[], origins: string[] = []): ViewerImage[] {
  const out: ViewerImage[] = [];
  for (let i: number = 0; i < keys.length; i++) {
    const key: string = keys[i] ?? '';
    const info: FeedImageInfo = feedImageInfo(key);
    const img: ViewerImage = new ViewerImage();
    img.origin = (i < origins.length && origins[i].length > 0 ? origins[i] : '') || info.origin || key;
    img.high = info.high || key || img.origin;
    img.thumb = info.thumb || key || img.high || img.origin;
    img.fallback = key || info.thumb || img.origin;
    img.originBytes = info.originBytes;
    out.push(img);
  }
  return out;
}

/** 从正文/评论图片构建查看器序列。 */
export function viewerImagesForBody(items: BodyImageSource[]): ViewerImage[] {
  const out: ViewerImage[] = [];
  for (let i: number = 0; i < items.length; i++) {
    const item: BodyImageSource = items[i];
    const img: ViewerImage = new ViewerImage();
    img.origin = bodyTransitionKey(item);
    img.high = item.bigImageUrl || item.imageUrl || item.staticUrl || img.origin;
    img.thumb = item.staticUrl || item.imageUrl || img.high || img.origin;
    img.fallback = item.imageUrl || item.staticUrl || img.origin;
    img.originBytes = item.originBytes;
    out.push(img);
  }
  return out;
}

/** 按档位改写 `himg.bdimg.com/sys/portrait[nh]?/item/`，保留 `?t=` 修订参数；`OFF` 返回空串。 */
export function avatarVariantForQuality(url: string, quality: ImageQuality): string {
  if (url.length === 0 || quality === ImageQuality.OFF) {
    return '';
  }
  const match: RegExpMatchArray | null = url.match(/^(https?:\/\/himg\.bdimg\.com\/sys\/)portrait[nh]?(\/item\/.+)$/i);
  if (match === null) {
    return url;
  }
  const segment: string = quality === ImageQuality.ORIGINAL
    ? 'portraith'
    : (quality === ImageQuality.THUMB ? 'portraitn' : 'portrait');
  return `${match[1]}${segment}${match[2]}`;
}

export function avatarSource(url: string, policy: ImageLoadPolicy): string {
  return avatarVariantForQuality(url, policy.quality);
}

/** 只改写 `himg.bdimg.com/sys/portrait[nh]?/item/`，保留 `?t=` 修订参数，其余地址原样返回。 */
export function avatarVariant(url: string, high: boolean): string {
  return avatarVariantForQuality(url, high ? ImageQuality.ORIGINAL : ImageQuality.HIGH);
}

export function formatOriginBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) {
    return '查看原图';
  }
  if (bytes >= 1024 * 1024) {
    return `查看原图（${(bytes / (1024 * 1024)).toFixed(1)} MB）`;
  }
  if (bytes >= 1024) {
    return `查看原图（${Math.round(bytes / 1024)} KB）`;
  }
  return `查看原图（${Math.round(bytes)} B）`;
}
