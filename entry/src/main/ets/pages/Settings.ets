import { forumLevelStore } from '../common/appearance/ForumLevelStore';
import { forumDefaultTabStore } from '../common/appearance/ForumDefaultTabStore';
import { ForumDefaultTab, forumDefaultTabLabel } from '../model/ForumDefaultTab';
import { ForumLevelBadge } from '../components/ForumLevelBadge';
import { AvatarEditVM } from '../viewmodel/AvatarEditVM';
import { AvatarCropPage } from '../components/AvatarCropPage';
import { AvatarCrop } from '../model/AvatarUpload';

import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { authSession } from '../auth/AuthSession';
import { StoreResult } from '../auth/AuthStore';
import { AppTheme } from '../theme/Theme';
import { GlassBackButton } from '../components/GlassBackButton';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { materialManager } from '../common/material/MaterialManager';
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
import { signStrategyStore } from '../common/appearance/SignStrategyStore';

import {
  CacheMeasure, CachePhase, cachePhaseAmountLabel, cachePhaseCanClear, cachePhaseOf, cacheResultLines
} from '../model/CacheClean';
import { ClearResult, clearExportCache, measureExportCache } from '../utils/CacheCleaner';

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

const TOP_NAV_PREVIEW_DUAL_H: number = 119 + 28;

@Entry
@ComponentV2
struct SettingsPage {

  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;

  @Local pane: SettingsPane = SettingsPane.NONE;

  @Local avatarVm: AvatarEditVM = new AvatarEditVM();

  @Local cropOpen: boolean = false;

  @Local popupKey: string = '';

  @Local popupPane: SettingsPane = SettingsPane.NONE;
  @Local fontSheetOpen: boolean = false;

  @Local previewNavRowH: number = 54;
  @Local previewChannel: string = '推荐';

  @Local cacheMeasure: CacheMeasure = new CacheMeasure();
  @Local cachePhase: CachePhase = CachePhase.STATTING;

  @Local lastCleared: number = 0;
  @Local lastFailed: number = 0;
  @Local lastFreedBytes: number = 0;
  @Local searchCount: number = 0;
  @Local browseCount: number = 0;

  @Local cacheBusy: boolean = false;

  aboutToAppear(): void {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    readStatusBarVp(context).then((vp: number) => {
      this.statusBarH = vp;
    }).catch(() => {

    });

    this.refreshCacheStats();
  }

  onPageShow(): void {
    if ((this.pane === SettingsPane.NONE || this.pane === SettingsPane.ACCOUNT) &&
      authSession.isLoggedIn()) {
      void authSession.refreshOwnAvatarOnEntry(
        this.getUIContext().getHostContext() as common.UIAbilityContext);
    }
    if (this.pane === SettingsPane.APP_PERMISSIONS) {
      this.paneRefreshSeq += 1;
    }
  }

  aboutToDisappear(): void {
    this.avatarVm.dispose();
  }

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

  private state(): SettingsState {
    return {
      loggedIn: authSession.snapshot.isLoggedIn(),
      materialLabel: modeLabel(materialManager.mode),
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

      cacheLabel: cachePhaseAmountLabel(this.cachePhase, this.cacheMeasure),
    };
  }

  private groups(): SettingsGroup[] {
    return buildSettingsGroups(this.state());
  }

  private categoryEntries(): SettingsEntry[] {
    return buildSettingsCategoryEntries(this.pane, this.state());
  }

  private titleBarH(): number {
    return 56 + this.statusBarH;
  }

  @Local navGlass: number = 0;

  @Local paneRefreshSeq: number = 0;

  @Local paneLoadMoreSeq: number = 0;
  private scroller: Scroller = new Scroller();

  private resetScroll(): void {
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
    this.navGlass = 0;
  }

  private paneScrollY: Map<string, number> = new Map<string, number>();

  private rememberScroll(pane: SettingsPane): void {
    this.paneScrollY.set(String(pane), this.scroller.currentOffset().yOffset);
  }

  private navSeq: number = 0;

  private navigateTo(next: SettingsPane): void {
    const from: SettingsPane = this.pane;
    if (from !== next) {
      this.rememberScroll(from);
    }
    this.navSeq += 1;
    this.pendingRestore = -1;
    this.paneScrollY.delete(String(next));
    this.autoFillCount = 0;
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

  private autoFillCount: number = 0;

  private paneContentH: number = 0;

  private viewportH: number = 0;

  private autoLoadMore(atEnd: boolean): void {
    if (this.pane !== SettingsPane.FORBIDDEN_FORUMS) { return; }
    if (this.paneContentH <= 0 || this.viewportH <= 0) { return; }
    const content: number = this.paneContentH;
    const extent: number = this.viewportH;
    if (content <= extent) {

      if (this.autoFillCount >= AUTO_FILL_MAX) { return; }
    } else {
      const offset: number = this.scroller.currentOffset().yOffset;
      const distanceToEnd: number = Math.max(0, content - extent - offset);
      if (!atEnd && distanceToEnd > AUTO_LOAD_TRIGGER_PX) { return; }
    }

    this.paneLoadMoreSeq += 1;
  }

  private goBack(): void {
    if (this.pane !== SettingsPane.NONE) {
      this.leaveToParent();
      return;
    }
    router.back();
  }

  @Local pendingRestore: number = -1;
  private pendingRestoreSeq: number = -1;

  private applyPendingRestore(): void {
    if (this.pendingRestore < 0 || this.pendingRestoreSeq !== this.navSeq) {
      this.pendingRestore = -1;
      return;
    }
    const y: number = this.pendingRestore;
    this.pendingRestore = -1;
    this.scroller.scrollTo({ xOffset: 0, yOffset: y });

    this.updateNavGlass();
  }

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

      this.pendingRestore = -1;
      this.resetScroll();
    }
  }

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

          this.navigateTo(entry.pane);

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

        return;
    }
  }

  private openPopup(entry: SettingsEntry): void {
    this.popupPane = entry.pane;
    this.popupKey = entry.key;
  }

  private closePopup(): void {
    this.popupKey = '';
  }

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
    if (pane === SettingsPane.ACTION_BAR) {
      return buildOptions(
        ALL_ACTION_BAR_STYLES.map((style: ThreadActionBarStyle): string => actionBarStyleLabel(style)),
        ALL_ACTION_BAR_STYLES.indexOf(threadActionBarStore.style), 'actionbar');
    }
    if (pane === SettingsPane.TOP_NAV) {

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
    this.closePopup();
    if (openFontSheet) {
      this.fontSheetOpen = true;
    }
  }

  private pickMaterialMode(mode: MaterialMode): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    materialManager.setMode(mode, context).catch(() => {});
  }

  private pickActionBarStyle(style: ThreadActionBarStyle): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    threadActionBarStore.setStyle(style, context).catch(() => {});
  }

  private pickTopNavStyle(style: HomeTopNavStyle): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    homeTopNavStore.setStyle(style, context).catch(() => {});
  }

  private setHidePart(part: HomeNavigationPart, checked: boolean): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    homeNavigationHideStore.set(part, checked, context).catch(() => {});
  }

  private setLowFlow(checked: boolean): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    lowFlowStore.setEnabled(checked, context).catch(() => {});
  }

  private setSuperResolution(checked: boolean): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    superResolutionStore.setEnabled(checked, context).catch(() => {});
  }

  private applySwitchEntry(entry: SettingsEntry, checked: boolean): void {
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

      confirmed = answer.index === 1;
    } catch (err) {

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
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.cacheMeasure = measureExportCache(context);
    this.cachePhase = cachePhaseOf(this.cacheMeasure);
  }

  private async confirmClearCache(): Promise<void> {
    if (this.cacheBusy || !cachePhaseCanClear(this.cachePhase)) {
      return;
    }
    let confirmed: boolean = false;
    try {
      const answer: promptAction.ShowDialogSuccessResponse = await promptAction.showDialog({
        title: '清理缓存',
        message: `将删除导出目录中的临时文件（${cachePhaseAmountLabel(this.cachePhase, this.cacheMeasure)}）。`
          + '已保存到相册的图片不受影响。',
        buttons: [
          { text: '取消', color: AppTheme.TEXT_SUB },
          { text: '清理', color: AppTheme.ACCENT_DARK }
        ]
      });

      confirmed = answer.index === 1;
    } catch (err) {

      return;
    }
    if (!confirmed) {
      return;
    }

    this.cacheBusy = true;
    this.cachePhase = CachePhase.CLEARING;
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result: ClearResult = clearExportCache(context);
      this.lastCleared = result.cleared;
      this.lastFailed = result.failed;
      this.lastFreedBytes = result.freedBytes;
    } finally {
      this.cacheBusy = false;

      this.refreshCacheStats();
      if (this.lastFailed > 0) {
        this.cachePhase = CachePhase.PARTIAL_DONE;
      }
    }
  }

  @Builder
  CacheResultNotes() {
    ForEach(cacheResultLines(this.cachePhase, this.lastCleared, this.lastFailed, this.lastFreedBytes),
      (line: string, index: number) => {
        SettingsNote({ text: line })
      }, (line: string, index: number) => `cache_line_${index}`)
  }

  @Builder
  CachePane() {
    SettingsCard({
      content: (): void => { this.CacheCardRows() }
    })
    this.CacheResultNotes()
  }

  @Builder
  CacheCardRows() {
    SettingsInfoRow({
      label: '图片与导出缓存',
      sub: '清理图片导出产生的临时文件，不影响已保存的图片',
      value: cachePhaseAmountLabel(this.cachePhase, this.cacheMeasure),
      showDivider: this.cachePhase !== CachePhase.READ_FAIL && this.cachePhase !== CachePhase.EMPTY
        && this.cachePhase !== CachePhase.STATTING
    })
    if (this.cachePhase === CachePhase.READ_FAIL) {
      SettingsStatusLine({
        kind: SettingsStatusKind.ERROR,
        message: '无法读取缓存占用',
        retryLabel: '重试',
        onRetry: (): void => {
          this.refreshCacheStats();
        }
      })
    } else if (this.cachePhase === CachePhase.CLEARING) {
      SettingsActionRow({ label: '正在清理…', busyLabel: '正在清理…', busy: true })
    } else if (cachePhaseCanClear(this.cachePhase)) {
      SettingsActionRow({
        label: '清理缓存',
        onTap: (): void => {
          this.confirmClearCache();
        }
      })
    }
  }

  build() {

    Stack({ alignContent: Alignment.TopStart }) {
      Scroll(this.scroller) {
        Column() {

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

          .onAreaChange((_o: Area, n: Area) => {

            const contentH: number = Number(n.height);

            this.paneContentH = contentH;
            this.autoLoadMore(false);
            this.applyPendingRestore();
          })

        }
        .width('100%')
        .padding({ bottom: SettingsLayout.PAGE_BOTTOM_GAP })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      .onAreaChange((_o: Area, n: Area) => {
        this.viewportH = Number(n.height);
        this.autoLoadMore(false);
      })

      .onReachEnd(() => {
        this.autoLoadMore(true);
      })
      .onScroll(() => {
        this.updateNavGlass();
        this.autoLoadMore(false);
      })

      this.TitleBar()

      Row() {
        GlassBackButton({
          onTap: (): void => {
            this.goBack();
          }
        })
      }
      .margin({ left: 14, top: this.statusBarH + 8 })

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

  @Builder
  HomeGroup(group: SettingsGroup) {
    ForEach(group.entries, (entry: SettingsEntry, index: number) => {
      this.HomeRow(entry)
    }, (entry: SettingsEntry) => settingsEntryRenderKey(entry))
  }

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

      this.AppearancePane()
    } else if (this.pane === SettingsPane.CACHE) {

      this.CachePane()
    } else if (this.pane === SettingsPane.PERSONALIZATION ||
      this.pane === SettingsPane.PRIVACY_SETTINGS) {

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

  private startAvatarEdit(): void {
    if (this.avatarVm.busy || this.avatarVm.preparing || this.cropOpen) { return; }
    void this.pickAvatarForCrop();
  }

  private async pickAvatarForCrop(): Promise<void> {
    await this.avatarVm.select();
    if (!this.avatarVm.ready || this.avatarVm.sourceUri().length === 0) { return; }
    if (this.avatarVm.sourceWidthPx() <= 0 || this.avatarVm.sourceHeightPx() <= 0) { return; }
    this.cropOpen = true;
  }

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

  private avatarActionLabel(): string {
    if (this.avatarVm.preparing) { return '选择中…'; }
    if (this.avatarVm.submitting) { return '上传中…'; }
    if (this.avatarVm.syncing) { return '读取中…'; }
    return '修改';
  }

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

          .width('100%')
          .padding({ left: 0, right: 0 })
        }
      }
      .width('100%')
      .height(homeTopNavStore.style === HomeTopNavStyle.OFFICIAL_DUAL_ROW
        ? TOP_NAV_PREVIEW_DUAL_H : Math.max(TOP_NAV_PREVIEW_H, this.previewNavRowH + 28))
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

  @Builder
  HarmonyMaterialRow() {
    ForEach(this.harmonyEntries().slice(0, 1), (entry: SettingsEntry) => {
      SettingsOptionRow({
        label: entry.label,
        value: entry.value,
        showDivider: false,
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
    ForEach(this.harmonyEntries().slice(1, 3), (entry: SettingsEntry, index: number) => {
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
    ForEach(this.harmonyEntries().slice(3, 6), (entry: SettingsEntry, index: number) => {
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
    ForEach(this.harmonyEntries().slice(6, 7), (entry: SettingsEntry) => {
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

      .padding({ left: 64, right: 16, top: this.statusBarH })
    }
    .width('100%')
    .height(this.titleBarH())
  }
}
