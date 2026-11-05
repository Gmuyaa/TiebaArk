import { MotionEffect } from '../common/appearance/MotionConfig';
import { motionDuration } from '../common/appearance/MotionPolicy';
import { motionStore } from '../common/appearance/MotionStore';
import { MaterialTabs } from './MaterialTabs';
import { common } from '@kit.AbilityKit';
import { ForumTab } from '../model/ThreadList';
import { AppTheme } from '../theme/Theme';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { smartReachStore, SmartReachStore } from '../common/appearance/SmartReachStore';
import { clampFloating, dockFloatingX, floatingBounds, holdingSide, HoldingSession } from '../model/SmartReach';
import { MotionHoldingSource } from '../common/appearance/MotionHoldingSource';

interface ForumTabsPoint { x: number; y: number; }

/** 分类浮层：视觉玻璃不参与触摸，横滑分类与长按移动各自仲裁。 */
@ComponentV2
export struct FloatingForumTabs {
  @Param tabs: ForumTab[] = [];
  @Param selectedId: number = 0;
  @Param viewportWidth: number = 0;
  @Param viewportHeight: number = 0;
  @Param sideInset: number = 8;
  @Param topInset: number = 0;
  @Param initialY: number = 0;
  @Param scrollRevision: number = 0;
  @Param atTop: boolean = true;
  @Param busy: boolean = false;
  /** busy仅暂停自动移动；分类/分页读取中仍可重新选择目标。 */
  @Param selectionEnabled: boolean = true;
  @Param active: boolean = true;
  @Param refreshOwnsCollision: boolean = false;
  @Param refreshX: number = -1;
  @Param refreshY: number = -1;
  @Event onMoveStart: () => void = (): void => {};
  @Event onBoundsChanged: (x: number, y: number, width: number, height: number) => void = (): void => {};
  @Event onSelect: (tab: ForumTab, index: number) => void = (): void => {};
  @Local expanded: boolean = true;
  @Local x: number = 12;
  @Local y: number = 120;
  @Local dragging: boolean = false;
  @Local prefs: SmartReachStore = smartReachStore;
  private ready: boolean = false;
  private alive: boolean = true;
  private moved: boolean = false;
  private anchorX: number = 12;
  private anchorY: number = 120;
  private dockRight: boolean = false;
  private originX: number = 0;
  private originY: number = 0;
  private suppressClickUntil: number = 0;
  private dragArmed: boolean = false;
  private panOffset: number = 0;
  private scrollingTabs: boolean = false;
  @Local tabWidths: Map<number, number> = new Map<number, number>();
  @Local scrollOffset: number = 0;
  @Local pageStart: number = 0;
  private revealRevision: number = 0;
  @Local selectionX: number = 4;
  @Local selectionW: number = 0;
  @Local selectionScaleY: number = 1;
  @Local selectionRestBlend: number = 1;
  private selectionId: number = -1;
  private selectionRevision: number = 0;
  private selectionFlowing: boolean = false;
  private scroller: Scroller = new Scroller();
  private holdingTimer: number = -1;
  private holdingSideValue: number = 0;
  private pendingHoldingSide: number = 0;
  private pressed: boolean = false;
  private holdingSession: HoldingSession = new HoldingSession(new MotionHoldingSource(), (status: number): void => {
    this.onHolding(status);
  });

  aboutToAppear(): void {
    this.alive = true;
    this.prefs.load(this.getUIContext().getHostContext() as common.UIAbilityContext);
    this.syncBounds(); this.revealSelected(); this.syncHolding();
  }
  aboutToDisappear(): void { ++this.selectionRevision; this.selectionFlowing = false; this.alive = false; this.cancelHolding(); this.stopHolding(); }
  private cancelHolding(): void {
    if (this.holdingTimer >= 0) { clearTimeout(this.holdingTimer); this.holdingTimer = -1; }
    this.pendingHoldingSide = 0;
  }
  private stopHolding(): void {
    this.holdingSideValue = 0;
    try { this.holdingSession.stop(); }
    catch (_) { this.prefs.status = '分类握姿监听停止失败，已暂停自动移动'; }
  }
  @Monitor('prefs.enabled', 'prefs.forumTabsEnabled', 'prefs.foreground', 'active')
  syncHolding(): void {
    if (!this.alive) { return; }
    if (!this.prefs.enabled || !this.prefs.forumTabsEnabled || !this.prefs.foreground || !this.active) {
      this.cancelHolding(); this.stopHolding(); return;
    }
    if (!canIUse('SystemCapability.MultimodalAwareness.Motion')) {
      this.prefs.status = '当前设备不支持智感握姿，可手动拖拽'; return;
    }
    try { this.holdingSession.start(); }
    catch (_) { this.prefs.status = '分类握姿暂不可用，可手动拖拽'; }
  }
  private onHolding(status: number): void {
    if (!this.alive || !this.active || !this.prefs.foreground || !this.prefs.enabled || !this.prefs.forumTabsEnabled) { return; }
    const side: number = holdingSide(status);
    if (side === 0) { this.cancelHolding(); this.holdingSideValue = 0; return; }
    if (side === this.holdingSideValue) { return; }
    this.holdingSideValue = side;
    this.pendingHoldingSide = side;
    this.scheduleHolding();
  }
  @Monitor('busy')
  scheduleHolding(): void {
    if (this.holdingTimer >= 0) { clearTimeout(this.holdingTimer); this.holdingTimer = -1; }
    if (!this.ready || this.pendingHoldingSide === 0 || this.pressed || this.dragging || this.busy) { return; }
    // 稍晚于刷新按钮换边，避免同一握姿事件让两块玻璃同时抢占落点。
    this.holdingTimer = setTimeout((): void => {
      this.holdingTimer = -1;
      if (!this.alive || !this.active || !this.prefs.enabled || !this.prefs.forumTabsEnabled ||
        !this.prefs.foreground || this.pressed || this.dragging || this.busy) { return; }
      const side: number = this.pendingHoldingSide;
      this.pendingHoldingSide = 0;
      if (side === 0) { return; }
      this.onMoveStart();
      this.getUIContext().animateTo({ duration: motionDuration(220, MotionEffect.MOVE), curve: Curve.EaseOut }, (): void => {
        this.moved = true; this.dockRight = side === 1;
        this.anchorX = this.dockRight ? this.maxX() : this.minX();
        this.avoidRefresh();
      });
    }, 650);
  }
  private label(): string { return this.tabs.find((tab: ForumTab) => tab.id === this.selectedId)?.name ?? '分类'; }
  private compactWidth(): number { return Math.min(152, Math.max(64, this.label().length * 15 + 28)); }
  private controlWidth(): number {
    return this.expanded ? this.pageWidth() :
      this.compactWidth();
  }
  private minX(): number { return this.expanded ? this.sideInset : 12; }
  private maxX(): number { return Math.max(this.minX(), this.viewportWidth - this.controlWidth() - this.minX()); }
  private displayX(): number { return clampFloating(this.x, this.minX(), this.maxX()); }
  private maxY(): number { return Math.max(this.topInset + 8, this.viewportHeight - AppTheme.BAR_CONTENT_H - 12); }
  private tabWidth(tab: ForumTab): number { return this.tabWidths.get(tab.id) ?? (tab.name.length * 14 + 24); }
  private tabStart(id: number): number {
    let start: number = 4;
    for (const tab of this.tabs) {
      if (tab.id === id) { return start; }
      start += this.tabWidth(tab) + 4;
    }
    return start;
  }
  private contentWidth(): number {
    return 8 + this.tabs.reduce((total: number, tab: ForumTab): number => total + this.tabWidth(tab), 0) +
      Math.max(0, this.tabs.length - 1) * 4;
  }
  private pageEndFrom(start: number): number {
    const limit: number = Math.max(84, this.viewportWidth - this.sideInset * 2);
    let width: number = 8 + (start > 0 ? 32 : 0);
    let end: number = start;
    for (let index: number = start; index < this.tabs.length; index++) {
      const next: number = width + this.tabWidth(this.tabs[index]) + (index > start ? 4 : 0);
      if (index > start && next + (index < this.tabs.length - 1 ? 32 : 0) > limit) { break; }
      width = next; end = index;
    }
    return end;
  }
  private pageWidth(): number {
    const end: number = this.pageEndFrom(this.pageStart);
    let width: number = 8 + (this.pageStart > 0 ? 32 : 0) + (end < this.tabs.length - 1 ? 32 : 0);
    for (let index: number = this.pageStart; index <= end && index < this.tabs.length; index++) {
      width += this.tabWidth(this.tabs[index]) + (index > this.pageStart ? 4 : 0);
    }
    return Math.min(Math.max(84, width), Math.max(84, this.viewportWidth - this.sideInset * 2));
  }
  private pageOffset(start: number): number {
    return start >= this.tabs.length ? 0 : Math.max(0, this.tabStart(this.tabs[start].id) - (start > 0 ? 36 : 4));
  }
  private hasLeft(): boolean { return this.pageStart > 0; }
  private hasRight(): boolean { return this.pageEndFrom(this.pageStart) < this.tabs.length - 1; }
  private fullyVisible(tab: ForumTab): boolean {
    const index: number = this.tabs.findIndex((item: ForumTab): boolean => item.id === tab.id);
    if (index < this.pageStart || index > this.pageEndFrom(this.pageStart)) { return false; }
    const left: number = this.tabStart(tab.id) - this.scrollOffset;
    // 非选中标签没有底面，12vp触摸留白可进入边缘区；只要文字完整就应显示。
    return left + 12 >= (this.hasLeft() ? 36 : 4) - 0.5 &&
      left + this.tabWidth(tab) - 12 <= this.controlWidth() - (this.hasRight() ? 36 : 4) + 0.5;
  }
  // 固定玻璃底板尺寸，使2字/4字标签切换也只改变transform，不再改变HDS底板尺寸。
  private selectionSurfaceWidth(): number { return AppTheme.BAR_CONTENT_H; }

  private selectedWidth(): number {
    const tab: ForumTab | undefined = this.tabs.find((item: ForumTab): boolean => item.id === this.selectedId);
    return tab === undefined ? 0 : this.tabWidth(tab);
  }
  private resetSelection(): void {
    ++this.selectionRevision;
    this.selectionFlowing = false;
    this.selectionId = this.selectedId;
    this.selectionX = this.tabStart(this.selectedId);
    this.selectionW = this.selectedWidth();
    this.selectionScaleY = 1;
    this.selectionRestBlend = 1;
  }

  private flowSelection(): void {
    const targetX: number = this.tabStart(this.selectedId);
    const targetW: number = this.selectedWidth();
    if (!motionStore.isOn(MotionEffect.MOVE) || targetW <= 0 || this.selectionW <= 0 || !this.expanded || !this.active) {
      this.resetSelection(); return;
    }
    if (this.selectionId === this.selectedId) {
      // 字重/字体测量可能在流动中回报新宽度；由收尾阶段读取最终几何。
      if (!this.selectionFlowing) { this.resetSelection(); }
      return;
    }
    const revision: number = ++this.selectionRevision;
    this.selectionId = this.selectedId;
    if (!motionStore.isOn(MotionEffect.SPRING) || !motionStore.isOn(MotionEffect.SCALE)) {
      this.getUIContext().animateTo({ duration: motionDuration(220), curve: Curve.EaseOut }, (): void => {
        this.selectionX = targetX;
        this.selectionW = targetW;
        this.selectionScaleY = 1;
        this.selectionRestBlend = 1;
      });
      this.selectionFlowing = false;
      return;
    }
    this.selectionFlowing = true;
    // 先提交可见面交接，避免同一批关键帧把0→1合并后跳过流动层。
    this.getUIContext().animateTo({ duration: 0 }, (): void => { this.selectionRestBlend = 0; });
    // 头部先探向目标，尾部暂留原位；拉长时稍微变扁，形成粘连的玻璃流体。
    const left: number = Math.min(this.selectionX, targetX);
    const right: number = Math.max(this.selectionX + this.selectionW, targetX + targetW);
    // 一次提交全部关键帧，避免每段完成后再回到UI线程接续。
    // 动画只驱动transform，HDS底板布局宽度在不同标签间也保持不变。
    this.getUIContext().keyframeAnimateTo({
      onFinish: (): void => {
        if (this.alive && revision === this.selectionRevision) { this.resetSelection(); }
      }
    }, [
      { duration: 140, curve: Curve.EaseInOut, event: (): void => {
        this.selectionX = left;
        this.selectionW = right - left;
        this.selectionScaleY = 0.82;
        this.selectionRestBlend = 0;
      } },
      { duration: 130, curve: Curve.EaseOut, event: (): void => {
        this.selectionX = targetX + targetW * 0.06;
        this.selectionW = targetW * 0.88;
        this.selectionScaleY = 1.10;
      } },
      { duration: 90, curve: Curve.EaseOut, event: (): void => {
        this.selectionX = targetX - targetW * 0.02;
        this.selectionW = targetW * 1.04;
        this.selectionScaleY = 0.97;
      } },
      { duration: 110, curve: Curve.EaseInOut, event: (): void => {
        this.selectionX = targetX;
        this.selectionW = targetW;
        this.selectionScaleY = 1;
        // 关闭淡化时保持流动面，完成后由 resetSelection 直接交接静止面。
        this.selectionRestBlend = motionStore.isOn(MotionEffect.FADE) ? 1 : 0;
      } }
    ]);
  }

  private selectionVisible(): boolean {
    return this.selectionFits(this.scrollOffset);
  }
  private selectionFits(offset: number): boolean {
    const tab: ForumTab | undefined = this.tabs.find((item: ForumTab): boolean => item.id === this.selectedId);
    if (tab === undefined) { return false; }
    const left: number = this.tabStart(tab.id) - offset;
    // 选中玻璃面的描边需要完整空间，不能复用仅检查文字的规则。
    return left >= (this.hasLeft() ? 32 : 4) - 0.5 &&
      left + this.tabWidth(tab) <= this.controlWidth() -
      (this.hasRight() ? 32 : 4) + 0.5;
  }
  private showPage(start: number): void {
    this.getUIContext().animateTo({ duration: motionDuration(220, MotionEffect.MOVE), curve: Curve.EaseOut }, (): void => {
      this.pageStart = Math.max(0, Math.min(start, this.tabs.length - 1));
      this.anchorX = this.dockRight ? this.maxX() : this.minX();
      this.avoidRefresh();
    });
    this.scrollToOffset(this.pageOffset(this.pageStart));
  }
  private settleTabs(): void {
    if (!this.scrollingTabs) { return; }
    this.scrollingTabs = false;
    if (!this.alive || !this.expanded || this.dragging) { return; }
    if (Math.abs(this.panOffset) > 24) { this.browseEdge(this.panOffset < 0 ? 1 : -1); }
    else { this.showPage(this.pageStart); }
  }
  private scrollToOffset(offset: number): void {
    this.scroller.scrollTo({ xOffset: clampFloating(offset, 0, Math.max(0, this.contentWidth() - this.controlWidth())),
      yOffset: 0, animation: { duration: motionDuration(280), curve: Curve.EaseOut } });
  }
  private browseEdge(direction: number): void {
    ++this.revealRevision;
    if (direction > 0 && this.hasRight()) { this.showPage(this.pageEndFrom(this.pageStart) + 1); }
    else if (direction < 0 && this.hasLeft()) {
      const last: number = this.pageStart - 1;
      let start: number = last;
      while (start > 0 && this.pageEndFrom(start - 1) >= last) { --start; }
      this.showPage(start);
    } else { this.showPage(this.pageStart); }
  }
  private selectedPage(): number {
    const selected: number = this.tabs.findIndex((tab: ForumTab): boolean => tab.id === this.selectedId);
    let start: number = Math.max(0, Math.min(this.pageStart, this.tabs.length - 1));
    if (selected < 0) { return start; }
    if (selected < start) { return selected; }
    while (start < selected && this.pageEndFrom(start) < selected) { ++start; }
    return start;
  }
  private selectedOffset(): number {
    return this.pageOffset(this.selectedPage());
  }

  @Monitor('selectedId', 'tabs')
  revealSelected(): void {
    this.flowSelection();
    const revision: number = ++this.revealRevision;
    // 首次进入及分类异步到达也需定位；不能只在收起后展开时定位。
    setTimeout((): void => {
      if (revision === this.revealRevision && this.alive && this.expanded && !this.dragging) {
        this.showPage(this.selectedPage());
      }
    }, 240);
  }

  @Monitor('viewportWidth', 'viewportHeight', 'sideInset', 'topInset', 'initialY')
  syncBounds(): void {
    if (this.viewportWidth <= 0 || this.viewportHeight <= 0 || this.dragging) { return; }
    if (!this.ready || !this.moved) {
      this.anchorY = this.initialY;
      this.dockRight = false;
      this.ready = true;
    }
    this.anchorX = this.dockRight ? this.maxX() : this.minX();
    this.anchorY = clampFloating(this.anchorY, this.topInset + 8, this.maxY());
    this.avoidRefresh();
  }

  @Monitor('x', 'y', 'expanded', 'pageStart', 'tabWidths', 'viewportWidth')
  reportBounds(): void { this.onBoundsChanged(this.displayX(), this.y, this.controlWidth(), AppTheme.BAR_CONTENT_H); }

  @Monitor('prefs.xRatio', 'prefs.yRatio', 'refreshX', 'refreshY')
  refreshMoved(): void {
    if (!this.ready || this.dragging || this.refreshOwnsCollision) { return; }
    this.getUIContext().animateTo({ duration: motionDuration(220, MotionEffect.MOVE), curve: Curve.EaseOut }, (): void => { this.avoidRefresh(); });
  }

  private avoidRefresh(): void {
    if (this.dragging) { return; }
    // 每次从用户放置的锚点求解，碰撞产生的临时位移不成为下一次的起点。
    this.x = clampFloating(this.anchorX, this.minX(), this.maxX());
    this.y = clampFloating(this.anchorY, this.topInset + 8, this.maxY());
    const bounds = floatingBounds(this.viewportWidth, this.viewportHeight, this.topInset);
    const refreshX: number = this.refreshX >= 0 ? this.refreshX : (this.prefs.xRatio < 0 ? bounds.maxX :
      dockFloatingX(bounds.minX + this.prefs.xRatio * (bounds.maxX - bounds.minX), bounds));
    const refreshY: number = this.refreshY >= 0 ? this.refreshY : (this.prefs.yRatio < 0 ? clampFloating(this.viewportHeight - 128, bounds.minY, bounds.maxY) :
      bounds.minY + this.prefs.yRatio * (bounds.maxY - bounds.minY));
    const gap: number = 8;
    if (this.x < refreshX + 48 + gap && this.x + this.controlWidth() + gap > refreshX &&
      this.y < refreshY + 48 + gap && this.y + AppTheme.BAR_CONTENT_H + gap > refreshY) {
      const candidates: ForumTabsPoint[] = [
        { x: refreshX - this.controlWidth() - gap, y: this.y },
        { x: refreshX + 48 + gap, y: this.y },
        { x: this.x, y: refreshY - AppTheme.BAR_CONTENT_H - gap },
        { x: this.x, y: refreshY + 48 + gap }
      ];
      let distance: number = Number.MAX_VALUE;
      let bestX: number = this.x;
      let bestY: number = this.y;
      for (const point of candidates) {
        if (point.x < this.minX() || point.x > this.maxX() || point.y < this.topInset + 8 || point.y > this.maxY()) { continue; }
        const nextDistance: number = Math.pow(point.x - this.x, 2) + Math.pow(point.y - this.y, 2);
        if (nextDistance < distance) { distance = nextDistance; bestX = point.x; bestY = point.y; }
      }
      this.x = bestX; this.y = bestY;
    }
  }

  @Monitor('scrollRevision')
  collapseForScroll(): void { if (!this.dragging) { this.setExpanded(false); } }
  @Monitor('atTop')
  returnToTop(): void { if (this.atTop && !this.dragging) { this.setExpanded(true); this.syncBounds(); } }

  private setExpanded(value: boolean): void {
    if (this.expanded === value) { return; }
    this.resetSelection();
    this.getUIContext().animateTo({ duration: motionDuration(220, MotionEffect.MOVE), curve: Curve.EaseOut }, (): void => {
      this.expanded = value;
      // 展开/收起只改变宽度，沿用拖动或握姿确定的停靠侧。
      this.anchorX = this.dockRight ? this.maxX() : this.minX();
      this.avoidRefresh();
    });
    if (value) { this.revealSelected(); }
  }

  private finishDrag(): void {
    // 长按识别失败也会触发取消；普通轻点不能因此被吞掉。
    if (this.dragging || this.dragArmed) { this.suppressClickUntil = Date.now() + 350; }
    const didDrag: boolean = this.dragging;
    this.dragging = false; this.dragArmed = false;
    if (didDrag) {
      this.moved = true;
      this.dockRight = this.displayX() >= (this.minX() + this.maxX()) / 2;
      this.anchorX = this.dockRight ? this.maxX() : this.minX();
      this.anchorY = clampFloating(this.y, this.topInset + 8, this.maxY());
      this.getUIContext().animateTo({ duration: motionDuration(220, MotionEffect.MOVE), curve: Curve.EaseOut }, (): void => { this.avoidRefresh(); });
    }
  }

  private activateAt(localX: number): void {
    if (!this.alive || this.dragging || Date.now() < this.suppressClickUntil) { return; }
    if (!this.expanded) { this.setExpanded(true); return; }
    if (localX < 32 && this.hasLeft()) { this.browseEdge(-1); return; }
    if (localX > this.controlWidth() - 32 && this.hasRight()) { this.browseEdge(1); return; }
    if (!this.selectionEnabled) { return; }
    const contentX: number = localX - 4 + this.scroller.currentOffset().xOffset;
    let start: number = 0;
    for (let index: number = 0; index < this.tabs.length; index++) {
      const tab: ForumTab = this.tabs[index];
      const width: number = this.tabWidths.get(tab.id) ?? (tab.name.length * 14 + 24);
      if (contentX >= start && contentX < start + width) {
        if (this.fullyVisible(tab) && tab.id !== this.selectedId) { this.onSelect(tab, index); }
        return;
      }
      start += width + 4;
    }
  }

  @Builder
  GlassContent() { Row().width('100%').height('100%') }

  build() {
    Stack() {
      MaterialTabs({ slot: MaterialSlot.BOTTOM_BAR, barHeight: AppTheme.BAR_CONTENT_H, barWidth: this.controlWidth(),
        barContent: (): void => { this.GlassContent(); } })
        .width(this.controlWidth()).height(AppTheme.BAR_CONTENT_H).borderRadius(AppTheme.BAR_CONTENT_H / 2).clip(false).hitTestBehavior(HitTestMode.None)
      if (this.expanded) {
        Stack({ alignContent: Alignment.TopStart }) {
          Scroll(this.scroller) {
            Stack({ alignContent: Alignment.TopStart }) {
              // 单个选中玻璃面在分类间移动，避免每个标签各自突然亮灭。
              MaterialTabs({ slot: MaterialSlot.FORUM_TAB_SELECTION, barHeight: AppTheme.BAR_CONTENT_H - 8, barWidth: this.selectionSurfaceWidth(),
        barContent: (): void => { this.GlassContent(); } })
                .width(this.selectionSurfaceWidth()).height(AppTheme.BAR_CONTENT_H - 8)
                .borderRadius((AppTheme.BAR_CONTENT_H - 8) / 2).clip(false).hitTestBehavior(HitTestMode.None)

                .position({ x: 0, y: 4 })
                .scale({ x: this.selectionW / Math.max(1, this.selectionSurfaceWidth()), y: this.selectionScaleY,
                  centerX: 0, centerY: '50%' })
                .translate({ x: this.selectionX, y: 0 })
                .opacity(this.selectionVisible() ? 1 - this.selectionRestBlend : 0)
              // 最后110ms交接到真实宽度的HDS面，静止时两端保持半圆而非拉长的椭圆。
              MaterialTabs({ slot: MaterialSlot.FORUM_TAB_SELECTION, barHeight: AppTheme.BAR_CONTENT_H - 8, barWidth: this.selectedWidth(),
        barContent: (): void => { this.GlassContent(); } })
                .width(this.selectedWidth()).height(AppTheme.BAR_CONTENT_H - 8)
                .borderRadius((AppTheme.BAR_CONTENT_H - 8) / 2).clip(false).hitTestBehavior(HitTestMode.None)

                .position({ x: this.tabStart(this.selectedId), y: 4 })
                .opacity(this.selectionVisible() ? this.selectionRestBlend : 0)
            Row({ space: 4 }) {
              ForEach(this.tabs, (tab: ForumTab, index: number) => {
                Text(tab.name).fontSize(14).maxFontScale(1.25)
                  .fontColor(tab.id === this.selectedId ? $r('app.color.app_accent_dark') : AppTheme.TEXT_MAIN)
                  .fontWeight(tab.id === this.selectedId ? FontWeight.Bold : FontWeight.Normal)
                  .padding({ left: 12, right: 12 }).height(AppTheme.BAR_CONTENT_H - 8).borderRadius(24)
                  .opacity(this.fullyVisible(tab) ? 1 : 0)
                  .accessibilityText(`分类 ${tab.name}${tab.id === this.selectedId ? '，已选中' : ''}`)
                  .onAreaChange((_old: Area, area: Area): void => {
                    const width: number = Number(area.width);
                    if (this.tabWidths.get(tab.id) !== width) {
                      this.tabWidths.set(tab.id, width);
                      this.revealSelected();
                    }
                  })
              }, (tab: ForumTab) => String(tab.id))
            }.height(AppTheme.BAR_CONTENT_H).padding({ left: 4, right: 4 }).alignItems(VerticalAlign.Center)
            }.width(this.contentWidth()).height(AppTheme.BAR_CONTENT_H)
          }.width(this.controlWidth()).height(AppTheme.BAR_CONTENT_H).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
            .onDidScroll((): void => { this.scrollOffset = this.scroller.currentOffset().xOffset; })
            .clip(true).align(Alignment.Start)
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(16).maxFontScale(1)
              .fontWeight(FontWeight.Medium).fontColor([AppTheme.TEXT_MAIN])
          }.width(28).height(AppTheme.BAR_CONTENT_H).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
            .position({ x: 4, y: 0 }).opacity(this.hasLeft() ? 1 : 0)
            .translate({ x: this.hasLeft() ? 0 : -8 }).animation({ duration: motionDuration(180, MotionEffect.MOVE), curve: Curve.EaseOut })
            .accessibilityText('向左浏览分类')
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).maxFontScale(1)
              .fontWeight(FontWeight.Medium).fontColor([AppTheme.TEXT_MAIN])
          }.width(28).height(AppTheme.BAR_CONTENT_H).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
            .position({ x: this.controlWidth() - 32, y: 0 }).opacity(this.hasRight() ? 1 : 0)
            .translate({ x: this.hasRight() ? 0 : 8 }).animation({ duration: motionDuration(180, MotionEffect.MOVE), curve: Curve.EaseOut })
            .accessibilityText('向右浏览分类')
        }.width(this.controlWidth()).height(AppTheme.BAR_CONTENT_H).hitTestBehavior(HitTestMode.None)
      } else {
        Row({ space: 6 }) {
          Text(this.label()).fontSize(14).maxFontScale(1).fontWeight(FontWeight.Medium).fontColor($r('app.color.app_accent_dark'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.width(this.controlWidth()).height(AppTheme.BAR_CONTENT_H).justifyContent(FlexAlign.Center)
          .accessibilityText(`当前分类${this.label()}，点击展开，长按拖动`)
          .hitTestBehavior(HitTestMode.None)
      }
    }.width(this.controlWidth()).height(AppTheme.BAR_CONTENT_H)
      .animation({ duration: motionDuration(220, MotionEffect.MOVE), curve: Curve.EaseOut })
      .borderRadius(AppTheme.BAR_CONTENT_H / 2)
      .clip(false)
      .position({ x: this.displayX(), y: this.y }).id('floating-forum-tabs')
      .zIndex(20)
      .hitTestBehavior(HitTestMode.Block)
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Down) { this.pressed = true; this.cancelHolding(); }
        else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.pressed = false; this.cancelHolding(); }
      })
      .gesture(GestureGroup(GestureMode.Exclusive,
        GestureGroup(GestureMode.Sequence,
        LongPressGesture({ duration: 350, repeat: false })
          .onAction((): void => { this.dragArmed = true; }),
        PanGesture({ direction: PanDirection.All, distance: 3 })
          .onActionStart((): void => {
            this.dragging = true; this.cancelHolding(); this.originX = this.displayX(); this.originY = this.y; this.onMoveStart();
          })
          .onActionUpdate((event: GestureEvent): void => {
            this.x = clampFloating(this.originX + event.offsetX, this.minX(), this.maxX());
            this.y = clampFloating(this.originY + event.offsetY, this.topInset + 8, this.maxY());
          })
          .onActionEnd((): void => { this.finishDrag(); })
          .onActionCancel((): void => { this.finishDrag(); })),
        PanGesture({ direction: PanDirection.All, distance: 8 })
          .onActionStart((): void => { this.scrollingTabs = true; this.panOffset = 0; ++this.revealRevision; })
          .onActionUpdate((event: GestureEvent): void => {
            const delta: number = event.offsetX - this.panOffset; this.panOffset = event.offsetX;
            if (this.expanded) { this.scroller.scrollBy(-delta, 0); }
          })
          .onActionEnd((): void => { this.settleTabs(); })
          .onActionCancel((): void => { this.settleTabs(); }),
        TapGesture().onAction((event: GestureEvent): void => {
          if (event.fingerList.length > 0) { this.activateAt(event.fingerList[0].globalX - this.displayX()); }
        })))
  }
}
