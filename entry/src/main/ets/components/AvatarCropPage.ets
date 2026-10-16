
import { AvatarCrop, AvatarCropLimits, avatarCropFromViewport, avatarCropOffsetLimits } from '../model/AvatarUpload';
import { AppTheme } from '../theme/Theme';

const CROP_BAR_HEIGHT: number = 56;
const CROP_FRAME_MIN: number = 120;
const CROP_FRAME_MAX: number = 340;
const CROP_FRAME_MARGIN: number = 48;
const CROP_ZOOM_MIN: number = 1;
const CROP_ZOOM_MAX: number = 4;
const CROP_BAR_BG: string = '#FFFFFF';
const CROP_BAR_TEXT: string = '#1B1B1B';
const CROP_DONE_WIDTH: number = 88;
const CROP_DONE_HEIGHT: number = 44;
const CROP_DONE_BOTTOM: number = 40;
const CROP_DONE_RIGHT: number = 24;
const CROP_BACKDROP: string = '#141414';
/** 框内、圆外的压暗程度：看得见位置，又不至于抢走圆内的判断。 */
const CROP_MASK_OPACITY: number = 0.35;
const CROP_RING_COLOR: string = '#B3FFFFFF';
const CROP_FRAME_COLOR: string = '#4DFFFFFF';

@ComponentV2
export struct AvatarCropPage {
  /** 原图 uri 与它的像素尺寸：都来自 `AvatarEditVM` 刚选中的那张图。 */
  @Param uri: string = '';
  @Param sourceWidth: number = 0;
  @Param sourceHeight: number = 0;
  @Param statusBarH: number = 0;
  @Event onCancel: () => void = (): void => {};
  @Event onDone: (crop: AvatarCrop) => void = (_crop: AvatarCrop): void => {};
  @Local zoom: number = CROP_ZOOM_MIN;
  /** 图像相对"居中"位置的位移（vp）；右移为正，与裁剪窗口左移等价。 */
  @Local panX: number = 0;
  @Local panY: number = 0;
  @Local areaWidth: number = 0;
  @Local areaHeight: number = 0;
  @Local pinchActive: boolean = false;
  private panBaseX: number = 0;
  private panBaseY: number = 0;
  private pinchBase: number = CROP_ZOOM_MIN;
  private pinchPanBaseX: number = 0;
  private pinchPanBaseY: number = 0;
  private pinchFocalX: number = 0;
  private pinchFocalY: number = 0;

  /** 裁剪框边长：跟着可用区域走，短边留出边距后封顶，保证小屏也放得下顶栏与框。 */
  private frameEdge(): number {
    const room: number = Math.min(this.areaWidth, this.areaHeight) - CROP_FRAME_MARGIN;
    return Math.max(CROP_FRAME_MIN, Math.min(room, CROP_FRAME_MAX));
  }

  /** 原图像素 → vp：图像按原图宽高比铺满裁剪框后，再按倍率放大。 */
  private imageScale(): number {
    const short: number = Math.min(this.sourceWidth, this.sourceHeight);
    if (!Number.isFinite(short) || short <= 0 || this.frameEdge() <= 0) { return 1; }
    return this.frameEdge() / short * this.zoom;
  }

  private clampPan(): void {
    const limits: AvatarCropLimits | undefined =
      avatarCropOffsetLimits(this.sourceWidth, this.sourceHeight, this.zoom, this.frameEdge());
    if (limits === undefined) { this.panX = 0; this.panY = 0; return; }
    this.panX = Math.min(Math.max(this.panX, -limits.x), limits.x);
    this.panY = Math.min(Math.max(this.panY, -limits.y), limits.y);
  }

  private finish(): void {
    const crop: AvatarCrop | undefined = avatarCropFromViewport(
      this.sourceWidth, this.sourceHeight, this.zoom, this.panX, this.panY, this.frameEdge());
    // 只有源图尺寸无效或倍率越界才会为空；那时不该上传，留在裁剪页让用户重来。
    if (crop === undefined) { return; }
    this.onDone(crop);
  }

  @Builder
  private CropImage(masked: boolean) {
    Image(this.uri)
      .objectFit(ImageFit.Fill)
      .width(this.sourceWidth * this.imageScale())
      .height(this.sourceHeight * this.imageScale())
      .translate({ x: this.panX, y: this.panY })
      .opacity(masked ? CROP_MASK_OPACITY : 1)
  }

  @Builder
  private CropBar() {
    Row() {
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(20)
        .fontColor([CROP_BAR_TEXT])
        .padding(8)
        .onClick(() => { this.onCancel(); })
      Text('裁剪')
        .fontSize(18)
        .fontColor(CROP_BAR_TEXT)
        .fontWeight(FontWeight.Medium)
        .margin({ left: 6 })
        .layoutWeight(1)
    }
    .width('100%')
    .height(CROP_BAR_HEIGHT + this.statusBarH)
    .padding({ left: 8, right: 16, top: this.statusBarH })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(CROP_BAR_BG)
  }

  @Builder
  private CropFrame() {
    Stack() {
      // ① 框内底色：整块压暗的原图。
      this.CropImage(true)
      // ② 圆形亮窗：同一张原图不压暗，裁成内切圆。
      Stack() {
        this.CropImage(false)
      }
      .width(this.frameEdge())
      .height(this.frameEdge())
      .borderRadius(this.frameEdge() / 2)
      .clip(true)
      // ③ 圆环与 ④ 方框只是描边，不挡手势。
      Stack() {
      }
      .width(this.frameEdge())
      .height(this.frameEdge())
      .borderRadius(this.frameEdge() / 2)
      .border({ width: 1, color: CROP_RING_COLOR })
      Stack() {
      }
      .width(this.frameEdge())
      .height(this.frameEdge())
      .border({ width: 1, color: CROP_FRAME_COLOR })
    }
    .width(this.frameEdge())
    .height(this.frameEdge())
    .clip(true)
    .gesture(
      GestureGroup(GestureMode.Parallel,
        PanGesture({ fingers: 1, distance: 3 })
          .onActionStart(() => {
            this.panBaseX = this.panX;
            this.panBaseY = this.panY;
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.pinchActive) { return; }
            this.panX = this.panBaseX + event.offsetX;
            this.panY = this.panBaseY + event.offsetY;
            this.clampPan();
          })
          .onActionEnd(() => { this.clampPan(); }),
        PinchGesture({ fingers: 2 })
          .onActionStart((event: GestureEvent) => {
            this.pinchActive = true;
            this.pinchBase = this.zoom;
            this.pinchPanBaseX = this.panX;
            this.pinchPanBaseY = this.panY;
            /*
             * 焦点取"捏合中心相对裁剪框中心"的偏移。起手事件里中心点为 (0,0) 时按框中心处理
             * （用户恰好捏在框左上角才会与真实焦点重合，代价可接受）。
             */
            const unknown: boolean = event.pinchCenterX === 0 && event.pinchCenterY === 0;
            this.pinchFocalX = unknown ? 0 : event.pinchCenterX - this.frameEdge() / 2;
            this.pinchFocalY = unknown ? 0 : event.pinchCenterY - this.frameEdge() / 2;
          })
          .onActionUpdate((event: GestureEvent) => {
            const next: number = Math.min(Math.max(this.pinchBase * event.scale, CROP_ZOOM_MIN), CROP_ZOOM_MAX);
            const k: number = next / this.pinchBase;
            // 焦点下的那个像素在缩放前后停在同一位置。
            this.zoom = next;
            this.panX = this.pinchFocalX - k * (this.pinchFocalX - this.pinchPanBaseX);
            this.panY = this.pinchFocalY - k * (this.pinchFocalY - this.pinchPanBaseY);
            this.clampPan();
          })
          .onActionEnd(() => {
            this.pinchActive = false;
            this.clampPan();
          })
      )
    )
  }

  build() {
    Column() {
      this.CropBar()
      Stack({ alignContent: Alignment.Center }) {
        this.CropFrame()
        if (this.areaWidth > CROP_DONE_WIDTH + CROP_DONE_RIGHT &&
          this.areaHeight > CROP_DONE_HEIGHT + CROP_DONE_BOTTOM) {
          Button('完成')
            .fontSize(16)
            .fontColor(Color.White)
            .backgroundColor(AppTheme.ACCENT)
            .borderRadius(8)
            .width(CROP_DONE_WIDTH)
            .height(CROP_DONE_HEIGHT)
            .position({
              x: this.areaWidth - CROP_DONE_RIGHT - CROP_DONE_WIDTH,
              y: this.areaHeight - CROP_DONE_BOTTOM - CROP_DONE_HEIGHT
            })
            .onClick(() => { this.finish(); })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.areaWidth = newValue.width as number;
        this.areaHeight = newValue.height as number;
        this.clampPan();
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CROP_BACKDROP)
  }
}
