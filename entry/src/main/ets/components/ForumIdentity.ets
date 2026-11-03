import { ForumExperience } from './ForumExperience';
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { authSession, AuthSession } from '../auth/AuthSession';
import { AppTheme } from '../theme/Theme';
import { formatCount } from '../model/UserProfile';
import { ForumHeaderVM } from '../viewmodel/ForumHeaderVM';
import { cachedForumAvatar } from '../viewmodel/ForumReadCache';
import { ForumAvatarImage, forumAvatarRadius } from './ForumAvatarImage';
import { ForumActionButton } from './ForumActionButton';
import { ForegroundRefresh, foregroundRefresh } from '../viewmodel/ForegroundRefresh';
import { hilog } from '@kit.PerformanceAnalysisKit';

const FORUM_AVATAR_SIZE: number = 64;
const FORUM_AVATAR_FRAME_SIZE: number = 72;
const FORUM_AVATAR_OVERLAP: number = 32;
const FORUM_IDENTITY_ROW_GAP: number = 12;
/** 大吧名行的起点，供宿主按同一布局阈值交接固定工具栏标题。 */
export const FORUM_IDENTITY_TITLE_TOP: number = FORUM_AVATAR_FRAME_SIZE - FORUM_AVATAR_OVERLAP + FORUM_IDENTITY_ROW_GAP;

/** 吧头身份区：未关注为关注入口，确认关注后同一按钮切换为签到。 */
@ComponentV2
export struct ForumIdentity {
  @Param active: boolean = true;
  @Local foreground: ForegroundRefresh = foregroundRefresh;
  private foregroundRevision: number = foregroundRefresh.revision;
  private foregroundRefreshPending: boolean = false;
  private foregroundAccount: string = '';

  @Monitor('foreground.revision', 'active')
  onForegroundRefresh(): void {
    if (!this.active) { this.foregroundRefreshPending = false; return; }
    if (this.foregroundRevision === this.foreground.revision) { return; }
    this.foregroundRevision = this.foreground.revision;
    this.foregroundAccount = authSession.forumCacheSessionKey();
    this.foregroundRefreshPending = true;
    this.applyForegroundRefresh();
  }

  @Monitor('vm.reading', 'vm.signing', 'vm.follow.loading', 'vm.follow.pending', 'vm.follow.known')
  applyForegroundRefresh(): void {
    if (!this.foregroundRefreshPending || !this.active || this.vm.reading || this.vm.signing ||
      this.vm.follow.loading || this.vm.follow.pending || !this.vm.follow.known) { return; }
    this.foregroundRefreshPending = false;
    if (this.foregroundAccount.length === 0 || this.foregroundAccount !== authSession.forumCacheSessionKey()) { return; }
    hilog.info(0x0000, 'ForegroundRefresh', 'forum requested revision=%{public}d', this.foregroundRevision);
    void this.vm.ensureMembership(this.context(), true);
  }

  @Param forumId: number = 0;
  @Param forumName: string = '';
  @Param avatar: string = '';
  @Param refreshRevision: number = 0;
  @Param memberCount: number = 0;
  @Event onOpenInformation: () => void = (): void => {};
  @Event onIntroductionVisible: (visible: boolean) => void = (visible: boolean): void => {};
  @Local vm: ForumHeaderVM = new ForumHeaderVM();
  @Local auth: AuthSession = authSession;
  private boundAccount: string = '';
  private boundForumId: number = 0;
  private boundForumName: string = '';

  aboutToAppear(): void { void this.bind(); }
  aboutToDisappear(): void { this.vm.dispose(); }
  @Monitor('forumId', 'forumName', 'auth.snapshot')
  onIdentityChanged(): void {
    if (this.boundForumId === this.forumId && this.boundForumName === this.forumName &&
      this.boundAccount === authSession.forumCacheSessionKey()) { return; }
    void this.bind();
  }
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
    this.boundAccount = authSession.forumCacheSessionKey();
    this.boundForumId = this.forumId;
    this.boundForumName = this.forumName;
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
    Column({ space: FORUM_IDENTITY_ROW_GAP }) {
      Row() {
        Stack() {
          ForumAvatarImage({
            url: this.avatar.length > 0 ? this.avatar : cachedForumAvatar(this.forumName, this.forumId),
            forumName: this.forumName, avatarSize: FORUM_AVATAR_SIZE, radius: forumAvatarRadius(FORUM_AVATAR_SIZE),
            bgColor: AppTheme.SURFACE_MUTED
          })
        }
        .width(FORUM_AVATAR_FRAME_SIZE).height(FORUM_AVATAR_FRAME_SIZE)
        .backgroundColor(AppTheme.CARD).borderRadius(forumAvatarRadius(FORUM_AVATAR_SIZE) + 4)
        .border({ width: 1, color: AppTheme.TEXT_MUTED })
        .translate({ y: -FORUM_AVATAR_OVERLAP }).flexShrink(0)
        .id('forum-overlap-avatar').onClick(() => { this.onOpenInformation(); })
      }
      .width('100%').height(FORUM_AVATAR_FRAME_SIZE - FORUM_AVATAR_OVERLAP)
      .justifyContent(FlexAlign.SpaceBetween).alignItems(VerticalAlign.Top).clip(false)
      Column({ space: 6 }) {
        Row({ space: 12 }) {
          Text(this.forumName.endsWith('吧') ? this.forumName : `${this.forumName}吧`)
            .fontSize(20).fontWeight(FontWeight.Bold).fontColor(AppTheme.TEXT_MAIN)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            .id('forum-identity-name-line').onClick(() => { this.onOpenInformation(); })
          ForumActionButton({ label: this.vm.buttonLabel(), onHero: false,
            busy: this.vm.signing || (this.vm.reading && this.vm.membership.signed === undefined),
            disabled: this.forumId <= 0 || this.vm.follow.pending || this.vm.signing || this.vm.reading,
            onTap: (): void => { void this.activate(); } })
            .flexShrink(0).id('forum-identity-action')
        }.width('100%').alignItems(VerticalAlign.Center).id('forum-identity-title-row')
        // FRS 的 thread_num 随分区变化；吧头只使用公共资料的全吧 thread_count。
        Text(`关注 ${formatCount(this.vm.publicMemberCount >= 0 ? this.vm.publicMemberCount : this.memberCount)}    帖子 ${this.vm.publicThreadCount >= 0 ? formatCount(this.vm.publicThreadCount) : (this.vm.introductionError.length > 0 ? '读取失败' : '--')}`)
          .fontSize(12).fontColor(AppTheme.TEXT_SUB).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .onClick(() => { this.onOpenInformation(); })
        if (this.vm.follow.known && this.vm.follow.following && this.vm.membership.level >= 0) {
          ForumExperience({ currentScore: this.vm.membership.currentScore,
            nextScore: this.vm.membership.nextScore, level: this.vm.membership.level,
            levelName: this.vm.membership.levelName, compact: true })
            .id('forum-membership-summary')
            .onClick(() => { this.onOpenInformation(); })
        }
      }
      .width('100%').alignItems(HorizontalAlign.Start)
      if (this.showIntroduction()) {
        Row({ space: 8 }) {
          Text('吧简介').fontSize(12).fontColor(AppTheme.TEXT_SUB)
          Text(this.vm.introductionLoading ? '正在读取吧简介…' :
            (this.vm.introductionError || this.vm.introduction || '暂无简介'))
            .fontSize(13).fontColor(AppTheme.TEXT_SUB).layoutWeight(1).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([AppTheme.TEXT_SUB])
        }
        .width('100%').constraintSize({ minHeight: 32 }).alignItems(VerticalAlign.Center)
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .backgroundColor(AppTheme.SURFACE_MUTED).borderRadius(10).id('forum-introduction-summary')
        .onClick(() => {
          if (this.vm.introductionError.length > 0) { void this.vm.ensureIntroduction(this.context(), true); }
          else { this.onOpenInformation(); }
        })
      }
    }
    .width('100%').clip(false)
    .onVisibleAreaChange([1], (visible: boolean) => {
      if (visible) { void this.vm.ensureMembership(this.context()); }
    })
  }
}
