import { forumLevelStore } from '../common/appearance/ForumLevelStore';
import { signStrategyStore } from '../common/appearance/SignStrategyStore';
import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { hdsMaterial } from '@kit.UIDesignKit';
import { authSession } from '../auth/AuthSession';
import { materialManager } from '../common/material/MaterialManager';
import { threadActionBarStore } from '../common/appearance/ThreadActionBarStore';
import { homeTopNavStore } from '../common/appearance/HomeTopNavStore';
import { homeNavigationHideStore } from '../common/appearance/HomeNavigationHideStore';
import { themeModeStore } from '../common/appearance/ThemeModeStore';
import { fontScaleStore } from '../common/appearance/FontSizeScaleStore';
import { lowFlowStore } from '../common/appearance/LowFlowStore';
import { forumDefaultTabStore } from '../common/appearance/ForumDefaultTabStore';
import { superResolutionStore } from '../common/appearance/SuperResolutionStore';
import { smartReachStore } from '../common/appearance/SmartReachStore';
import { videoPlayback } from '../viewmodel/VideoPlaybackVM';
import { voicePlayback } from '../viewmodel/VoicePlaybackVM';
import { restoreForumCache } from '../viewmodel/ForumReadCache';
import { foregroundRefresh } from '../viewmodel/ForegroundRefresh';
import app from '@system.app';
import { IMAGE_DISK_CACHE_BYTES } from '../model/CachePolicy';
import { trimExportCache } from '../utils/ExportCachePolicy';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    app.setImageFileCacheSize(IMAGE_DISK_CACHE_BYTES);
    try { trimExportCache(this.context); }
    catch (_) { hilog.warn(DOMAIN, 'CachePolicy', 'export cache maintenance failed'); }
    hilog.info(DOMAIN, 'TiebaArk', '%{public}s', 'Ability onCreate');

    themeModeStore.load(this.context);
    smartReachStore.load(this.context);

    fontScaleStore.load(this.context);

    lowFlowStore.load(this.context).catch(() => {});
    forumDefaultTabStore.load(this.context).catch(() => {});

    superResolutionStore.load(this.context).catch(() => {});

    // 恢复登录态：异步且不 await——启动流程不被存储 IO 拖住，
    // 读不到就当未登录（只读浏览照旧可用）。
    authSession.restore(this.context).then(() => {
      restoreForumCache(this.context);
      hilog.info(DOMAIN, 'TiebaArk', 'auth restore done: %{public}s', authSession.describe());
    }).catch(() => {
      hilog.warn(DOMAIN, 'TiebaArk', '%{public}s', 'auth restore failed, fallback to logged-out');
    });
    /*
     * 沉浸光感偏好（用户选的强度档位）：同样异步、不 await ——
     * `MaterialManager.load` 内部已把异常吞掉并回落 `SYSTEM`，读不出来不影响启动。
     * 必须在首帧前发起：页面 `aboutToAppear` 里读到的可能是默认值，
     * 但 `mode` 是 `@Trace` 的，读到偏好后会自己刷新一次。
     */
    materialManager.load(this.context).catch(() => {});

    threadActionBarStore.load(this.context).catch(() => {});

    /*
     * 首页顶部频道页签样式偏好：与操作栏样式同一套取舍（异步、不 await、异常已吞）。
     * `style` 是 `@Trace` 的，读到偏好后 ForumListView 自己会刷新一次。
     */
    forumLevelStore.load(this.context).catch(() => {});
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
    });

    windowStage.getMainWindow().then((win: window.Window) => {

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
    smartReachStore.foreground = true;
    foregroundRefresh.onForeground();
    hilog.info(DOMAIN, 'TiebaArk', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    smartReachStore.foreground = false;
    foregroundRefresh.onBackground();
    void videoPlayback.stop();
    void voicePlayback.stop();
    hilog.info(DOMAIN, 'TiebaArk', '%{public}s', 'Ability onBackground');
  }
}
