import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { motion } from '@kit.MultimodalAwarenessKit';
import { curves } from '@kit.ArkUI';
import { GlassCircleButton } from './GlassCircleButton';
import { smartReachStore, SmartReachStore } from '../common/appearance/SmartReachStore';
import { floatingBounds, clampFloating, positionRatio, dockFloatingX, holdingSide, HoldingSession, HoldingSource } from '../model/SmartReach';

class MotionHoldingSource implements HoldingSource {
  on(callback: (status: number) => void): void { motion.on('holdingHandChanged', callback); }
  off(callback: (status: number) => void): void { motion.off('holdingHandChanged', callback); }
}

/** 页面尺寸坐标系内的48vp按钮；握姿只换边，拖拽松手吸附最近侧边，保留高度。 */
@ComponentV2
export struct ForumRefreshButton {
  @Param viewportWidth: number = 0;
  @Param viewportHeight: number = 0;
  @Param topInset: number = 0;
  @Param active: boolean = true;
  @Param busy: boolean = false;
  @Event onRefresh: () => void = (): void => {};
  @Local prefs: SmartReachStore = smartReachStore;
  @Local x: number = 16;
  @Local y: number = 16;
  @Local left: boolean = false;
  @Local dragging: boolean = false;
  private pressed: boolean = false;
  private ready: boolean = false;
  private alive: boolean = false;
  private originX: number = 0;
  private originY: number = 0;
  private lastSide: number = 0;
  private pendingSide: number = 0;
  private timer: number = -1;
  private suppressClickUntil: number = 0;
  private session: HoldingSession = new HoldingSession(new MotionHoldingSource(), (status: number): void => {
    this.onHolding(status);
  });

  aboutToAppear(): void {
    this.alive = true;
    this.prefs.load(this.context());
    this.restorePosition();
    this.syncSubscription();
  }
  aboutToDisappear(): void { this.alive = false; this.cancelPending(); this.stop(); }
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }

  @Monitor('viewportWidth', 'viewportHeight', 'topInset')
  restorePosition(): void {
    if (this.viewportWidth <= 0 || this.viewportHeight <= 0) { return; }
    const b = floatingBounds(this.viewportWidth, this.viewportHeight, this.topInset);
    this.x = this.prefs.xRatio < 0 ? b.maxX : dockFloatingX(b.minX + this.prefs.xRatio * (b.maxX - b.minX), b);
    this.y = this.prefs.yRatio < 0 ? clampFloating(this.viewportHeight - 128, b.minY, b.maxY) :
      b.minY + this.prefs.yRatio * (b.maxY - b.minY);
    this.left = this.x < this.viewportWidth / 2;
    this.ready = true;
    this.scheduleMove();
  }

  @Monitor('prefs.enabled', 'prefs.foreground', 'active')
  syncSubscription(): void {
    if (!this.alive) { return; }
    if (!this.prefs.enabled || !this.prefs.foreground || !this.active) {
      this.cancelPending(); this.stop(); return;
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
    if (!this.alive || !this.active || !this.prefs.foreground || !this.prefs.enabled) { return; }
    const side = holdingSide(status);
    this.prefs.status = side === -1 ? '已识别左手握持' : side === 1 ? '已识别右手握持' :
      status === 3 ? '双手握持，保持当前位置' : status === 0 ? '未握持，保持当前位置' : '未识别，保持当前位置';
    if (side === 0) { this.cancelPending(); this.lastSide = 0; return; }
    if (side === this.lastSide) { return; }
    this.lastSide = side;
    this.pendingSide = side;
    this.scheduleMove();
  }
  @Monitor('busy')
  scheduleMove(): void {
    if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
    if (this.pendingSide === 0 || this.pressed || this.dragging || this.busy || !this.ready) { return; }
    // 防抖；用户正在按压/拖拽/刷新时不改目标位置。
    this.timer = setTimeout((): void => {
      this.timer = -1;
      if (!this.alive || !this.active || !this.prefs.enabled || !this.prefs.foreground ||
        this.pressed || this.dragging || this.busy) { return; }
      const b = floatingBounds(this.viewportWidth, this.viewportHeight, this.topInset);
      const side = this.pendingSide;
      this.pendingSide = 0;
      this.getUIContext().animateTo({ curve: curves.interpolatingSpring(0, 1, 170, 17) }, (): void => {
        this.left = side === -1;
        this.x = this.left ? b.minX : b.maxX;
      });
    }, 400);
  }

  private savePosition(): void {
    const b = floatingBounds(this.viewportWidth, this.viewportHeight, this.topInset);
    this.prefs.setPosition(positionRatio(this.x, b.minX, b.maxX), positionRatio(this.y, b.minY, b.maxY),
      this.context()).catch((error: Error): void => {
      if (this.alive) { this.getUIContext().getPromptAction().showToast({ message: error.message }); }
    });
  }

  @Builder
  Button(left: boolean) {
    // HdsTabs 内部手势不参与拖拽仲裁，外层统一处理点击与移动。
    Stack() {
      GlassCircleButton({ symbol: $r('sys.symbol.arrow_clockwise'), diameter: 48, iconSize: 24 })
        .hitTestBehavior(HitTestMode.None)
    }
      .width(48).height(48)
      .hitTestBehavior(HitTestMode.Block)
      .id('forumRefreshButton')
      .position({ x: this.x, y: this.y })
      .opacity(this.busy ? 0.6 : 1)
      .accessibilityText('刷新当前分类，可拖拽移动')
      .onClick((): void => {
        if (!this.dragging && Date.now() >= this.suppressClickUntil && !this.busy) { this.onRefresh(); }
      })
      .transition(TransitionEffect.translate({ x: left ? -80 : 80 }).animation({ curve: curves.interpolatingSpring(0, 1, 170, 17) }))
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Down) { this.pressed = true; }
        else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressed = false; this.scheduleMove();
        }
      })
      .priorityGesture(PanGesture({ direction: PanDirection.All, distance: 8 })
        .onActionStart((): void => {
          this.dragging = true; this.cancelPending(); this.originX = this.x; this.originY = this.y;
        })
        .onActionUpdate((event: GestureEvent): void => {
          const b = floatingBounds(this.viewportWidth, this.viewportHeight, this.topInset);
          this.x = clampFloating(this.originX + event.offsetX, b.minX, b.maxX);
          this.y = clampFloating(this.originY + event.offsetY, b.minY, b.maxY);
        })
        .onActionEnd((): void => {
          this.dragging = false; this.pressed = false; this.suppressClickUntil = Date.now() + 300;
          // 拖拽期间收到的握姿不能在松手后把用户刚选的位置抢走。
          this.cancelPending();
          const b = floatingBounds(this.viewportWidth, this.viewportHeight, this.topInset);
          this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, (): void => {
            this.x = dockFloatingX(this.x, b);
          });
          this.savePosition();
        })
        .onActionCancel((): void => {
          this.dragging = false; this.pressed = false; this.suppressClickUntil = Date.now() + 300;
          this.x = this.originX; this.y = this.originY; this.scheduleMove();
        }))
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.left) { this.Button(true); } else { this.Button(false); }
    }
    .width('100%').height('100%').hitTestBehavior(HitTestMode.Transparent)
  }
}
