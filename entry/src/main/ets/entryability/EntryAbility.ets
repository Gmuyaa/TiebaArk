/**
 * 应用入口：创建时装载外观/材质/字号等设置、初始化吧头像索引、注入屏蔽名单的账号作用域，
 * 并异步恢复登录态（不 await，避免启动被存储 IO 拖住）；窗口与前后台生命周期在下方转发。
 */
import { visualThemeStore } from '../common/appearance/VisualThemeStore';
import { applyNativeTheme } from '../theme/NativeTheme';
import { forumLevelStore } from '../common/appearance/ForumLevelStore';
import { followLayoutStore } from '../common/appearance/FollowLayoutStore';
import { signStrategyStore } from '../common/appearance/SignStrategyStore';
import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { hdsMaterial } from '@kit.UIDesignKit';
import { materialManager } from '../common/material/MaterialManager';
import { threadActionBarStore } from '../common/appearance/ThreadActionBarStore';
import { homeTopNavStore } from '../common/appearance/HomeTopNavStore';
import { homeNavigationHideStore } from '../common/appearance/HomeNavigationHideStore';
import { themeModeStore } from '../common/appearance/ThemeModeStore';
import { fontScaleStore } from '../common/appearance/FontSizeScaleStore';
import { appIconStore } from '../common/appearance/AppIconStore';
import { imageLoadStore } from '../common/appearance/ImageLoadStore';
import { imageLayoutStore } from '../common/appearance/ImageLayoutStore';
import { voicePlayerStyleStore } from '../common/appearance/VoicePlayerStyleStore';
import { forumDefaultTabStore } from '../common/appearance/ForumDefaultTabStore';
import { superResolutionStore } from '../common/appearance/SuperResolutionStore';
import { longImageMinimapStore } from '../common/appearance/LongImageMinimapStore';
import { smartReachStore } from '../common/appearance/SmartReachStore';
import { motionStore } from '../common/appearance/MotionStore';
import { windowBreakpoint } from '../common/appearance/WindowBreakpointStore';
import { videoPlayback } from '../viewmodel/VideoPlaybackVM';
import { voicePlayback } from '../viewmodel/VoicePlaybackVM';
import { threadBlockScope } from '../viewmodel/SessionOwner';
import { setThreadBlockScopeProvider } from '../utils/ThreadBlockStore';
import { foregroundRefresh } from '../viewmodel/ForegroundRefresh';
import app from '@system.app';
import { IMAGE_DISK_CACHE_BYTES } from '../model/CachePolicy';
import { trimExportCache } from '../utils/ExportCachePolicy';
import { flushForumAvatarCache } from '../utils/ForumAvatarPrefs';
import { launchDisclaimerStore } from '../utils/LaunchDisclaimerStore';
import { closeSharedHttpSession } from '../net/HttpClient';
import { startPostConsentServices, stopPostConsentServices } from '../viewmodel/AppStartup';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    launchDisclaimerStore.load(this.context);
    app.setImageFileCacheSize(IMAGE_DISK_CACHE_BYTES);
    try { trimExportCache(this.context); }
    catch (_) { hilog.warn(DOMAIN, 'CachePolicy', 'export cache maintenance failed'); }
    hilog.info(DOMAIN, 'TiebaArk', '%{public}s', 'Ability onCreate');

    // 屏蔽名单按账号分键，但落盘层（utils/ThreadBlockStore）不该 import 认证层：
    // 账号作用域在这里注入一次，口径在 viewmodel/SessionOwner；惰性求值，只需早于第一个读取它的页面。
    setThreadBlockScopeProvider(threadBlockScope);

    visualThemeStore.load(this.context);
    themeModeStore.load(this.context);
    smartReachStore.load(this.context);
    motionStore.load(this.context);
    motionStore.startSystemTracking();

    fontScaleStore.load(this.context);
    appIconStore.refresh().catch(() => {});

    imageLoadStore.load(this.context).catch(() => {});
    imageLayoutStore.load(this.context).catch(() => {});
    voicePlayerStyleStore.load(this.context).catch(() => {});
    forumDefaultTabStore.load(this.context).catch(() => {});

    superResolutionStore.load(this.context).catch(() => {});
    longImageMinimapStore.load(this.context).catch(() => {});

    if (launchDisclaimerStore.accepted) {
      startPostConsentServices(this.context);
    }
    /*
     * 沉浸光感偏好：异步、不 await——`MaterialManager.load` 内部已吞异常并回落 `SYSTEM`。
     * 必须在首帧前发起：`mode` 是 `@Trace` 的，读到偏好后会自己刷新一次。
     */
    materialManager.load(this.context).catch(() => {});

    threadActionBarStore.load(this.context).catch(() => {});

    // 首页顶部频道页签样式偏好：同上（异步、不 await、异常已吞）；`style` 是 `@Trace` 的。
    forumLevelStore.load(this.context).catch(() => {});
    followLayoutStore.load(this.context).catch(() => {});
    signStrategyStore.load(this.context).catch(() => {});
    homeTopNavStore.load(this.context).catch(() => {});
    homeNavigationHideStore.load(this.context).catch(() => {});

    try {
      const supported: number[] = hdsMaterial.getSystemMaterialTypes() as number[];
      hilog.info(DOMAIN, 'TiebaMaterial', 'system material types: %{public}s',
        JSON.stringify(supported));
    } catch (e) {
      hilog.warn(DOMAIN, 'TiebaMaterial', 'getSystemMaterialTypes failed: %{public}s', String(e));
    }
  }

  onDestroy(): void {
    motionStore.stopSystemTracking();
    stopPostConsentServices();
    closeSharedHttpSession();
    hilog.info(DOMAIN, 'TiebaArk', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'TiebaArk', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'TiebaArk', 'Failed to load the content. Cause: %{public}s',
          JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'TiebaArk', '%{public}s', 'Succeeded in loading the content.');
      visualThemeStore.setThemeRefresher(applyNativeTheme);
      themeModeStore.setPaletteRefresher(applyNativeTheme);
      applyNativeTheme();
    });

    windowStage.getMainWindow().then((win: window.Window) => {
      windowBreakpoint.attachWindow(win);

      win.setWindowLayoutFullScreen(true).catch((e: Error) => {
        hilog.warn(DOMAIN, 'TiebaArk', 'setWindowLayoutFullScreen failed: %{public}s', e.message);
      });
      this.applySystemBarContentColor(win);
      // 深色模式档位变化（设置页选档 / 跟随系统时系统切深浅色）后重设系统栏内容色
      themeModeStore.setSystemBarRefresher(() => {
        this.applySystemBarContentColor(win);
      });
    }).catch((e: Error) => {
      hilog.warn(DOMAIN, 'TiebaArk', 'getMainWindow failed: %{public}s', e.message);
    });
  }

  onWindowStageDestroy(): void {
    windowBreakpoint.detachWindow();
    visualThemeStore.setThemeRefresher(undefined);
    themeModeStore.setPaletteRefresher(undefined);
    // 系统栏回调持有 mainWindow：窗口销毁后必须撤销，否则主题变化会对着已销毁的 Window 调用
    themeModeStore.setSystemBarRefresher(undefined);
    hilog.info(DOMAIN, 'TiebaArk', '%{public}s', 'Ability onWindowStageDestroy');
  }

  private applySystemBarContentColor(win: window.Window): void {
    let contentColor: string;
    try {
      const color: number = this.context.resourceManager
        .getColorSync($r('app.color.app_status_bar_content').id);
      // getColorSync 返回 0xAARRGGBB；系统栏 API 吃 '#RRGGBB' —— 剥掉 alpha（内容色恒不透明）
      contentColor = `#${(color & 0xFFFFFF).toString(16).padStart(6, '0').toUpperCase()}`;
    } catch (e) {
      contentColor = themeModeStore.isDark ? '#F2F3F4' : '#1B1B1B';
    }
    win.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      statusBarContentColor: contentColor,
      navigationBarColor: '#00000000',
      navigationBarContentColor: contentColor
    }).catch((e: Error) => {
      hilog.warn(DOMAIN, 'TiebaArk', 'setWindowSystemBarProperties failed: %{public}s',
        e.message);
    });
  }

  onForeground(): void {
    motionStore.startSystemTracking();
    smartReachStore.foreground = true;
    if (launchDisclaimerStore.accepted) {
      foregroundRefresh.onForeground();
    }
    hilog.info(DOMAIN, 'TiebaArk', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    smartReachStore.foreground = false;
    foregroundRefresh.onBackground();
    void videoPlayback.stop();
    void voicePlayback.stop();
    // 切后台是落盘点：吧头像索引只在这里（以及 10s 兜底定时器）写盘。
    void flushForumAvatarCache();
    hilog.info(DOMAIN, 'TiebaArk', '%{public}s', 'Ability onBackground');
  }
}
