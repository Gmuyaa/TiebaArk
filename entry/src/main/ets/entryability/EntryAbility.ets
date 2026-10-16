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
import { videoPlayback } from '../viewmodel/VideoPlaybackVM';
import { voicePlayback } from '../viewmodel/VoicePlaybackVM';
import { restoreForumCache } from '../viewmodel/ForumReadCache';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'TiebaArk', '%{public}s', 'Ability onCreate');

    themeModeStore.load(this.context);

    fontScaleStore.load(this.context);

    lowFlowStore.load(this.context).catch(() => {});
    forumDefaultTabStore.load(this.context).catch(() => {});

    superResolutionStore.load(this.context).catch(() => {});

    authSession.restore(this.context).then(() => {
      restoreForumCache(this.context);
      hilog.info(DOMAIN, 'TiebaArk', 'auth restore done: %{public}s', authSession.describe());
    }).catch(() => {
      hilog.warn(DOMAIN, 'TiebaArk', '%{public}s', 'auth restore failed, fallback to logged-out');
    });

    materialManager.load(this.context).catch(() => {});

    threadActionBarStore.load(this.context).catch(() => {});

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
    hilog.info(DOMAIN, 'TiebaArk', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    void videoPlayback.stop();
    void voicePlayback.stop();
    hilog.info(DOMAIN, 'TiebaArk', '%{public}s', 'Ability onBackground');
  }
}
