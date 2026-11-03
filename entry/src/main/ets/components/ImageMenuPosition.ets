import { common } from '@kit.AbilityKit';
import { smartReachStore, SmartReachStore } from '../common/appearance/SmartReachStore';
import { HoldingSession, holdingSide, clampFloating, positionRatio } from '../model/SmartReach';
import { MotionHoldingSource } from '../common/appearance/MotionHoldingSource';

/** 仅胶囊区域接收手势；长按后拖动，松手吸边，位置独立保存。 */
@ComponentV2
export struct ImageMenuPosition {
  @Param viewportWidth: number = 0;
  @Param viewportHeight: number = 0;
  @Param capsuleHeight: number = 200;
  @Param bottomInset: number = 28;
  @Param busy: boolean = false;
  @BuilderParam content: () => void = this.Empty;
  @Local prefs: SmartReachStore = smartReachStore;
  @Local x: number = 12;
  @Local y: number = 12;
  @Local dragging: boolean = false;
  private alive: boolean = false;
  private pressed: boolean = false;
  private originX: number = 0;
  private originY: number = 0;
  private timer: number = -1;
  private session: HoldingSession = new HoldingSession(new MotionHoldingSource(), (status: number): void => {
    this.onHolding(status);
  });
  @Builder Empty() {}
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private maxX(): number { return Math.max(0, this.viewportWidth - 60); }
  private minX(): number { return Math.min(12, this.maxX()); }
  private maxY(): number { return Math.max(0, this.viewportHeight - this.capsuleHeight - Math.max(28, this.bottomInset) - 12); }
  private minY(): number { return Math.min(12, this.maxY()); }
  aboutToAppear(): void { this.alive = true; this.prefs.load(this.context()); this.restore(); this.subscribe(); }
  aboutToDisappear(): void { this.alive = false; this.cancel(); this.stop(); }
  @Monitor('viewportWidth', 'viewportHeight', 'capsuleHeight', 'bottomInset')
  restore(): void {
    this.x = this.prefs.imageXRatio < 0 ? this.minX() : this.minX() + this.prefs.imageXRatio * (this.maxX() - this.minX());
    this.y = this.prefs.imageYRatio < 0 ? this.maxY() : this.minY() + this.prefs.imageYRatio * (this.maxY() - this.minY());
  }
  private cancel(): void { if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; } }
  private stop(): void { try { this.session.stop(); } catch (_) { this.prefs.status = '看图握姿监听停止失败，已暂停自动移动'; } }
  @Monitor('prefs.enabled', 'prefs.imageMenuEnabled', 'prefs.foreground')
  subscribe(): void {
    if (!this.alive) { return; }
    if (!this.prefs.enabled || !this.prefs.imageMenuEnabled || !this.prefs.foreground) { this.cancel(); this.stop(); return; }
    if (!canIUse('SystemCapability.MultimodalAwareness.Motion')) { return; }
    try { this.session.start(); } catch (_) { this.prefs.status = '看图智感握姿暂不可用，可长按拖拽'; }
  }
  private onHolding(status: number): void {
    this.cancel();
    const side = holdingSide(status);
    if (!this.alive || !this.prefs.enabled || !this.prefs.imageMenuEnabled || !this.prefs.foreground ||
      side === 0 || this.pressed || this.dragging || this.busy) { return; }
    this.timer = setTimeout((): void => {
      this.timer = -1;
      if (!this.alive || this.pressed || this.dragging || this.busy || !this.prefs.enabled ||
        !this.prefs.imageMenuEnabled || !this.prefs.foreground) { return; }
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, (): void => {
        this.x = side === -1 ? this.minX() : this.maxX();
      });
    }, 400);
  }
  private finish(): void {
    this.dragging = false; this.pressed = false; this.cancel();
    this.x = this.x < (this.minX() + this.maxX()) / 2 ? this.minX() : this.maxX();
    this.prefs.setImagePosition(positionRatio(this.x, this.minX(), this.maxX()),
      positionRatio(this.y, this.minY(), this.maxY()), this.context()).catch((error: Error): void => {
      if (this.alive) { this.getUIContext().getPromptAction().showToast({ message: error.message }); }
    });
  }
  build() {
    Stack() { this.content() }
      .width(48).height(this.capsuleHeight)
      .position({ x: this.x, y: this.y })
      .onTouch((event: TouchEvent): void => {
        event.stopPropagation();
        if (event.type === TouchType.Down) { this.pressed = true; this.cancel(); }
        else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.pressed = false; }
      })
      .priorityGesture(GestureGroup(GestureMode.Sequence,
        LongPressGesture({ duration: 450 }).onAction((): void => {
          this.dragging = true; this.originX = this.x; this.originY = this.y; this.cancel();
        }),
        PanGesture({ direction: PanDirection.All, distance: 8 })
          .onActionUpdate((event: GestureEvent): void => {
            this.x = clampFloating(this.originX + event.offsetX, this.minX(), this.maxX());
            this.y = clampFloating(this.originY + event.offsetY, this.minY(), this.maxY());
          })
          .onActionEnd((): void => { this.finish(); })
      ).onCancel((): void => { this.dragging = false; this.pressed = false; this.cancel(); }))
  }
}
