import { FrameCallback } from '@kit.ArkUI';
import {
  LongImageCandidate, LongImageRect, LongImageSelection, longImageAnchorDelta,
  longImageViewport, selectLongImageButton, validLongImageRect
} from '../model/LongImageLayout';

let nextLongImageHost: number = 0;

/** onIdle 在本帧布局/绘制之后执行，避免读到收起前的图片几何。 */
class LongImageLayoutFrame extends FrameCallback {
  private ready: () => void;
  constructor(ready: () => void) { super(); this.ready = ready; }
  onIdle(_timeLeft: number): void { this.ready(); }
}

/**
 * 每个详情页一个控制器，只接该页主 List；独立楼中楼面板不得复用它。
 * 注册表仅包含已挂载且已展开的图片，滚动只更新一颗按钮，不广播逐帧滚动状态。
 */
@ObservedV2
export class LongImageController {
  readonly hostId: string = `long-image-host-${++nextLongImageHost}`;
  readonly viewportId: string = `${this.hostId}-viewport`;
  @Trace activeId: string = '';
  @Trace buttonX: number = 0;
  @Trace buttonY: number = 0;
  private context: UIContext | undefined = undefined;
  private scroller: ListScroller | undefined = undefined;
  private expanded: Map<string, () => void> = new Map<string, () => void>();
  private topInset: number = 0;
  private bottomInset: number = 0;
  private active: boolean = true;
  private generation: number = 0;
  private refreshPending: boolean = false;
  private anchorRevision: number = 0;
  private anchorId: string = '';

  bind(context: UIContext, scroller: ListScroller, topInset: number, bottomInset: number): void {
    if (this.scroller !== undefined && this.scroller !== scroller) { this.invalidatePending(); }
    this.context = context;
    this.scroller = scroller;
    this.topInset = Number.isFinite(topInset) ? Math.max(0, topInset) : 0;
    this.bottomInset = Number.isFinite(bottomInset) ? Math.max(0, bottomInset) : 0;
    this.requestRefresh();
  }

  /** 页面隐藏/被弹层覆盖时暂停；保留图的展开与注册，返回后重新测量。 */
  setActive(active: boolean): void {
    if (this.active === active) { return; }
    this.active = active;
    this.invalidatePending();
    if (!active) { this.hide(); }
    else { this.requestRefresh(); }
  }

  register(id: string, collapse: () => void): void {
    if (id.length === 0) { return; }
    if (this.anchorId === id) { this.cancelAnchor(); }
    this.expanded.set(id, collapse);
    this.requestRefresh();
  }

  unregister(id: string): void {
    this.expanded.delete(id);
    // 原节点离场、换图或再次展开后，旧回锚帧不能继续控制当前 List。
    if (this.anchorId === id) { this.cancelAnchor(); }
    if (this.activeId === id) { this.hide(); }
    this.requestRefresh();
  }

  /** List.onDidScroll 可直接调用，几何统一转成 vp 后再计算。 */
  refresh(): void {
    const context: UIContext | undefined = this.context;
    if (!this.active || context === undefined || this.expanded.size === 0) { this.hide(); return; }
    try { context.runScopedTask((): void => { this.refreshNow(context); }); }
    catch (_) { this.hide(); }
  }

  /** 布局/图片解码回调合并到一个后布局帧，避免同一帧反复扫描注册表。 */
  requestRefresh(): void {
    const context: UIContext | undefined = this.context;
    if (!this.active || context === undefined || this.refreshPending || this.expanded.size === 0) { return; }
    this.refreshPending = true;
    const generation: number = this.generation;
    try {
      context.postFrameCallback(new LongImageLayoutFrame((): void => {
        if (generation !== this.generation || !this.active) { return; }
        this.refreshPending = false;
        this.refresh();
      }));
    } catch (_) { this.refreshPending = false; }
  }

  /** 收起只影响指定图；先把图顶带回，再在布局后校正，防止虚拟回复因高度骤减而被回收。 */
  collapse(id: string): void {
    if (!this.active) { return; }
    const collapse: (() => void) | undefined = this.expanded.get(id);
    if (collapse === undefined) { return; }
    const context: UIContext | undefined = this.context;
    const scroller: ListScroller | undefined = this.scroller;
    const generation: number = this.generation;
    const revision: number = ++this.anchorRevision;
    this.anchorId = id;
    this.expanded.delete(id);
    if (this.activeId === id) { this.hide(); }
    if (context === undefined || scroller === undefined) {
      collapse();
      this.cancelAnchor();
      this.requestRefresh();
      return;
    }
    const image: LongImageRect | undefined = this.measure(context, id);
    const viewport: LongImageRect | undefined = this.readViewport(context);
    try {
      context.runScopedTask((): void => {
        // scrollBy 无动画，在同一个 UI 更新中完成预定位与收起，避免先闪到后续回复。
        if (image !== undefined && viewport !== undefined) {
          this.scrollToImageTop(scroller, image, viewport);
        }
        collapse();
      });
    } catch (_) {
      this.cancelAnchor();
      this.requestRefresh();
      return;
    }
    this.scheduleAnchor(context, scroller, id, generation, revision, 0);
    this.requestRefresh();
  }

  /** 真正离场才清空；临时隐藏用 setActive(false)，避免返回时丢失仍展开的图。 */
  clear(): void {
    this.invalidatePending();
    this.active = false;
    this.expanded.clear();
    this.context = undefined;
    this.scroller = undefined;
    this.hide();
  }

  private hide(): void { if (this.activeId.length > 0) { this.activeId = ''; } }

  private cancelAnchor(): void { ++this.anchorRevision; this.anchorId = ''; }

  private invalidatePending(): void {
    ++this.generation;
    this.refreshPending = false;
    this.cancelAnchor();
  }

  private measure(context: UIContext, id: string): LongImageRect | undefined {
    try {
      const info = context.getComponentUtils().getRectangleById(id);
      // ComponentInfo.size / windowOffset 均为 px；不能直接与 ArkUI 的 vp 混算。
      const rect: LongImageRect = {
        x: context.px2vp(info.windowOffset.x), y: context.px2vp(info.windowOffset.y),
        width: context.px2vp(info.size.width), height: context.px2vp(info.size.height)
      };
      return validLongImageRect(rect) ? rect : undefined;
    } catch (_) { return undefined; }
  }

  private readViewport(context: UIContext, measuredHost: LongImageRect | undefined = undefined): LongImageRect | undefined {
    const host: LongImageRect | undefined = measuredHost ?? this.measure(context, this.hostId);
    const list: LongImageRect | undefined = this.measure(context, this.viewportId);
    if (host === undefined || list === undefined) { return undefined; }
    const viewport: LongImageRect = longImageViewport(host, list, this.topInset, this.bottomInset);
    return validLongImageRect(viewport) ? viewport : undefined;
  }

  private refreshNow(context: UIContext): void {
    const host: LongImageRect | undefined = this.measure(context, this.hostId);
    const viewport: LongImageRect | undefined = this.readViewport(context, host);
    if (host === undefined || viewport === undefined) { this.hide(); return; }
    const images: LongImageCandidate[] = [];
    this.expanded.forEach((_collapse: () => void, id: string): void => {
      const rect: LongImageRect | undefined = this.measure(context, id);
      if (rect !== undefined) { images.push({ id: id, rect: rect }); }
    });
    const selected: LongImageSelection = selectLongImageButton(images, viewport, host, this.activeId);
    if (!selected.visible) { this.hide(); return; }
    if (this.buttonX !== selected.x) { this.buttonX = selected.x; }
    if (this.buttonY !== selected.y) { this.buttonY = selected.y; }
    if (this.activeId !== selected.id) { this.activeId = selected.id; }
  }

  private scrollToImageTop(scroller: ListScroller, image: LongImageRect, viewport: LongImageRect): void {
    const delta: number = longImageAnchorDelta(image.y, viewport.y);
    if (delta === 0) { return; }
    try { scroller.scrollBy(0, delta); }
    catch (_) { /* List 正在卸载或尚未挂载时，不牵动其它滚动器。 */ }
  }

  private anchorIsCurrent(scroller: ListScroller, id: string, generation: number, revision: number): boolean {
    return this.active && this.scroller === scroller && generation === this.generation &&
      revision === this.anchorRevision && this.anchorId === id && !this.expanded.has(id);
  }

  private scheduleAnchor(context: UIContext, scroller: ListScroller, id: string,
    generation: number, revision: number, attempt: number): void {
    if (!this.anchorIsCurrent(scroller, id, generation, revision)) { return; }
    try {
      context.postFrameCallback(new LongImageLayoutFrame((): void => {
        if (!this.anchorIsCurrent(scroller, id, generation, revision)) { return; }
        try {
          context.runScopedTask((): void => {
            const image: LongImageRect | undefined = this.measure(context, id);
            const viewport: LongImageRect | undefined = this.readViewport(context);
            if (image !== undefined && viewport !== undefined) {
              const delta: number = longImageAnchorDelta(image.y, viewport.y);
              this.scrollToImageTop(scroller, image, viewport);
              // 最多两次校正；触达列表首尾后仍有余差时不连续抢夺滚动。
              if (delta !== 0 && attempt < 1) {
                this.scheduleAnchor(context, scroller, id, generation, revision, attempt + 1);
              } else { this.cancelAnchor(); }
            } else { this.cancelAnchor(); }
            this.refreshNow(context);
          });
        } catch (_) { this.cancelAnchor(); this.hide(); }
      }));
    } catch (_) { this.cancelAnchor(); }
  }
}
