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
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { authSession } from '../auth/AuthSession';
import { StoreResult } from '../auth/AuthStore';
import { AppTheme } from '../theme/Theme';
import { GlassBackButton } from '../components/GlassBackButton';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { materialManager } from '../common/material/MaterialManager';
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
import { SETTINGS_ACTION_LOGIN, SETTINGS_ACTION_LOGOUT, SettingsAboutItem, SettingsEntry, SettingsEntryKind, SettingsGroup, SettingsOptionItem, SettingsPane, SettingsPanePresentation, SettingsState, SETTINGS_APP_VERSION, SETTINGS_VERSION_CODE, aboutItems, aboutNotes, buildOptions, buildSettingsCategoryEntries, buildSettingsGroups, settingsEntryRenderKey, settingsGroupRenderKey, settingsPageTitle, settingsPanePresentation } from '../model/SettingsModel';

const TOP_NAV_PREVIEW_H: number = 108;
// 「官方沉浸」预览：整片玻璃面板（statusBarHeight 传 0）= 48 + 6 + 56 + 上下内距 8 = 118，
// 再露出 28vp 内容让玻璃有东西可透。
const TOP_NAV_PREVIEW_DUAL_H: number = 119 + 28;

@Entry
@ComponentV2
struct SettingsPage {
  @Local smartReach: SmartReachStore = smartReachStore;

  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;

  /** 当前分类或内容页；`NONE` = 设置入口列表。 */
  @Local pane: SettingsPane = SettingsPane.NONE;

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
    this.refreshCacheStats();
    if ((this.pane === SettingsPane.NONE || this.pane === SettingsPane.ACCOUNT) &&
      authSession.isLoggedIn()) {
      void authSession.refreshOwnAvatarOnEntry(
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
    this.avatarVm.dispose();
    this.cacheStats.dispose();
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

  private parentPaneOf(pane: SettingsPane): SettingsPane {
    if (pane === SettingsPane.FORBIDDEN_FORUMS || pane === SettingsPane.BLOCK_MANAGE ||
      pane === SettingsPane.APP_PERMISSIONS || pane === SettingsPane.DATA_USE) {
      return SettingsPane.PRIVACY_SETTINGS;
    }
    if (pane === SettingsPane.SIGN_SETTINGS || pane === SettingsPane.TAILS ||
      pane === SettingsPane.PRIVACY_MARKS) {
      return SettingsPane.PERSONALIZATION;
    }
    if (pane === SettingsPane.IMAGE_WATERMARK) {
      return SettingsPane.BROWSING;
    }
    if (pane === SettingsPane.MATERIAL || pane === SettingsPane.ACTION_BAR ||
      pane === SettingsPane.TOP_NAV) {
      // 这三项都是弹层（不换页），留在鸿蒙特性设置页上；这里只是把语义写全，
      // 万一将来某条改成换页也不会回错地方。
      return SettingsPane.HARMONY_FEATURES;
    }
    if (pane === SettingsPane.OFFICIAL_MESSAGES) {
      return SettingsPane.MESSAGE;
    }
    if (pane === SettingsPane.VERSION) {
      return SettingsPane.ABOUT;
    }
    return SettingsPane.NONE;
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
      hideStatusBar: homeNavigationHideStore.hideStatusBar,
      hideTopNavigation: homeNavigationHideStore.hideTopNavigation,
      hideBottomNavigation: homeNavigationHideStore.hideBottomNavigation,
      lowFlow: lowFlowStore.enabled,
      superResolution: superResolutionStore.enabled,
      smartReach: this.smartReach.enabled,
      // 入口显示系统应用缓存总量，不再用导出目录大小冒充总量。
      cacheLabel: this.cacheStats.label(),
    };
  }

  private groups(): SettingsGroup[] {
    return buildSettingsGroups(this.state());
  }

  private categoryEntries(): SettingsEntry[] {
    return buildSettingsCategoryEntries(this.pane, this.state());
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

  /** 所有页面入口统一走这里：进入前保存当前页偏移，新页从顶部开始。 */
  private navigateTo(next: SettingsPane): void {
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
      void authSession.refreshOwnAvatarOnEntry(
        this.getUIContext().getHostContext() as common.UIAbilityContext);
    }
    this.resetScroll();
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
    const next: SettingsPane = this.parentPaneOf(from);
    const seq: number = ++this.navSeq;
    this.pane = next;
    if ((next === SettingsPane.NONE || next === SettingsPane.ACCOUNT) &&
      from !== next && authSession.isLoggedIn()) {
      void authSession.refreshOwnAvatarOnEntry(
        this.getUIContext().getHostContext() as common.UIAbilityContext);
    }
    this.pendingRestore = this.paneScrollY.get(String(next)) ?? 0;
    this.pendingRestoreSeq = seq;
    if (this.pendingRestore === 0) {
      // 目标本来就在顶部：无需等布局，直接复位
      this.pendingRestore = -1;
      this.resetScroll();
    }
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
      return buildOptions(['逐个签到', '官方签到'], signStrategyStore.strategy, 'sign_strategy');
    }
    if (pane === SettingsPane.FORUM_LEVEL) {
      return buildOptions(['简洁', '官方'], forumLevelStore.style, 'forum_level');
    }
    if (pane === SettingsPane.FORUM_DEFAULT_TAB) {
      return buildOptions(['热门', '最新'], forumDefaultTabStore.value, 'forum_default_tab');
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
    if (pane === SettingsPane.SIGN_SETTINGS) {
      if (index !== 0 && index !== 1) { return; }
      void signStrategyStore.setStrategy(index, this.getUIContext().getHostContext() as common.UIAbilityContext)
        .catch((error: Error) => { this.getUIContext().getPromptAction().showToast({ message: error.message }); });
      this.closePopup(); return;
    }
    if (pane === SettingsPane.FORUM_LEVEL) {
      void forumLevelStore.setStyle(index, this.getUIContext().getHostContext() as common.UIAbilityContext)
        .catch((error: Error) => { this.getUIContext().getPromptAction().showToast({ message: error.message }); });
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
      materialManager.setHdsLevel(ALL_HDS_LEVELS[index], context).catch(() => {});
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
   * 失败也在里面吞掉了（本次会话内仍然生效，只是下次启动可能回到旧值）。
   */
  private pickMaterialMode(mode: MaterialMode): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    materialManager.setMode(mode, context).catch(() => {});
  }

  /** 切换帖子详情页底部操作栏样式（与 pickMaterialMode 同一条链路）。 */
  private pickActionBarStyle(style: ThreadActionBarStyle): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    threadActionBarStore.setStyle(style, context).catch(() => {});
  }

  /** 切换首页顶栏样式（同一条链路）。 */
  private pickTopNavStyle(style: HomeTopNavStyle): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    homeTopNavStore.setStyle(style, context).catch(() => {});
  }

  /** 三个「滑动时自动隐藏」开关：按部件写偏好。 */
  private setHidePart(part: HomeNavigationPart, checked: boolean): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    homeNavigationHideStore.set(part, checked, context).catch(() => {});
  }

  /** 低流量模式（本机偏好；与三个隐藏开关**不是**同一个存储）。 */
  private setLowFlow(checked: boolean): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    lowFlowStore.setEnabled(checked, context).catch(() => {});
  }

  /** 图像超分入口开关（本机偏好；又一个独立存储，只管查看器里那枚按钮的显隐）。 */
  private setSuperResolution(checked: boolean): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    superResolutionStore.setEnabled(checked, context).catch(() => {});
  }

  /** 旧行渲染器里的开关分发（按稳定 action 串，不比较中文文案）。 */
  private applySwitchEntry(entry: SettingsEntry, checked: boolean): void {
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
    SettingsNote({ text: '清理后图片等内容会按需重新加载。不会退出登录，也不会删除设置、浏览历史或已保存的图片。系统统计可能稍后更新，正在使用的缓存可能重新生成。' })
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

  build() {
    /*
     * ── 结构 ──
     * `Scroll` 占满全高（不为顶栏让位），玻璃顶栏 + 返回按钮悬浮其上（Stack 后声明者在上）。
     * 列表首项是一个与顶栏等高的占位 `Row` —— 参考图里第一张卡片的顶边**正好压在
     * 顶栏渐隐的终点**上，所以这里不留任何额外间距。
     */
    Stack({ alignContent: Alignment.TopStart }) {
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

      // 顶栏：悬浮层，最后声明 → 盖在内容层之上
      this.TitleBar()

      Row() {
        GlassBackButton({
          onTap: (): void => {
            this.goBack();
          }
        })
      }
      .margin({ left: 14, top: this.statusBarH + 8 })

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
          .layoutWeight(1)
          .selectedColor(AppTheme.ACCENT)
          .onChange((value: number, mode: SliderChangeMode): void => {
            const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
            fontScaleStore.setCustomSize(value, context,
              mode !== SliderChangeMode.Begin && mode !== SliderChangeMode.Moving);
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

      case 'harmony_features':
        return $r('sys.symbol.HarmonyOS_Next');
      case 'personalization':
        return $r('sys.symbol.personalized_sticker');
      case 'other_settings':
        return $r('sys.symbol.gearshape');
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
        this.navigateTo(SettingsPane.ACCOUNT);
      })
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
    } else if (this.pane === SettingsPane.OTHER_SETTINGS) {

      this.OtherSettingsPane()
    } else {
      this.CategoryPane()
    }
  }

  @Builder
  CategoryPane() {
    if (this.pane === SettingsPane.BROWSING) {
      // P3：第三个改用公共组件的页面（另一个偏好页）
      this.BrowsingPane()
    } else if (this.pane === SettingsPane.HARMONY_FEATURES) {

      this.HarmonyPane()
    } else if (this.pane === SettingsPane.MESSAGE) {
      MessageSettingsPane({
        onOpenOfficial: (): void => {
          this.navigateTo(SettingsPane.OFFICIAL_MESSAGES);
        }
      })
    } else if (this.pane === SettingsPane.OFFICIAL_MESSAGES) {
      OfficialMessagesPane()
    } else if (this.pane === SettingsPane.TAILS) {
      TailsPane()
    } else if (this.pane === SettingsPane.FORBIDDEN_FORUMS) {
      ForbiddenForumsPane({
        loadMoreSeq: this.paneLoadMoreSeq,
        onPageStarted: (): void => { if (this.paneContentH <= this.viewportH) { this.autoFillCount++; } },
        onPageSettled: (): void => { this.autoLoadMore(false); }
      })
    } else if (this.pane === SettingsPane.BLOCK_MANAGE) {
      BlockManagePane()
    } else if (this.pane === SettingsPane.PRIVACY_MARKS) {
      PrivacyMarksPane()
    } else if (this.pane === SettingsPane.IMAGE_WATERMARK) {
      ImageWatermarkPane()
    } else if (this.pane === SettingsPane.APP_PERMISSIONS) {
      AppPermissionsPane({
        refreshSeq: this.paneRefreshSeq
      })
    } else if (this.pane === SettingsPane.APPEARANCE) {
      // P2：首个改用公共组件的页面（偏好页）
      this.AppearancePane()
    } else if (this.pane === SettingsPane.CACHE) {
      // P2：第二个改用公共组件的页面（状态页，阶段驱动）
      this.CachePane()
    } else if (this.pane === SettingsPane.PERSONALIZATION ||
      this.pane === SettingsPane.PRIVACY_SETTINGS) {
      // 中间层：内容都是入口行（结构由模型给），用公共组件渲染
      this.EntryRowsPane()
    }
  }

  @Builder
  OtherSettingsPane() {
    SettingsCard({
      content: (): void => { this.OtherSettingsEmptyRow() }
    })
    SettingsNote({ text: '这个分类下暂时还没有设置项。后续新增的设置会先收进这里。' })
  }

  @Builder
  OtherSettingsEmptyRow() {
    SettingsInfoRow({ label: '暂无设置项', showDivider: false })
  }

  @Builder
  SignSettingsPane() {
    SettingsCard({
      content: (): void => { this.SignSettingsRows() }
    })
    SettingsNote({ text: signStrategyStore.strategy === 1
      ? '官方批量签到暂不可用：协议与真实结果仍待验证。点击一键签到不会发出请求。'
      : '逐个签到按关注吧顺序依次提交，可逐项确认结果。' })
  }

  @Builder
  SignSettingsRows() {
    SettingsOptionRow({
      label: '签到方案',
      value: signStrategyStore.strategy === 1 ? '官方签到' : '逐个签到',
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
    this.AppearancePreview()
    Row({ space: 10 }) {
      Text('等级标签预览').fontSize(13).fontColor(AppTheme.TEXT_SUB)
      ForumLevelBadge({ level: 8, levelName: '核心会员' })
    }.width('100%').margin({ top: 12 })
  }

  @Builder
  AppearanceRows() {
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

  /**
   * 效果预览：紧凑示意，跟随当前主题与字号（两行文字与两个胶囊都走同一套 token 与 fp），
   * 胶囊叠 `SHEET` 槽位的玻璃，因此也会随「沉浸光感强度」变化。真机观感仍需人工确认。
   */
  @Builder
  AppearancePreview() {
    Column() {
      Text('效果预览')
        .fontSize(SettingsLayout.SUB_SIZE)
        .fontColor(AppTheme.NOTE_TEXT)
        .width('100%')
        .margin({ bottom: 8 })
      Column({ space: 6 }) {
        Text('示例帖子标题，用来观察字号层级')
          .fontSize(SettingsLayout.LABEL_SIZE)
          .fontColor(AppTheme.TEXT_MAIN)
          .width('100%')
        Text('示例吧 · 示例作者 · 9-30')
          .fontSize(SettingsLayout.SUB_SIZE)
          .fontColor(AppTheme.NOTE_TEXT)
          .width('100%')
        Row({ space: 8 }) {
          this.PreviewPill('回复 12')
          this.PreviewPill('赞 34')
        }
        .margin({ top: 6 })
      }
      .width('100%')
      .padding(14)
      .backgroundColor(AppTheme.CARD)
      .borderRadius(SettingsLayout.CARD_RADIUS - 6)
    }
    .width('100%')
    .padding(12)
    .margin({ top: SettingsLayout.GROUP_GAP })
    .backgroundColor(AppTheme.SURFACE_MUTED)
    .borderRadius(SettingsLayout.CARD_RADIUS)
  }

  @Builder
  PreviewPill(text: string) {
    Text(text)
      .fontSize(SettingsLayout.VALUE_SIZE)
      .fontColor(AppTheme.TEXT_MAIN)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundEffect(materialManager.glassOf(MaterialSlot.SHEET))
      .systemMaterial(materialManager.officialOf(MaterialSlot.SHEET))
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
    SettingsCard({
      content: (): void => { this.BrowsingLowFlowRow() }
    })
    SettingsCard({
      marginTop: SettingsLayout.GROUP_GAP,
      content: (): void => { this.BrowsingWatermarkRow() }
    })
    SettingsCard({
      marginTop: SettingsLayout.GROUP_GAP,
      content: (): void => { this.BrowsingDefaultTabRow() }
    })
  }

  private browsingEntries(): SettingsEntry[] {
    return buildSettingsCategoryEntries(SettingsPane.BROWSING, this.state());
  }

  @Builder
  BrowsingLowFlowRow() {
    ForEach(this.browsingEntries().slice(0, 1), (entry: SettingsEntry) => {
      SettingsSwitchRow({
        label: entry.label,
        sub: '列表与正文不自动加载图片',
        checked: entry.checked === true,
        showDivider: false,
        onToggle: (next: boolean): void => {
          this.applySwitchEntry(entry, next);
        }
      })
    }, (entry: SettingsEntry) => settingsEntryRenderKey(entry))
  }

  @Builder
  BrowsingWatermarkRow() {
    ForEach(this.browsingEntries().slice(1, 2), (entry: SettingsEntry) => {
      SettingsEntryRow({
        label: entry.label,
        summary: entry.value,
        showDivider: false,
        onTap: (): void => {
          this.onEntry(entry);
        }
      })
    }, (entry: SettingsEntry) => settingsEntryRenderKey(entry))
  }

  @Builder
  BrowsingDefaultTabRow() {
    ForEach(this.browsingEntries().slice(2, 3), (entry: SettingsEntry) => {
      SettingsOptionRow({
        label: entry.label,
        value: entry.value,
        showDivider: false,
        popupOpen: this.popupKey === entry.key,
        items: this.optionsFor(entry.pane),
        onTap: (): void => { this.openPanePopup(entry.key, entry.pane); },
        onPick: (index: number): void => { this.pickOption(entry.pane, index); },
        onPopupClosed: (): void => { this.closePopup(); }
      })
    }, (entry: SettingsEntry) => settingsEntryRenderKey(entry))
  }

  @Builder
  HarmonyPane() {
    SettingsCard({
      content: (): void => { this.HarmonyMaterialRow() }
    })
    SettingsNote({ text: '厚度控制弹层、一体玻璃和吧页按钮；材质等级控制官方沉浸顶栏、搜索框、圆按钮和底部胶囊。两项独立生效。' })
    SettingsCard({
      marginTop: SettingsLayout.GROUP_GAP,
      content: (): void => { this.HarmonyStyleRows() }
    })
    this.HomeTopNavPreview()
    SettingsGroupTitle({ title: '滑动时自动隐藏' })
    SettingsCard({
      content: (): void => { this.HarmonyHideRows() }
    })
    SettingsNote({ text: '首页上滑时隐藏所选区域，下滑即恢复。' })
    SettingsCard({
      marginTop: SettingsLayout.GROUP_GAP,
      content: (): void => { this.HarmonySuperResolutionRow() }
    })
    SettingsCard({ marginTop: SettingsLayout.GROUP_GAP,
      content: (): void => { this.HarmonySmartReachRow() } })
  }

  @Builder
  HarmonySmartReachRow() {
    ForEach(this.harmonyEntries().filter((entry: SettingsEntry): boolean => entry.key === 'smart_reach'),
      (entry: SettingsEntry) => {
        SettingsSwitchRow({ label: entry.label,
          checked: entry.checked === true, showDivider: false,
          onToggle: (next: boolean): void => { this.applySwitchEntry(entry, next); } })
      }, (entry: SettingsEntry) => settingsEntryRenderKey(entry))
  }

  private harmonyEntries(): SettingsEntry[] {
    return buildSettingsCategoryEntries(SettingsPane.HARMONY_FEATURES, this.state());
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
        if (homeTopNavStore.style === HomeTopNavStyle.OFFICIAL_DUAL_ROW) {

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
      .height(homeTopNavStore.style === HomeTopNavStyle.OFFICIAL_DUAL_ROW
        ? TOP_NAV_PREVIEW_DUAL_H + homeDualRowHeight(fontSizeScaleOf(fontScaleStore.pref,
          fontScaleStore.systemScale, fontScaleStore.customSize)) - OFFICIAL_DUAL_ROW_HEIGHT
        : Math.max(TOP_NAV_PREVIEW_H, this.previewNavRowH + 28))
      .clip(true)
      .borderRadius(SettingsLayout.CARD_RADIUS - 6)
      .backgroundColor(AppTheme.BG)
    }
    .width('100%')
    .padding(12)
    .margin({ top: SettingsLayout.GROUP_GAP })
    .backgroundColor(AppTheme.SURFACE_MUTED)
    .borderRadius(SettingsLayout.CARD_RADIUS)
  }

  /** 沉浸光感强度：单行一张卡，选项形态与另外两套样式一致（都是弹层）。 */
  @Builder
  HarmonyMaterialRow() {
    ForEach(this.harmonyEntries().filter((entry: SettingsEntry): boolean =>
      entry.pane === SettingsPane.MATERIAL || entry.pane === SettingsPane.HDS_MATERIAL),
      (entry: SettingsEntry, index: number) => {
      SettingsOptionRow({
        label: entry.label,
        value: entry.value,
        showDivider: index === 0,
        popupOpen: this.popupKey === entry.key,
        items: this.optionsFor(entry.pane),
        onTap: (): void => {
          this.openPanePopup(entry.key, entry.pane);
        },
        onPick: (optionIndex: number): void => {
          this.pickOption(entry.pane, optionIndex);
        },
        onPopupClosed: (): void => {
          this.closePopup();
        }
      })
    }, (entry: SettingsEntry) => settingsEntryRenderKey(entry))
  }

  @Builder
  HarmonyStyleRows() {
    ForEach(this.harmonyEntries().filter((entry: SettingsEntry): boolean =>
      entry.pane === SettingsPane.ACTION_BAR || entry.pane === SettingsPane.TOP_NAV),
      (entry: SettingsEntry, index: number) => {
      SettingsOptionRow({
        label: entry.label,
        value: entry.value,
        showDivider: index === 0,
        popupOpen: this.popupKey === entry.key,
        items: this.optionsFor(entry.pane),
        onTap: (): void => {
          this.openPanePopup(entry.key, entry.pane);
        },
        onPick: (optionIndex: number): void => {
          this.pickOption(entry.pane, optionIndex);
        },
        onPopupClosed: (): void => {
          this.closePopup();
        }
      })
    }, (entry: SettingsEntry) => settingsEntryRenderKey(entry))
  }

  @Builder
  HarmonyHideRows() {
    ForEach(this.harmonyEntries().filter((entry: SettingsEntry): boolean => entry.key.startsWith('hide_')),
      (entry: SettingsEntry, index: number) => {
      SettingsSwitchRow({
        label: entry.label,
        checked: entry.checked === true,
        showDivider: index < 2,
        onToggle: (next: boolean): void => {
          this.applySwitchEntry(entry, next);
        }
      })
    }, (entry: SettingsEntry) => settingsEntryRenderKey(entry))
  }

  @Builder
  HarmonySuperResolutionRow() {
    ForEach(this.harmonyEntries().filter((entry: SettingsEntry): boolean => entry.key === 'super_resolution'),
      (entry: SettingsEntry) => {
      SettingsSwitchRow({
        label: entry.label,
        sub: '关闭后全屏看图不再显示超分按钮',
        checked: entry.checked === true,
        showDivider: false,
        onToggle: (next: boolean): void => {
          this.applySwitchEntry(entry, next);
        }
      })
    }, (entry: SettingsEntry) => settingsEntryRenderKey(entry))
  }

  /** 中间层页面（个性化 / 隐私设置）：入口行由模型给，页面只负责渲染与点击分发。 */
  @Builder
  EntryRowsPane() {
    SettingsCard({
      content: (): void => { this.EntryRows() }
    })
  }

  @Builder
  EntryRows() {
    ForEach(this.categoryEntries(), (entry: SettingsEntry, index: number) => {
      SettingsEntryRow({
        label: entry.label,
        summary: entry.value,
        showDivider: index < this.categoryEntries().length - 1,
        onTap: (): void => {
          this.onEntry(entry);
        }
      })
    }, (entry: SettingsEntry) => settingsEntryRenderKey(entry))
  }

  // ── 顶栏 ────────────────────────────────────────────────────────────────

  @Builder
  TitleBar() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(AppTheme.BG)

      Column()
        .width('100%')
        .height('100%')
        .opacity(this.navGlass)
        // 深色关于页的顶部与页面同底色，避免导航玻璃把参考图的黑色区域漂成灰色（沿用旧口径）

        .backgroundColor(themeModeStore.isDark ? AppTheme.BG : AppTheme.NAV_FADE_CLEAR)
        .backgroundEffect(themeModeStore.isDark ? undefined :
          materialManager.glassOf(MaterialSlot.NAV_BAR))
        .systemMaterial(themeModeStore.isDark ? undefined :
          materialManager.officialOf(MaterialSlot.NAV_BAR))
        .linearGradient({
          angle: 180,
          colors: [
            [AppTheme.NAV_FADE, 0.0],
            [AppTheme.NAV_FADE_CLEAR, 1.0]
          ]
        })

      Row() {
        // 分类与内容页更换标题；具体选项仍是弹层，不换页（判据在 settingsPageTitle）。
        Text(settingsPageTitle(this.pane))
          .fontSize(SettingsLayout.TITLE_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_MAIN)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      /*
       * 左内边距 = 按钮直径 40 + 左右各 12 的间隙。
       *
       * ⚠️ 返回按钮**已经不在这层里了**（见 build 内注释）：嵌在顶栏内部时它的
       * `backgroundEffect` backdrop 采不到滚动内容，真机连续 8 帧圆内均值纹丝不动。
       * 这里只负责给标题让出按钮原来的位置。
       */
      .padding({ left: 64, right: 16, top: this.statusBarH })
    }
    .width('100%')
    .height(this.titleBarH())
  }
}
