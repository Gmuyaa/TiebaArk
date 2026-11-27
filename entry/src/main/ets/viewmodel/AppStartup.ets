/**
 * 同意免责声明后才允许启动的服务集合（网络监听、登录恢复与缓存/吧头像索引）。
 * 由 EntryAbility（已同意的冷启动）与 Index（首次同意放行）共用，避免两处重复维护。
 */

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { authSession } from '../auth/AuthSession';
import { networkKindWatch } from '../utils/NetworkKindWatch';
import { initForumAvatarCache } from '../utils/ForumAvatarPrefs';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { restoreForumCache } from './ForumReadCache';

const DOMAIN: number = 0x0000;
let postConsentStarted: boolean = false;

export function startPostConsentServices(context: common.UIAbilityContext): void {
  if (postConsentStarted) { return; }
  postConsentStarted = true;
  void initForumAvatarCache(context);
  void DeviceIdentity.ensure(context);
  networkKindWatch.start();
  authSession.restore(context).then(() => {
    restoreForumCache(context);
    hilog.info(DOMAIN, 'TiebaArk', 'auth restore done: %{public}s', authSession.describe());
  }).catch(() => {
    hilog.warn(DOMAIN, 'TiebaArk', '%{public}s', 'auth restore failed, fallback to logged-out');
  });
}

export function stopPostConsentServices(): void {
  postConsentStarted = false;
  networkKindWatch.stop();
}
