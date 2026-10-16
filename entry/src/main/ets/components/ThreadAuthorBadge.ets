import { DetailTheme } from '../theme/Theme';
import { UIContext } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';

const BADGE_FONT_SIZE: number = 10;
const BADGE_RADIUS: number = 4;
const BADGE_HORIZONTAL_PADDING: number = 5;
const BADGE_VERTICAL_PADDING: number = 2;

@Builder
export function ThreadAuthorBadge() {
  Text('楼主')
    .fontSize(BADGE_FONT_SIZE)
    .fontColor(DetailTheme.AUTHOR_BADGE_TEXT)
    .backgroundColor(DetailTheme.AUTHOR_BADGE_BACKGROUND)
    .borderRadius(BADGE_RADIUS)
    .padding({
      left: BADGE_HORIZONTAL_PADDING, right: BADGE_HORIZONTAL_PADDING,
      top: BADGE_VERTICAL_PADDING, bottom: BADGE_VERTICAL_PADDING
    })
}

export class ThreadAuthorBadgeImage {
  bitmap: image.PixelMap;
  widthVp: number;
  heightVp: number;

  constructor(bitmap: image.PixelMap, widthVp: number, heightVp: number) {
    this.bitmap = bitmap;
    this.widthVp = widthVp;
    this.heightVp = heightVp;
  }
}

let cachedKey: string = '';
let cachedImage: Promise<ThreadAuthorBadgeImage> | undefined = undefined;

export function loadThreadAuthorBadgeImage(ui: UIContext, key: string,
  builder: CustomBuilder): Promise<ThreadAuthorBadgeImage> {
  if (cachedImage !== undefined && cachedKey === key) {
    return cachedImage;
  }
  cachedKey = key;
  cachedImage = ui.getComponentSnapshot().createFromBuilder(builder, 0, true,
    { waitUntilRenderFinished: true }).then((bitmap: image.PixelMap) => {
    const size = bitmap.getImageInfoSync().size;
    return new ThreadAuthorBadgeImage(bitmap, ui.px2vp(size.width), ui.px2vp(size.height));
  }).catch((err: Error) => {
    if (cachedKey === key) {
      cachedImage = undefined;
    }
    throw err;
  });
  return cachedImage;
}

interface InlineBadgeParams {
  badge: ThreadAuthorBadgeImage | undefined;
}

@Builder
export function ThreadAuthorBadgeInline($$: InlineBadgeParams) {
  Span(' ')
  if ($$.badge !== undefined) {
    ImageSpan($$.badge.bitmap)
      .width($$.badge.widthVp)
      .height($$.badge.heightVp)
      .verticalAlign(ImageSpanAlignment.CENTER)
      .objectFit(ImageFit.Contain)
      .accessibilityText('楼主')
  } else {

    Span('楼主')
      .fontSize(BADGE_FONT_SIZE)
      .fontColor(DetailTheme.AUTHOR_BADGE_TEXT)
  }
}
