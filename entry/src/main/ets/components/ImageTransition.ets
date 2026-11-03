import { UIContext } from '@kit.ArkUI';

/** 一次性桥接点击源与浮层；不按 URL 全局配对，重复图片仍各有独立返回位置。 */
export class ImageTransitionSeed {
  id: string;
  preview: string;
  origin: string;

  constructor(id: string = '', preview: string = '', origin: string = '') {
    this.id = id;
    this.preview = preview;
    this.origin = origin;
  }
}

let nextSource: number = 0;
let pending: ImageTransitionSeed | undefined = undefined;

export class ImageTransitionSource {
  private prefix: string = `image-transition-${++nextSource}`;

  id(url: string, index: number = 0): string {
    // URL 参与身份：列表组件复用后不能把旧图收回到新图的位置。
    return `${this.prefix}:${index}:${url}`;
  }

  open(context: UIContext, preview: string, origin: string, action: () => void,
    index: number = 0, showPreview: boolean = true): void {
    pending = new ImageTransitionSeed(showPreview ? this.id(preview, index) : '',
      showPreview ? preview : '', origin);
    animateImageTransition(context, action);
  }
}

export function takeImageTransition(origin: string): ImageTransitionSeed {
  const seed: ImageTransitionSeed | undefined = pending;
  pending = undefined;
  return seed !== undefined && seed.origin === origin ? seed : new ImageTransitionSeed();
}

export function animateImageTransition(context: UIContext, action: () => void): void {
  context.animateTo({ duration: 300, curve: Curve.Friction }, action);
}
