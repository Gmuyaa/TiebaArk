import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { authSession } from '../auth/AuthSession';
import { AppTheme } from '../theme/Theme';
import { ensureForumIdentity, ForumIdentity, forumIdentity, toggleForumFollow } from '../viewmodel/ForumStateStore';
import { ForumActionButton } from './ForumActionButton';

/**
 * 吧的关注按钮（吧资料、吧广场）。状态来自 `ForumStateStore`：
 * 同一账号同一个吧与吧页头共享一份实例，关注/取关一次即可让所有挂载中的入口同步，
 * 不再各自发一次首页请求去确认关注关系。
 */
@ComponentV2
export struct ForumFollowButton {
  @Param targetId: number = 0;
  @Param targetName: string = '';
  @Local identity: ForumIdentity = new ForumIdentity();
  private auth = authSession;

  aboutToAppear(): void { this.bind(); }
  @Monitor('targetId', 'targetName', 'auth.snapshot')
  syncTarget(): void { this.bind(); }
  @Monitor('identity.verificationError')
  reportVerification(): void {
    if (this.identity.verificationError.length > 0) {
      this.getUIContext().getPromptAction().showToast({ message: this.identity.verificationError });
    }
  }
  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }
  private bind(): void {
    const name: string = this.targetName.trim();
    if (this.targetId <= 0 && name.length === 0) { return; }
    const identity: ForumIdentity = forumIdentity(this.targetId, name);
    if (identity !== this.identity) { this.identity = identity; }
    void ensureForumIdentity(this.context(), this.targetId, name);
  }
  private async activate(): Promise<void> {
    if (!authSession.isLoggedIn()) { router.pushUrl({ url: 'pages/Login' }); return; }
    if (this.busy()) { return; }
    if (this.identity.known() && this.identity.follows()) {
      const confirm = await this.getUIContext().getPromptAction().showDialog({
        title: '取消关注', message: '确定取消关注这个吧吗？',
        buttons: [{ text: '保留关注', color: AppTheme.TEXT_SUB }, { text: '取消关注', color: AppTheme.ACCENT_DARK }]
      });
      if (confirm.index !== 1) { return; }
    }
    const message: string = await toggleForumFollow(this.context(), this.targetId, this.targetName.trim());
    if (message.length > 0) {
      this.getUIContext().getPromptAction().showToast({ message });
    }
  }
  private busy(): boolean {
    return this.identity.pending || this.identity.reading ||
      (this.identity.verifying && !this.identity.known());
  }
  /** 进行中只由按钮内的转圈表示，文案保持状态本身（2026-11-13 持有者要求去掉「…中…」字样）。 */
  private label(): string {
    if (!this.identity.known()) { return '重试'; }
    return this.identity.follows() ? '已关注' : '关注';
  }
  private followedAppearance(): boolean {
    return this.identity.known() && this.identity.follows() && !this.identity.pending;
  }
  build() {
    if (this.targetId > 0 || this.targetName.trim().length > 0) {
      ForumActionButton({ label: this.label(), busy: this.busy(), completed: this.followedAppearance(),
        retry: !this.identity.known() && !this.busy(),
        accessibilityLabel: `${this.targetName}，${this.label()}`,
        onTap: (): void => { void this.activate(); } })
    }
  }
}
