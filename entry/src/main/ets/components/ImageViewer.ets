/** 全屏图片查看器，支持缩放、滑动切换、导出与当前图片超分。 */

import { promptAction, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { KeyCode } from '@ohos.multimodalInput.keyCode';
import {
  copyImageToPasteboard,
  fetchImageBytes,
  imageFileName,
  saveImageToGallery,
  shareImageFile,
  writeImageToCache
} from '../utils/ImageExport';
import { srEncodePixelMap } from '../utils/ImageSuperResolution';
import { superResolutionStore } from '../common/appearance/SuperResolutionStore';
import {
  SR_BUTTON_BASE,
  SR_BUTTON_ICON,
  SR_BUTTON_INSET,
  SR_BUTTON_MARGIN,
  SR_BUTTON_TOUCH,
  SrButtonBox,
  SrStatus,
  srButtonPosition,
  srExportFileName,
  srExportFormat,
  srFormatExtension
} from '../model/ImageSuperResolution';
import {
  ImageSuperResolutionSession,
  PageSuperResolutionState,
  SrToggleResult
} from '../viewmodel/ImageSuperResolutionVM';

const MIN_SCALE: number = 1;
const MAX_SCALE: number = 4;
const DOUBLE_TAP_SCALE: number = 2;
const ANIMATION_DURATION: number = 180;
/** 导出菜单日志（C-06／H-07 真机取证用；只记状态与地址前 60 字符，不含凭据） */
const EXPORT_DOMAIN: number = 0x0;
const EXPORT_TAG: string = 'ImageViewerExport';

class ImageSize {
  width: number = 0;
  height: number = 0;
}

interface ImageCompleteInfo {
  width: number;
  height: number;
  loadingStatus: number;
}

enum ImageLoadState {
  LOADING,
  SUCCESS,
  ERROR
}

/**
 * 每页的缩放 / 位移状态就放在页内（`@State`）。
 *
 * 曾经这里挂着一个 `@Observed class PageViewState` + 父组件持有数组 + `@ObjectLink`，
 * 目的是"翻页时不重建页面，同时把离开的那页缩放复位"。实测发现这条路**没有意义**：
 * 本页放大后 `PanGesture`（`ZoomedImage` 上那条，`distance: 5`）会独占横向手势，
 * `swipe` 与 `fling` 都推不动 `Swiper`（实测页码纹丝不动停在 `1 / 8`）——
 * 也就是说**放大状态下根本切不了页**，"翻页时复位别的页"永远不会发生。
 * 于是退回页内 `@State`：新页在 `aboutToAppear` 里自然回到 1x，够用且少一层状态。
 */

@Component
struct ZoomableImagePage {
  imageUrl: string = '';

  onTapImage: () => void = (): void => {};
  /** 长按画面：打开导出菜单（C-06／H-07） */
  onLongPressImage: () => void = (): void => {};

  @State private zoomScale: number = MIN_SCALE;
  @State private panX: number = 0;
  @State private panY: number = 0;
  @State private containerWidth: number = 0;
  @State private containerHeight: number = 0;
  @State private sourceWidth: number = 0;
  @State private sourceHeight: number = 0;
  @State private loadState: ImageLoadState = ImageLoadState.LOADING;
  @State private retryCount: number = 0;
  /** 顶部避让区（状态栏）高度 vp：超分按钮不得钻到状态栏底下 */
  @State private topSafeVp: number = 0;

  /** 本页在图片列表里的下标（回调时原样带回，不依赖 `currentIndex` 的时序） */
  index: number = 0;
  /** 点超分按钮：由查看器决定语义（起任务 / 关闭 / 只解释原因） */
  onSuperResolutionToggle: (index: number) => void = (): void => {};
  /** 解码成功时把**真实像素尺寸**报给查看器：尺寸不合规的图在点击前就能灰显 */
  onImageDecoded: (index: number, width: number, height: number) => void = (): void => {};
  /**
   * 这一页的超分状态。**`@ObjectLink`**：处理完成 / 被淘汰 / 失败这些变化由会话发起，
   * 只有 `@ObjectLink` 能把它们推进到本页界面，而不必改 `ForEach` 的 key
   * （改 key 会重建页面、`Image` 重新加载 —— 翻页闪一下、缩放复位的老路）。
   */
  @ObjectLink sr: PageSuperResolutionState;

  private srTouchActive: boolean = false;
  private srGuardUntil: number = 0;

  private pinchBase: number = MIN_SCALE;
  private panBaseX: number = 0;
  private panBaseY: number = 0;

  aboutToAppear(): void {
    this.resetImageState();
    this.readWindowSize();
  }

  private resetImageState(): void {
    this.zoomScale = MIN_SCALE;
    this.panX = 0;
    this.panY = 0;
    this.loadState = ImageLoadState.LOADING;
    this.retryCount = 0;
    this.sourceWidth = 0;
    this.sourceHeight = 0;
  }

  private readWindowSize(): void {
    try {
      const context = this.getUIContext().getHostContext();
      window.getLastWindow(context).then((win: window.Window) => {
        const rect = win.getWindowProperties().windowRect;
        this.containerWidth = rect.width > 0 ? px2vp(rect.width) : this.containerWidth;
        this.containerHeight = rect.height > 0 ? px2vp(rect.height) : this.containerHeight;
        // 查看器用 expandSafeArea 铺满全屏，状态栏是叠在上面画的 ——
        // 超分按钮要靠避让区把自己压到状态栏下面，否则会和时钟/电量叠在一起。
        const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        this.topSafeVp = px2vp(area.topRect.height);
      }).catch(() => {
        // onAreaChange 会提供更精确的组件尺寸；这里仅作为早期兜底。
      });
    } catch (err) {
      // 不影响图片加载和手势。
    }
  }

  private sourceForLoad(): string {
    if (this.retryCount <= 0) {
      return this.imageUrl;
    }
    const separator: string = this.imageUrl.indexOf('?') >= 0 ? '&' : '?';
    return `${this.imageUrl}${separator}preview_retry=${this.retryCount}`;
  }

  // ───────────────────────── 图像超分：本页按钮 ─────────────────────────

  /** 当前显示的是不是增强图。**增强图与原图各自独立引用**，原图 URL 始终留着 */
  private showingEnhanced(): boolean {
    return this.sr.status === SrStatus.ON && this.sr.pixelMap !== null;
  }

  /** 交给 `Image` 的源：开着超分用增强 PixelMap，否则用原图 URL */
  private displaySource(): image.PixelMap | string {
    const enhanced: image.PixelMap | null = this.sr.pixelMap;
    if (this.sr.status === SrStatus.ON && enhanced !== null) {
      return enhanced;
    }
    return this.sourceForLoad();
  }

  /** 当前画面的原始像素宽：增强图用结果尺寸，原图用 `onComplete` 报的尺寸 */
  private displayedSourceWidth(): number {
    if (this.showingEnhanced() && this.sr.resultWidth > 0) {
      return this.sr.resultWidth;
    }
    return this.sourceWidth;
  }

  private displayedSourceHeight(): number {
    if (this.showingEnhanced() && this.sr.resultHeight > 0) {
      return this.sr.resultHeight;
    }
    return this.sourceHeight;
  }

  /** 手势护栏：刚碰过超分按钮的一小段时间内，不认"单击关闭 / 双击放大 / 长按导出" */
  private srBlocked(): boolean {
    return this.srTouchActive || Date.now() < this.srGuardUntil;
  }

  private srIconColor(): ResourceColor {
    if (this.sr.status === SrStatus.UNAVAILABLE) {
      return '#80FFFFFF';
    }
    return Color.White;
  }

  private srBaseColor(): ResourceColor {
    if (this.sr.status === SrStatus.UNAVAILABLE) {
      return '#33000000';
    }
    if (this.sr.status === SrStatus.ON) {
      // 与主题强调色同源（`#0A59F7`）：开启成功才变蓝，一眼能看出"现在看的是增强图"
      return '#CC0A59F7';
    }
    return '#66000000';
  }

  private srAccessibilityText(): string {
    if (this.sr.status === SrStatus.PROCESSING) {
      return '正在处理图像超分';
    }
    if (this.sr.status === SrStatus.ON) {
      return '关闭图像超分';
    }
    if (this.sr.status === SrStatus.UNAVAILABLE) {
      return '图像超分不可用';
    }
    if (this.sr.status === SrStatus.ERROR) {
      return '图像超分失败，点击重试';
    }
    return '开启图像超分';
  }

  /**
   * 按钮落点：以**图片实际显示区域的右上角**为锚、内缩 12vp，再夹进可操作区域。
   * 几何全在纯逻辑 `srButtonPosition()` 里，边界（小图/长图/满屏/放大拖动出屏）
   * 由 Node 侧用例钉住；这里只把当前页的实时数值喂进去。
   */
  private srButtonBox(): SrButtonBox {
    const fit: ImageSize = this.sourceImageSize();
    return srButtonPosition(this.containerWidth, this.containerHeight, fit.width, fit.height,
      this.zoomScale, this.panX, this.panY, SR_BUTTON_INSET, this.topSafeVp + SR_BUTTON_MARGIN);
  }

  @Builder
  private SuperResolutionButton() {
    Stack() {
      Stack() {
        if (this.sr.status === SrStatus.PROCESSING) {
          LoadingProgress()
            .width(SR_BUTTON_ICON)
            .height(SR_BUTTON_ICON)
            .color(Color.White)
        } else {
          // 两态与全站图标约定一致：未开启用线框、开启后用实心
          SymbolGlyph(this.sr.status === SrStatus.ON
            ? $r('sys.symbol.wand_and_stars_fill')
            : $r('sys.symbol.wand_and_stars'))
            .fontSize(SR_BUTTON_ICON)
            .fontColor([this.srIconColor()])
        }
      }
      .width(SR_BUTTON_BASE)
      .height(SR_BUTTON_BASE)
      .borderRadius(SR_BUTTON_BASE / 2)
      .backgroundColor(this.srBaseColor())
    }
    .width(SR_BUTTON_TOUCH)
    .height(SR_BUTTON_TOUCH)
    .position({ x: this.srButtonBox().x, y: this.srButtonBox().y })
    .accessibilityText(this.srAccessibilityText())
    .accessibilityLevel('yes')
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.srTouchActive = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.srTouchActive = false;
      }
      this.srGuardUntil = Date.now() + 400;
    })
    .onClick(() => {
      this.srGuardUntil = Date.now() + 400;
      this.onSuperResolutionToggle(this.index);
    })
  }

  private sourceImageSize(): ImageSize {
    const result: ImageSize = new ImageSize();
    const widthPx: number = this.displayedSourceWidth();
    const heightPx: number = this.displayedSourceHeight();
    if (widthPx <= 0 || heightPx <= 0) {
      result.width = this.containerWidth;
      result.height = this.containerHeight;
      return result;
    }
    const imageWidth: number = px2vp(widthPx);
    const imageHeight: number = px2vp(heightPx);
    if (this.containerWidth <= 0 || this.containerHeight <= 0) {
      result.width = imageWidth;
      result.height = imageHeight;
      return result;
    }
    const fitScale: number = Math.min(this.containerWidth / imageWidth, this.containerHeight / imageHeight);
    result.width = imageWidth * fitScale;
    result.height = imageHeight * fitScale;
    return result;
  }

  private offsetLimitX(): number {
    const size = this.sourceImageSize();
    return Math.max(0, (size.width * this.zoomScale - this.containerWidth) / 2);
  }

  private offsetLimitY(): number {
    const size = this.sourceImageSize();
    return Math.max(0, (size.height * this.zoomScale - this.containerHeight) / 2);
  }

  private clampOffsets(): void {
    const limitX: number = this.offsetLimitX();
    const limitY: number = this.offsetLimitY();
    this.panX = Math.max(-limitX, Math.min(limitX, this.panX));
    this.panY = Math.max(-limitY, Math.min(limitY, this.panY));
  }

  private setScale(value: number): void {
    const next: number = Math.max(MIN_SCALE, Math.min(MAX_SCALE, value));
    this.zoomScale = next;
    if (next === MIN_SCALE) {
      this.panX = 0;
      this.panY = 0;
    } else {
      this.clampOffsets();
    }
  }

  private settleScale(): void {
    const target: number = Math.max(MIN_SCALE, Math.min(MAX_SCALE, this.zoomScale));
    animateTo({ duration: ANIMATION_DURATION }, () => {
      this.setScale(target);
      if (target === MIN_SCALE) {
        this.panX = 0;
        this.panY = 0;
      }
    });
  }

  private toggleDoubleTapZoom(): void {
    animateTo({ duration: ANIMATION_DURATION }, () => {
      if (this.zoomScale > MIN_SCALE) {
        this.setScale(MIN_SCALE);
      } else {
        this.setScale(DOUBLE_TAP_SCALE);
      }
    });
  }

  private retry(): void {
    this.retryCount += 1;
    this.loadState = ImageLoadState.LOADING;
    this.sourceWidth = 0;
    this.sourceHeight = 0;
  }

  @Builder
  private PreviewImage() {
    Image(this.displaySource())
      .objectFit(ImageFit.Contain)
      // 全屏缩放优先保留边缘细节；列表缩略图继续使用默认插值以控制开销。
      .interpolation(this.zoomScale > MIN_SCALE ? ImageInterpolation.High : ImageInterpolation.Medium)
      .width('100%')
      .height('100%')
      .scale({ x: this.zoomScale, y: this.zoomScale })
      .translate({ x: this.panX, y: this.panY })
      .onComplete((event?: ImageCompleteInfo) => {
        // 0 仅表示数据已加载，1 才表示解码完成、图片可以显示。
        if (event === undefined || event.loadingStatus !== 1) { return; }
        /*
         * 增强图的尺寸**不写进原图口径**：原图始终保留自己的身份，
         * 于是关掉开关时能立刻回到原来那张，且下次开着超分时基准尺寸不被污染。
         * 图片解码尺寸同时上报查看器，用于"尺寸不合规就提前灰显"。
         */
        if (!this.showingEnhanced()) {
          this.sourceWidth = event.width;
          this.sourceHeight = event.height;
          this.onImageDecoded(this.index, event.width, event.height);
        }
        this.loadState = ImageLoadState.SUCCESS;
        this.clampOffsets();
      })
      .onError(() => {
        this.loadState = ImageLoadState.ERROR;
      })
  }

  @Builder
  private ZoomedImage() {
    Stack() {
      this.PreviewImage()
    }
    .width('100%')
    .height('100%')
      .gesture(
        PanGesture({ fingers: 1, distance: 5 })
          .onActionStart(() => {
            this.panBaseX = this.panX;
            this.panBaseY = this.panY;
          })
          .onActionUpdate((event: GestureEvent) => {
            this.panX = this.panBaseX + event.offsetX;
            this.panY = this.panBaseY + event.offsetY;
            this.clampOffsets();
          })
          .onActionEnd(() => {
            this.clampOffsets();
          })
      )
  }

  @Builder
  private LoadOverlay() {
    if (this.loadState === ImageLoadState.LOADING) {
      Progress({ value: 0, total: 100, type: ProgressType.Ring })
        .width(34)
        .height(34)
        .color(Color.White)
    } else if (this.loadState === ImageLoadState.ERROR) {
      Column({ space: 10 }) {
        Text('图片加载失败')
          .fontSize(15)
          .fontColor(Color.White)
        Text('点击重试')
          .fontSize(14)
          .fontColor('#B8D8FF')
          .onClick(() => {
            this.retry();
          })
      }
      .padding({ left: 18, right: 18, top: 14, bottom: 14 })
      .borderRadius(10)
      .backgroundColor('#99000000')
    }
  }

  build() {
    Stack() {
      /*
       * ① 手势层：图片 + 缩放/拖动/单击(关闭)/双击(放大)/长按(导出菜单)。
       *
       * 超分按钮**刻意不放这一层**：放在这里它会和 TapGesture(count:1) 抢手势竞技场，
       * 点按钮有概率被判定成"单击画面 → 关闭查看器"。见 ②。
       */
      Stack() {
        if (this.zoomScale > MIN_SCALE) {
          this.ZoomedImage()
        } else {
          this.PreviewImage()
        }
        this.LoadOverlay()
      }
      .width('100%')
      .height('100%')
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.containerWidth = newValue.width as number;
        this.containerHeight = newValue.height as number;
        this.clampOffsets();
      })
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          PinchGesture({ fingers: 2 })
            .onActionStart(() => {
              this.pinchBase = this.zoomScale;
            })
            .onActionUpdate((event: GestureEvent) => {
              this.setScale(this.pinchBase * event.scale);
            })
            .onActionEnd(() => {
              this.settleScale();
            }),
          TapGesture({ count: 2 })
            .onAction(() => {
              if (this.srBlocked()) {
                return;
              }
              this.toggleDoubleTapZoom();
            }),
          TapGesture({ count: 1 })
            .onAction(() => {
              if (this.srBlocked()) {
                return;
              }
              this.onTapImage();
            })
        )
      )

      .parallelGesture(
        LongPressGesture({ repeat: false, duration: 400 })
          .onAction(() => {
            if (this.srBlocked()) {
              return;
            }
            hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'gesture longpress fired');
            this.onLongPressImage();
          })
      )

      /*
       * ② 超分按钮层：**独立兄弟节点**，压在手势层之上。
       *
       * 命中测试只走最上面那个节点，因此手指落在按钮上时，①那一层根本收不到这次触摸 ——
       * 单击关闭、双击放大、长按导出、拖动都不会被误触发，按钮的 `onClick` 也不会被手势吃掉。
       * 按钮位置由 `srButtonPosition()` 算：贴着图片显示区域右上角，且始终留在屏幕可操作区域内。
       *
       * 设置里把「图像超分」关掉后**整层都不渲染**（连"本机不支持"的灰显也不留位），
       * 这就是那个开关的唯一作用；超分本身仍是每张图各自的手动动作。
       */
      if (superResolutionStore.enabled) {
        this.SuperResolutionButton()
      }
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct ImageViewer {
  imageUrl: string = '';
  imageUrls: string[] = [];
  initialIndex: number = 0;
  onClose: () => void = (): void => {};

  /** 当前页下标：驱动 `Swiper.index` 与底部页码 */
  @State private currentIndex: number = 0;
  /** 底部安全区（系统手势条高度，vp）：页码贴底时用它把文字顶到手势条之上 */
  @State private bottomSafeVp: number = 0;
  /** 导出菜单是否打开（C-06／H-07） */
  @State private exportOpen: boolean = false;
  /** 导出准备状态：0 未开始｜1 下载中｜2 就绪｜3 失败 */
  @State private exportState: number = 0;
  /** 准备失败原因（原话展示，不吞） */
  @State private exportError: string = '';
  /** 正在执行的动作名（防重复点击，仅用于提示） */
  @State private exportBusy: string = '';
  /**
   * 超分状态变化的计数器。
   *
   * 按钮在页组件里走 `@ObjectLink`，不依赖它；它只服务于**导出菜单**：
   * `srStates` 是普通数组（不参与 ArkUI 观察），菜单里"增强图"那一段是否出现
   * 必须靠一个真正的 `@State` 参与求值才会跟着重算（见 `showEnhancedSection()`）。
   */
  @State private srTick: number = 0;

  /** 已下载的图片字节与沙箱文件 URI（非状态，避免深观察大数组） */
  private exportBytes: Uint8Array | null = null;
  private exportUri: string = '';
  /** 长按抬手后的一小段时间内忽略"单击关闭"（长按与单击可能同时被判定，见 parallelGesture 注释） */
  private suppressCloseUntil: number = 0;

  /** 本次看图会话的超分状态机（打开时建、关闭时 `close()` 释放） */
  private srSession: ImageSuperResolutionSession = new ImageSuperResolutionSession();
  /** 与图片一一对应的状态对象：**按 URL 复用**，翻页回来仍是同一个对象 */
  private srStates: PageSuperResolutionState[] = [];

  aboutToAppear(): void {
    const urls: string[] = this.effectiveImageUrls();
    this.currentIndex = this.clampedIndex(this.initialIndex, urls.length);
    this.buildSrStates(urls);
    this.readSafeArea();
    this.hideSystemStatusBar();
  }

  aboutToDisappear(): void {
    // 会话结束：使在飞任务失效、清空增强图缓存、在安全时机释放分析器
    this.srSession.close();
    this.restoreSystemStatusBar();
  }

  /** 打开看图时抓住的窗口对象：关闭时用它还原状态栏，不再重新取一次（组件已在销毁中） */
  private viewerWindow: window.Window | null = null;
  /** 打开前状态栏是否可见 —— 还原时按这个值走，不无脑点亮 */
  private statusWasVisible: boolean = true;
  /** 本次是否真的成功隐藏过（没隐藏过就不去"还原"） */
  private statusHiddenByViewer: boolean = false;

  private hideSystemStatusBar(): void {
    try {
      const context = this.getUIContext().getHostContext();
      window.getLastWindow(context).then((win: window.Window) => {
        this.viewerWindow = win;
        const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        this.statusWasVisible = px2vp(area.topRect.height) > 0;
        win.setSpecificSystemBarEnabled('status', false, true).then(() => {
          this.statusHiddenByViewer = true;
        }).catch(() => {
          // 隐藏失败就照旧显示：看图不受影响，不弹错（用户一眼能看出状态栏还在）
        });
      }).catch(() => {
        // 拿不到窗口对象：保持原样
      });
    } catch (err) {
      // 同上：不影响图片加载与手势
    }
  }

  /** 关闭查看器：按打开时的可见性还原状态栏 */
  private restoreSystemStatusBar(): void {
    if (!this.statusHiddenByViewer || this.viewerWindow === null) {
      return;
    }
    this.statusHiddenByViewer = false;
    this.viewerWindow.setSpecificSystemBarEnabled('status', this.statusWasVisible, true)
      .catch(() => {
        // 还原失败不阻断关闭：首页下一次滚动/回到前台会按自己的状态再设一次
      });
  }

  /** 按当前图片列表准备每张图的状态对象，并把"当前是谁"告诉会话（用于切图失效判定） */
  private buildSrStates(urls: string[]): void {
    const states: PageSuperResolutionState[] = [];
    for (let i: number = 0; i < urls.length; i++) {
      states.push(this.srSession.stateFor(urls[i]));
    }
    this.srStates = states;
    if (urls.length > 0) {
      this.srSession.setCurrentKey(urls[this.clampedIndex(this.initialIndex, urls.length)]);
    }
  }

  /** 当前页状态对象（`ForEach` 里取用）。列表在打开期间固定，这里只兜住越界 */
  private srStateAt(index: number, url: string): PageSuperResolutionState {
    if (index >= 0 && index < this.srStates.length) {
      return this.srStates[index];
    }
    return this.srSession.stateFor(url);
  }

  /** 翻页 / 长按换页时同步"当前图"：切走会让在飞任务的**结果作废**（底层仍会跑完） */
  private syncSrCurrent(index: number): void {
    const urls: string[] = this.effectiveImageUrls();
    if (index < 0 || index >= urls.length) {
      return;
    }
    this.srSession.setCurrentKey(urls[index]);
    this.srTick += 1;
  }

  /** 页组件上报解码尺寸：尺寸不合规的图在点击前就灰显并给出原因 */
  private noteDecoded(index: number, width: number, height: number): void {
    const urls: string[] = this.effectiveImageUrls();
    if (index < 0 || index >= urls.length) {
      return;
    }
    this.srSession.noteDecodedSize(urls[index], width, height);
  }

  /** 点一次超分按钮（页组件回调）；提示文案由会话决定，这里只负责原话展示 */
  private async toggleSuperResolution(index: number): Promise<void> {
    const urls: string[] = this.effectiveImageUrls();
    if (index < 0 || index >= urls.length) {
      return;
    }
    hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'sr toggle index=%{public}d url=%{public}s',
      index, urls[index].slice(0, 60));
    const outcome: SrToggleResult = await this.srSession.toggle(urls[index]);
    this.srTick += 1;
    if (outcome.message.length > 0) {
      this.toast(outcome.message);
    }
  }

  private effectiveImageUrls(): string[] {
    if (this.imageUrls.length > 0) {
      return this.imageUrls;
    }
    return this.imageUrl.length > 0 ? [this.imageUrl] : [];
  }

  private clampedIndex(index: number, count: number): number {
    if (count <= 0 || index < 0) {
      return 0;
    }
    return index >= count ? count - 1 : index;
  }

  private readSafeArea(): void {
    try {
      const context = this.getUIContext().getHostContext();
      window.getLastWindow(context).then((win: window.Window) => {
        const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        this.bottomSafeVp = px2vp(area.bottomRect.height);
      }).catch(() => {
        // 没有避让区信息时保持 0，页码仍有自身视觉间距。
      });
    } catch (err) {
      // 不影响预览主体。
    }
  }

  /**
   * 页码提示：贴在**底部居中**，只显示 `n / N`，**常显**。
   *
   * 单击画面的语义已从"切换这枚页码的显隐"改为"关闭查看器"（对齐常见看图 App 的手感），
   * 于是不再有隐藏态：`count > 1` 时一直显示。单图（`count <= 1`）没有可翻的页，不显示。
   *
   * 给一层 `#66000000` 圆角药丸底：页码压在照片上，纯白字遇到浅色照片会看不见。
   */
  @Builder
  private PageBadge(count: number) {
    if (count > 1) {
      Row() {
        Text(`${this.currentIndex + 1} / ${count}`)
          .fontSize(14)
          .fontColor(Color.White)
      }
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .borderRadius(12)
      .backgroundColor('#66000000')
      .margin({ bottom: this.bottomSafeVp + 12 })
    }
  }

  // ───────────────────────── C-06／H-07：长按导出 ─────────────────────────

  /** 当前页地址 */
  private currentUrl(): string {
    const urls: string[] = this.effectiveImageUrls();
    if (urls.length === 0) {
      return this.imageUrl;
    }
    const index: number = this.clampedIndex(this.currentIndex, urls.length);
    return urls[index];
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  /** 长按：打开菜单并**先把图下下来**（安全控件的授权窗口很短，不能在点保存时才去下载） */
  private openExport(): void {
    hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'openExport index=%{public}d url=%{public}s',
      this.currentIndex, this.currentUrl().slice(0, 60));
    this.suppressCloseUntil = Date.now() + 700;
    this.exportOpen = true;
    this.exportError = '';
    this.exportBytes = null;
    this.exportUri = '';
    this.exportState = 1;
    this.prepareExport();
  }

  private async prepareExport(): Promise<void> {
    const url: string = this.currentUrl();
    try {
      const bytes: Uint8Array = await fetchImageBytes(url);
      const name: string = imageFileName(url, this.currentIndex);
      const uri: string = writeImageToCache(this.hostContext(), bytes, name);
      this.exportBytes = bytes;
      this.exportUri = uri;
      this.exportState = 2;
      hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'prepare ok bytes=%{public}d', bytes.length);
    } catch (err) {
      this.exportState = 3;
      this.exportError = err instanceof Error ? err.message : String(err);
      hilog.error(EXPORT_DOMAIN, EXPORT_TAG, 'prepare failed: %{public}s', this.exportError);
    }
  }

  private closeExport(): void {
    this.exportOpen = false;
    this.exportState = 0;
    this.exportError = '';
    this.exportBusy = '';
    this.exportBytes = null;
    this.exportUri = '';
  }

  private toast(message: string): void {
    promptAction.showToast({ message: message, duration: 2000 });
  }

  /** 保存到相册：只在 `SaveButton` 授权成功后调用（见 utils/ImageExport 头注释） */
  private async saveToGallery(): Promise<void> {
    if (this.exportState !== 2 || this.exportUri.length === 0) {
      hilog.warn(EXPORT_DOMAIN, EXPORT_TAG, 'save skipped state=%{public}d uri=%{public}d',
        this.exportState, this.exportUri.length);
      this.toast('图片还没准备好');
      return;
    }
    this.exportBusy = 'save';
    try {
      await saveImageToGallery(this.hostContext(), this.exportUri);
      hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'save ok');
      this.toast('已保存到相册');
      this.closeExport();
    } catch (err) {
      hilog.error(EXPORT_DOMAIN, EXPORT_TAG, 'save failed: %{public}s',
        err instanceof Error ? err.message : String(err));
      this.toast(`保存失败：${err instanceof Error ? err.message : String(err)}`);
    } finally {
      this.exportBusy = '';
    }
  }

  private async copyImage(): Promise<void> {
    if (this.exportBytes === null || this.exportState !== 2) {
      hilog.warn(EXPORT_DOMAIN, EXPORT_TAG, 'copy skipped state=%{public}d bytes=%{public}d',
        this.exportState, this.exportBytes === null ? -1 : this.exportBytes.length);
      this.toast('图片还没准备好');
      return;
    }
    this.exportBusy = 'copy';
    try {
      await copyImageToPasteboard(this.exportBytes);
      hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'copy ok');
      this.toast('已复制图片');
      this.closeExport();
    } catch (err) {
      hilog.error(EXPORT_DOMAIN, EXPORT_TAG, 'copy failed: %{public}s',
        err instanceof Error ? err.message : String(err));
      this.toast(`复制失败：${err instanceof Error ? err.message : String(err)}`);
    } finally {
      this.exportBusy = '';
    }
  }

  private async shareImage(): Promise<void> {
    if (this.exportState !== 2 || this.exportUri.length === 0) {
      hilog.warn(EXPORT_DOMAIN, EXPORT_TAG, 'share skipped state=%{public}d uri=%{public}d',
        this.exportState, this.exportUri.length);
      this.toast('图片还没准备好');
      return;
    }
    this.exportBusy = 'share';
    try {
      await shareImageFile(this.hostContext(), this.exportUri, '贴吧图片');
      hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'share panel shown');
      this.closeExport();
    } catch (err) {
      hilog.error(EXPORT_DOMAIN, EXPORT_TAG, 'share failed: %{public}s',
        err instanceof Error ? err.message : String(err));
      this.toast(`分享失败：${err instanceof Error ? err.message : String(err)}`);
    } finally {
      this.exportBusy = '';
    }
  }

  /** 菜单里的段标题：把"原图"和"增强图"两段分开，避免两张「保存图片」分不清 */
  @Builder
  private ExportSectionLabel(label: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor('#B3FFFFFF')
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 10, bottom: 2 })
  }

  @Builder
  private SaveToGalleryButton(kind: number) {
    SaveButton({ icon: SaveIconStyle.FULL_FILLED, text: SaveDescription.SAVE_IMAGE })
      .iconSize(22)
      .fontSize(16)
      .fontColor(Color.White)
      .backgroundColor(Color.Transparent)
      .width('100%')
      .height(52)
      .padding({ left: 12 })
      .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
        if (result !== SaveButtonOnClickResult.SUCCESS) {
          hilog.warn(EXPORT_DOMAIN, EXPORT_TAG, 'save not authorized result=%{public}d', result);
          this.toast('未获得保存授权');
          return;
        }
        if (kind === 5) {
          this.exportEnhanced(false);
        } else {
          this.saveToGallery();
        }
      })
  }

  @Builder
  private ExportRow(icon: Resource, label: string, kind: number) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([this.exportRowColor(kind)])
      Text(label)
        .fontSize(16)
        .fontColor(this.exportRowColor(kind))
        .layoutWeight(1)
    }
    .width('100%')
    .height(52)
    .padding({ left: 20, right: 20 })
    .onClick(() => {
      this.runExportAction(kind);
    })
  }

  /** 行的可用性：复制/分享原图依赖原图已就绪；增强图的保存/分享依赖增强图已生成 */
  private exportRowEnabled(kind: number): boolean {
    if (kind === 0 || kind === 1) {
      return this.exportState === 2;
    }
    if (kind === 5) {
      return this.enhancedReady();
    }
    return true;
  }

  private exportRowColor(kind: number): ResourceColor {
    return this.exportRowEnabled(kind) ? Color.White : '#66FFFFFF';
  }

  private runExportAction(kind: number): void {
    if (!this.exportRowEnabled(kind)) {
      hilog.warn(EXPORT_DOMAIN, EXPORT_TAG, 'row %{public}d ignored state=%{public}d',
        kind, this.exportState);
      this.toast('图片还没准备好');
      return;
    }
    if (kind === 0) {
      this.copyImage();
    } else if (kind === 1) {
      this.shareImage();
    } else if (kind === 5) {
      this.exportEnhanced(true);
    } else if (kind === 2) {
      this.exportState = 1;
      this.exportError = '';
      this.prepareExport();
    } else {
      this.closeExport();
    }
  }

  // ───────────────────────── 图像超分：增强图导出 ─────────────────────────

  /** 当前页的状态对象（页码越界返回 null） */
  private currentSrState(): PageSuperResolutionState | null {
    const index: number = this.currentIndex;
    if (index < 0 || index >= this.srStates.length) {
      return null;
    }
    return this.srStates[index];
  }

  /**
   * 当前图是否有**可导出的增强图**。
   * 处理中、失败、结果被淘汰都不算 —— 这些情况下菜单里不出现增强图那一段。
   */
  private enhancedReady(): boolean {
    const state: PageSuperResolutionState | null = this.currentSrState();
    return state !== null && state.hasResult && state.pixelMap !== null
      && state.status !== SrStatus.PROCESSING;
  }

  /**
   * 菜单里要不要显示"增强图"那一段。
   *
   * `this.srTick >= 0` 不是废话：`srStates` 是普通数组，ArkUI 不观察它，
   * 必须让一个真正的 `@State` 参与这次求值，状态变化后菜单才会重算。
   */
  private showEnhancedSection(): boolean {
    return this.srTick >= 0 && this.enhancedReady();
  }

  /**
   * 导出增强图（保存到相册 / 分享）。
   *
   * **开始时钉住图片身份与结果版本**：编码是异步的，期间翻页不能把"导出这张"
   * 变成"导出另一张"。编码回来后再核对版本，变了就如实说"请重新导出"，不交一份错文件。
   * 增强图用**独立缓存文件名**（`tieba_sr_*`），不覆盖原图缓存。
   * 保存同样走 `SaveButton` 安全控件授权后的调用，**不扩大权限范围**。
   */
  private async exportEnhanced(share: boolean): Promise<void> {
    const state: PageSuperResolutionState | null = this.currentSrState();
    const held: image.PixelMap | null = state === null ? null : state.pixelMap;
    if (state === null || held === null || !this.enhancedReady()) {
      this.toast('增强图还没准备好');
      return;
    }
    const pinnedKey: string = state.key;
    const pinnedVersion: number = state.resultVersion;
    const format: string = srExportFormat(state.resultHasAlpha);
    const extension: string = srFormatExtension(format);
    hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'enhanced export start share=%{public}s ver=%{public}d',
      String(share), pinnedVersion);
    this.exportBusy = share ? 'share-sr' : 'save-sr';
    this.srSession.setExportPin(pinnedKey);
    try {
      const encoded: ArrayBuffer = await srEncodePixelMap(held, format, 100);
      if (state.resultVersion !== pinnedVersion || state.pixelMap === null) {
        hilog.warn(EXPORT_DOMAIN, EXPORT_TAG, 'enhanced export aborted: result changed');
        this.toast('增强图已更新，请重新导出');
        return;
      }
      const uri: string = writeImageToCache(this.hostContext(), new Uint8Array(encoded),
        srExportFileName(this.currentIndex, Date.now(), extension));
      if (share) {
        await shareImageFile(this.hostContext(), uri, '贴吧图片（超分）');
        hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'enhanced share panel shown');
        this.toast('已打开分享面板');
      } else {
        await saveImageToGallery(this.hostContext(), uri);
        hilog.info(EXPORT_DOMAIN, EXPORT_TAG, 'enhanced save ok');
        this.toast('已保存增强图到相册');
      }
      this.closeExport();
    } catch (err) {
      const message: string = err instanceof Error ? err.message : String(err);
      hilog.error(EXPORT_DOMAIN, EXPORT_TAG, 'enhanced export failed: %{public}s', message);
      this.toast(`${share ? '分享' : '保存'}失败：${message}`);
    } finally {
      this.srSession.clearExportPin();
      this.exportBusy = '';
    }
  }

  @Builder
  private ExportSheet() {
    Column() {
      // 遮罩：点它只关菜单，不关查看器
      Column()
        .width('100%')
        .layoutWeight(1)
        .onClick(() => {
          this.closeExport();
        })

      Column({ space: 2 }) {
        Row() {
          Text('图片')
            .fontSize(14)
            .fontColor('#B3FFFFFF')
          Blank()
          if (this.exportState === 1) {
            Row({ space: 6 }) {
              LoadingProgress().width(16).height(16).color(Color.White)
              Text('准备中…').fontSize(13).fontColor('#B3FFFFFF')
            }
          } else if (this.exportState === 3) {
            Text('准备失败')
              .fontSize(13)
              .fontColor('#FF9A9A')
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 12, bottom: 6 })

        if (this.exportState === 3) {
          Text(this.exportError)
            .fontSize(13)
            .fontColor('#FF9A9A')
            .width('100%')
            .padding({ left: 20, right: 20, bottom: 8 })
          this.ExportRow($r('sys.symbol.exclamationmark_circle'), '重试', 2)
        } else {
          // 原图段：保存 / 复制 / 分享**依旧只针对原图**，增强图不顶替它
          this.ExportSectionLabel('原图')
          this.SaveToGalleryButton(4)
          // 复制用 `doc_text_on_doc_text`（与评论长按「复制全部」同一枚，项目已验证可编译可渲染）
          this.ExportRow($r('sys.symbol.doc_text_on_doc_text'), '复制图片', 0)

          this.ExportRow($r('sys.symbol.arrow_up_right'), '分享图片', 1)

          /*
           * 增强图段：**只有真的存在一份增强结果时才出现**。
           * 处理中 / 失败 / 结果已被淘汰都不显示可执行的导出项（`showEnhancedSection()`）。
           * 段标题把两张"保存图片"区分开：安全控件的文案由系统给，改不了。
           */
          if (this.showEnhancedSection()) {
            this.ExportSectionLabel('增强图（图像超分结果）')
            this.SaveToGalleryButton(5)
            this.ExportRow($r('sys.symbol.arrow_up_right'), '分享增强图', 5)
          }
        }

        Divider().color('#33FFFFFF').margin({ top: 4 })
        this.ExportRow($r('sys.symbol.xmark'), '取消', 3)
      }
      .width('100%')
      .backgroundColor('#E61C1C1E')
      .borderRadius({ topLeft: 18, topRight: 18 })
      // 底部留白至少 12vp：真机实测 `TYPE_SYSTEM` 避让区在查看器里可能返回 0
      .padding({ bottom: Math.max(this.bottomSafeVp, 12) + 8 })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    // `Bottom` 对齐：页码提示贴底。`Swiper` 自身 100%×100%，不受对齐方式影响。
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.effectiveImageUrls().length > 0) {
        Swiper() {
          ForEach(this.effectiveImageUrls(), (url: string, index: number) => {
            ZoomableImagePage({
              imageUrl: url,
              index: index,
              sr: this.srStateAt(index, url),
              onSuperResolutionToggle: (tapped: number): void => {
                this.toggleSuperResolution(tapped);
              },
              onImageDecoded: (decoded: number, width: number, height: number): void => {
                this.noteDecoded(decoded, width, height);
              },
              onTapImage: (): void => {
                // 长按抬手可能同时被判成一次单击（parallelGesture 的代价）：这段时间内不关查看器
                if (this.exportOpen || Date.now() < this.suppressCloseUntil) {
                  return;
                }
                this.onClose();
              },
              onLongPressImage: (): void => {
                // 长按当前页才有效：翻页动画期间 currentIndex 可能还没跟上
                this.currentIndex = index;
                this.syncSrCurrent(index);
                this.openExport();
              }
            })
          },
          // key **不能带 `this.currentIndex`**：带上的话每翻一页所有 key 都变，
          // `Swiper` 会把整批页面销毁重建、`Image` 重新加载 —— 视觉上就是翻页"闪一下"。
          // 实测：key 含 currentIndex 时打开查看器 mount 3 次、翻一页 mount 8 次；
          // 去掉后翻页只 mount 1 次，且那次是预建屏幕外的下一页。
          (url: string, index: number) => `${index}:${url}`)
        }
        .index(this.currentIndex)
        .indicator(false)
        .loop(false)
        .onChange((index: number) => {
          this.currentIndex = index;
          // 切图使**在飞任务**失效（结果作废、底层照跑完）；已缓存的开关状态保留
          this.syncSrCurrent(index);
        })
        .width('100%')
        .height('100%')
      }
      if (!this.exportOpen) {
        this.PageBadge(this.effectiveImageUrls().length)
      }
      // 导出菜单盖在最上层；打开期间页码隐藏、遮罩接住所有触摸
      if (this.exportOpen) {
        this.ExportSheet()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onKeyEvent((event: KeyEvent): boolean => {
      // 保留但**不生效**：这个 `Stack` 不持有焦点，收不到按键。真正拦返回键的是
      // 宿主 Index / ThreadDetailPage 的 onBackPress（查看器是页面上的浮层）。
      if (event.keyCode === KeyCode.KEYCODE_BACK) {
        this.onClose();
        return true;
      }
      return false;
    })
  }
}
