import { visualThemeStore } from '../common/appearance/VisualThemeStore';
import { VisualTheme, PaperLayout, visualThemeLabel, ALL_VISUAL_THEMES } from '../common/appearance/VisualTheme';
import { homeDualRowHeight, OFFICIAL_DUAL_ROW_HEIGHT } from '../common/appearance/HomeTopNavStyle';
import { fontSizeScaleOf } from '../common/appearance/FontSizeScale';
import { forumLevelStore } from '../common/appearance/ForumLevelStore';
import { forumDefaultTabStore } from '../common/appearance/ForumDefaultTabStore';
import { ForumDefaultTab, forumDefaultTabLabel } from '../model/ForumDefaultTab';
import { ForumLevelBadge } from '../components/ForumLevelBadge';
import { AvatarEditVM } from '../viewmodel/AvatarEditVM';
import { CacheStatsVM } from '../viewmodel/CacheStatsVM';
import { AvatarCropPage } from '../components/AvatarCropPage';
import { AvatarCrop } from '../model/AvatarUpload';
/**
 * 设置页：分类首页、子页和锚定选项菜单。
 * 信息结构由 SettingsModel 提供，尺寸由 SettingsLayout 提供，颜色读取 AppTheme。
 * 页面与选项菜单沿用共享材质槽位。
 * 列表 key 必须包含实时展示值，避免偏好变化后复用旧节点而保留旧文案。
 * 设置内容底部间距遵循 SettingsLayout.PAGE_BOTTOM_GAP。
 * 历史视觉与迁移过程见项目开发记录和设置系统设计规范。
 */

import { common } from '@kit.AbilityKit';
import { FrameCallback, router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { authSession } from '../auth/AuthSession';
import { ForegroundRefresh, foregroundRefresh } from '../viewmodel/ForegroundRefresh';
import { StoreResult } from '../auth/AuthStore';
import { AppTheme } from '../theme/Theme';
import { GlassBackButton } from '../components/GlassBackButton';
import { GlassCircleButton } from '../components/GlassCircleButton';
import { GlassPillButton } from '../components/GlassPillButton';
import { ForbiddenForumsVM } from '../viewmodel/ForbiddenForumsVM';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { SearchTopMaterial } from '../components/SearchTopMaterial';
import { materialManager } from '../common/material/MaterialManager';
import { MotionSettingsPane } from '../components/MotionSettingsPane';
import { sliderMaterial } from '../common/appearance/MotionPolicy';
import { MotionEffect } from '../common/appearance/MotionConfig';
import { motionStore } from '../common/appearance/MotionStore';
import { ALL_HDS_LEVELS, hdsLevelLabel } from '../common/material/MaterialStrength';
import { MessageSettingsPane } from '../components/MessageSettingsPane';
import { OfficialMessagesPane } from '../components/OfficialMessagesPane';
import { TailsPane } from '../components/TailsPane';
import { ForbiddenForumsPane } from '../components/ForbiddenForumsPane';
import { BlockManagePane } from '../components/BlockManagePane';
import { ImageWatermarkPane } from '../components/ImageWatermarkPane';
import { PrivacyMarksPane } from '../components/PrivacyMarksPane';
import { AppPermissionsPane } from '../components/AppPermissionsPane';
import { ALL_MODES, MaterialMode, MaterialSlot, modeLabel } from '../common/material/MaterialConfig';

import {
  ALL_ACTION_BAR_STYLES, ThreadActionBarStyle, actionBarStyleLabel
} from '../common/appearance/ThreadActionBarStyle';
import {
  ALL_HOME_TOP_NAV_OPTIONS, HomeTopNavOption, HomeTopNavStyle, homeTopNavOptionIndexOf,
  homeTopNavStyleLabel
} from '../common/appearance/HomeTopNavStyle';
import { homeTopNavStore } from '../common/appearance/HomeTopNavStore';

import { HomeTopNav } from '../components/HomeTopNav';
import { HomeDualRowTopBar } from '../components/HomeDualRowTopBar';
import { HomeNavigationPart, homeNavigationHideStore } from '../common/appearance/HomeNavigationHideStore';
import { lowFlowStore } from '../common/appearance/LowFlowStore';
import { imageLayoutStore } from '../common/appearance/ImageLayoutStore';
import { ImageLayoutMode, imageLayoutLabel } from '../model/ImageLayout';
import { superResolutionStore } from '../common/appearance/SuperResolutionStore';
import { smartReachStore, SmartReachStore } from '../common/appearance/SmartReachStore';
import { signStrategyStore } from '../common/appearance/SignStrategyStore';
// 系统总量与注册缓存根内的可清理文件量分别读取。
import {
  CachePhase, cachePhaseAmountLabel, cachePhaseCanClear, cacheResultLines
} from '../model/CacheClean';
import { ClearResult } from '../utils/CacheCleaner';
import { clearApplicationCache } from '../utils/ApplicationCache';
import { videoPlayback } from '../viewmodel/VideoPlaybackVM';
import { voicePlayback } from '../viewmodel/VoicePlaybackVM';

import { threadActionBarStore } from '../common/appearance/ThreadActionBarStore';

import {
  ALL_THEME_MODE_PREFS, ThemeModePref, themeModeLabel
} from '../common/appearance/ThemeMode';
import { themeModeStore } from '../common/appearance/ThemeModeStore';

import {
  ALL_FONT_SIZE_PREFS, FONT_SIZE_MAX, FONT_SIZE_MIN, FontSizePref, fontSizeLabel
} from '../common/appearance/FontSizeScale';
import { fontScaleStore } from '../common/appearance/FontSizeScaleStore';

import { SettingsLayout, AUTO_LOAD_TRIGGER_PX, AUTO_FILL_MAX } from '../common/appearance/SettingsLayout';
import { portraitUrl } from '../model/ThreadDetail';
import {
  SettingsActionRow, SettingsActionTone, SettingsCard, SettingsEntryRow, SettingsGroupTitle,
  SettingsInfoRow, SettingsNote, SettingsOptionRow, SettingsStatusKind, SettingsStatusLine,
  SettingsSwitchRow
} from '../components/SettingsComponents';
import { AvatarComponent } from '../components/AvatarComponent';
import { SETTINGS_ACTION_LOGIN, SETTINGS_ACTION_LOGOUT, SettingsAboutItem, SettingsEntry, SettingsEntryKind, SettingsGroup, SettingsOptionItem, SettingsPane, SettingsPanePresentation, SettingsState, SETTINGS_APP_VERSION, SETTINGS_VERSION_CODE, aboutItems, aboutNotes, buildOptions, buildSettingsCategoryEntries, buildSettingsGroups, settingsEntryRenderKey, settingsGroupRenderKey, settingsPageTitle, settingsPanePresentation, settingsParentPane } from '../model/SettingsModel';

const TOP_NAV_PREVIEW_H: number = 108;
// 「官方沉浸」预览：整片玻璃面板（statusBarHeight 传 0）= 48 + 6 + 56 + 上下内距 8 = 118，
// 再露出 28vp 内容让玻璃有东西可透。
const TOP_NAV_PREVIEW_DUAL_H: number = 119 + 28;
const PANE_ENTRY_DISTANCE: number = 18;
const PANE_ENTRY_DURATION: number = 180;

class SettingsPaneFrame extends FrameCallback {
  private ready: () => void;
  constructor(ready: () => void) { super(); this.ready = ready; }
  onIdle(_timeLeft: number): void { this.ready(); }
}

@Entry
@ComponentV2
struct SettingsPage {
  @Local smartReach: SmartReachStore = smartReachStore;
  @Local pageVisible: boolean = false;
  @Local foreground: ForegroundRefresh = foregroundRefresh;
  private foregroundRevision: number = foregroundRefresh.revision;

  @Monitor('foreground.revision', 'pageVisible')
  onForegroundRefresh(): void {
    if (!this.pageVisible || this.cropOpen || this.foregroundRevision === this.foreground.revision) { return; }
    this.foregroundRevision = this.foreground.revision;
    if (this.pane === SettingsPane.NONE || this.pane === SettingsPane.ACCOUNT) {
      void this.foreground.refreshAvatar(this.getUIContext().getHostContext() as common.UIAbilityContext);
    }
  }

  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;

  /** 当前分类或内容页；`NONE` = 设置入口列表。 */
  @Local pane: SettingsPane = SettingsPane.NONE;
  @Local paneOffset: number = 0;
  @Local paneOpacity: number = 1;
  private paneMotionVersion: number = 0;

  @Local avatarVm: AvatarEditVM = new AvatarEditVM();

  /** 裁剪页是否盖在本页之上（`AvatarCropPage` 自持手势状态，本页只开关它）。 */
  @Local cropOpen: boolean = false;

  /**
   * 哪个入口行的弹层是开着的（存行的 `key`，空串 = 全关）。
   *
   * 为什么用 `key` 而不是 `boolean` + 记录面板：`bindPopup` 要挂在**行自己**身上
   * （弹层的锚点是那一行的 bounds），而每行都要写一句"该不该显示"，
   * 于是 `show = this.popupKey === entry.key` 天然保证**任何时刻最多只有一层弹层**，
   * 不会出现两个行同时为 true 的中间态。
   */
  @Local popupKey: string = '';

  /** 开着的那层弹层展示哪一组选项（只在 `popupKey` 非空时有意义） */
  @Local popupPane: SettingsPane = SettingsPane.NONE;
  @Local fontSheetOpen: boolean = false;

  @Local previewNavRowH: number = 54;
  @Local previewChannel: string = '推荐';
  @Local cacheStats: CacheStatsVM = new CacheStatsVM();
  /** 上一次清理的实数：结果行由纯逻辑 `cacheResultLines()` 按阶段与它们生成 */
  @Local lastCleared: number = 0;
  @Local lastFailed: number = 0;
  @Local lastFreedBytes: number = 0;
  @Local searchCount: number = 0;
  @Local browseCount: number = 0;
  /** 清理进行中：挡住连点（清理是"统计→删→再统计"，中途重入会报错数字） */
  @Local cacheBusy: boolean = false;

  aboutToAppear(): void {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    readStatusBarVp(context).then((vp: number) => {
      this.statusBarH = vp;
    }).catch(() => {
      // 拿不到就保持兜底值
    });
  }

  onPageShow(): void {
    this.pageVisible = true;
    this.refreshCacheStats();
    if ((this.pane === SettingsPane.NONE || this.pane === SettingsPane.ACCOUNT) &&
      authSession.isLoggedIn()) {
      void this.foreground.refreshAvatar(
        this.getUIContext().getHostContext() as common.UIAbilityContext);
    }
    if (this.pane === SettingsPane.APP_PERMISSIONS) {
      this.paneRefreshSeq += 1;
    }
  }

  /**
   * 页面销毁时收掉头像流程。上传已发出但读回还没回来时，`dispose()` 会把这次读回
   * 交接给共享刷新队列（换号则放弃），不是静默丢弃 —— 语义在 `AvatarEditVM.handOffSync`。
   */
  aboutToDisappear(): void {
    this.pageVisible = false;
    this.finishPaneEntry();
    this.avatarVm.dispose();
    this.cacheStats.dispose();
  }

  onPageHide(): void {
    this.pageVisible = false;
    this.finishPaneEntry();
  }

  /**
   * 系统返回：先退出关于页内层或其它设置的数据说明，再回分类列表。
   *
   * 返回 `true` = 已消费。不做这一步的话，用户在二级页里按返回会**直接关掉设置页**，
   * 而顶栏那枚返回按钮却是回列表 —— 两个返回走两条路是最容易被忽略的不一致。
   *
   * 弹层**不走这里**：`bindPopup` 自己管蒙层与返回键的关闭（`autoCancel` 默认开），
   * 它关掉时会回调 `onStateChange`，我们在那里清 `popupKey`。
   *
   * 裁剪页盖在最上层时同理：返回键先收裁剪页（等同点「✕」），不退设置页。
   */
  onBackPress(): boolean {
    if (this.pane === SettingsPane.FORBIDDEN_FORUMS && this.forbiddenVm.executing) {
      this.forbiddenVm.requestStop(); return true;
    }
    if (this.pane === SettingsPane.FORBIDDEN_FORUMS && this.forbiddenVm.selecting && !this.forbiddenVm.actionBusy) {
      this.forbiddenVm.toggleSelection(); return true;
    }
    if (this.cropOpen) {
      this.cropOpen = false;
      return true;
    }
    if (this.pane !== SettingsPane.NONE) {
      this.leaveToParent();
      return true;
    }
    return false;
  }


  /**
   * 入口列表模型。**唯一真值源**：三档文案分别读三个全局单例（都是 `@Trace`），
   * 登录态读 `authSession.snapshot`。所以"选完档位返回列表，值已经变了"、
   * "退出登录后整张卡片消失"都是自动的，不需要手动刷新。
   */
  private state(): SettingsState {
    return {
      loggedIn: authSession.snapshot.isLoggedIn(),
      materialLabel: modeLabel(materialManager.mode),
      hdsMaterialLabel: hdsLevelLabel(materialManager.hdsLevel),
      actionBarLabel: actionBarStyleLabel(threadActionBarStore.style),
      topNavLabel: homeTopNavStyleLabel(homeTopNavStore.style),
      darkModeLabel: themeModeLabel(themeModeStore.pref),
      fontLabel: fontSizeLabel(fontScaleStore.pref),
      forumDefaultTabLabel: forumDefaultTabLabel(forumDefaultTabStore.value),
      imageLayoutLabel: imageLayoutLabel(imageLayoutStore.mode),
      hideStatusBar: homeNavigationHideStore.hideStatusBar,
      hideTopNavigation: homeNavigationHideStore.hideTopNavigation,
      hideBottomNavigation: homeNavigationHideStore.hideBottomNavigation,
      lowFlow: lowFlowStore.enabled,
      superResolution: superResolutionStore.enabled,
      smartReach: this.smartReach.enabled,
      homeComposeSmartReach: this.smartReach.homeComposeEnabled,
      imageMenuSmartReach: this.smartReach.imageMenuEnabled,
      imageMenuLongPress: this.smartReach.imageMenuLongPress,
      forumTabsSmartReach: this.smartReach.forumTabsEnabled,
      forumTabsFloating: this.smartReach.forumTabsFloating,
      // 入口显示系统应用缓存总量，不再用导出目录大小冒充总量。
      cacheLabel: this.cacheStats.label(),
    };
  }

  private groups(): SettingsGroup[] {
    return buildSettingsGroups(this.state());
  }

  private entriesFor(pane: SettingsPane, keys: string[]): SettingsEntry[] {
    return buildSettingsCategoryEntries(pane, this.state())
      .filter((entry: SettingsEntry): boolean => keys.includes(entry.key));
  }

  /**
   * 玻璃顶栏总高（vp）= 56 内容高 + 状态栏避让。
   * 顶栏自身、列表顶部占位项、顶栏渐隐高度**共用这一个值**，改一处三边同步。
   */
  private titleBarH(): number {
    return 56 + this.statusBarH;
  }

  /** 顶栏玻璃层的不透明度：0 = 与页面底色齐平（静止态），1 = 目标强度。 */
  @Local navGlass: number = 0;
  /** 从系统设置返回时通知权限子页重读；初值 0 不触发。 */
  @Local paneRefreshSeq: number = 0;
  /** 通知分页子页「接近底部」（滚动到底 → 自增；同一时间只允许一个分页请求，由 VM 单飞吸收） */
  @Local paneLoadMoreSeq: number = 0;
  @Local forbiddenVm: ForbiddenForumsVM = new ForbiddenForumsVM();
  @Local forbiddenUnblockSeq: number = 0;
  private scroller: Scroller = new Scroller();

  private resetScroll(): void {
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
    this.navGlass = 0;
  }

  /**
   * 每页记住的滚动偏移（返回上级时恢复；**从入口进入新页仍从顶部开始**）。
   * 键用 pane 的数值串，避免依赖枚举名字面量。
   */
  private paneScrollY: Map<string, number> = new Map<string, number>();

  /** 离开当前页前记下它的偏移。 */
  private rememberScroll(pane: SettingsPane): void {
    this.paneScrollY.set(String(pane), this.scroller.currentOffset().yOffset);
  }

  /**
   * 导航代号：每次切页自增。**延迟恢复只在代号仍是最新时生效** ——
   * 布局期间又发生了一次导航，旧的恢复必须作废（否则会出现迟到滚动/顶栏错配）。
   */
  private navSeq: number = 0;

  /** 复用当前页面与 Scroller，只为新内容补方向提示，避免并存两份设置状态。 */
  private beginPaneEntry(direction: number): void {
    const version: number = ++this.paneMotionVersion;
    const move: boolean = motionStore.isOn(MotionEffect.MOVE);
    const fade: boolean = motionStore.isOn(MotionEffect.FADE);
    const context: UIContext = this.getUIContext();
    context.animateTo({ duration: 0, curve: Curve.Linear }, (): void => {
      this.paneOffset = move ? PANE_ENTRY_DISTANCE * direction : 0;
      this.paneOpacity = fade ? 0.92 : 1;
    });
    if (!move && !fade) { return; }
    context.postFrameCallback(new SettingsPaneFrame((): void => {
      if (!this.pageVisible || version !== this.paneMotionVersion) { return; }
      const enabled: boolean = motionStore.isOn(MotionEffect.MOVE) || motionStore.isOn(MotionEffect.FADE);
      context.animateTo({ duration: enabled ? PANE_ENTRY_DURATION : 0, curve: Curve.EaseOut }, (): void => {
        this.paneOffset = 0;
        this.paneOpacity = 1;
      });
    }));
  }

  private finishPaneEntry(): void {
    ++this.paneMotionVersion;
    this.getUIContext().animateTo({ duration: 0, curve: Curve.Linear }, (): void => {
      this.paneOffset = 0;
      this.paneOpacity = 1;
    });
  }

  /** 所有页面入口统一走这里：进入前保存当前页偏移，新页从顶部开始。 */
  private navigateTo(next: SettingsPane): void {
    if (next === SettingsPane.FORBIDDEN_FORUMS && this.pane !== next) {
      this.forbiddenVm = new ForbiddenForumsVM(); this.forbiddenUnblockSeq = 0;
    }
    const from: SettingsPane = this.pane;
    if (from !== next) {
      this.rememberScroll(from);
    }
    this.navSeq += 1;
    this.pendingRestore = -1;          // 新页面从顶部开始：作废任何未决恢复
    this.paneScrollY.delete(String(next));
    this.autoFillCount = 0;            // 首屏补页计数随新页归零
    this.pane = next;
    if (next === SettingsPane.ACCOUNT && from !== next && authSession.isLoggedIn()) {
      void this.foreground.refreshAvatar(
        this.getUIContext().getHostContext() as common.UIAbilityContext);
    }
    this.resetScroll();
    if (from !== next) { this.beginPaneEntry(1); }
  }

  private updateNavGlass(): void {
    const offset: number = this.scroller.currentOffset().yOffset;
    const span: number = SettingsLayout.NAV_GLASS_FULL - SettingsLayout.NAV_GLASS_START;
    const ratio: number = span > 0 ? (offset - SettingsLayout.NAV_GLASS_START) / span : 0;
    this.navGlass = Math.max(0, Math.min(1, ratio));
  }

  /** 首屏补页的本次进入计数：每次切页（`navigateTo`/恢复顶部）归零。 */
  private autoFillCount: number = 0;
  /** 内容列的实际高度（vp）：由内容容器 `onAreaChange` 记录（Scroller 没有内容总高 API）。 */
  private paneContentH: number = 0;
  /** 滚动视口高度（vp）：由滚动容器 `onAreaChange` 记录。 */
  private viewportH: number = 0;

  /**
   * 接近底部自动加载：距内容底部小于 `AUTO_LOAD_TRIGGER_PX` 即请求下一页。
   *
   * 两条触发路径：
   * - `onScroll`（atEnd=false）：滚动途中**提前**加载，用户看到到底之前下一页已在路上；
   * - `onReachEnd`（atEnd=true）：兜底，惯性滚动跨过触发窗口、或内容不足一屏时也能补上。
   *
   * **首屏不足一屏**（内容高度 ≤ 视口，无滚动发生）：由 `AUTO_FILL_MAX` 限制连续补页
   * 次数，只在 VM 真正接受续页时计数；达到上限后由「点击加载更多」继续。
   * 新页进入时归零，内容增长和重复触底都不重置计数。
   */
  private autoLoadMore(atEnd: boolean): void {
    if (this.pane !== SettingsPane.FORBIDDEN_FORUMS) { return; }
    if (this.paneContentH <= 0 || this.viewportH <= 0) { return; }
    const content: number = this.paneContentH;
    const extent: number = this.viewportH;
    if (content <= extent) {
      // 首屏不足一屏：只允许有限次连续补页（到达上限就停手）
      if (this.autoFillCount >= AUTO_FILL_MAX) { return; }
    } else {
      const offset: number = this.scroller.currentOffset().yOffset;
      const distanceToEnd: number = Math.max(0, content - extent - offset);
      if (!atEnd && distanceToEnd > AUTO_LOAD_TRIGGER_PX) { return; }
    }
    // VM 单飞守卫吸收重复触发，onPageStarted 只报告实际接受的续页。

    this.paneLoadMoreSeq += 1;
  }

  /** 顶栏返回：二级页里回列表，列表上才真的退出设置页 */
  private goBack(): void {
    if (this.pane === SettingsPane.FORBIDDEN_FORUMS && this.forbiddenVm.executing) {
      this.forbiddenVm.requestStop(); return;
    }
    if (this.pane === SettingsPane.FORBIDDEN_FORUMS && this.forbiddenVm.selecting && !this.forbiddenVm.actionBusy) {
      this.forbiddenVm.toggleSelection(); return;
    }
    if (this.pane !== SettingsPane.NONE) {
      this.leaveToParent();
      return;
    }
    router.back();
  }

  /**
   * 待恢复的偏移与它的导航代号。
   *
   * ⚠️ 不能用 `setTimeout(0)` 当"布局已就绪"：那只是晚一拍执行，内容可能还没换完，
   * 于是 `scrollTo` 作用在**旧内容**上（或被旧的最大偏移夹取）。真正的就绪信号是
   * 内容容器的 `onAreaChange` —— 新内容参与布局后才会回调，这里才做恢复。
   */
  @Local pendingRestore: number = -1;
  private pendingRestoreSeq: number = -1;

  /** 内容布局完成后调用：代号仍最新才恢复，恢复后顶栏由 `updateNavGlass()` 按**实际偏移**校正。 */
  private applyPendingRestore(): void {
    if (this.pendingRestore < 0 || this.pendingRestoreSeq !== this.navSeq) {
      this.pendingRestore = -1;
      return;
    }
    const y: number = this.pendingRestore;
    this.pendingRestore = -1;
    this.scroller.scrollTo({ xOffset: 0, yOffset: y });
    /*
     * 这里**故意不写 navGlass**：`y` 只是目标值，内容变短时实际偏移会被夹取到更小的值。
     * 顶栏状态必须来自恢复后的真实偏移 —— 由 `Scroll.onScroll → updateNavGlass()` 负责。
     */
    this.updateNavGlass();
  }

  /**
   * 统一的"返回上一级"：记住当前页偏移 → 换页 → 交给内容布局回调去恢复。
   * 期间若再次导航，`navSeq` 已变，本次恢复作废（不会出现迟到滚动）。
   */
  private leaveToParent(): void {
    const from: SettingsPane = this.pane;
    this.rememberScroll(from);
    const next: SettingsPane = settingsParentPane(from);
    const seq: number = ++this.navSeq;
    this.pane = next;
    if ((next === SettingsPane.NONE || next === SettingsPane.ACCOUNT) &&
      from !== next && authSession.isLoggedIn()) {
      void this.foreground.refreshAvatar(
        this.getUIContext().getHostContext() as common.UIAbilityContext);
    }
    this.pendingRestore = this.paneScrollY.get(String(next)) ?? 0;
    this.pendingRestoreSeq = seq;
    if (this.pendingRestore === 0) {
      // 目标本来就在顶部：无需等布局，直接复位
      this.pendingRestore = -1;
      this.resetScroll();
    }
    if (from !== next) { this.beginPaneEntry(-1); }
  }

  /**
   * 行点击分发。**只看 `kind` / `action`，不比较中文文案**。
   * 置灰行不是死行：点击如实提示"开发中"（与改造前一致）。
   */
  private onEntry(entry: SettingsEntry): void {
    if (!entry.enabled) {
      promptAction.showToast({ message: '该设置项开发中', duration: 2000 });
      return;
    }
    switch (entry.kind) {
      case SettingsEntryKind.PANE:
        if (settingsPanePresentation(entry.pane) === SettingsPanePresentation.POPUP) {
          this.openPopup(entry);
        } else {
          // 从入口进入是"新页面"：统一走导航方法（保存父页偏移 + 新页从顶部开始）
          this.navigateTo(entry.pane);
          // G-03：进缓存清理页**先统计**，行右侧的占用必须是进去那一刻的真实值
          if (entry.pane === SettingsPane.CACHE) {
            this.refreshCacheStats();
          }
        }
        return;
      case SettingsEntryKind.ACTION:
        if (entry.action === SETTINGS_ACTION_LOGIN) {
          router.pushUrl({ url: 'pages/Login' });
        } else if (entry.action === SETTINGS_ACTION_LOGOUT) {
          this.confirmLogout();
        }
        return;
      default:
        // INFO 行没有去处，不做任何事
        return;
    }
  }

  /**
   * 打开某一行的选项弹层。
   *
   * 先设 `popupPane` 再设 `popupKey`：`popupKey` 是"显示"的开关，它会立刻触发弹层
   * 创建并渲染内容 —— 顺序反了的话，弹层第一帧会渲染到**上一次**那一组选项。
   */
  private openPopup(entry: SettingsEntry): void {
    this.popupPane = entry.pane;
    this.popupKey = entry.key;
  }

  /** 关掉弹层（选中一项、点面板外、或页面切走时都走这里） */
  private closePopup(): void {
    this.popupKey = '';
  }

  /**
   * 某一组设置的全部选项。三组共用 `buildOptions()` 的结构规则，
   * 档位文案从各自的来源取（`MaterialConfig` 带 `@kit.UIDesignKit`，
   * 进不了 `SettingsModel`，所以在这里拼）。
   */
  private optionsFor(pane: SettingsPane): SettingsOptionItem[] {
    if (pane === SettingsPane.SIGN_SETTINGS) {
      return buildOptions(['逐个签到', '官方签到', '混合签到'], signStrategyStore.strategy, 'sign_strategy');
    }
    if (pane === SettingsPane.FORUM_LEVEL) {
      return buildOptions(['简洁', '官方'], forumLevelStore.style, 'forum_level');
    }
    if (pane === SettingsPane.IMAGE_MENU) {
      return buildOptions(['常显胶囊', '长按显示'], this.smartReach.imageMenuLongPress ? 1 : 0, 'image_menu');
    }
    if (pane === SettingsPane.FORUM_DEFAULT_TAB) {
      return buildOptions(['热门', '最新'], forumDefaultTabStore.value, 'forum_default_tab');
    }
    if (pane === SettingsPane.IMAGE_LAYOUT) {
      return buildOptions([imageLayoutLabel(ImageLayoutMode.MODERN), imageLayoutLabel(ImageLayoutMode.CLASSIC)],
        imageLayoutStore.mode, 'image_layout');
    }
    if (pane === SettingsPane.MATERIAL) {
      return buildOptions(
        ALL_MODES.map((mode: MaterialMode): string => modeLabel(mode)),
        ALL_MODES.indexOf(materialManager.mode), 'material');
    }
    if (pane === SettingsPane.HDS_MATERIAL) {
      return buildOptions(ALL_HDS_LEVELS.map((level): string => hdsLevelLabel(level)),
        ALL_HDS_LEVELS.indexOf(materialManager.hdsLevel), 'hds_material');
    }
    if (pane === SettingsPane.ACTION_BAR) {
      return buildOptions(
        ALL_ACTION_BAR_STYLES.map((style: ThreadActionBarStyle): string => actionBarStyleLabel(style)),
        ALL_ACTION_BAR_STYLES.indexOf(threadActionBarStore.style), 'actionbar');
    }
    if (pane === SettingsPane.TOP_NAV) {
      /*
       * 仅提供官方沉浸（默认）与一体玻璃；按展示表取持久化值，不把下标当枚举值。
       */
      return buildOptions(
        ALL_HOME_TOP_NAV_OPTIONS.map((option: HomeTopNavOption): string => option.label),
        homeTopNavOptionIndexOf(homeTopNavStore.style), 'topnav');
    }
    if (pane === SettingsPane.DARK_MODE) {
      return buildOptions(
        ALL_THEME_MODE_PREFS.map((pref: ThemeModePref): string => themeModeLabel(pref)),
        ALL_THEME_MODE_PREFS.indexOf(themeModeStore.pref), 'darkmode');
    }
    if (pane === SettingsPane.FONT_SIZE) {
      return buildOptions(
        ALL_FONT_SIZE_PREFS.map((pref: FontSizePref): string => fontSizeLabel(pref)),
        ALL_FONT_SIZE_PREFS.indexOf(fontScaleStore.pref), 'fontsize');
    }
    return [];
  }

  /** 选中弹层里的第 `index` 项：按组分发到对应的单例，然后关掉弹层。 */
  private pickOption(pane: SettingsPane, index: number): void {
    if (pane === SettingsPane.IMAGE_LAYOUT) {
      if (index !== ImageLayoutMode.MODERN && index !== ImageLayoutMode.CLASSIC) { return; }
      void imageLayoutStore.setMode(index as ImageLayoutMode,
        this.getUIContext().getHostContext() as common.UIAbilityContext);
      this.closePopup(); return;
    }
    if (pane === SettingsPane.SIGN_SETTINGS) {
      if (index !== 0 && index !== 1 && index !== 2) { return; }
      void signStrategyStore.setStrategy(index, this.getUIContext().getHostContext() as common.UIAbilityContext)
        .catch((error: Error) => { this.getUIContext().getPromptAction().showToast({ message: error.message }); });
      this.closePopup(); return;
    }
    if (pane === SettingsPane.FORUM_LEVEL) {
      void forumLevelStore.setStyle(index, this.getUIContext().getHostContext() as common.UIAbilityContext)
        .catch((error: Error) => { this.getUIContext().getPromptAction().showToast({ message: error.message }); });
      this.closePopup(); return;
    }
    if (pane === SettingsPane.IMAGE_MENU) {
      if (index !== 0 && index !== 1) { return; }
      this.smartReach.setImageMenuLongPress(index === 1, this.getUIContext().getHostContext() as common.UIAbilityContext)
        .catch((error: Error): void => { promptAction.showToast({ message: error.message }); });
      this.closePopup(); return;
    }
    if (pane === SettingsPane.FORUM_DEFAULT_TAB) {
      if (index !== 0 && index !== 1) { return; }
      void forumDefaultTabStore.setValue(index as ForumDefaultTab,
        this.getUIContext().getHostContext() as common.UIAbilityContext)
        .catch((error: Error) => { this.getUIContext().getPromptAction().showToast({ message: error.message }); });
      this.closePopup(); return;
    }
    let openFontSheet: boolean = false;
    if (pane === SettingsPane.MATERIAL && index >= 0 && index < ALL_MODES.length) {
      this.pickMaterialMode(ALL_MODES[index]);
    } else if (pane === SettingsPane.ACTION_BAR
      && index >= 0 && index < ALL_ACTION_BAR_STYLES.length) {
      this.pickActionBarStyle(ALL_ACTION_BAR_STYLES[index]);
    } else if (pane === SettingsPane.TOP_NAV
      && index >= 0 && index < ALL_HOME_TOP_NAV_OPTIONS.length) {
      this.pickTopNavStyle(ALL_HOME_TOP_NAV_OPTIONS[index].value);
    } else if (pane === SettingsPane.DARK_MODE
      && index >= 0 && index < ALL_THEME_MODE_PREFS.length) {
      this.pickThemeMode(ALL_THEME_MODE_PREFS[index]);
    } else if (pane === SettingsPane.FONT_SIZE
      && index >= 0 && index < ALL_FONT_SIZE_PREFS.length) {
      this.pickFontSize(ALL_FONT_SIZE_PREFS[index]);
      openFontSheet = ALL_FONT_SIZE_PREFS[index] === FontSizePref.CUSTOM;
    }
    if (pane === SettingsPane.HDS_MATERIAL && index >= 0 && index < ALL_HDS_LEVELS.length) {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      void materialManager.setHdsLevel(ALL_HDS_LEVELS[index], context);
    }
    this.closePopup();
    if (openFontSheet) {
      this.fontSheetOpen = true;
    }
  }

  /**
   * 切换沉浸光感强度。
   *
   * 写的是全局单例 `materialManager`，持久化与失效广播都在里面：
   * 落盘成功后，所有**读到它**的组件（V2）下一帧就是新观感 —— 包括本页顶栏
   * 那枚返回按钮，所以选完关掉弹层就能看到顶栏变了。
   * 保存失败由 Store 暴露，当前分类页提供明确提示和重试。
   */
  private pickMaterialMode(mode: MaterialMode): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void materialManager.setMode(mode, context);
  }

  /** 切换帖子详情页底部操作栏样式（与 pickMaterialMode 同一条链路）。 */
  private pickActionBarStyle(style: ThreadActionBarStyle): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void threadActionBarStore.setStyle(style, context);
  }

  /** 切换首页顶栏样式（同一条链路）。 */
  private pickTopNavStyle(style: HomeTopNavStyle): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void homeTopNavStore.setStyle(style, context);
  }

  /** 三个「滑动时自动隐藏」开关：按部件写偏好。 */
  private setHidePart(part: HomeNavigationPart, checked: boolean): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void homeNavigationHideStore.set(part, checked, context);
  }

  /** 低流量模式（本机偏好；与三个隐藏开关**不是**同一个存储）。 */
  private setLowFlow(checked: boolean): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void lowFlowStore.setEnabled(checked, context);
  }

  /** 图像超分入口开关（本机偏好；又一个独立存储，只管查看器里那枚按钮的显隐）。 */
  private setSuperResolution(checked: boolean): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void superResolutionStore.setEnabled(checked, context);
  }

  /** 旧行渲染器里的开关分发（按稳定 action 串，不比较中文文案）。 */
  private applySwitchEntry(entry: SettingsEntry, checked: boolean): void {
    if (!entry.enabled) { return; }
    if (entry.action === 'home_compose_smart_reach') {
      this.smartReach.setHomeComposeEnabled(checked, this.getUIContext().getHostContext() as common.UIAbilityContext)
        .catch((error: Error): void => { promptAction.showToast({ message: error.message }); });
      return;
    }
    if (entry.action === 'forum_tabs_smart_reach' || entry.action === 'forum_tabs_floating') {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const saved: Promise<void> = entry.action === 'forum_tabs_smart_reach' ?
        this.smartReach.setForumTabsEnabled(checked, context) : this.smartReach.setForumTabsFloating(checked, context);
      saved.catch((error: Error): void => { promptAction.showToast({ message: error.message }); });
      return;
    }
    if (entry.action === 'image_menu_smart_reach') {
      this.smartReach.setImageMenuEnabled(checked, this.getUIContext().getHostContext() as common.UIAbilityContext)
        .catch((error: Error): void => { promptAction.showToast({ message: error.message }); });
      return;
    }
    if (entry.action === 'smart_reach') {
      this.smartReach.setEnabled(checked, this.getUIContext().getHostContext() as common.UIAbilityContext)
        .catch((error: Error): void => { promptAction.showToast({ message: error.message }); });
      return;
    }
    if (entry.action === 'low_flow') {
      this.setLowFlow(checked);
      return;
    }
    if (entry.action === 'super_resolution') {
      this.setSuperResolution(checked);
      return;
    }
    if (entry.action === 'hide_status_bar') {
      this.setHidePart(HomeNavigationPart.STATUS, checked);
      return;
    }
    if (entry.action === 'hide_top_navigation') {
      this.setHidePart(HomeNavigationPart.TOP, checked);
      return;
    }
    if (entry.action === 'hide_bottom_navigation') {
      this.setHidePart(HomeNavigationPart.BOTTOM, checked);
    }
  }

  private pickThemeMode(pref: ThemeModePref): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    themeModeStore.setMode(pref, context);
  }

  private pickFontSize(pref: FontSizePref): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    fontScaleStore.setPref(pref, context);
  }

  /**
   * 退出登录。先确认再执行：退出会让点赞等写操作立刻不可用，属于不可逆操作。
   * 失败如实提示（存储清理失败时内存态仍已清空，重启后可能仍是登录态——这点必须说清）。
   */
  private async confirmLogout(): Promise<void> {
    let confirmed: boolean = false;
    try {
      const answer: promptAction.ShowDialogSuccessResponse = await promptAction.showDialog({
        title: '退出登录',
        message: '退出后点赞等需要登录的操作将不可用，浏览不受影响。',
        buttons: [
          { text: '取消', color: AppTheme.TEXT_SUB },
          { text: '退出', color: AppTheme.ACCENT_DARK }
        ]
      });
      // buttons[1] 即"退出"
      confirmed = answer.index === 1;
    } catch (err) {
      // 弹窗不可用时不擅自退出，保持原状态
      return;
    }
    if (!confirmed) {
      return;
    }

    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const result: StoreResult = await authSession.logout(context);
    if (result.ok) {
      promptAction.showToast({ message: '已退出登录', duration: 1800 });
    } else {
      promptAction.showToast({
        message: `已退出，但本机凭据未清理干净（重启后可能仍是登录态）：${result.message}`,
        duration: 2600
      });
    }
  }

  private refreshCacheStats(): void {
    if (this.cacheBusy) { return; }
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    void this.cacheStats.refresh(context);
  }

  /**
   * 清理入口：**没有可清内容就直接说明**（不弹假确认框），有内容先二次确认。
   *
   * 统计中与读取失败都**不进入**这里 —— 阶段判定在 `cachePhaseCanClear()`：
   * 连占用都没读出来就提供"清理"，只会让用户点进去看到"没有可清理的内容"。
   */
  private async confirmClearCache(): Promise<void> {
    if (this.cacheBusy || !cachePhaseCanClear(this.cacheStats.phase)) {
      return;
    }
    let confirmed: boolean = false;
    try {
      const answer: promptAction.ShowDialogSuccessResponse = await promptAction.showDialog({
        title: '清理缓存',
        message: '将清理图片、导出临时文件及其他应用文件缓存，并停止当前音视频播放。'
          + '不会退出登录，不删除设置、浏览历史和已保存到相册的图片。缓存可在使用时重新生成。',
        buttons: [
          { text: '取消', color: AppTheme.TEXT_SUB },
          { text: '清理', color: AppTheme.ACCENT_DARK }
        ]
      });
      // buttons[1] 即"清理"
      confirmed = answer.index === 1;
    } catch (err) {
      // 弹窗不可用时不擅自清理，保持原状
      return;
    }
    if (!confirmed) {
      return;
    }

    this.cacheBusy = true;
    this.cacheStats.beginClear();
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const videoStopped: boolean = await videoPlayback.stop();
      const voiceStopped: boolean = await voicePlayback.stop();
      const result: ClearResult = videoStopped && voiceStopped ? await clearApplicationCache(context) : new ClearResult();
      if (!videoStopped || !voiceStopped) { result.failed += 1; }
      this.lastCleared = result.cleared;
      this.lastFailed = result.failed;
      this.lastFreedBytes = result.freedBytes;
    } finally {
      // 正常结束**自动重新统计**（回读成功就是"现在还剩多少"）；
      // 只有"删了一部分又删不掉"时才停在"部分完成"，因为那时剩余占用本身未确认。
      await this.cacheStats.refresh(this.getUIContext().getHostContext() as common.UIAbilityContext);
      this.cacheBusy = false;
      if (this.lastFailed > 0) {
        this.cacheStats.phase = CachePhase.PARTIAL_DONE;
      }
    }
  }

  /**
   * 卡片下面的结果与剩余说明：文案由纯逻辑 `cacheResultLines()` 给
   * （部分完成必须写明"剩余占用暂未确认"，**不宣称已清空**）。
   */
  @Builder
  CacheResultNotes() {
    ForEach(cacheResultLines(this.cacheStats.phase, this.lastCleared, this.lastFailed, this.lastFreedBytes),
      (line: string, index: number) => {
        SettingsNote({ text: line })
      }, (line: string, index: number) => `cache_line_${index}`)
  }

  /**
   * 「缓存清理」页（P2 第二个用公共组件的页面）：**一张卡**装名称 + 占用/阶段 + 简短说明
   * + 一个明确动作；结果与剩余状态放在卡片下方。
   * 统计中与读取失败**都不提供清理**，读取失败给就近重试。
   */
  @Builder
  CachePane() {
    SettingsCard({
      content: (): void => { this.CacheCardRows() }
    })
    SettingsNote({ text: '仅清理缓存，不会退出登录或删除设置、浏览历史和已保存的图片。占用可能稍后更新。' })
    this.CacheResultNotes()
  }

  @Builder
  CacheCardRows() {
    SettingsInfoRow({
      label: '应用缓存总量',
      sub: '由系统统计，包含图片导出缓存及其他应用缓存',
      value: this.cacheStats.label(),
      showDivider: true
    })
    if (this.cacheStats.failed) {
      SettingsStatusLine({
        kind: SettingsStatusKind.ERROR,
        message: '无法读取系统缓存总量',
        retryLabel: '重试',
        onRetry: (): void => { this.refreshCacheStats(); }
      })
    }
    SettingsInfoRow({
      label: '可清理的缓存文件',
      sub: '图片、导出临时文件及其他应用文件缓存',
      value: cachePhaseAmountLabel(this.cacheStats.phase, this.cacheStats.measure),
      showDivider: this.cacheStats.phase !== CachePhase.READ_FAIL && this.cacheStats.phase !== CachePhase.EMPTY
        && this.cacheStats.phase !== CachePhase.STATTING
    })
    if (this.cacheStats.phase === CachePhase.READ_FAIL) {
      SettingsStatusLine({
        kind: SettingsStatusKind.ERROR,
        message: '无法读取缓存占用',
        retryLabel: '重试',
        onRetry: (): void => {
          this.refreshCacheStats();
        }
      })
    } else if (this.cacheStats.phase === CachePhase.PARTIAL_DONE) {
      SettingsStatusLine({
        kind: SettingsStatusKind.ERROR,
        message: '部分缓存未能清理，请重新统计后重试',
        retryLabel: '重新统计',
        onRetry: (): void => { this.refreshCacheStats(); }
      })
    } else if (this.cacheStats.phase === CachePhase.CLEARING) {
      SettingsActionRow({ label: '正在清理…', busyLabel: '正在清理…', busy: true })
    } else if (cachePhaseCanClear(this.cacheStats.phase)) {
      SettingsActionRow({
        label: '清理缓存',
        onTap: (): void => {
          this.confirmClearCache();
        }
      })
    }
  }

  pageTransition() {
    // 不声明匹配项时沿用原生 router 转场；关闭时覆盖入、出两端。
    if (!motionStore.isOn(MotionEffect.MOVE)) {
      PageTransitionEnter({ duration: 0, curve: Curve.Linear })
      PageTransitionExit({ duration: 0, curve: Curve.Linear })
    }
  }

  build() {
    /*
     * ── 结构 ──
     * `Scroll` 占满全高（不为顶栏让位），玻璃顶栏 + 返回按钮悬浮其上（Stack 后声明者在上）。
     * 列表首项是一个与顶栏等高的占位 `Row` —— 参考图里第一张卡片的顶边**正好压在
     * 顶栏渐隐的终点**上，所以这里不留任何额外间距。
     */
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.pane === SettingsPane.FORBIDDEN_FORUMS) {
        ForbiddenForumsPane({ vm: this.forbiddenVm, scroller: this.scroller, topInset: this.titleBarH(),
          unblockSeq: this.forbiddenUnblockSeq, refreshSeq: this.paneRefreshSeq,
          onScrolled: (): void => { this.updateNavGlass(); } })
          .translate({ x: motionStore.isOn(MotionEffect.MOVE) ? this.paneOffset : 0 })
          .opacity(motionStore.isOn(MotionEffect.FADE) ? this.paneOpacity : 1)
      } else {
      Scroll(this.scroller) {
        Column() {
          // 顶栏占位：让首张卡片的顶边与顶栏渐隐终点齐平
          Row()
            .width('100%')
            .height(this.titleBarH())

          Column() {
            if (this.pane === SettingsPane.NONE) {
              this.EntryList()
            } else {
              this.PaneBody()
            }
          }
          .width('100%')
          .padding({ left: SettingsLayout.PAGE_GUTTER, right: SettingsLayout.PAGE_GUTTER })
          // 内容布局变化 = 真正就绪的信号（不用 setTimeout 猜）
          .onAreaChange((_o: Area, n: Area) => {
            // 记录内容实际高度供接近底部判定；内容变高 = 自动补页有了新进展
            const contentH: number = Number(n.height);

            this.paneContentH = contentH;
            this.autoLoadMore(false);
            this.applyPendingRestore();
          })
          // 底部间距放在滚动内容内，滑到底后末卡不贴屏幕边缘。
        }
        .width('100%')
        .padding({ bottom: SettingsLayout.PAGE_BOTTOM_GAP })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .translate({ x: motionStore.isOn(MotionEffect.MOVE) ? this.paneOffset : 0 })
      .opacity(motionStore.isOn(MotionEffect.FADE) ? this.paneOpacity : 1)
      .align(Alignment.Top)
      // 记录视口高度供接近底部判定（Scroller 没有视口尺寸 API）
      .onAreaChange((_o: Area, n: Area) => {
        this.viewportH = Number(n.height);
        this.autoLoadMore(false);
      })
      // 顶栏玻璃层跟随滚动渐显（阈值集中定义，见 updateNavGlass）

      .onReachEnd(() => {
        this.autoLoadMore(true);
      })
      .onScroll(() => {
        this.updateNavGlass();
        this.autoLoadMore(false);
      })
      }

      // 顶栏：悬浮层，最后声明 → 盖在内容层之上
      this.TitleBar()

      Row() {
        if (this.pane === SettingsPane.FORBIDDEN_FORUMS && this.forbiddenVm.selecting) {
          GlassCircleButton({ symbol: $r('sys.symbol.xmark'), iconWeight: FontWeight.Regular,
            accessibilityLabel: this.forbiddenVm.executing ? '停止取消屏蔽' : '退出多选',
            onTap: (): void => { this.goBack(); } }).enabled(!this.forbiddenVm.actionBusy || this.forbiddenVm.executing)
        } else {
          GlassBackButton({ onTap: (): void => { this.goBack(); } })
        }
      }
      .margin({ left: 14, top: this.statusBarH + 8 })

      if (this.pane === SettingsPane.FORBIDDEN_FORUMS) {
        Row({ space: 10 }) {
          if (this.forbiddenVm.selecting) {
            GlassPillButton({ label: this.forbiddenVm.allSelected() ? '取消全选' : '全选',
              pillWidth: this.forbiddenVm.allSelected() ? 88 : 64,
              active: !this.forbiddenVm.actionBusy && !this.forbiddenVm.loading && !this.forbiddenVm.loadingMore,
              onTap: (): void => { void this.forbiddenVm.toggleAll(this.getUIContext().getHostContext() as common.UIAbilityContext); } })
          } else {
            GlassPillButton({ label: '多选', pillWidth: 64,
              active: !this.forbiddenVm.actionBusy && !this.forbiddenVm.loading && !this.forbiddenVm.loadingMore && this.forbiddenVm.items.length > 0,
              onTap: (): void => { this.forbiddenVm.toggleSelection(); } })
          }
        }.width('100%').justifyContent(FlexAlign.End).padding({ right: 14 })
          .hitTestBehavior(HitTestMode.Transparent)
          .margin({ top: this.statusBarH + 8 })
        if (this.forbiddenVm.selecting) {
          Row() {
            GlassCircleButton({ symbol: $r('sys.symbol.trash'), iconWeight: FontWeight.Regular,
              accessibilityLabel: '取消所选屏蔽', diameter: 56, iconSize: 24, slot: MaterialSlot.BOTTOM_BAR,
              onTap: (): void => { this.forbiddenUnblockSeq++; } })
              .enabled(this.forbiddenVm.selectedIds.length > 0 && !this.forbiddenVm.actionBusy && !this.forbiddenVm.loading && !this.forbiddenVm.loadingMore)
              .opacity(this.forbiddenVm.selectedIds.length > 0 && !this.forbiddenVm.actionBusy ? 1 : 0.4)
          }.width('100%').justifyContent(FlexAlign.Center).hitTestBehavior(HitTestMode.Transparent)
            .position({ x: 0, y: '100%' }).translate({ y: -84 })
        }
      }

      /*
       * 头像裁剪页：全屏浮层，盖在设置页所有内容之上（含顶栏与返回按钮）。
       * 与看图器同一模式 —— 这里只管开关，倍率/位移/裁剪换算都由 `AvatarCropPage` 自己持有。
       */
      if (this.cropOpen) {
        AvatarCropPage({
          uri: this.avatarVm.sourceUri(),
          sourceWidth: this.avatarVm.sourceWidthPx(),
          sourceHeight: this.avatarVm.sourceHeightPx(),
          statusBarH: this.statusBarH,
          onCancel: (): void => {
            this.cropOpen = false;
          },
          onDone: (crop: AvatarCrop): void => {
            this.cropOpen = false;
            this.commitAvatarCrop(crop);
          }
        })
          .zIndex(100)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG)
    .bindSheet(this.fontSheetOpen, this.FontSizeSheet(), {
      height: 180,
      dragBar: true,
      showClose: false,
      backgroundColor: AppTheme.BG,
      onDisappear: (): void => {
        this.fontSheetOpen = false;
      }
    })
  }

  @Builder
  FontSizeSheet() {
    Column() {
      Row() {
        Text('字体大小')
          .fontSize(18)
          .fontColor(AppTheme.TEXT_MAIN)
          .layoutWeight(1)
        Text(`${fontScaleStore.customSize} fp`)
          .fontSize(18)
          .fontColor(AppTheme.TEXT_MAIN)
      }
      .width('100%')
      .margin({ bottom: 28 })

      Row() {
        Text('A').fontSize(18).fontColor(AppTheme.TEXT_MAIN)
        Slider({ value: fontScaleStore.customSize, min: FONT_SIZE_MIN, max: FONT_SIZE_MAX, step: 1,
          style: SliderStyle.InSet })
          .systemMaterial(sliderMaterial())
          .layoutWeight(1)
          .selectedColor(AppTheme.ACCENT)
          .onChange((value: number, mode: SliderChangeMode): void => {
            const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
            fontScaleStore.setCustomSize(value, context,
              mode !== SliderChangeMode.Begin && mode !== SliderChangeMode.Moving);
            if (mode !== SliderChangeMode.Begin && mode !== SliderChangeMode.Moving &&
              fontScaleStore.saveError.length > 0) {
              this.getUIContext().getPromptAction().showToast({ message: fontScaleStore.saveError });
            }
          })
          .margin({ left: 12, right: 12 })
        Text('A').fontSize(30).fontColor(AppTheme.TEXT_MAIN)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 26 })
  }

  // ── 入口列表 ────────────────────────────────────────────────────────────

  private homeIconOf(key: string): Resource | undefined {
    switch (key) {
      case 'appearance':
        return $r('sys.symbol.sun');
      case 'browsing':
        return $r('sys.symbol.rectangle_grid_1x2');
      case 'messages':
        return $r('sys.symbol.message');

      case 'interaction':
        return $r('sys.symbol.gearshape');
      case 'posting':
        return $r('sys.symbol.personalized_sticker');
      case 'cache_clean':
        return $r('sys.symbol.trash');
      case 'permissions':
        return $r('sys.symbol.checkmark_shield');
      case 'about':
        return $r('sys.symbol.info_circle');
      default:
        return undefined;
    }
  }

  private accountTitle(): string {
    if (!authSession.snapshot.isLoggedIn()) {
      return '登录贴吧账号';
    }
    return authSession.snapshot.nickname.length > 0 ? authSession.snapshot.nickname : '未设置昵称';
  }

  private accountSubtitle(): string {
    return authSession.snapshot.isLoggedIn() ? '已登录 · 账号与资料' : '登录后可查看资料与账号设置';
  }

  @Builder
  AccountCard() {
    Column() {
      Row({ space: 12 }) {
        AvatarComponent({
          url: portraitUrl(authSession.snapshot.portrait, authSession.avatarRevision),
          avatarSize: 48,
          fallbackName: authSession.snapshot.nickname,
          traceTag: 'settings-account-card'
        })
        Column({ space: 3 }) {
          Text(this.accountTitle())
            .fontSize(SettingsLayout.LABEL_SIZE)
            .fontColor(AppTheme.TEXT_MAIN)
            .width('100%')
          Text(this.accountSubtitle())
            .fontSize(SettingsLayout.SUB_SIZE)
            .fontColor(AppTheme.NOTE_TEXT)
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(SettingsLayout.CHEVRON_SIZE).maxFontScale(1)
          .fontColor([AppTheme.CHEVRON_TINT])
          .margin({ right: SettingsLayout.CHEVRON_INSET })
      }
      .width('100%')
      .constraintSize({ minHeight: SettingsLayout.ACCOUNT_ROW_MIN_H })
      .padding({
        left: SettingsLayout.ROW_PAD_L, right: SettingsLayout.ROW_PAD_R,
        top: SettingsLayout.ROW_PAD_V, bottom: SettingsLayout.ROW_PAD_V
      })
      .onClick(() => {
        this.navigateTo(SettingsPane.ACCOUNT);
      })
      .id('settings-account')
    }
    .width('100%')
    .backgroundColor(AppTheme.CARD)
    .borderRadius(SettingsLayout.CARD_RADIUS)
    .clip(true)
  }

  @Builder
  EntryList() {

    this.AccountCard()
    ForEach(this.groups(), (group: SettingsGroup, index: number) => {
      this.HomeGroup(group)
    }, (group: SettingsGroup) => settingsGroupRenderKey(group))
  }

  /** 首页的一个分组：只把该组的入口行摊平（无标题、无整卡），分组顺序仍由模型给出。 */
  @Builder
  HomeGroup(group: SettingsGroup) {
    ForEach(group.entries, (entry: SettingsEntry, index: number) => {
      this.HomeRow(entry)
    }, (entry: SettingsEntry) => settingsEntryRenderKey(entry))
  }

  /**
   * 首页的一个入口行：**自己就是一张卡**（圆角 + 卡底 + 裁剪），行间 10vp。
   *
   * 不再靠外层 `SettingsCard` 提供底色 —— 一层 `Column` 只是承载卡面属性的壳，
   * 行内组件照旧读 `SettingsLayout` 的高度/内距，分隔线恒为 `false`（一卡一行）。
   */
  @Builder
  HomeRow(entry: SettingsEntry) {
    Column() {
      SettingsEntryRow({
        label: entry.label,
        summary: entry.value,
        icon: this.homeIconOf(entry.key),
        showDivider: false,
        onTap: (): void => {
          this.onEntry(entry);
        }
      })
    }
    .width('100%')
    .backgroundColor(AppTheme.CARD)
    .borderRadius(SettingsLayout.CARD_RADIUS)
    .clip(true)
    .margin({ top: SettingsLayout.ROW_GAP })
    .id(`settings-home-${entry.key}`)
  }

  // ── 分类与内容页 ───────────────────────────────────────────────────────

  @Builder
  PaneBody() {
    if (this.pane === SettingsPane.ABOUT) {
      this.AboutPane()
    } else if (this.pane === SettingsPane.VERSION) {
      this.VersionPane()
    } else if (this.pane === SettingsPane.ACCOUNT) {
      this.AccountPane()
    } else if (this.pane === SettingsPane.DATA_USE) {
      this.DataUsePane()
    } else if (this.pane === SettingsPane.SIGN_SETTINGS) {
      this.SignSettingsPane()
    } else {
      this.CategoryPane()
    }
    this.PrefSaveErrors()
  }

  /** 只在发生保存错误时显示；重试保存当前选择，不重置偏好。 */
  @Builder
  PrefSaveErrors() {
    if (this.pane === SettingsPane.APPEARANCE) {
      if (themeModeStore.saveError.length > 0) {
        SettingsStatusLine({ kind: SettingsStatusKind.ERROR,
          message: themeModeStore.saveError, retryLabel: '重试保存',
          onRetry: (): void => {
            themeModeStore.retrySave(this.getUIContext().getHostContext() as common.UIAbilityContext);
          } })
      }
      if (fontScaleStore.saveError.length > 0) {
        SettingsStatusLine({ kind: SettingsStatusKind.ERROR,
          message: fontScaleStore.saveError, retryLabel: '重试保存',
          onRetry: (): void => {
            fontScaleStore.retrySave(this.getUIContext().getHostContext() as common.UIAbilityContext);
          } })
      }
    } else if (this.pane === SettingsPane.NAVIGATION_LAYOUT) {
      if (homeTopNavStore.saveError.length > 0) {
        SettingsStatusLine({ kind: SettingsStatusKind.ERROR,
          message: homeTopNavStore.saveError, retryLabel: '重试保存',
          onRetry: (): void => {
            void homeTopNavStore.retrySave(this.getUIContext().getHostContext() as common.UIAbilityContext);
          } })
      }
      if (threadActionBarStore.saveError.length > 0) {
        SettingsStatusLine({ kind: SettingsStatusKind.ERROR,
          message: threadActionBarStore.saveError, retryLabel: '重试保存',
          onRetry: (): void => {
            void threadActionBarStore.retrySave(this.getUIContext().getHostContext() as common.UIAbilityContext);
          } })
      }
      if (homeNavigationHideStore.saveError.length > 0) {
        SettingsStatusLine({ kind: SettingsStatusKind.ERROR,
          message: homeNavigationHideStore.saveError, retryLabel: '重试保存',
          onRetry: (): void => {
            void homeNavigationHideStore.retrySave(this.getUIContext().getHostContext() as common.UIAbilityContext);
          } })
      }
    } else if (this.pane === SettingsPane.BROWSING) {
      if (imageLayoutStore.loadError.length > 0) {
        SettingsStatusLine({ kind: SettingsStatusKind.ERROR,
          message: imageLayoutStore.loadError, retryLabel: '重新读取',
          onRetry: (): void => {
            void imageLayoutStore.load(this.getUIContext().getHostContext() as common.UIAbilityContext);
          } })
      }
      if (imageLayoutStore.saveError.length > 0) {
        SettingsStatusLine({ kind: SettingsStatusKind.ERROR,
          message: imageLayoutStore.saveError, retryLabel: '重试保存',
          onRetry: (): void => {
            void imageLayoutStore.retrySave(this.getUIContext().getHostContext() as common.UIAbilityContext);
          } })
      }
      if (lowFlowStore.saveError.length > 0) {
        SettingsStatusLine({ kind: SettingsStatusKind.ERROR,
          message: lowFlowStore.saveError, retryLabel: '重试保存',
          onRetry: (): void => {
            void lowFlowStore.retrySave(this.getUIContext().getHostContext() as common.UIAbilityContext);
          } })
      }
      if (superResolutionStore.saveError.length > 0) {
        SettingsStatusLine({ kind: SettingsStatusKind.ERROR,
          message: superResolutionStore.saveError, retryLabel: '重试保存',
          onRetry: (): void => {
            void superResolutionStore.retrySave(this.getUIContext().getHostContext() as common.UIAbilityContext);
          } })
      }
    } else if (this.pane === SettingsPane.MATERIAL_EFFECTS && materialManager.saveError.length > 0) {
      SettingsStatusLine({ kind: SettingsStatusKind.ERROR,
        message: materialManager.saveError, retryLabel: '重试保存',
        onRetry: (): void => {
          void materialManager.retrySave(this.getUIContext().getHostContext() as common.UIAbilityContext);
        } })
    }
  }

  @Builder
  CategoryPane() {
    if (this.pane === SettingsPane.BROWSING) {
      this.BrowsingPane()
    } else if (this.pane === SettingsPane.NAVIGATION_LAYOUT) {
      this.NavigationLayoutPane()
    } else if (this.pane === SettingsPane.MATERIAL_EFFECTS) {
      this.MaterialEffectsPane()
    } else if (this.pane === SettingsPane.INTERACTION) {
      this.InteractionPane()
    } else if (this.pane === SettingsPane.POSTING) {
      this.PostingPane()
    } else if (this.pane === SettingsPane.PRIVACY_SETTINGS) {
      this.PrivacyPane()
    } else if (this.pane === SettingsPane.MOTION) {
      MotionSettingsPane()
    } else if (this.pane === SettingsPane.MESSAGE) {
      MessageSettingsPane({
        onOpenOfficial: (): void => { this.navigateTo(SettingsPane.OFFICIAL_MESSAGES); }
      })
    } else if (this.pane === SettingsPane.OFFICIAL_MESSAGES) {
      OfficialMessagesPane()
    } else if (this.pane === SettingsPane.TAILS) {
      TailsPane()
    } else if (this.pane === SettingsPane.BLOCK_MANAGE) {
      BlockManagePane()
    } else if (this.pane === SettingsPane.HIDDEN_THREADS) {
      BlockManagePane({ hiddenThreads: true })
    } else if (this.pane === SettingsPane.PRIVACY_MARKS) {
      PrivacyMarksPane()
    } else if (this.pane === SettingsPane.IMAGE_WATERMARK) {
      ImageWatermarkPane()
    } else if (this.pane === SettingsPane.APP_PERMISSIONS) {
      AppPermissionsPane({ refreshSeq: this.paneRefreshSeq })
    } else if (this.pane === SettingsPane.APPEARANCE) {
      this.AppearancePane()
    } else if (this.pane === SettingsPane.CACHE) {
      this.CachePane()
    }
  }

  @Builder
  SignSettingsPane() {
    SettingsCard({
      content: (): void => { this.SignSettingsRows() }
    })
    if (signStrategyStore.strategy === 1) {
      SettingsNote({ text: '官方签到有等级限制，不符合条件的吧可改用逐个签到。' })
    } else if (signStrategyStore.strategy === 2) {
      SettingsNote({ text: '7级及以上使用官方批量签到，低于7级逐个签到；等级或官方条件未确认的吧会跳过并提示。' })
    }
  }

  @Builder
  SignSettingsRows() {
    SettingsOptionRow({
      label: '签到方案',
      value: signStrategyStore.strategy === 2 ? '混合签到' : (signStrategyStore.strategy === 1 ? '官方签到' : '逐个签到'),
      popupOpen: this.popupKey === 'sign_strategy',
      items: this.optionsFor(SettingsPane.SIGN_SETTINGS),
      onTap: (): void => { this.openPanePopup('sign_strategy', SettingsPane.SIGN_SETTINGS); },
      onPick: (index: number): void => { this.pickOption(SettingsPane.SIGN_SETTINGS, index); },
      onPopupClosed: (): void => { this.closePopup(); }
    })
  }

  /** 打开某一组选项弹层（按稳定 key 标记是哪一行，保证同时只有一层）。 */
  private openPanePopup(key: string, pane: SettingsPane): void {
    this.popupPane = pane;
    this.popupKey = key;
  }

  @Builder
  AppearancePane() {
    SettingsCard({
      content: (): void => { this.AppearanceRows() }
    })
    Row({ space: 10 }) {
      Text('等级标签预览').fontSize(SettingsLayout.SUB_SIZE).fontColor(AppTheme.NOTE_TEXT)
      ForumLevelBadge({ level: 8, levelName: '核心会员' })
    }.width('100%').margin({ top: 12 })
    SettingsCard({
      marginTop: SettingsLayout.GROUP_GAP,
      content: (): void => {
        this.CategoryRows(SettingsPane.APPEARANCE, ['navigation_layout', 'material_effects'])
      }
    })
  }

  @Builder
  AppearanceRows() {
    SettingsOptionRow({
      label: '视觉主题', value: visualThemeLabel(visualThemeStore.theme),
      popupOpen: this.popupKey === 'visual_theme',
      items: buildOptions(ALL_VISUAL_THEMES.map((theme: VisualTheme): string => visualThemeLabel(theme)),
        ALL_VISUAL_THEMES.indexOf(visualThemeStore.theme), 'visual_theme'),
      onTap: (): void => { this.popupKey = this.popupKey === 'visual_theme' ? '' : 'visual_theme'; },
      onPick: (index: number): void => {
        if (!Number.isInteger(index) || index < 0 || index >= ALL_VISUAL_THEMES.length) { return; }
        const saved: boolean = visualThemeStore.setTheme(ALL_VISUAL_THEMES[index],
          this.getUIContext().getHostContext() as common.UIAbilityContext);
        this.closePopup();
        if (!saved) { this.getUIContext().getPromptAction().showToast({ message: '主题未能保存，请重试' }); }
      },
      onPopupClosed: (): void => { this.closePopup(); }
    })
    SettingsOptionRow({
      label: '深色模式',
      value: themeModeLabel(themeModeStore.pref),
      popupOpen: this.popupKey === 'dark_mode',
      items: this.optionsFor(SettingsPane.DARK_MODE),
      onTap: (): void => {
        this.openPanePopup('dark_mode', SettingsPane.DARK_MODE);
      },
      onPick: (index: number): void => {
        this.pickOption(SettingsPane.DARK_MODE, index);
      },
      onPopupClosed: (): void => {
        this.closePopup();
      }
    })
    SettingsOptionRow({
      label: '字体大小',
      value: fontSizeLabel(fontScaleStore.pref),
      popupOpen: this.popupKey === 'font_size',
      items: this.optionsFor(SettingsPane.FONT_SIZE),
      onTap: (): void => {
        this.openPanePopup('font_size', SettingsPane.FONT_SIZE);
      },
      onPick: (index: number): void => {
        this.pickOption(SettingsPane.FONT_SIZE, index);
      },
      onPopupClosed: (): void => {
        this.closePopup();
      }
    })
    SettingsOptionRow({
      label: '吧等级标签', value: forumLevelStore.style === 1 ? '官方' : '简洁',
      showDivider: false, popupOpen: this.popupKey === 'forum_level',
      items: this.optionsFor(SettingsPane.FORUM_LEVEL),
      onTap: (): void => { this.openPanePopup('forum_level', SettingsPane.FORUM_LEVEL); },
      onPick: (index: number): void => { this.pickOption(SettingsPane.FORUM_LEVEL, index); },
      onPopupClosed: (): void => { this.closePopup(); }
    })
  }

  @Builder
  AccountPane() {
    if (!authSession.snapshot.isLoggedIn()) {
      SettingsCard({
        content: (): void => { this.AccountLoginRow() }
      })
    } else {
      SettingsCard({
        content: (): void => { this.AccountAvatarRows() }
      })
      if (this.avatarFlowNote().length > 0) {
        SettingsNote({ text: this.avatarFlowNote() })
      }
      SettingsCard({
        marginTop: SettingsLayout.GROUP_GAP,
        content: (): void => { this.AccountInfoRows() }
      })
      SettingsCard({
        marginTop: SettingsLayout.GROUP_GAP,
        content: (): void => { this.AccountDangerRow() }
      })
    }
  }

  @Builder
  AccountAvatarRows() {
    this.AccountAvatarRow()
    if (this.avatarVm.error.length > 0) {
      Divider()
        .color(AppTheme.DIVIDER)
        .strokeWidth(0.5)
        .margin({ left: SettingsLayout.ROW_PAD_L })
      SettingsStatusLine({
        kind: SettingsStatusKind.ERROR,
        message: this.avatarVm.error,
        retryLabel: '重试',
        onRetry: (): void => {
          this.startAvatarEdit();
        }
      })
    }
  }

  /**
   * 点「修改」：开系统图库**只选图**（系统「编辑」入口已关，见 `pickAvatarImage`），
   * 选完进本页自己的裁剪页；点裁剪页「完成」才上传（`commitAvatarCrop`）。
   * 取消选图不发任何请求；进行中或裁剪页已开时不重入。
   */
  private startAvatarEdit(): void {
    if (this.avatarVm.busy || this.avatarVm.preparing || this.cropOpen) { return; }
    void this.pickAvatarForCrop();
  }

  /** 选图成功后开裁剪页；取消选图（`ready` 仍为 false）什么都不做。 */
  private async pickAvatarForCrop(): Promise<void> {
    await this.avatarVm.select();
    if (!this.avatarVm.ready || this.avatarVm.sourceUri().length === 0) { return; }
    if (this.avatarVm.sourceWidthPx() <= 0 || this.avatarVm.sourceHeightPx() <= 0) { return; }
    this.cropOpen = true;
  }

  /** 裁剪页「完成」：用同一张原图与用户框定的区域换出 960×960，再走既有上传与读回。 */
  private commitAvatarCrop(crop: AvatarCrop): void {
    void this.uploadCroppedAvatar(crop);
  }

  private async uploadCroppedAvatar(crop: AvatarCrop): Promise<void> {
    const uri: string = this.avatarVm.sourceUri();
    if (uri.length === 0) { return; }
    await this.avatarVm.prepare(uri, crop);
    if (!this.avatarVm.ready || this.avatarVm.error.length > 0) { return; }
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    await this.avatarVm.confirmUpload(context);
  }

  /** 头像行右侧文案：进行中如实显示阶段，空闲仍是「修改」。 */
  private avatarActionLabel(): string {
    if (this.avatarVm.preparing) { return '选择中…'; }
    if (this.avatarVm.submitting) { return '上传中…'; }
    if (this.avatarVm.syncing) { return '读取中…'; }
    return '修改';
  }

  /**
   * 头像流程的说明行：只写服务端已经发生的事。
   * 「已接收」「审核中」「读回是否看到变化」分开说，绝不把候选图说成已生效头像。
   */
  private avatarFlowNote(): string {
    const lines: string[] = [];
    if (this.avatarVm.received) {
      lines.push(this.avatarVm.pendingReview ? '已上传，审核中，当前头像尚未更新。' : '服务端已接收本次上传。');
    }
    if (this.avatarVm.pendingReview) {
      lines.push('审核通过前，「我的」与本人主页仍显示服务端当前生效的头像。');
    }
    if (this.avatarVm.profileRead) {
      lines.push(this.avatarVm.portraitChanged ? '已读到当前账号头像记录变化。' : '当前账号头像记录尚未变化。');
    }
    if (this.avatarVm.note.length > 0) { lines.push(this.avatarVm.note); }
    return lines.join('\n');
  }

  @Builder
  AccountLoginRow() {
    SettingsActionRow({
      label: '登录贴吧账号',
      onTap: (): void => {
        router.pushUrl({ url: 'pages/Login' });
      }
    })
  }

  /** 头像行：头像缩略图 + 「头像」+ 右侧阶段文案 + 箭头（点它开系统图库选图）。 */
  @Builder
  AccountAvatarRow() {
    Row({ space: 12 }) {
      AvatarComponent({
        url: portraitUrl(authSession.snapshot.portrait, authSession.avatarRevision),
        avatarSize: 48,
        fallbackName: authSession.snapshot.nickname,
        traceTag: 'settings-account-avatar'
      })
      Text('头像')
        .fontSize(SettingsLayout.LABEL_SIZE)
        .fontColor(AppTheme.TEXT_MAIN)
        .layoutWeight(1)
      Text(this.avatarActionLabel())
        .fontSize(SettingsLayout.VALUE_SIZE)
        .fontColor(AppTheme.VALUE_TEXT)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(SettingsLayout.CHEVRON_SIZE)
        .fontColor([AppTheme.CHEVRON_TINT])
        .margin({ right: SettingsLayout.CHEVRON_INSET })
    }
    .width('100%')
    .constraintSize({ minHeight: SettingsLayout.ACCOUNT_ROW_MIN_H })
    .padding({
      left: SettingsLayout.ROW_PAD_L, right: SettingsLayout.ROW_PAD_R,
      top: SettingsLayout.ROW_PAD_V, bottom: SettingsLayout.ROW_PAD_V
    })
    .onClick(() => {
      this.startAvatarEdit();
    })
  }

  @Builder
  AccountInfoRows() {
    SettingsInfoRow({ label: '昵称', value: this.accountNickname() })
    SettingsInfoRow({
      label: '贴吧 ID',
      value: authSession.snapshot.userName.length > 0 ? authSession.snapshot.userName : '—'
    })
    SettingsInfoRow({
      label: '用户 ID',
      value: authSession.snapshot.uid > 0 ? `${authSession.snapshot.uid}` : '—',
      showDivider: false
    })
  }

  private accountNickname(): string {
    return authSession.snapshot.nickname.length > 0 ? authSession.snapshot.nickname : '—';
  }

  @Builder
  AccountDangerRow() {
    SettingsActionRow({
      label: '退出登录',
      tone: SettingsActionTone.DANGER,
      onTap: (): void => {
        this.confirmLogout();
      }
    })
  }

  // ── 弹出式选项菜单 ──────────────────────────────────────────────────────

  /**
   * 「关于贴吧Ark」：应用图标与名称 + 版本 + VersionCode + GitHub 链接。
   *
   * VersionCode 直接显示在本页；
   * 「数据与隐私」已升为首页分组标题，这里不再挂旧入口。
   */
  @Builder
  AboutPane() {
    Column() {
      Column({ space: 12 }) {
        Image($r('app.media.app_icon'))
          .width(72)
          .height(72)
          .borderRadius(18)
          .objectFit(ImageFit.Cover)
        Text($r('app.string.app_name'))
          .fontSize(SettingsLayout.TITLE_SIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT_MAIN)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .margin({ top: 20, bottom: 24 })

      SettingsCard({
        content: (): void => { this.AboutRows() }
      })
    }
    .width('100%')
  }

  @Builder
  AboutRows() {
    SettingsInfoRow({ label: '版本', value: SETTINGS_APP_VERSION })
    SettingsInfoRow({ label: 'VersionCode', value: SETTINGS_VERSION_CODE })
    SettingsEntryRow({
      label: 'GitHub',
      showDivider: false,
      onTap: (): void => {
        this.confirmOpenGitHub();
      }
    })
  }

  /** 用户确认后才离开应用打开项目主页；取消或弹窗失败时保持在本页。 */
  private async confirmOpenGitHub(): Promise<void> {
    let confirmed: boolean = false;
    try {
      const answer: promptAction.ShowDialogSuccessResponse = await promptAction.showDialog({
        title: '前往 GitHub',
        message: '即将前往浏览器打开项目主页。',
        buttons: [
          { text: '取消', color: AppTheme.TEXT_SUB },
          { text: '确定', color: AppTheme.ACCENT_DARK }
        ]
      });
      confirmed = answer.index === 1;
    } catch (err) {
      return;
    }
    if (!confirmed) { return; }
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    context.openLink('https://github.com/Gm0201/TiebaArk').catch(() => {
      promptAction.showToast({ message: '无法打开项目主页', duration: 1800 });
    });
  }

  @Builder
  DataUsePane() {
    SettingsCard({
      content: (): void => { this.DataUseRows() }
    })
  }

  @Builder
  DataUseRows() {
    Column({ space: 14 }) {
      ForEach(aboutNotes(), (note: string, index: number) => {
        Text(note)
          .fontSize(SettingsLayout.SUB_SIZE)
          .fontColor(AppTheme.NOTE_TEXT)
          .lineHeight(20)
          .width('100%')
      }, (note: string, index: number) => `data_use_${index}`)
    }
    .width('100%')
    .padding(SettingsLayout.ROW_PAD_L)
  }

  /** 「版本详情」：版本 / 版本代码 / 目标平台（关于首页只留版本号）。 */
  @Builder
  VersionPane() {
    SettingsCard({
      content: (): void => { this.VersionRows() }
    })
  }

  @Builder
  VersionRows() {
    ForEach(aboutItems(), (item: SettingsAboutItem, index: number) => {
      SettingsInfoRow({
        label: item.label,
        value: item.value,
        showDivider: index < aboutItems().length - 1
      })
    }, (item: SettingsAboutItem) => `version_${item.label}`)
  }

  @Builder
  BrowsingPane() {
    SettingsGroupTitle({ title: '内容浏览' })
    SettingsCard({
      content: (): void => {
        this.CategoryRows(SettingsPane.BROWSING, ['forum_default_tab', 'image_layout', 'low_flow'])
      }
    })
    SettingsGroupTitle({ title: '看图' })
    SettingsCard({
      content: (): void => {
        this.CategoryRows(SettingsPane.BROWSING, ['image_menu', 'super_resolution'])
      }
    })
  }

  @Builder
  MaterialEffectsPane() {
    SettingsCard({
      content: (): void => {
        this.CategoryRows(SettingsPane.MATERIAL_EFFECTS, ['material_mode', 'hds_material_level'])
      }
    })
    SettingsNote({ text: materialManager.useArkUI
      ? '兼容材质效果仅在不支持沉浸材质的设备上生效。'
      : '当前设备使用兼容材质效果。' })
  }

  @Builder
  NavigationLayoutPane() {
    SettingsGroupTitle({ title: '导航样式' })
    SettingsCard({
      content: (): void => {
        this.CategoryRows(SettingsPane.NAVIGATION_LAYOUT, ['home_top_nav_style'])
      }
    })
    this.HomeTopNavPreview()
    SettingsCard({
      marginTop: SettingsLayout.GROUP_GAP,
      content: (): void => {
        this.CategoryRows(SettingsPane.NAVIGATION_LAYOUT, ['action_bar_style'])
      }
    })
    if (visualThemeStore.isPaper) {
      SettingsNote({ text: '切换到经典鸿蒙可自定义顶栏和底栏样式。' })
    }
    SettingsGroupTitle({ title: '分类显示' })
    SettingsCard({
      content: (): void => {
        this.CategoryRows(SettingsPane.NAVIGATION_LAYOUT, ['forum_tabs_floating'])
      }
    })
    SettingsGroupTitle({ title: '首页滑动隐藏' })
    SettingsCard({
      content: (): void => {
        this.CategoryRows(SettingsPane.NAVIGATION_LAYOUT,
          ['hide_status_bar', 'hide_top_navigation', 'hide_bottom_navigation'])
      }
    })
    SettingsNote({ text: '上滑隐藏，下滑恢复。' })
  }

  @Builder
  InteractionPane() {
    SettingsGroupTitle({ title: '单手操作' })
    SettingsCard({
      content: (): void => {
        this.CategoryRows(SettingsPane.INTERACTION,
          ['smart_reach', 'home_compose_smart_reach', 'forum_tabs_smart_reach', 'image_menu_smart_reach'])
      }
    })
    SettingsCard({
      marginTop: SettingsLayout.GROUP_GAP,
      content: (): void => { this.CategoryRows(SettingsPane.INTERACTION, ['motion']) }
    })
  }

  @Builder
  PostingPane() {
    SettingsGroupTitle({ title: '发布与身份' })
    SettingsCard({
      content: (): void => {
        this.CategoryRows(SettingsPane.POSTING, ['image_watermark', 'tails', 'privacy_marks'])
      }
    })
    SettingsGroupTitle({ title: '签到' })
    SettingsCard({
      content: (): void => { this.CategoryRows(SettingsPane.POSTING, ['sign_settings']) }
    })
  }

  @Builder
  PrivacyPane() {
    SettingsGroupTitle({ title: '内容屏蔽' })
    SettingsCard({
      content: (): void => {
        this.CategoryRows(SettingsPane.PRIVACY_SETTINGS, ['forbidden_forums', 'block_manage', 'hidden_threads'])
      }
    })
    SettingsGroupTitle({ title: '权限与数据' })
    SettingsCard({
      content: (): void => {
        this.CategoryRows(SettingsPane.PRIVACY_SETTINGS, ['app_permissions', 'data_use'])
      }
    })
  }

  @Builder
  HomeTopNavPreview() {
    Column() {
      Text('顶栏预览')
        .fontSize(SettingsLayout.SUB_SIZE)
        .fontColor(AppTheme.NOTE_TEXT)
        .width('100%')
        .margin({ bottom: 8 })
      Stack({ alignContent: Alignment.TopStart }) {
        // 示意色块：只用于观察玻璃层次，不代表任何真实内容。
        // ⚠️ 刻意**不用** ACCENT_LIGHT：它与选中底的浅蓝同色，会让人误以为那是选中态。
        // 整层再压到 55% 不透明度：深灰块原色（#B7B7BC）会让压在上面的未选中频道文字
        // 掉到约 2.4:1 对比度（真机截图实测），压淡后既能看出玻璃、文字也还读得清。
        Row({ space: 8 }) {
          Column()
            .width(72).height(72).borderRadius(10)
            .backgroundColor(AppTheme.TEXT_MUTED)
          Column()
            .width(96).height(56).borderRadius(10)
            .backgroundColor(AppTheme.CARD)
          Column()
            .width(56).height(88).borderRadius(10)
            .backgroundColor(AppTheme.SURFACE_MUTED)
          Blank()
        }
        .width('100%')
        .opacity(0.55)
        .padding({ left: 12, right: 12, top: 6 })
        if (visualThemeStore.isPaper || homeTopNavStore.style === HomeTopNavStyle.OFFICIAL_DUAL_ROW) {

          HomeDualRowTopBar({
            statusBarHeight: 0,
            selectedChannel: this.previewChannel,
            onSelectChannel: (label: string): void => { this.previewChannel = label; },
            onSearch: (): void => {}
          })
          .width('100%')
          .padding({ top: 6 })
        } else {
          HomeTopNav({
            style: homeTopNavStore.style,
            selectedChannel: this.previewChannel,
            onRowHeightChanged: (height: number): void => { this.previewNavRowH = height; },
            hidden: false,
            onSelectChannel: (label: string): void => { this.previewChannel = label; },
            onSearch: (): void => {}
          })
          // 预览卡片自己收边：左右边距交给外层 padding，顶栏行贴卡片上沿（top = 0）
          .width('100%')
          .padding({ left: 0, right: 0 })
        }
      }
      .width('100%')
      .height(visualThemeStore.isPaper
        ? TOP_NAV_PREVIEW_DUAL_H + PaperLayout.BRAND_HEIGHT
        : homeTopNavStore.style === HomeTopNavStyle.OFFICIAL_DUAL_ROW
        ? TOP_NAV_PREVIEW_DUAL_H + homeDualRowHeight(fontSizeScaleOf(fontScaleStore.pref,
          fontScaleStore.systemScale, fontScaleStore.customSize)) - OFFICIAL_DUAL_ROW_HEIGHT
        : Math.max(TOP_NAV_PREVIEW_H, this.previewNavRowH + 28))
      .clip(true)
      .borderRadius(SettingsLayout.CARD_RADIUS - 6)
      .backgroundColor(AppTheme.BG)
    }
    .width('100%')
    .padding(12)
    .margin({ top: SettingsLayout.GROUP_TITLE_GAP })
    .backgroundColor(AppTheme.SURFACE_MUTED)
    .borderRadius(SettingsLayout.CARD_RADIUS)
  }

  /** 以稳定 key 选择页内分组，值和开关仍读取模型，避免迁移后依赖旧数组下标。 */
  @Builder
  CategoryRows(pane: SettingsPane, keys: string[]) {
    ForEach(this.entriesFor(pane, keys), (entry: SettingsEntry, index: number) => {
      if (entry.kind === SettingsEntryKind.SWITCH) {
        SettingsSwitchRow({
          label: entry.label, sub: entry.subtitle ?? '', checked: entry.checked === true,
          interactionEnabled: entry.enabled, showDivider: index < this.entriesFor(pane, keys).length - 1,
          onToggle: (next: boolean): void => { this.applySwitchEntry(entry, next); }
        }).id(`settings-entry-${entry.key}`)
      } else if (visualThemeStore.isPaper &&
        (entry.pane === SettingsPane.TOP_NAV || entry.pane === SettingsPane.ACTION_BAR)) {
        SettingsInfoRow({
          label: entry.label,
          value: entry.pane === SettingsPane.TOP_NAV ? '纸境品牌顶栏' : '纸境悬浮互动栏',
          showDivider: index < this.entriesFor(pane, keys).length - 1
        }).id(`settings-entry-${entry.key}`)
      } else if (settingsPanePresentation(entry.pane) === SettingsPanePresentation.POPUP) {
        SettingsOptionRow({
          label: entry.label, value: entry.value,
          showDivider: index < this.entriesFor(pane, keys).length - 1,
          popupOpen: this.popupKey === entry.key, items: this.optionsFor(entry.pane),
          onTap: (): void => { this.openPanePopup(entry.key, entry.pane); },
          onPick: (optionIndex: number): void => { this.pickOption(entry.pane, optionIndex); },
          onPopupClosed: (): void => { this.closePopup(); }
        }).id(`settings-entry-${entry.key}`)
      } else {
        SettingsEntryRow({
          label: entry.label, summary: entry.value,
          showDivider: index < this.entriesFor(pane, keys).length - 1,
          onTap: (): void => { this.onEntry(entry); }
        }).id(`settings-entry-${entry.key}`)
      }
    }, (entry: SettingsEntry) => settingsEntryRenderKey(entry))
  }

  // ── 顶栏 ────────────────────────────────────────────────────────────────

  @Builder
  TitleBar() {
    Stack() {
      SearchTopMaterial({ slot: MaterialSlot.NAV_BAR, panelHeight: this.titleBarH() })
        .opacity(this.navGlass)

      Row() {
        // 分类与内容页更换标题；具体选项仍是弹层，不换页（判据在 settingsPageTitle）。
        Text(this.pane === SettingsPane.FORBIDDEN_FORUMS && this.forbiddenVm.selecting ?
          (this.forbiddenVm.executing ? (this.forbiddenVm.actionMessage === '正在停止…' ? '正在停止…' :
          `正在取消 ${this.forbiddenVm.processed}/${this.forbiddenVm.preparedCount}`) :
          (this.forbiddenVm.selectedIds.length > 0 ? `已选择 ${this.forbiddenVm.selectedIds.length} 项` : '未选择')) : settingsPageTitle(this.pane))
          .fontSize(SettingsLayout.TITLE_SIZE)
          .id('settings-title')
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_MAIN)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .translate({ x: motionStore.isOn(MotionEffect.MOVE) ? this.paneOffset : 0 })
          .opacity(motionStore.isOn(MotionEffect.FADE) ? this.paneOpacity : 1)
      }
      .width('100%')
      .height('100%')
      /*
       * 左内边距 = 按钮直径 40 + 左右各 12 的间隙。
       *
       * ⚠️ 返回按钮**已经不在这层里了**（见 build 内注释）：嵌在顶栏内部时它的
       * 返回按钮保持独立，避免材质背板与标题内容互相影响。
       * 这里只负责给标题让出按钮原来的位置。
       */
      .padding({ left: 64, right: this.pane === SettingsPane.FORBIDDEN_FORUMS ?
        (this.forbiddenVm.selecting && this.forbiddenVm.allSelected() ? 102 : 78) : 16, top: this.statusBarH })
    }
    .width('100%')
    .height(this.titleBarH())
  }
}
