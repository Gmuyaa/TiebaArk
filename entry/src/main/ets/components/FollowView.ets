import { RootPageHeader } from './PageHeader';
import { PageState } from './PageState';
import { followChanges } from '../viewmodel/FollowActionVM';

import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { FollowVM } from '../viewmodel/FollowVM';
import { ForumActionButton } from './ForumActionButton';
import { GlassCircleButton } from './GlassCircleButton';
import { ForumLevelBadge } from './ForumLevelBadge';
import { FollowForumItem } from '../model/FollowForum';
import { authSession, AuthSession } from '../auth/AuthSession';
import { LoginEmptyView } from './LoginEmptyView';
import { ForumAvatarImage } from './ForumAvatarImage';
import { AppTheme } from '../theme/Theme';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { NavigationService } from '../navigation/AppNavigation';
import { SignStrategyStore, signStrategyStore } from '../common/appearance/SignStrategyStore';
import { ForegroundRefresh, foregroundRefresh } from '../viewmodel/ForegroundRefresh';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UiLayout } from '../common/appearance/UiLayout';

@ComponentV2
export struct FollowView {
  @Param active: boolean = true;
  @Local foreground: ForegroundRefresh = foregroundRefresh;
  private foregroundRevision: number = foregroundRefresh.revision;
  private foregroundRefreshPending: boolean = false;
  private foregroundExperiencePending: boolean = false;
  private foregroundAccount: string = '';
  @Local refreshing: boolean = false;
  private refreshGestureId: number = 0;
  private consumedRefreshGestureId: number = -1;
  private refreshSequence: number = 0;

  private resetPullRefresh(): void {
    this.refreshSequence++;
    this.refreshing = false;
    this.consumedRefreshGestureId = -1;
  }

  private handleRefreshTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) { this.refreshGestureId++; }
  }

  private releaseRefreshAnimation(): void {
    if (this.refreshing) { return; }
    // 原生组件可能在同一手势结束后重放回调；主动复位动画而不重复请求。
    const sequence: number = this.refreshSequence;
    this.refreshing = true;
    setTimeout((): void => {
      if (sequence === this.refreshSequence) { this.refreshing = false; }
    }, 0);
  }

  private async refreshForums(fromGesture: boolean = false): Promise<void> {
    if (fromGesture && this.consumedRefreshGestureId === this.refreshGestureId) {
      this.releaseRefreshAnimation();
      return;
    }
    if (fromGesture) { this.consumedRefreshGestureId = this.refreshGestureId; }
    if (!this.active || !authSession.isLoggedIn() || this.vm.loading || this.vm.signingAll ||
      this.vm.signingFname.length > 0) {
      if (fromGesture) { this.releaseRefreshAnimation(); }
      return;
    }
    const sequence: number = ++this.refreshSequence;
    this.refreshing = true;
    // 与回前台一致：列表完成后只强制核对当前可见吧的签到、等级与连签信息。
    this.foregroundExperiencePending = true;
    try {
      await this.vm.load(this.hostContext(), true);
    } finally {
      if (sequence === this.refreshSequence) { this.refreshing = false; }
    }
  }

  @Monitor('foreground.revision', 'active')
  onForegroundRefresh(): void {
    if (!this.active) {
      this.foregroundRefreshPending = false; this.foregroundExperiencePending = false;
      this.resetPullRefresh();
      return;
    }
    if (this.foregroundRevision === this.foreground.revision) { return; }
    this.foregroundRevision = this.foreground.revision;
    this.foregroundAccount = authSession.forumCacheSessionKey();
    this.foregroundRefreshPending = true;
    this.applyForegroundRefresh();
  }

  @Monitor('vm.loading', 'vm.signingAll', 'vm.signingFname')
  applyForegroundRefresh(): void {
    if (!this.foregroundRefreshPending || !this.active || this.vm.loading || this.vm.signingAll ||
      this.vm.signingFname.length > 0) { return; }
    this.foregroundRefreshPending = false;
    if (this.foregroundAccount.length === 0 || this.foregroundAccount !== authSession.forumCacheSessionKey()) { return; }
    this.foregroundExperiencePending = true;
    hilog.info(0x0000, 'ForegroundRefresh', 'follow requested revision=%{public}d', this.foregroundRevision);
    void this.vm.load(this.hostContext(), true);
  }

  private changes = followChanges;
  private relationshipRefreshPending: boolean = false;
  private visibleForums: Map<number, FollowForumItem> = new Map();
  @Monitor('changes.forums')
  refreshRelationships(): void {
    this.relationshipRefreshPending = true;
    this.applyRelationshipRefresh();
  }
  @Monitor('vm.loading')
  applyRelationshipRefresh(): void {
    if (this.vm.loading) { return; }
    const force: boolean = this.active && this.foregroundExperiencePending;
    this.foregroundExperiencePending = false;
    for (const item of this.vm.forums) {
      if (this.active && this.visibleForums.has(item.fid)) { this.vm.ensureExperience(this.hostContext(), item, force); }
    }
    if (!this.relationshipRefreshPending) { return; }
    this.relationshipRefreshPending = false;
    this.vm.load(this.hostContext(), true);
  }
  /** 悬浮底栏实际遮挡高度；尾部占位让最后一行能滚到导航上方。 */
  @Param bottomBarOcclusion: number = 0;
  @Local vm: FollowVM = new FollowVM();
  @Local auth: AuthSession = authSession;
  @Local signStrategy: SignStrategyStore = signStrategyStore;
  private account: string = authSession.forumCacheSessionKey();
  @Monitor('auth.snapshot')
  onAccountChanged(): void {
    const account: string = authSession.forumCacheSessionKey();
    if (account === this.account) { return; }
    this.account = account;
    this.resetPullRefresh();
    this.foregroundExperiencePending = false;
    this.visibleForums.clear();
    void this.vm.load(this.hostContext());
  }
  /** 状态栏高度（vp），见 SafeArea.ets */
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;

  aboutToAppear(): void {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    readStatusBarVp(context).then((vp: number) => {
      this.statusBarH = vp;
    }).catch(() => {
      // 拿不到就保持兜底值
    });
    // 切回先显示缓存，过期后台刷新；跨日不复用昨天的签到标记。
    this.vm.load(context);
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }
  aboutToDisappear(): void { this.resetPullRefresh(); this.vm.dispose(); }

  build() {
    Column() {
      RootPageHeader({ title: '我的关注',
        actions: (): void => { this.HeaderActions(); } })
      Column() { this.FollowContent() }.width('100%').layoutWeight(1)
    }.width('100%').height('100%')
  }

  @Builder
  ForumSquareEntry() {
    GlassCircleButton({ symbol: $r('sys.symbol.compass'), diameter: 40, iconSize: 22,
      iconWeight: FontWeight.Regular, accessibilityLabel: '吧广场',
      onTap: (): void => { NavigationService.openForumSquare(); } })
      .id('follow-square-entry').margin(4)
  }

  @Builder
  FollowContent() {
    if (!authSession.snapshot.isLoggedIn()) {
      // 未登录：沿用 Index 原空态的引导组件（登录返回后切 Tab 重建自然刷新）
      LoginEmptyView({
        icon: $r('app.media.icon_follow'),
        title: '关注列表是空的',
        subtitle: '登录后可查看关注的吧；关注吧的帖子在首页关注频道查看',
        onLogin: (): void => {
          router.pushUrl({ url: 'pages/Login' });
        }
      }).layoutWeight(1)
    } else {
      Refresh({ refreshing: this.refreshing }) {
        this.FollowPage()
      }
      .width('100%').layoutWeight(1)
      .pullToRefresh(!this.vm.loading && !this.vm.signingAll && this.vm.signingFname.length === 0)
      .onTouch((event: TouchEvent): void => { this.handleRefreshTouch(event); })
      .onRefreshing((): void => { void this.refreshForums(true); })
      .id('follow-refresh')
    }
  }

  private allSigned(): boolean {
    return this.vm.forums.length > 0 && this.vm.forums.every((item: FollowForumItem): boolean =>
      item.signKnown && item.isSigned);
  }

  private signAllDisabled(): boolean {
    return this.vm.signingAll || this.vm.loading || this.vm.signingFname.length > 0 ||
      this.vm.forums.length === 0 || this.allSigned();
  }

  private signAll(): void {
    if (this.signAllDisabled()) { return; }
    this.vm.signInAll(this.hostContext()).then((message: string) => {
      if (message.length > 0) { promptAction.showToast({ message, duration: 2400 }); }
    });
  }

  @Builder
  SignAllProgress() {
    LoadingProgress().width(20).height(20).color(AppTheme.TEXT_SUB)
  }

  /** 顶栏两个圆形动作保持同尺寸；列表签到仍沿用小型胶囊。 */
  @Builder
  HeaderActions() {
    Row({ space: 4 }) {
      this.ForumSquareEntry()
      if (authSession.snapshot.isLoggedIn()) {
        GlassCircleButton({
          symbol: this.allSigned() ? $r('sys.symbol.checkmark') : $r('sys.symbol.calendar'),
          diameter: 40, iconSize: 22, iconWeight: FontWeight.Regular,
          useCustomIcon: this.vm.signingAll, customIcon: (): void => { this.SignAllProgress(); },
          accessibilityLabel: this.vm.signingAll ? '正在签到' :
            (this.allSigned() ? '所有关注的吧已签到' :
              (this.signStrategy.strategy === 2 ? '混合签到' : (this.signStrategy.strategy === 1 ? '官方批量签到' : '一键签到'))),
          onTap: (): void => { this.signAll(); }
        }).id('follow-sign-all').margin(4).enabled(!this.signAllDisabled())
          .opacity(this.signAllDisabled() && !this.vm.signingAll ? 0.5 : 1)
      }
    }.id('follow-header-actions')
  }

  @Builder
  FollowPage() {
    Column() {
      if (this.vm.loading && !this.vm.loadedOnce) {
        PageState({ fillRemaining: true, loading: true, message: '正在加载关注的吧…' }).layoutWeight(1)
      } else if (this.vm.forums.length === 0 && this.vm.errorText.length > 0) {
        PageState({ fillRemaining: true, title: '加载失败', message: this.vm.errorText, actionLabel: '重试',
          onAction: (): void => { void this.refreshForums(); } }).layoutWeight(1)
      } else if (this.vm.forums.length === 0) {
        PageState({ fillRemaining: true, message: '还没有关注任何吧' }).layoutWeight(1)
      } else {
        if (this.vm.errorText.length > 0) {
          PageState({ compact: true, message: '更新失败，正在显示上次数据', actionLabel: '重试',
            onAction: (): void => { void this.refreshForums(); } })
        }
        this.FollowList()
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 关注吧列表：头像、吧名／等级标签、已知签到次数和签到按钮。 */
  @Builder
  FollowList() {
    List({ space: 0 }) {
      ForEach(this.vm.forums, (item: FollowForumItem) => {
        ListItem() {
          this.FollowRow(item)
        }
        // ⚠️ key 必须含 isSigned：VM 签到成功后整体替换数组，若 key 不变
        // ForEach 会复用旧组件（拿到旧 item 对象），按钮永远停在"签到"
      }, (item: FollowForumItem) => `${item.fid}-${item.fname}-${item.isSigned ? 1 : 0}-${item.signKnown ? 1 : 0}-${item.level}-${item.levelName}-${item.continuousCount}-${item.totalCount}`)
      ListItem() {
        Column().width('100%').height(this.bottomBarOcclusion)
          .accessibilityLevel('no').hitTestBehavior(HitTestMode.None)
      }.id('follow-bottom-occlusion')
    }
    .width('100%')
    .layoutWeight(1)
    .clip(true)
    .scrollBar(BarState.Off)
    .divider({
      strokeWidth: 0.5,
      color: AppTheme.DIVIDER,
      startMargin: 66,
      endMargin: 16
    })
  }

  @Builder
  FollowRow(item: FollowForumItem) {
    Row({ space: 10 }) {

      ForumAvatarImage({ url: item.avatar, forumName: item.fname,
        avatarSize: 40, radius: 40 * 14 / 64 })

      Column({ space: 3 }) {
        Text(item.fname.endsWith('吧') ? item.fname : `${item.fname}吧`)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_MAIN)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 6 }) {
          ForumLevelBadge({ level: item.level, levelName: item.levelName }).flexShrink(0)
          if (item.continuousCount >= 0) {
            Text(`连签 ${item.continuousCount} 天`)
              .fontSize(UiLayout.META).fontColor(AppTheme.TEXT_SUB)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      this.SignButton(item)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)

    .onVisibleAreaChange([0.01], (visible: boolean) => {
      if (visible) {
        this.visibleForums.set(item.fid, item); void this.vm.ensureExperience(this.hostContext(), item);
      } else if (this.visibleForums.get(item.fid) === item) { this.visibleForums.delete(item.fid); }
    })
    .onClick(() => {
      if (item.fname.length === 0) {
        return;
      }

      NavigationService.openForum({ forumName: item.fname });
    })
  }

  private signLabel(item: FollowForumItem): string {
    if (this.vm.signingFname === item.fname) { return '签到中…'; }
    if (!item.signKnown) { return this.vm.loading ? '读取中…' : '重试签到状态'; }
    return item.isSigned ? '已签到' : '签到';
  }

  /** 未知状态只读重试；提交和完成状态均不允许重复写入。 */
  @Builder
  SignButton(item: FollowForumItem) {
    ForumActionButton({ label: this.signLabel(item), actionSymbol: $r('sys.symbol.calendar'),
      busy: this.vm.signingFname === item.fname || (!item.signKnown && this.vm.loading),
      completed: item.signKnown && item.isSigned, retry: !item.signKnown && !this.vm.loading,
      disabled: (item.signKnown && item.isSigned) || this.vm.loading || this.vm.signingAll || this.vm.signingFname.length > 0,
      accessibilityLabel: `${item.fname}，${this.signLabel(item)}`,
      onTap: (): void => {
        if (!item.signKnown) { void this.refreshForums(); return; }
        // 写操作防连点在 VM 内部（signingFname 占位）；结果用 toast 反馈
        this.vm.signIn(this.hostContext(), item).then((message: string) => {
          if (message.length > 0) {
            promptAction.showToast({ message: message, duration: 2000 });
          }
        });
      }
    })
  }
}
