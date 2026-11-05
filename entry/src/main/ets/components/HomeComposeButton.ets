import { MotionEffect } from '../common/appearance/MotionConfig';
import { motionDuration, motionSpringCurve } from '../common/appearance/MotionPolicy';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { GlassCircleButton } from './GlassCircleButton';
import { smartReachStore, SmartReachStore } from '../common/appearance/SmartReachStore';
import { homeComposeBounds, clampFloating, positionRatio, dockFloatingX, holdingSide, HoldingSession } from '../model/SmartReach';
import { AppTheme } from '../theme/Theme';
import { MotionHoldingSource } from '../common/appearance/MotionHoldingSource';

/** 首页发帖：自由拖动松手吸边，握姿仅换边，位置独立保存。 */
@ComponentV2
export struct HomeComposeButton {
  @Param viewportWidth: number = 0;
  @Param viewportHeight: number = 0;
  @Param topInset: number = 0;
  @Param active: boolean = true;
  @Event onCompose: () => void = (): void => {};
  @Local prefs: SmartReachStore = smartReachStore;
  @Local x: number = 16;
  @Local y: number = 16;
  @Local dragging: boolean = false;
  private pressed: boolean = false;
  @Local ready: boolean = false;
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
    const b = homeComposeBounds(this.viewportWidth, this.viewportHeight, this.topInset);
    this.x = this.prefs.homeXRatio < 0 ? b.maxX : dockFloatingX(b.minX + this.prefs.homeXRatio * (b.maxX - b.minX), b);
    this.y = this.prefs.homeYRatio < 0 ? clampFloating(this.viewportHeight - AppTheme.BAR_TOTAL_H - 68, b.minY, b.maxY) :
      b.minY + this.prefs.homeYRatio * (b.maxY - b.minY);
    this.ready = true;
    this.scheduleMove();
  }

  @Monitor('prefs.enabled', 'prefs.homeComposeEnabled', 'prefs.foreground', 'active')
  syncSubscription(): void {
    if (!this.alive) { return; }
    if ((!this.prefs.enabled || !this.prefs.homeComposeEnabled) || !this.prefs.foreground || !this.active) {
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
    if (!this.alive || !this.active || !this.prefs.foreground || (!this.prefs.enabled || !this.prefs.homeComposeEnabled)) { return; }
    const side = holdingSide(status);
    this.prefs.status = side === -1 ? '已识别左手握持' : side === 1 ? '已识别右手握持' :
      status === 3 ? '双手握持，保持当前位置' : status === 0 ? '未握持，保持当前位置' : '未识别，保持当前位置';
    if (side === 0) { this.cancelPending(); this.lastSide = 0; return; }
    if (this.pressed || this.dragging) { this.cancelPending(); return; }
    if (side === this.lastSide) { return; }
    this.lastSide = side;
    this.pendingSide = side;
    this.scheduleMove();
  }
  scheduleMove(): void {
    if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
    if (this.pendingSide === 0 || this.pressed || this.dragging || !this.ready) { return; }
    // 防抖；用户正在按压或拖拽时不改目标位置。
    this.timer = setTimeout((): void => {
      this.timer = -1;
      if (!this.alive || !this.active || (!this.prefs.enabled || !this.prefs.homeComposeEnabled) || !this.prefs.foreground ||
        this.pressed || this.dragging) { return; }
      const b = homeComposeBounds(this.viewportWidth, this.viewportHeight, this.topInset);
      const side = this.pendingSide;
      this.pendingSide = 0;
      this.getUIContext().animateTo({ duration: motionDuration(300), curve: motionSpringCurve() }, (): void => {
        this.x = side === -1 ? b.minX : b.maxX;
      });
    }, 400);
  }

  private finishMove(): void {
    this.dragging = false; this.pressed = false; this.suppressClickUntil = Date.now() + 300;
    this.cancelPending();
    const b = homeComposeBounds(this.viewportWidth, this.viewportHeight, this.topInset);
    this.getUIContext().animateTo({ duration: motionDuration(220, MotionEffect.MOVE), curve: Curve.EaseOut }, (): void => {
      this.x = dockFloatingX(this.x, b);
    });
    this.savePosition();
  }

  private savePosition(): void {
    const b = homeComposeBounds(this.viewportWidth, this.viewportHeight, this.topInset);
    this.prefs.setHomePosition(positionRatio(this.x, b.minX, b.maxX), positionRatio(this.y, b.minY, b.maxY),
      this.context()).catch((error: Error): void => {
      if (this.alive) { this.getUIContext().getPromptAction().showToast({ message: error.message }); }
    });
  }

  @Builder
  Button() {
    // 材质承载器内部手势不参与拖拽仲裁，外层统一处理点击与移动。
    Stack() {
      GlassCircleButton({ symbol: $r('sys.symbol.plus'), diameter: 52, iconSize: 26 })
        .hitTestBehavior(HitTestMode.None)
    }
      .width(52).height(52)
      .hitTestBehavior(HitTestMode.Block)
      .id('home-compose-button')
      .position({ x: this.x, y: this.y })
      .visibility(this.ready ? Visibility.Visible : Visibility.Hidden)
      .accessibilityText('发帖，可自由拖拽移动')
      .onClick((): void => {
        if (!this.dragging && Date.now() >= this.suppressClickUntil) { this.onCompose(); }
      })
      .onTouch((event: TouchEvent): void => {
        event.stopPropagation();
        if (event.type === TouchType.Down) { this.pressed = true; this.cancelPending(); }
        else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressed = false; this.scheduleMove();
        }
      })
      .priorityGesture(PanGesture({ direction: PanDirection.All, distance: 8 })
        .onActionStart((): void => {
          this.dragging = true; this.cancelPending(); this.originX = this.x; this.originY = this.y;
        })
        .onActionUpdate((event: GestureEvent): void => {
          const b = homeComposeBounds(this.viewportWidth, this.viewportHeight, this.topInset);
          this.x = clampFloating(this.originX + event.offsetX, b.minX, b.maxX);
          this.y = clampFloating(this.originY + event.offsetY, b.minY, b.maxY);
        })
        .onActionEnd((): void => {
          this.finishMove();
        })
        .onActionCancel((): void => {
          this.dragging = false; this.pressed = false; this.suppressClickUntil = Date.now() + 300;
          this.x = this.originX; this.y = this.originY; this.scheduleMove();
        }))
  }

  build() {
    this.Button()
  }
}
