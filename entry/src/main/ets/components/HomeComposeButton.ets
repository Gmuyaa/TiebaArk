import { MotionEffect } from '../common/appearance/MotionConfig';
import { motionDuration, motionSpringCurve } from '../common/appearance/MotionPolicy';
import { motionStore } from '../common/appearance/MotionStore';
import { common } from '@kit.AbilityKit';
import { curves } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { GlassCircleButton } from './GlassCircleButton';
import { smartReachStore, SmartReachStore } from '../common/appearance/SmartReachStore';
import {
  homeComposeBounds, clampFloating, positionRatio, dockFloatingX, holdingSide, HoldingSession, floatingButtonHitRegion,
  HOME_COMPOSE_BUTTON_SIZE
} from '../model/SmartReach';
import { AppTheme } from '../theme/Theme';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { MotionHoldingSource } from '../common/appearance/MotionHoldingSource';

/** 发帖面直径（vp），与 SmartReach 的触控区、边界共用同一口径。 */
const COMPOSE_FACE: number = HOME_COMPOSE_BUTTON_SIZE;
/**
 * 按压点光源强度。0 = 不发光。
 * `intensity` 的取值口径三处打架：API 参考"建议 0~1"、官方指南正文示例 10、另一份文档 0-5。
 * 按 API 参考区间定 0.8，再亮就过曝。
 */
const LIGHT_INTENSITY: number = 0.8;

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
  /** 按压时点光源强度：0 = 不发光。按钮是**光源**，被照亮的是周围挂了 illuminatedType 的卡片。 */
  @Local pressLightOn: number = 0;
  /**
   * 按压缩放。独立悬浮按钮不在标题栏/底部 TabBar 槽位，材质的 `interactive` 在此不生效
   * （官方生效区域限制），按官方建议自行用 scale + 弹簧曲线模拟。
   */
  @Local pressScale: number = 1;
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
        // 握姿换边也是实际位置：不落盘的话，切页重建会先回默认右侧再等下一次握姿事件。
        this.savePosition();
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
    // 整个材质子树退出命中测试，触控区外的手势交给底下的列表。
    Stack() {
      // 光源就挂在材质圆面本体上（酷安同款做法）；本轮试验"照亮周围"，具体受光在帖子卡片上，
      // 由 `ThreadPreviewCard.litType` 控制，本组件不再自照边缘。
      // 圆面是固定的不透明强调色（深浅同色），图标必须固定白色；跟随 TEXT_MAIN 会在浅色下变黑。
      // `hitRegion: 32` 保留：材质形变要求触摸真正落到持有材质的 Button 上（2026-11-09 已实测的修法），
      // 32 与 `floatingButtonHitRegion` 的外层热区同一口径。
      GlassCircleButton({ symbol: $r('sys.symbol.plus'), diameter: COMPOSE_FACE, iconSize: 24,
        slot: MaterialSlot.COMPOSE_BUTTON, hitRegion: 32, composePressLight: this.pressLightOn * LIGHT_INTENSITY,
        iconColor: Color.White,
        onTap: (): void => {
          if (!this.dragging && Date.now() >= this.suppressClickUntil) { this.onCompose(); }
        } })
    }
      .width(COMPOSE_FACE).height(COMPOSE_FACE)
      .responseRegion(floatingButtonHitRegion(COMPOSE_FACE))
      .id('home-compose-button')
      .position({ x: this.x, y: this.y })
      .visibility(this.ready ? Visibility.Visible : Visibility.Hidden)
      .hitTestBehavior(this.active ? HitTestMode.Default : HitTestMode.BLOCK_DESCENDANTS)
      .accessibilityLevel(this.active ? 'auto' : 'no-hide-descendants')
      .accessibilityText('发帖，可自由拖拽移动')
      .onTouch((event: TouchEvent): void => {
        // 材质 interactive 在悬浮按钮上不生效（官方生效区域限制），形变由 scale + 弹簧曲线自行模拟。
        if (event.type === TouchType.Down) {
          this.pressed = true; this.cancelPending();
          if (motionStore.isOn(MotionEffect.HDS_POINT_LIGHT)) { this.pressLightOn = 1; }
          this.getUIContext().animateTo({ curve: curves.springMotion(0.15, 0.86) }, (): void => {
            this.pressScale = 0.9;
          });
        }
        else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressed = false; this.pressLightOn = 0; this.scheduleMove();
          // 欠阻尼回弹，带轻微过冲；Up 与 Cancel 都要恢复，避免中断后停在缩小态。
          this.getUIContext().animateTo({ curve: curves.springMotion(0.55, 0.825) }, (): void => {
            this.pressScale = 1;
          });
        }
      })
      .scale({ x: this.pressScale, y: this.pressScale })
      .animation({ duration: motionDuration(300), curve: motionSpringCurve() })
      // ⚠️ 用普通 gesture 而不是 priorityGesture：优先手势一识别就把触摸从持有材质的 Button
      // 手里拿走了，`interactive` 形变随之中断（2026-11-10 实测仍未见形变，保留此写法以备后查）。
      // 距离阈值 8vp 仍能区分"按下拖走"与"原地点击"，拖拽实测正常。
      .gesture(PanGesture({ direction: PanDirection.All, distance: 8 })
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
