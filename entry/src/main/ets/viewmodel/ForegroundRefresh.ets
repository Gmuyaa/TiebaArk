import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { authSession } from '../auth/AuthSession';

/** 只在后台返回时通知可见页面；冷启动沿用各页已有的首次读取。 */
@ObservedV2
export class ForegroundRefresh {
  @Trace revision: number = 0;
  private backgrounded: boolean = false;
  private epoch: number = 0;
  private avatarRequest: Promise<void> | undefined = undefined;
  private avatarRequestRevision: number = -1;
  private avatarOwner: string = '';

  onBackground(): void {
    if (!this.backgrounded) { this.epoch++; }
    this.backgrounded = true;
  }

  onForeground(): void {
    if (!this.backgrounded) { return; }
    this.backgrounded = false;
    this.revision++;
    hilog.info(0x0000, 'ForegroundRefresh', 'resume revision=%{public}d', this.revision);
  }

  /** 页面显示与前台通知可能同帧到达，同账号同一轮共用资料和图片补读。 */
  async refreshAvatar(context: common.UIAbilityContext): Promise<void> {
    const owner: string = authSession.forumCacheSessionKey();
    if (this.avatarRequest !== undefined && this.avatarRequestRevision === this.epoch &&
      this.avatarOwner === owner) { return this.avatarRequest; }
    const request: Promise<void> = authSession.refreshOwnAvatarOnEntry(context);
    // 系统可能先调用页面 onPageShow，再调用 Ability.onForeground，二者仍属于同一轮。
    this.avatarRequestRevision = this.epoch;
    this.avatarOwner = owner;
    this.avatarRequest = request;
    try { await request; }
    finally { if (this.avatarRequest === request) { this.avatarRequest = undefined; } }
  }
}

export const foregroundRefresh: ForegroundRefresh = new ForegroundRefresh();
