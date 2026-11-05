import { ComponentContent, LevelMode, LevelOrder, UIContext, window } from '@kit.ArkUI';
import { animateImageTransition } from './ImageTransition';
import { motionGeometryId } from '../common/appearance/MotionPolicy';

/** 仅持有当前按压的一张预览；抬手收回后释放，不新增文件缓存。 */
@ObservedV2
class SavedEmojiPreviewState {
  @Trace visible: boolean = false;
  @Trace originalReady: boolean = false;
  preview: string = '';
  original: string = '';
  transitionId: string = '';
  width: number = 240;
  height: number = 240;
}

@ComponentV2
struct SavedEmojiPreviewLayer {
  @Require @Param state: SavedEmojiPreviewState;
  build() {
    Stack() {
      if (this.state.visible) {
        Stack() {
          Image(this.state.preview).width('100%').height('100%').objectFit(ImageFit.Contain)
          if (this.state.original.length > 0 && this.state.original !== this.state.preview) {
            Image(this.state.original).width('100%').height('100%').objectFit(ImageFit.Contain)
              .opacity(this.state.originalReady ? 1 : 0)
              .onComplete((): void => { this.state.originalReady = true; })
          }
        }
        .width(this.state.width).height(this.state.height)
        .geometryTransition(motionGeometryId(this.state.transitionId)).renderFit(RenderFit.RESIZE_FILL).clip(true)
        .id('saved-emoji-preview-image').accessibilityText('收藏表情放大预览')
      }
    }
    .width('100%').height('100%')
    .backgroundColor(this.state.visible ? '#55000000' : Color.Transparent)
    .hitTestBehavior(HitTestMode.None)
    .focusable(false)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}

@Builder
function savedEmojiPreviewBuilder(state: SavedEmojiPreviewState) {
  SavedEmojiPreviewLayer({ state: state })
}

/** 高于回复面板的无触摸浮层；源格子持续接收抬手和取消事件。 */
export class SavedEmojiPreview {
  private content: ComponentContent<SavedEmojiPreviewState> | undefined = undefined;
  private state: SavedEmojiPreviewState = new SavedEmojiPreviewState();
  private context: UIContext | undefined = undefined;
  private generation: number = 0;
  private held: boolean = false;
  private cleanupTimer: number = -1;
  private suppressUntil: number = 0;

  canInsert(): boolean { return !this.held && Date.now() >= this.suppressUntil; }

  show(context: UIContext, preview: string, original: string, transitionId: string,
    imageWidth: number, imageHeight: number): void {
    this.suppressUntil = Date.now() + 600;
    if (this.content !== undefined || preview.length === 0) { return; }
    this.context = context; this.held = true;
    const mine: number = ++this.generation;
    const state: SavedEmojiPreviewState = new SavedEmojiPreviewState();
    state.preview = preview; state.original = original; state.transitionId = transitionId;
    let availableWidth: number = 360;
    let availableHeight: number = 640;
    try {
      const rect: window.Rect = window.findWindow(context.getWindowName() ?? '').getWindowProperties().windowRect;
      availableWidth = context.px2vp(rect.width); availableHeight = context.px2vp(rect.height);
    } catch (err) { /* 窗口离场时仍有有界兜底，预览随面板销毁。 */ }
    const maxWidth: number = Math.max(120, availableWidth - 48);
    const ratio: number = imageWidth > 0 && imageHeight > 0 ? imageWidth / imageHeight : 1;
    // 长图多用纵向空间，普通收藏图保持当前预览大小。
    const maxHeight: number = Math.max(120, availableHeight * (ratio < 0.5 ? 0.85 : 0.55));
    state.width = Math.min(maxWidth, maxHeight * ratio);
    state.height = state.width / ratio;
    this.state = state;
    const content: ComponentContent<SavedEmojiPreviewState> =
      new ComponentContent(context, wrapBuilder(savedEmojiPreviewBuilder), state);
    this.content = content;
    context.getOverlayManager().openOrderOverlay(content, {
      levelOrder: LevelOrder.clamp(1000), levelMode: LevelMode.OVERLAY
    }).then((): void => {
      if (mine !== this.generation || !this.held) { return; }
      animateImageTransition(context, (): void => { state.visible = true; });
    }).catch((): void => { if (mine === this.generation) { this.dispose(); } });
  }

  hide(): void {
    if (!this.held) { return; }
    this.held = false; this.suppressUntil = Date.now() + 450;
    const context: UIContext | undefined = this.context;
    if (context === undefined) { return; }
    animateImageTransition(context, (): void => { this.state.visible = false; });
    this.cleanupTimer = setTimeout((): void => { this.dispose(); }, 340);
  }

  dispose(): void {
    ++this.generation; this.held = false;
    if (this.cleanupTimer >= 0) { clearTimeout(this.cleanupTimer); this.cleanupTimer = -1; }
    const content: ComponentContent<SavedEmojiPreviewState> | undefined = this.content;
    this.content = undefined;
    if (content !== undefined) {
      this.context?.getOverlayManager().removeComponentContent(content);
      content.dispose();
    }
    this.context = undefined;
  }
}
