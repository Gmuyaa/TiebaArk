import { ForumExperience } from './ForumExperience';
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { authSession, AuthSession } from '../auth/AuthSession';
import { AppTheme } from '../theme/Theme';
import { formatForumCount } from '../model/UserProfile';
import { ForumHeaderVM } from '../viewmodel/ForumHeaderVM';
import { cachedForumAvatar } from '../viewmodel/ForumReadCache';
import { ForumAvatarImage, forumAvatarRadius } from './ForumAvatarImage';
import { ForumActionButton } from './ForumActionButton';
import { ForegroundRefresh, foregroundRefresh } from '../viewmodel/ForegroundRefresh';
import { hilog } from '@kit.PerformanceAnalysisKit';

const FORUM_AVATAR_SIZE: number = 64;
export const FORUM_AVATAR_FRAME_SIZE: number = 72;
/** 吧头右侧：关注按钮在布局里只占视觉高度 32（触控由 ForumActionButton 的 responseRegion 补到 44），
 *  这样「经验条/数量行」的底边才能和关注按钮的视觉底边对齐（见 FORUM_IDENTITY_HERO_RIGHT_H）。 */
const FORUM_HERO_ACTION_LAYOUT_H: number = 32;
/** 吧头右侧列高：「名称行 32 + 行距 4 + 经验条 16」放进头像框 72 后上下等距 →
 *  inset = (72 − 32 − 4 − 16) / 2 = 10，列高 = 72 − 10 = 62。
 *  这样「经验条底 → 头像框底」与「关注按钮顶 → 头像框顶」都等于 10vp（持有者第 1 条，恒相等）。 */
const FORUM_HERO_EXP_H: number = 16;
/** 名称行与「经验条/数量行」之间的行距（2026-11-11 持有者两次要求拉开：4 → 8）。 */
const FORUM_HERO_ROW_GAP: number = 8;
const FORUM_IDENTITY_HERO_INSET: number =
  (FORUM_AVATAR_FRAME_SIZE - FORUM_HERO_ACTION_LAYOUT_H - FORUM_HERO_ROW_GAP - FORUM_HERO_EXP_H) / 2;
const FORUM_IDENTITY_HERO_RIGHT_H: number = FORUM_AVATAR_FRAME_SIZE - FORUM_IDENTITY_HERO_INSET;
/** 图上吧简介：1 行胶囊，高度与字体参考「看帖顺序」右侧的 回复/发布 胶囊（24vp / 12fp）。 */
const FORUM_IDENTITY_INTRO_H: number = 24;
export const FORUM_IDENTITY_INTRO_GAP: number = 6;
export const FORUM_IDENTITY_INTRO_HEIGHT: number = FORUM_IDENTITY_INTRO_H;
const FORUM_INTRO_FONT_SIZE: number = 12;
/** 大吧名行的起点，供宿主按同一布局阈值交接固定工具栏标题。 */
/** 大吧名行在吧头里的起点（vp）：头像框 72 − 32（旧跨界量）+ 12（旧行距）= 52。
 *  宿主的固定工具栏按同一阈值交接标题；分支清理后按数值保留。 */
export const FORUM_IDENTITY_TITLE_TOP: number = 52;

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

  @Monitor('vm.identity.reading', 'vm.identity.signing', 'vm.identity.pending', 'vm.identity.following')
  applyForegroundRefresh(): void {
    if (!this.foregroundRefreshPending || !this.active || this.vm.identity.reading || this.vm.identity.signing ||
      this.vm.identity.pending || !this.vm.followKnown()) { return; }
    this.foregroundRefreshPending = false;
    if (this.foregroundAccount.length === 0 || this.foregroundAccount !== authSession.forumCacheSessionKey()) { return; }
    hilog.info(0x0000, 'ForegroundRefresh', 'forum requested revision=%{public}d', this.foregroundRevision);
    void this.vm.ensureMembership(this.context(), true);
  }

  @Param forumId: number = 0;
  @Param forumName: string = '';
  @Param avatar: string = '';
  @Param refreshRevision: number = 0;
  /** 顶栏完全盖住吧头像后，英雄区这枚头像退出组件树（作为共享元素转场的 out 端）。 */
  @Param avatarVisible: boolean = true;
  @Param memberCount: number = 0;
  /**
   * 吧信息浮在吧头图上（2026-11-10 持有者定）：文字与数据直接落在图上，
   * 不再有独立的卡片底。开启后整套配色换成随图可读的浅色文字 + 文字投影，
   * 吧简介摘要条改成半透明深色胶囊；头像保留白描边确保在任意图上都可辨。
   */
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
  @Monitor('vm.identity.following', 'vm.identity.pending')
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
    return this.vm.followKnown() && (!this.vm.follows() || this.vm.followPending());
  }
  build() {
    // 2026-11-11 清理：非图上（头像跨界卡片）分支已无人使用，只保留吧头图上的形态。
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        Stack() {
          if (this.avatarVisible) {
          ForumAvatarImage({
            url: this.avatar.length > 0 ? this.avatar : cachedForumAvatar(this.forumName, this.forumId),
            forumName: this.forumName, avatarSize: FORUM_AVATAR_SIZE, radius: forumAvatarRadius(FORUM_AVATAR_SIZE),
            bgColor: AppTheme.SURFACE_MUTED
          })
            .geometryTransition('forum-avatar')
            // 飞入时大图要尽快隐去（2026-11-12 持有者反馈）：out 端只留 90ms 淡出，
            // 免得 morph 全程都看得见那枚大头像。
            .transition(TransitionEffect.OPACITY.animation({ duration: 90, curve: Curve.EaseOut }))
          }
        }
        .width(FORUM_AVATAR_FRAME_SIZE).height(FORUM_AVATAR_FRAME_SIZE)
        .borderRadius(forumAvatarRadius(FORUM_AVATAR_SIZE))
        .flexShrink(0)
        .id('forum-overlap-avatar').onClick(() => { this.onOpenInformation(); })

        // 右侧两行（2026-11-11 持有者定）：上排 吧名 + 关注/签到，下排按关注态二选一——
        // 已关注显示经验条，未关注显示「关注 / 帖子」数量。列高 62 且底部对齐、两行间距 8，
        // 于是下排底边落在「头像框底 − 8vp」，与关注按钮顶距头像框顶的 8vp 相等（持有者第 1 条）。
        Column({ space: FORUM_HERO_ROW_GAP }) {
          Row({ space: 8 }) {
            Text(this.forumName.endsWith('吧') ? this.forumName : `${this.forumName}吧`)
              .fontSize(20).fontWeight(FontWeight.Bold)
              // 白字可读。不给 Text 挂 .shadow——ArkUI 的投影画在组件矩形框上，
              // 白字会变成"每行拖一个半透明胶囊底"（2026-11-10 实测）。
              .fontColor(Color.White)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              .id('forum-identity-name-line').onClick(() => { this.onOpenInformation(); })

            ForumActionButton({ label: this.vm.buttonLabel(),
              actionSymbol: this.vm.buttonIsSign() ? $r('sys.symbol.calendar') : $r('sys.symbol.plus'),
              busy: this.vm.buttonBusy(), completed: this.vm.buttonCompleted(),
              retry: this.vm.buttonLabel().startsWith('重试'),
              disabled: this.forumId <= 0 || this.vm.buttonCompleted(),
              accessibilityLabel: `${this.forumName}，${this.vm.buttonLabel()}`,
              minTouchHeight: FORUM_HERO_ACTION_LAYOUT_H,
              onTap: (): void => { void this.activate(); } })
              .flexShrink(0).id('forum-identity-action')
          }
          .width('100%').height(FORUM_HERO_ACTION_LAYOUT_H).alignItems(VerticalAlign.Center)

          if (this.vm.followKnown() && this.vm.follows()) {
            ForumExperience({ currentScore: this.vm.identity.currentScore,
              nextScore: this.vm.identity.nextScore, level: this.vm.identity.level,
              levelName: this.vm.identity.levelName, onHero: true, compact: true })
              .id('forum-membership-summary')
          } else {
            Text(`关注 ${formatForumCount(this.vm.publicMemberCount >= 0 ? this.vm.publicMemberCount : this.memberCount)}  帖子 ${this.vm.publicThreadCount >= 0 ? formatForumCount(this.vm.publicThreadCount) : '--'}`)
              .fontSize(12).fontColor('#E6FFFFFF')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              // 与经验条同高：两种情况都让名称行/数量行的上下留白相等（否则这一行 14 高会差 2vp）。
              .height(FORUM_HERO_EXP_H)
              .id('forum-identity-counts').onClick(() => { this.onOpenInformation(); })
          }
        }
        .layoutWeight(1).height(FORUM_IDENTITY_HERO_RIGHT_H)
        .justifyContent(FlexAlign.End).alignItems(HorizontalAlign.Start)
      }
      .width('100%').alignItems(VerticalAlign.Top)
      .id('forum-identity-hero-row')

      // 未关注时在头像下方给一行简介（2026-11-11 持有者定）：1 行、超出省略，
      // 胶囊高度/字号对齐「看帖顺序」右侧的 回复/发布 胶囊；关注后即消失。
      if (this.showIntroduction()) {
        Row() {
          Text(this.vm.introductionLoading ? '简介 正在读取…' :
            `简介 ${this.vm.introductionError || this.vm.introduction || '暂无简介'}`)
            .fontSize(FORUM_INTRO_FONT_SIZE).fontColor('#E6FFFFFF')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        }
        .width('100%').height(FORUM_IDENTITY_INTRO_H)
        .borderRadius(FORUM_IDENTITY_INTRO_H / 2)
        .backgroundColor('#66000000')
        .padding({ left: 10, right: 10 })
        .margin({ top: FORUM_IDENTITY_INTRO_GAP })
        .alignItems(VerticalAlign.Center)
        .id('forum-introduction-summary')
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
