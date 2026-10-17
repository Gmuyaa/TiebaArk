import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { motion } from '@kit.MultimodalAwarenessKit';
import { curves } from '@kit.ArkUI';
import { GlassCircleButton } from './GlassCircleButton';
import { smartReachStore, SmartReachStore } from '../common/appearance/SmartReachStore';
import { MaterialSlot } from '../common/material/MaterialConfig';
import {
  clampFloating, dockFloatingX, holdingSide, HoldingSession, HoldingSource, positionRatio,
  threadActionBounds, threadFanPoints, ThreadFanPoint, THREAD_ACTION_BUTTON_SIZE, THREAD_ACTION_HIT_INSET
} from '../model/SmartReach';

class ThreadHoldingSource implements HoldingSource {
  on(callback: (status: number) => void): void { motion.on('holdingHandChanged', callback); }
  off(callback: (status: number) => void): void { motion.off('holdingHandChanged', callback); }
}

/** 沉浸光感帖子操作按钮；只有按钮内侧处理触摸，松手吸附最近侧边并保留高度。 */
@ComponentV2
export struct ThreadPopupButton {
  @Param viewportWidth: number = 0;
  @Param viewportHeight: number = 0;
  @Param topInset: number = 0;
  @Param active: boolean = true;
  @Param open: boolean = false;
  @Event onOpenChange: (open: boolean) => void = (): void => {};
  @Builder emptyAction(_index: number) {}
  @BuilderParam action: (index: number) => void = this.emptyAction;
  @Local prefs: SmartReachStore = smartReachStore;
  @Local x: number = 0;
  @Local y: number = 0;
  @Local ready: boolean = false;
  private alive: boolean = false;
  private pressed: boolean = false;
  private dragging: boolean = false;
  private originX: number = 0;
  private originY: number = 0;
  private lastSide: number = 0;
  private pendingSide: number = 0;
  private timer: number = -1;
  private suppressClickUntil: number = 0;
  private session: HoldingSession = new HoldingSession(new ThreadHoldingSource(), (status: number): void => {
    this.onHolding(status);
  });

  aboutToAppear(): void {
    this.alive = true;
    this.prefs.load(this.context());
    this.restorePosition();
    this.syncSubscription();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.cancelPending();
    this.stop();
    this.onOpenChange(false);
  }

  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }

  @Monitor('viewportWidth', 'viewportHeight', 'topInset')
  restorePosition(): void {
    if (this.viewportWidth <= 0 || this.viewportHeight <= 0) { return; }
    const b = threadActionBounds(this.viewportWidth, this.viewportHeight, this.topInset);
    this.x = this.prefs.threadXRatio < 0 ? b.maxX :
      dockFloatingX(b.minX + this.prefs.threadXRatio * (b.maxX - b.minX), b);
    this.y = this.prefs.threadYRatio < 0 ? b.maxY : b.minY + this.prefs.threadYRatio * (b.maxY - b.minY);
    this.ready = true;
    this.onOpenChange(false);
    this.scheduleMove();
  }

  @Monitor('prefs.enabled', 'prefs.foreground', 'active')
  syncSubscription(): void {
    if (!this.alive) { return; }
    if (!this.active || !this.prefs.enabled || !this.prefs.foreground) {
      this.cancelPending(); this.stop();
      if (!this.active || !this.prefs.foreground) { this.onOpenChange(false); }
      return;
    }
    if (!canIUse('SystemCapability.MultimodalAwareness.Motion')) {
      this.prefs.status = '当前设备不支持智感握姿，可手动拖拽'; return;
    }
    try { this.session.start(); this.prefs.status = '等待识别握姿'; }
    catch (error) {
      const code = (error as BusinessError).code;
      this.prefs.status = code === 801 ? '当前设备不支持智感握姿，可手动拖拽' :
        code === 201 ? '握姿权限未授予，可手动拖拽' : '握姿服务暂不可用，可手动拖拽';
    }
  }

  private stop(): void {
    this.lastSide = 0;
    try { this.session.stop(); }
    catch (_) { this.prefs.status = '握姿监听停止失败，已暂停自动移动'; }
  }

  private cancelPending(): void {
    if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
    this.pendingSide = 0;
  }

  private onHolding(status: number): void {
    if (!this.alive || !this.active || !this.prefs.enabled || !this.prefs.foreground) { return; }
    const side = holdingSide(status);
    this.prefs.status = side === -1 ? '已识别左手握持' : side === 1 ? '已识别右手握持' :
      status === 3 ? '双手握持，保持当前位置' : status === 0 ? '未握持，保持当前位置' : '未识别，保持当前位置';
    if (side === 0) { this.cancelPending(); this.lastSide = 0; return; }
    // 操作期间到达的握姿不排队，避免关闭菜单/松手后抢走位置。
    if (this.pressed || this.dragging || this.open) { return; }
    if (side === this.lastSide) { return; }
    this.lastSide = side;
    this.pendingSide = side;
    this.scheduleMove();
  }

  @Monitor('open')
  menuChanged(): void {
    if (this.open) { this.cancelPending(); }
  }

  private scheduleMove(): void {
    if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
    if (this.pendingSide === 0 || !this.ready || this.pressed || this.dragging || this.open) { return; }
    this.timer = setTimeout((): void => {
      this.timer = -1;
      if (!this.alive || !this.active || !this.prefs.enabled || !this.prefs.foreground ||
        this.pressed || this.dragging || this.open) { return; }
      const b = threadActionBounds(this.viewportWidth, this.viewportHeight, this.topInset);
      const side = this.pendingSide;
      this.pendingSide = 0;
      this.getUIContext().animateTo({ curve: curves.interpolatingSpring(0, 1, 170, 17) }, (): void => {
        this.x = side === -1 ? b.minX : b.maxX;
      });
    }, 400);
  }

  private dragStart(): void {
    this.dragging = true;
    this.cancelPending();
    this.onOpenChange(false);
    this.originX = this.x;
    this.originY = this.y;
  }

  private dragUpdate(event: GestureEvent): void {
    const b = threadActionBounds(this.viewportWidth, this.viewportHeight, this.topInset);
    this.x = clampFloating(this.originX + event.offsetX, b.minX, b.maxX);
    this.y = clampFloating(this.originY + event.offsetY, b.minY, b.maxY);
  }

  private dragEnd(cancelled: boolean): void {
    this.dragging = false;
    this.pressed = false;
    this.suppressClickUntil = Date.now() + 300;
    this.cancelPending();
    this.lastSide = 0;
    if (cancelled) { this.x = this.originX; this.y = this.originY; return; }
    const b = threadActionBounds(this.viewportWidth, this.viewportHeight, this.topInset);
    const dockedX: number = dockFloatingX(this.x, b);
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, (): void => {
      this.x = dockedX;
    });
    this.prefs.setThreadPosition(positionRatio(dockedX, b.minX, b.maxX), positionRatio(this.y, b.minY, b.maxY),
      this.context()).catch((error: Error): void => {
      if (this.alive) { this.getUIContext().getPromptAction().showToast({ message: error.message }); }
    });
  }

  private fanPoint(index: number): ThreadFanPoint {
    return threadFanPoints(this.x, this.y, this.viewportWidth, this.viewportHeight, this.topInset)[index];
  }

  /** 展开层仅命中六个按钮的内侧，空隙直接交给下方帖子列表。 */
  private hitRegions(): Rectangle[] {
    const inset: number = THREAD_ACTION_HIT_INSET;
    const size: number = THREAD_ACTION_BUTTON_SIZE - 2 * inset;
    const regions: Rectangle[] = [{ x: this.x + inset, y: this.y + inset, width: size, height: size }];
    if (this.open && this.ready && this.active) {
      for (const point of threadFanPoints(this.x, this.y, this.viewportWidth, this.viewportHeight, this.topInset)) {
        regions.push({ x: point.x + inset, y: point.y + inset, width: size, height: size });
      }
    }
    return regions;
  }

  @Builder
  MainButton() {
    Stack() {
      GlassCircleButton({ symbol: $r('sys.symbol.more'), diameter: THREAD_ACTION_BUTTON_SIZE,
        iconSize: 24, slot: MaterialSlot.BOTTOM_BAR })
        .hitTestBehavior(HitTestMode.None)
    }
    .width(THREAD_ACTION_BUTTON_SIZE).height(THREAD_ACTION_BUTTON_SIZE)
    .opacity(this.ready ? 1 : 0)
    .position({ x: this.x, y: this.y })
    .responseRegion({ x: THREAD_ACTION_HIT_INSET, y: THREAD_ACTION_HIT_INSET,
      width: THREAD_ACTION_BUTTON_SIZE - 2 * THREAD_ACTION_HIT_INSET,
      height: THREAD_ACTION_BUTTON_SIZE - 2 * THREAD_ACTION_HIT_INSET })
    .hitTestBehavior(HitTestMode.Block)
    .id('thread-popup-action-button')
    .accessibilityText('帖子操作，可拖拽移动')
    .onClick((): void => {
      if (this.active && !this.dragging && Date.now() >= this.suppressClickUntil) {
        this.onOpenChange(!this.open);
      }
    })
    .onTouch((event: TouchEvent): void => {
      event.stopPropagation();
      if (event.type === TouchType.Down) { this.pressed = true; this.cancelPending(); }
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.pressed = false; }
    })
    .priorityGesture(PanGesture({ direction: PanDirection.All, distance: 8 })
      .onActionStart((): void => { this.dragStart(); })
      .onActionUpdate((event: GestureEvent): void => { this.dragUpdate(event); })
      .onActionEnd((): void => { this.dragEnd(false); })
      .onActionCancel((): void => { this.dragEnd(true); }))
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.open && this.ready && this.active) {
        ForEach([0, 1, 2, 3, 4], (index: number) => {
          Stack() { this.action(index); }
          .width(THREAD_ACTION_BUTTON_SIZE).height(THREAD_ACTION_BUTTON_SIZE)
          .position(this.fanPoint(index))
          .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({
            x: this.x - this.fanPoint(index).x, y: this.y - this.fanPoint(index).y
          })).animation({ duration: 180, curve: Curve.EaseOut }))
        }, (index: number): string => `${index}`)
      }
      this.MainButton()
    }
    .width(this.viewportWidth).height(this.viewportHeight)
    .position({ x: 0, y: 0 })
    .responseRegion(this.hitRegions())
    .hitTestBehavior(HitTestMode.Default)
  }
}
