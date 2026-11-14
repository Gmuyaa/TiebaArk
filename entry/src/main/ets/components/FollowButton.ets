import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { authSession } from '../auth/AuthSession';
import { FollowKind } from '../model/FollowOperation';
import { AppTheme } from '../theme/Theme';
import { followAction, FollowActionVM } from '../viewmodel/FollowActionVM';
import { ForumActionButton } from './ForumActionButton';
import { ForumFollowButton } from './ForumFollowButton';

/**
 * 关注按钮（用户；吧的形态见 `ForumFollowButton`）。
 *
 * 2026-11-13（1.0.268）：吧的关注状态收敛到 `ForumStateStore` 后，这里只处理用户，
 * 避免同一份"是否关注这个吧"同时存在两套缓存与两套读取。
 */
@ComponentV2
export struct FollowButton {
  @Param kind: FollowKind = 'user';
  @Param targetId: number = 0;
  @Param portrait: string = '';
  @Param targetName: string = '';
  /** 本人的粉丝行：关注后即互关。 */
  @Param fansStyle: boolean = false;
  @Event onChanged: () => void = (): void => {};
  @Local vm: FollowActionVM = new FollowActionVM('user', 0, '', '');
  private auth = authSession;

  aboutToAppear(): void { this.bind(); }
  @Monitor('targetId', 'portrait', 'targetName', 'auth.snapshot')
  syncTarget(): void { this.bind(); }
  @Monitor('vm.verificationError')
  reportVerification(): void {
    if (this.vm.verificationError.length > 0) {
      this.getUIContext().getPromptAction().showToast({ message: this.vm.verificationError });
    }
  }
  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }
  private bind(): void {
    if (this.kind === 'forum') { return; }
    if (this.targetId <= 0 && this.portrait.length === 0) { return; }
    const vm: FollowActionVM = followAction(this.kind, this.targetId, this.portrait, this.targetName);
    if (vm === this.vm) { return; }
    this.vm = vm;
    this.vm.load(this.context());
  }
  private async activate(): Promise<void> {
    if (!authSession.isLoggedIn()) { router.pushUrl({ url: 'pages/Login' }); return; }
    if (this.vm.loading || this.vm.pending || (this.vm.verifying && !this.vm.known)) { return; }
    if (this.vm.known && this.vm.following) {
      const confirm = await this.getUIContext().getPromptAction().showDialog({
        title: '取消关注', message: '确定取消关注这位用户吗？',
        buttons: [{ text: '保留关注', color: AppTheme.TEXT_SUB }, { text: '取消关注', color: AppTheme.ACCENT_DARK }]
      });
      if (confirm.index !== 1) { return; }
    }
    const before: boolean = this.vm.following;
    const message: string = await this.vm.toggle(this.context());
    if (message.length > 0) { this.getUIContext().getPromptAction().showToast({ message }); }
    else if (before !== this.vm.following) { this.onChanged(); }
  }
  private busy(): boolean {
    return this.vm.loading || this.vm.pending || (this.vm.verifying && !this.vm.known);
  }
  /** 进行中只由按钮内的转圈表示，文案保持状态本身（2026-11-13 持有者要求去掉「…中…」字样）。 */
  private label(): string {
    if (!this.vm.known) { return '重试'; }
    return this.vm.following ? (this.fansStyle ? '已互关' : '已关注') : (this.fansStyle ? '回关' : '关注');
  }
  private followedAppearance(): boolean {
    return this.vm.known && this.vm.following && !this.vm.pending;
  }
  build() {
    if (this.kind === 'forum') {
      ForumFollowButton({ targetId: this.targetId, targetName: this.targetName })
    } else if (!this.vm.self && (this.targetId > 0 || this.portrait.length > 0)) {
      ForumActionButton({ label: this.label(), busy: this.busy(), completed: this.followedAppearance(),
        retry: !this.vm.known && !this.busy(),
        accessibilityLabel: `${this.targetName}，${this.label()}`,
        onTap: (): void => { void this.activate(); } })
    }
  }
}
