/** 首次启动免责声明的确认状态持久化；首帧前同步读取，不纳入缓存清理、不按账号隔离。 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  DISCLAIMER_VERSION, isDisclaimerAccepted, normalizeDisclaimerVersion
} from '../model/LaunchDisclaimer';

const DISCLAIMER_STORE_NAME: string = 'tieba_launch_disclaimer';
const DISCLAIMER_KEY_ACCEPTED_VERSION: string = 'accepted_version';

@ObservedV2
export class LaunchDisclaimerStore {
  @Trace acceptedVersion: number = 0;
  private loaded: boolean = false;

  get accepted(): boolean {
    return isDisclaimerAccepted(this.acceptedVersion);
  }

  /** 首帧前同步恢复；读盘失败保持未同意（fail-closed），不伪造已确认。 */
  load(context: common.UIAbilityContext): void {
    if (this.loaded) { return; }
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(
        context, { name: DISCLAIMER_STORE_NAME });
      this.acceptedVersion = normalizeDisclaimerVersion(
        store.getSync(DISCLAIMER_KEY_ACCEPTED_VERSION, 0) as number);
      this.loaded = true;
    } catch (_) {
      this.acceptedVersion = 0;
      hilog.warn(0x0000, 'LaunchDisclaimer', 'disclaimer preference unavailable, keep unaccepted');
    }
  }

  /** 落盘成功才发布已同意状态；存储失败返回 false，不伪装已保存。 */
  accept(context: common.UIAbilityContext): boolean {
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(
        context, { name: DISCLAIMER_STORE_NAME });
      store.putSync(DISCLAIMER_KEY_ACCEPTED_VERSION, DISCLAIMER_VERSION);
      store.flushSync();
      this.acceptedVersion = DISCLAIMER_VERSION;
      this.loaded = true;
      return true;
    } catch (_) {
      hilog.warn(0x0000, 'LaunchDisclaimer', 'disclaimer acceptance save failed');
      return false;
    }
  }
}

export const launchDisclaimerStore: LaunchDisclaimerStore = new LaunchDisclaimerStore();
