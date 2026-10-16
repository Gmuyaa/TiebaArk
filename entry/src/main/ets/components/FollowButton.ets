import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { authSession } from '../auth/AuthSession';
import { FollowKind } from '../model/FollowOperation';
import { AppTheme } from '../theme/Theme';
import { followAction, FollowActionVM } from '../viewmodel/FollowActionVM';

@ComponentV2
export struct FollowButton {
  @Param kind: FollowKind = 'user';
  @Param targetId: number = 0;
  @Param portrait: string = '';
  @Param targetName: string = '';
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
        title: '取消关注', message: `确定取消关注${this.kind === 'forum' ? '这个吧' : '这位用户'}吗？`,
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
  private label(): string {
    if (this.vm.loading) { return '读取中…'; }
    if (this.vm.pending) { return '提交中…'; }
    if (this.vm.verifying && !this.vm.known) { return '确认中…'; }
    return this.vm.known ? (this.vm.following ? '已关注' : '关注') : '重试关注状态';
  }
  build() {
    if (!this.vm.self && (this.targetId > 0 || this.portrait.length > 0)) {
      Text(this.label())
        .fontSize(13).fontColor(Color.White).textAlign(TextAlign.Center).constraintSize({ minHeight: 40 })
        .padding({ left: 16, right: 16, top: 8, bottom: 8 }).borderRadius(16).backgroundColor(AppTheme.ACCENT)
        .opacity(this.busy() ? 0.6 : 1).enabled(!this.busy())
        .accessibilityText(this.label())
        .onClick(() => { this.activate(); })
    }
  }
}
