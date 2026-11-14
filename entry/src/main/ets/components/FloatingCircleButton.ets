import { MotionEffect } from '../common/appearance/MotionConfig';
import { motionDuration, motionSpringCurve, motionTransition } from '../common/appearance/MotionPolicy';
import { motionStore } from '../common/appearance/MotionStore';
import { common } from '@kit.AbilityKit';
import { curves } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { GlassCircleButton } from './GlassCircleButton';
import { smartReachStore, SmartReachStore } from '../common/appearance/SmartReachStore';
import {
  buttonDockBounds, clampFloating, positionRatio, dockFloatingX, holdingSide, HoldingSession,
  floatingButtonHitRegion, FloatingBounds, FloatingButtonKind
} from '../model/SmartReach';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { MotionHoldingSource } from '../common/appearance/MotionHoldingSource';

/**
 * 按压点光源强度。0 = 不发光。
 * `intensity` 的取值口径三处打架：API 参考"建议 0~1"、官方指南正文示例 10、另一份文档 0-5。
 * 按 API 参考区间定 0.8，再亮就过曝。
 */
const LIGHT_INTENSITY: number = 0.8;
/**
 * 握姿换边的防抖延迟（ms）：识别到换手后等这么久再开始移动。
 * 原为 400，持有者反馈响应偏慢；`onHolding` 已对同侧重复事件去重，这里只需压住短时来回。
 */
const HOLDING_SWITCH_DELAY_MS: number = 200;
/** 侧滑出屏的位移（vp）：按钮 48 + 边距 20 = 68，80 足够完全出屏。 */
const SLIDE_OUT_DISTANCE: number = 80;

/**
 * 悬浮圆按钮公共实现。
 *
 * 承载首页发帖按钮与吧页刷新按钮的全部共有能力：智感握姿订阅、防抖、停靠吸附、
 * 绕屏换边、自由拖拽、边缘入场、触控区与按压缩放。差异只有两类，都从这里分发：
 *
 * - 停靠范围与记忆字段 → `kind` 查 `buttonDockBounds` / 下面两个读写函数；
 * - 能力差异（是否避让障碍、是否上报位置、是否 busy 锁）→ 参数，值为 0 / 空回调即关闭。
 *
 * 新增 ArkUI 特性时改这里，不要再往两个使用方各写一份。
 */
@ComponentV2
export struct FloatingCircleButton {
  /** 按钮种类：决定停靠范围与记忆字段。 */
  @Param kind: FloatingButtonKind = FloatingButtonKind.HOME_COMPOSE;
  @Param viewportWidth: number = 0;
  @Param viewportHeight: number = 0;
  @Param topInset: number = 0;
  @Param active: boolean = true;
  /** 刷新中的锁：不响应点击、不参与换边。发帖按钮保持默认 false。 */
  @Param busy: boolean = false;
  /** 外观 */
  @Param symbol: Resource = $r('sys.symbol.plus');
  @Param diameter: number = 48;
  @Param iconSize: number = 24;
  @Param slot: MaterialSlot = MaterialSlot.COMPOSE_BUTTON;
  /** 无障碍标签。不能叫 `accessibilityText`：与 `CustomComponent` 基类同名属性冲突。 */
  @Param label: string = '';
  /** 无记忆位置时，纵向默认落在距底部多少 vp 处。 */
  @Param fallbackYFromBottom: number = 128;
  /** 需要避让的障碍（如吧页悬浮分类胶囊）；宽高为 0 表示不避让。 */
  @Param obstacleX: number = 0;
  @Param obstacleY: number = 0;
  @Param obstacleWidth: number = 0;
  @Param obstacleHeight: number = 0;
  @Event onTap: () => void = (): void => {};
  @Event onMoveStart: () => void = (): void => {};
  @Event onPositionChanged: (x: number, y: number) => void = (): void => {};

  @Local prefs: SmartReachStore = smartReachStore;
  @Local x: number = 16;
  @Local y: number = 16;
  /** 当前停靠侧：决定入场动画从屏幕哪一侧平移进来。 */
  @Local left: boolean = false;
  /**
   * 握姿换边的横向位移（vp）。换边按"沿当前侧滑出屏幕 → 对侧屏外就位 → 滑入"三段走，
   * 单靠改动 `x` 会横穿内容区（2026-11-10 持有者反馈）。
   */
  @Local slideOffset: number = 0;
  @Local dragging: boolean = false;
  /** 按下态要驱动点光源，必须是可观察状态；普通字段不会触发重新渲染，光源永远拿不到强度。 */
  @Local pressed: boolean = false;
  /** 按压缩放：悬浮按钮不在标题栏/底部 TabBar，材质 interactive 不生效，按官方建议用 scale 自绘。 */
  @Local pressScale: number = 1;
  @Local ready: boolean = false;
  private alive: boolean = false;
  private originX: number = 0;
  private originY: number = 0;
  private lastSide: number = 0;
  private pendingSide: number = 0;
  private timer: number = -1;
  private slideTimer: number = -1;
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

  aboutToDisappear(): void {
    this.alive = false;
    this.cancelPending();
    if (this.slideTimer >= 0) { clearTimeout(this.slideTimer); this.slideTimer = -1; }
    this.stop();
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private bounds(): FloatingBounds {
    return buttonDockBounds(this.kind, this.viewportWidth, this.viewportHeight, this.topInset);
  }

  /** 记忆的横向比例；负值表示还没落过盘。 */
  private storedXRatio(): number {
    return this.kind === FloatingButtonKind.HOME_COMPOSE ? this.prefs.homeXRatio : this.prefs.xRatio;
  }

  private storedYRatio(): number {
    return this.kind === FloatingButtonKind.HOME_COMPOSE ? this.prefs.homeYRatio : this.prefs.yRatio;
  }

  /** 该按钮是否被用户启用（首页发帖有独立开关，共享总开关）。 */
  private enabledByUser(): boolean {
    if (!this.prefs.enabled) { return false; }
    return this.kind === FloatingButtonKind.HOME_COMPOSE ? this.prefs.homeComposeEnabled : true;
  }

  @Monitor('viewportWidth', 'viewportHeight', 'topInset')
  restorePosition(): void {
    if (this.viewportWidth <= 0 || this.viewportHeight <= 0) { return; }
    const b: FloatingBounds = this.bounds();
    const xr: number = this.storedXRatio();
    const yr: number = this.storedYRatio();
    this.x = xr < 0 ? b.maxX : dockFloatingX(b.minX + xr * (b.maxX - b.minX), b);
    this.y = yr < 0 ? clampFloating(this.viewportHeight - this.fallbackYFromBottom, b.minY, b.maxY) :
      b.minY + yr * (b.maxY - b.minY);
    this.left = this.x < this.viewportWidth / 2;
    this.ready = true;
    this.scheduleMove();
  }

  @Monitor('prefs.enabled', 'prefs.homeComposeEnabled', 'prefs.foreground', 'active')
  syncSubscription(): void {
    if (!this.alive) { return; }
    if (!this.enabledByUser() || !this.prefs.foreground || !this.active) {
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
    if (!this.alive || !this.active || !this.prefs.foreground || !this.enabledByUser()) { return; }
    const side: number = holdingSide(status);
    this.prefs.status = side === -1 ? '已识别左手握持' : side === 1 ? '已识别右手握持' :
      status === 3 ? '双手握持，保持当前位置' : status === 0 ? '未握持，保持当前位置' : '未识别，保持当前位置';
    if (side === 0) { this.cancelPending(); this.lastSide = 0; return; }
    if (this.pressed || this.dragging) { this.cancelPending(); return; }
    if (side === this.lastSide) { return; }
    this.lastSide = side;
    this.pendingSide = side;
    this.scheduleMove();
  }

  @Monitor('busy')
  scheduleMove(): void {
    if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
    if (this.pendingSide === 0 || this.pressed || this.dragging || this.busy || !this.ready) { return; }
    this.timer = setTimeout((): void => {
      this.timer = -1;
      if (!this.alive || !this.active || !this.enabledByUser() || !this.prefs.foreground ||
        this.pressed || this.dragging || this.busy) { return; }
      const side: number = this.pendingSide;
      this.pendingSide = 0;
      this.swapSide(side === -1, this.bounds());
    }, HOLDING_SWITCH_DELAY_MS);
  }

  /**
   * 握姿换边：先沿当前所在一侧滑出屏幕，再在对侧屏外就位、滑入。
   *
   * 官方「侧边按钮悬浮导航」示例是用 `if/else` 渲染左右两个节点，各自挂反方向的
   * `TransitionEffect.move`，由框架同步进出场。本项目只有一个节点（要支持自由拖拽），
   * 因此用 `translate` 拆成三段近似同一观感，不引入第二套定位状态机。
   *
   * 拖拽吸附不走这里：那是短距离补间，`finishMove` 的 `dockFloatingX` 保持原样。
   */
  private swapSide(toLeft: boolean, b: FloatingBounds): void {
    if (this.slideTimer >= 0) { clearTimeout(this.slideTimer); this.slideTimer = -1; }
    const target: number = toLeft ? b.minX : b.maxX;
    // 已在这一侧时只做位置落定，不播完整的出入场。
    if (this.left === toLeft && Math.abs(this.x - target) < 0.5) { return; }
    // 过渡期间不接受点击：按钮在半屏外时被点到会误触发业务动作。
    this.suppressClickUntil = Date.now() + 700;
    const out: number = this.left ? -SLIDE_OUT_DISTANCE : SLIDE_OUT_DISTANCE;
    let jumped: boolean = false;
    /*
     * 跳位必须等滑出动画**真正结束**再做。在动画进行中直接改 `slideOffset` 的反向值，
     * ArkUI 会把它当成"改动画目标"继续补间，表现成按钮从屏幕上横穿过去
     * （2026-11-10 持有者反馈）。用 `onFinish` 拿准结束点，另留一个兜底定时器。
     */
    const jump = (): void => {
      if (jumped || !this.alive) { return; }
      jumped = true;
      if (this.slideTimer >= 0) { clearTimeout(this.slideTimer); this.slideTimer = -1; }
      // 跳位：位置直接换到对侧屏外，再从这里滑入，中间不经过内容区。
      this.slideOffset = -out;
      this.x = target;
      this.left = toLeft;
      this.avoidObstacle();
      // 握姿换边也是实际位置：不落盘的话，切页重建会先回默认侧再等下一次握姿事件。
      this.savePosition();
      // 下一帧再启动滑入，保证 `-out` 是起点而不是新的动画目标。
      this.slideTimer = setTimeout((): void => {
        this.slideTimer = -1;
        if (!this.alive) { return; }
        this.getUIContext().animateTo({ duration: motionDuration(240), curve: motionSpringCurve() }, (): void => {
          this.slideOffset = 0;
        });
      }, 16);
    };
    // 完成回调走 `AnimateParam.onFinish`（本 SDK 的 `animateTo` 只有两个入参）。
    this.getUIContext().animateTo({ duration: motionDuration(150), curve: Curve.EaseIn, onFinish: jump }, (): void => {
      this.slideOffset = out;
    });
    // 兜底：动效被系统压制等情况下 `onFinish` 可能不回调，别让按钮卡在屏外。
    this.slideTimer = setTimeout(jump, 260);
  }

  @Monitor('x', 'y')
  reportPosition(): void {
    if (this.ready && this.alive) { this.onPositionChanged(this.x, this.y); }
  }

  /** 与障碍（如吧页悬浮分类胶囊）重叠时挪到最近的不重叠位置；障碍宽高为 0 时直接返回。 */
  private avoidObstacle(): void {
    if (this.obstacleWidth <= 0 || this.obstacleHeight <= 0) { return; }
    const gap: number = 8;
    const size: number = this.diameter;
    if (this.x >= this.obstacleX + this.obstacleWidth + gap || this.x + size + gap <= this.obstacleX ||
      this.y >= this.obstacleY + this.obstacleHeight + gap || this.y + size + gap <= this.obstacleY) { return; }
    const b: FloatingBounds = this.bounds();
    const xs: number[] = [this.obstacleX - size - gap, this.obstacleX + this.obstacleWidth + gap, this.x, this.x];
    const ys: number[] = [this.y, this.y, this.obstacleY - size - gap, this.obstacleY + this.obstacleHeight + gap];
    let bestX: number = this.x;
    let bestY: number = this.y;
    let distance: number = Number.MAX_VALUE;
    for (let index: number = 0; index < xs.length; index++) {
      if (xs[index] < b.minX || xs[index] > b.maxX || ys[index] < b.minY || ys[index] > b.maxY) { continue; }
      const nextDistance: number = Math.pow(xs[index] - this.x, 2) + Math.pow(ys[index] - this.y, 2);
      if (nextDistance < distance) { distance = nextDistance; bestX = xs[index]; bestY = ys[index]; }
    }
    this.x = bestX; this.y = bestY;
  }

  private finishMove(): void {
    this.dragging = false; this.pressed = false; this.suppressClickUntil = Date.now() + 300;
    this.cancelPending();
    const b: FloatingBounds = this.bounds();
    this.getUIContext().animateTo({ duration: motionDuration(220, MotionEffect.MOVE), curve: Curve.EaseOut }, (): void => {
      this.x = dockFloatingX(this.x, b);
      this.avoidObstacle();
    });
    this.left = this.x < this.viewportWidth / 2;
    this.savePosition();
  }

  private savePosition(): void {
    const b: FloatingBounds = this.bounds();
    const xr: number = positionRatio(this.x, b.minX, b.maxX);
    const yr: number = positionRatio(this.y, b.minY, b.maxY);
    const persist: Promise<void> = this.kind === FloatingButtonKind.HOME_COMPOSE
      ? this.prefs.setHomePosition(xr, yr, this.context())
      : this.prefs.setPosition(xr, yr, this.context());
    persist.catch((error: Error): void => {
      if (this.alive) { this.getUIContext().getPromptAction().showToast({ message: error.message }); }
    });
  }

  @Builder
  Button() {
    // 整个材质子树退出命中测试，触控区外的手势交给底下的列表。
    Stack() {
      // 材质形变要求触摸真正落到持有材质的 Button 上（2026-11-09 实测的修法），
      // 所以 `hitRegion` 必须与 `floatingButtonHitRegion` 同口径：
      // 内层比外层小会出现"拖得到、按不出反馈"的夹心区。40 是 2026-11-10 从 32 提上来的。
      GlassCircleButton({ symbol: this.symbol, diameter: this.diameter, iconSize: this.iconSize,
        slot: this.slot, iconColor: Color.White, hitRegion: Math.min(this.diameter, 40),
        composePressLight: this.pressed && motionStore.isOn(MotionEffect.HDS_POINT_LIGHT) ? LIGHT_INTENSITY : 0,
        onTap: (): void => {
          if (!this.dragging && Date.now() >= this.suppressClickUntil && !this.busy) { this.onTap(); }
        } })
    }
      .width(this.diameter).height(this.diameter)
      .responseRegion(floatingButtonHitRegion(this.diameter))
      .id(this.nodeId())
      .position({ x: this.x, y: this.y })
      // 握姿换边的"出屏 → 跳位 → 入屏"位移；静止与拖拽期间恒为 0。
      .translate({ x: this.slideOffset, y: 0 })
      // 入场从停靠侧边缘平移进来。不能改回 `.animation()` 隐式动画：它会把初始 (16,16)
      // 到记忆位置的跳变也做成动画，表现为"按钮从屏幕左上角飞过来"（2026-11-10 持有者反馈）。
      .transition(motionTransition(TransitionEffect.translate({ x: this.left ? -SLIDE_OUT_DISTANCE : SLIDE_OUT_DISTANCE }),
        MotionEffect.MOVE).animation({ duration: motionDuration(300), curve: motionSpringCurve() }))
      .hitTestBehavior(this.active ? HitTestMode.Default : HitTestMode.BLOCK_DESCENDANTS)
      .accessibilityLevel(this.active ? 'auto' : 'no-hide-descendants')
      .accessibilityText(this.label)
      .onTouch((event: TouchEvent): void => {
        // 材质 interactive 在悬浮按钮上不生效（官方生效区域限制），形变由 scale + 弹簧曲线自行模拟。
        if (event.type === TouchType.Down) {
          this.pressed = true; this.cancelPending();
          this.getUIContext().animateTo({ curve: curves.springMotion(0.15, 0.86) }, (): void => {
            this.pressScale = 0.9;
          });
        }
        else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressed = false; this.scheduleMove();
          // 欠阻尼回弹，带轻微过冲；Up 与 Cancel 都要恢复，避免中断后停在缩小态。
          this.getUIContext().animateTo({ curve: curves.springMotion(0.55, 0.825) }, (): void => {
            this.pressScale = 1;
          });
        }
      })
      .scale({ x: this.pressScale, y: this.pressScale })
      // ⚠️ 用普通 gesture 而不是 priorityGesture：优先手势一识别就把触摸从持有材质的 Button
      // 手里拿走了，`interactive` 形变随之中断（2026-11-10 实测仍未见形变，保留此写法以备后查）。
      // 距离阈值 8vp 仍能区分"按下拖走"与"原地点击"，拖拽实测正常。
      .gesture(PanGesture({ direction: PanDirection.All, distance: 8 })
        .onActionStart((): void => {
          this.dragging = true; this.cancelPending(); this.originX = this.x; this.originY = this.y;
          this.onMoveStart();
        })
        .onActionUpdate((event: GestureEvent): void => {
          const b: FloatingBounds = this.bounds();
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

  /** 保留原有 id，便于真机 dump 与既有排查脚本按 id 定位。 */
  private nodeId(): string {
    return this.kind === FloatingButtonKind.HOME_COMPOSE ? 'home-compose-button' : 'forumRefreshButton';
  }

  build() {
    // 用 `if` 而不是 `visibility`：transition 只在组件出现/消失时播放，visibility 切换不触发。
    // `ready` 之前不渲染，避免在初始 (16,16) 处闪一下。
    if (this.ready) {
      this.Button()
    }
  }
}
