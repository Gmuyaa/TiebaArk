import { ForumExperience } from './ForumExperience';
import { ForumLevelBadge } from './ForumLevelBadge';
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { authSession, AuthSession } from '../auth/AuthSession';
import { AppTheme } from '../theme/Theme';
import { formatCount } from '../model/UserProfile';
import { ForumHeaderVM } from '../viewmodel/ForumHeaderVM';
import { cachedForumAvatar } from '../viewmodel/ForumReadCache';
import { ForumAvatarImage, forumAvatarRadius } from './ForumAvatarImage';

@ComponentV2
export struct ForumIdentity {
  @Param forumId: number = 0;
  @Param forumName: string = '';
  @Param avatar: string = '';
  @Param refreshRevision: number = 0;
  @Param memberCount: number = 0;
  @Param threadCount: number = 0;
  @Event onOpenInformation: () => void = (): void => {};
  @Event onIntroductionVisible: (visible: boolean) => void = (visible: boolean): void => {};
  @Local vm: ForumHeaderVM = new ForumHeaderVM();
  @Local auth: AuthSession = authSession;

  aboutToAppear(): void { void this.bind(); }
  aboutToDisappear(): void { this.vm.dispose(); }
  @Monitor('forumId', 'forumName', 'auth.snapshot')
  onIdentityChanged(): void { void this.bind(); }
  @Monitor('vm.follow.following', 'vm.follow.known', 'vm.follow.pending')
  onFollowChanged(): void {
    this.onIntroductionVisible(this.showIntroduction());
    void this.vm.ensureMembership(this.context());
    void this.vm.ensureIntroduction(this.context());
  }
  @Monitor('refreshRevision')
  onRefresh(): void { void this.vm.ensureMembership(this.context(), true); void this.vm.ensureIntroduction(this.context(), true); }
  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }
  private async bind(): Promise<void> {
    await this.vm.initialize(this.context(), this.forumId, this.forumName);
    this.onIntroductionVisible(this.showIntroduction());
    void this.vm.ensureIntroduction(this.context());
  }
  private async activate(): Promise<void> {
    if (!authSession.isLoggedIn()) { router.pushUrl({ url: 'pages/Login' }); return; }
    const message: string = await this.vm.activate(this.context());
    if (message.length > 0) { this.getUIContext().getPromptAction().showToast({ message }); }
  }
  private showIntroduction(): boolean {
    return this.vm.follow.known && (!this.vm.follow.following || this.vm.follow.pending);
  }
  build() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Row({ space: 12 }) {

          ForumAvatarImage({
            url: this.avatar.length > 0 ? this.avatar : cachedForumAvatar(this.forumName, this.forumId),
            forumName: this.forumName, avatarSize: 64, radius: forumAvatarRadius(64), onHero: true,
            bgColor: AppTheme.SURFACE_MUTED
          })
          Column({ space: 6 }) {
            Text(this.forumName.endsWith('吧') ? this.forumName : `${this.forumName}吧`)
              .fontSize(22).fontWeight(FontWeight.Bold).fontColor(Color.White)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            if (!this.showIntroduction() && this.vm.follow.known && this.vm.follow.following && this.vm.membership.level >= 0) {
              Row({ space: 6 }) {
                ForumLevelBadge({ level: this.vm.membership.level, levelName: this.vm.membership.levelName, onHero: true })
                Column() {
                  ForumExperience({ currentScore: this.vm.membership.currentScore,
                    nextScore: this.vm.membership.nextScore, onHero: true })
                }.layoutWeight(1)
              }.width('100%')
            }
            if (this.showIntroduction()) {
              Text(`关注 ${formatCount(this.vm.publicMemberCount >= 0 ? this.vm.publicMemberCount : this.memberCount)}    帖子 ${formatCount(this.vm.publicThreadCount >= 0 ? this.vm.publicThreadCount : this.threadCount)}`)
                .fontSize(13).fontColor('#DDE3ED').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1).height(76).onClick(() => { this.onOpenInformation(); })
        Text(this.vm.buttonLabel())
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor(Color.White)
          .textAlign(TextAlign.Center).height(36).constraintSize({ minWidth: 72, maxWidth: 116 })
          .padding({ left: 12, right: 12 }).borderRadius(18).backgroundColor('#33FFFFFF')
          .backgroundEffect({ radius: 20, saturation: 1.1, brightness: 1.05, color: '#30FFFFFF' })
          .border({ width: 1, color: '#40FFFFFF' }).clip(true)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .opacity(this.vm.signing || (this.vm.reading && this.vm.membership.signed === undefined) ? 0.6 : 1)
          .enabled(this.forumId > 0 && !this.vm.follow.pending && !this.vm.signing && !this.vm.reading)
          .onClick(() => { void this.activate(); })
          .accessibilityText(this.vm.buttonLabel())
      }
      .width('100%').height(76).alignItems(VerticalAlign.Center)
      if (this.vm.follow.known && this.vm.follow.following &&
        (this.vm.membership.continuousCount >= 0 || this.vm.membership.totalCount >= 0)) {
        Text((this.vm.membership.continuousCount >= 0
          ? `连续签到 ${this.vm.membership.continuousCount} 天` : '') +
          (this.vm.membership.continuousCount >= 0 && this.vm.membership.totalCount >= 0 ? '  ·  ' : '') +
          (this.vm.membership.totalCount >= 0 ? `累计签到 ${this.vm.membership.totalCount} 次` : ''))
          .fontSize(12).fontColor('#DDE3ED')
          .width('100%')
      }
      if (this.showIntroduction()) {
        Row({ space: 8 }) {
          Text('吧简介').fontSize(13).fontWeight(FontWeight.Medium).fontColor(Color.White)
          Text(this.vm.introductionLoading ? '正在读取吧简介…' :
            (this.vm.introductionError || this.vm.introduction || '暂无吧简介'))
            .fontSize(13).fontColor('#DDE3ED').layoutWeight(1).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor(['#DDE3ED'])
        }
        .width('100%').height(44).alignItems(VerticalAlign.Top)
        .onClick(() => {
          if (this.vm.introductionError.length > 0) { void this.vm.ensureIntroduction(this.context(), true); }
          else { this.onOpenInformation(); }
        })
      }
    }
    .width('100%')
    .onVisibleAreaChange([1], (visible: boolean) => {
      if (visible) { void this.vm.ensureMembership(this.context()); }
    })
  }
}
