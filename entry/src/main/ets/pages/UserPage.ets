import { PageState, ListFooter } from '../components/PageState';
import { PullRefreshHeader, PULL_REFRESH_OFFSET } from '../components/RefreshSpinner';
import { FollowButton } from '../components/FollowButton';
import { followChanges } from '../viewmodel/FollowActionVM';
/** 官方公开个人主页：资料、社交列表、帖子/回复/关注的吧，沿用鸿蒙共享导航。 */
import { common } from '@kit.AbilityKit';
import { authSession } from '../auth/AuthSession';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { AvatarComponent } from '../components/AvatarComponent';
import { PageHeader } from '../components/PageHeader';
import { PostContentInline } from '../components/PostContentInline';
import { UserPostItem, userReplyKey } from '../model/MyContent';
import { profilePortrait } from '../model/PageDirectory';
import { ContentPiece, portraitUrl } from '../model/ThreadDetail';
import { displayName, formatCount, ProfileForum } from '../model/UserProfile';
import { NavigationService, UserPageParams } from '../navigation/AppNavigation';
import { openContentPiece } from '../navigation/ContentNavigation';
import { UserPageVM } from '../viewmodel/UserPageVM';
import { AppTheme } from '../theme/Theme';
import { avatarTrace } from '../utils/AvatarTrace';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';

@ComponentV2
export struct UserPage {
  @Local pullRefreshDragging: boolean = false;
  @Param routeParams: UserPageParams | undefined = undefined;
  @Local vm: UserPageVM = new UserPageVM();
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;
  @Local refreshing: boolean = false;
  private changes = followChanges;
  private relationshipRefreshPending: boolean = false;
  @Monitor('changes.users', 'changes.forums')
  refreshRelationships(): void {
    this.relationshipRefreshPending = true;
    this.applyRelationshipRefresh();
  }
  @Monitor('vm.loading', 'vm.loadingMore')
  applyRelationshipRefresh(): void {
    if (!this.relationshipRefreshPending || this.vm.loading || this.vm.loadingMore) { return; }
    this.relationshipRefreshPending = false;
    this.vm.refresh(this.context());
  }
  private tabs: string[] = ['帖子', '回复', '关注的吧'];

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }
  aboutToAppear(): void {
    readStatusBarVp(this.context()).then((vp: number) => { this.statusBarH = vp; }).catch(() => {});
    this.vm.initialize(this.context(), this.routeParams?.uid ?? 0,
      profilePortrait(this.routeParams?.portrait ?? ''), this.routeParams?.tab ?? 0);
  }
  private name(): string { return displayName(this.vm.profile, this.routeParams?.name || '贴吧用户'); }
  /**
   * 头像来源。
   *
   * 本人主页用**当前共享资料**里的服务端头像（不用打开本页时的路由 portrait，
   * 也不用编辑页的本机候选预览）；他人主页仍用本页 VM 自己读到的资料与展示版本。
   */
  private avatarUrl(): string {
    const uid: number = this.vm.profile.uid || this.routeParams?.uid || 0;
    const own: boolean = authSession.isLoggedIn() && uid === authSession.snapshot.uid;
    const shared: string = own ? authSession.snapshot.portrait : '';
    const source: string = shared.length > 0
      ? shared : (this.vm.profile.portrait || profilePortrait(this.routeParams?.portrait ?? ''));
    return portraitUrl(source, own ? authSession.avatarRevision : this.vm.avatarRevision);
  }
  /** 本人主页的图片加载/失败打点：只证明加载结果，不证明内容已更新。 */
  private ownAvatarTraceTag(): string {
    const uid: number = this.vm.profile.uid || this.routeParams?.uid || 0;
    return authSession.isLoggedIn() && uid === authSession.snapshot.uid ? 'self' : '';
  }
  private statCount(index: number): string {
    if (!this.vm.profileLoaded) { return '—'; }
    const values: number[] = [this.vm.profile.totalAgreeNum, this.vm.profile.concernNum,
      this.vm.profile.fansNum, this.vm.profile.likeForumNum];
    return formatCount(values[index]);
  }
  private openSocial(kind: 'fans' | 'following'): void {
    if (!this.vm.profileLoaded || this.vm.profile.uid <= 0) { return; }
    NavigationService.openDirectory({ kind, id: this.vm.profile.uid });
  }
  private openPost(item: UserPostItem): void {
    NavigationService.openThreadDetail({ tid: item.tid, forumName: item.forumName,
      targetPid: this.vm.tab === 1 && item.pid > 0 ? item.pid : undefined });
  }

  @Builder
  PullHeader() { PullRefreshHeader({ active: this.refreshing || this.pullRefreshDragging }) }

  build() {
    HdsNavDestination() {
      Column() {
        PageHeader({ title: '个人主页', onBack: (): void => { NavigationService.back(); } })
        Refresh({ refreshing: $$this.refreshing, builder: (): void => { this.PullHeader(); } }) {
          List({ space: 12 }) {
            ListItem() { this.ProfileCard() }
            if (this.vm.profileError.length > 0) {
              ListItem() {
                PageState({ compact: true, title: '读取失败', message: this.vm.profileError, actionLabel: '重试',
                  onAction: (): void => { void this.vm.refresh(this.context()); } })
              }
            }
            ListItem() {
              Row() {
                ForEach(this.tabs, (label: string, index: number) => {
                  Text(label).fontSize(15).fontWeight(this.vm.tab === index ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(this.vm.tab === index ? AppTheme.ACCENT_DARK : AppTheme.TEXT_SUB)
                    .layoutWeight(1).textAlign(TextAlign.Center).padding({ top: 16, bottom: 16 })
                    .onClick(() => { this.vm.selectTab(this.context(), index); })
                })
              }.width('100%').backgroundColor(AppTheme.CARD).borderRadius(AppTheme.CARD_RADIUS)
            }
            if (this.vm.error.length > 0) {
              ListItem() {
                PageState({ compact: true, title: '读取失败', message: this.vm.error, actionLabel: '重试',
                  onAction: (): void => { void this.vm.load(this.context()); } })
              }
            }
            if (this.vm.tab === 2) {
              ForEach(this.vm.forums, (forum: ProfileForum) => {
                ListItem() {
                  Row({ space: 14 }) {
                    AvatarComponent({ url: forum.avatar, avatarSize: 42, fallbackName: forum.name })
                    Text(forum.name.endsWith('吧') ? forum.name : `${forum.name}吧`).fontSize(16).fontColor(AppTheme.TEXT_MAIN).layoutWeight(1)
                    SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([AppTheme.ARROW_ROW])
                  }.width('100%').padding(16).backgroundColor(AppTheme.CARD).borderRadius(AppTheme.CARD_RADIUS)
                  .onClick(() => { NavigationService.openForum({ forumName: forum.name }); })
                }
              }, (forum: ProfileForum) => `${forum.name}-${forum.avatar}`)
            } else {
              ForEach(this.vm.items, (item: UserPostItem) => {
                ListItem() { this.PostCard(item) }
              }, (item: UserPostItem) => this.vm.tab === 1 ? userReplyKey(item) : String(item.tid))
            }
            if ((this.vm.tab === 2 ? this.vm.forums.length : this.vm.items.length) === 0) {
              ListItem() {
                if (this.vm.error.length === 0 && this.vm.profileError.length === 0) {
                  PageState({ loading: this.vm.loading,
                    message: this.vm.loading ? '正在加载…' : '暂无可见内容' })
                }
              }
            }
            ListItem() {
              if ((this.vm.tab === 2 ? this.vm.forums.length : this.vm.items.length) > 0) {
                ListFooter({ loading: this.vm.loadingMore, error: this.vm.pagingError, hasMore: this.vm.hasMore,
                  endText: '暂无更多可见内容', onRetry: (): void => { void this.vm.load(this.context(), true); } })
              }
            }
          }.width('100%').height('100%').padding({ left: 12, right: 12, top: 8 })
          .edgeEffect(EdgeEffect.Spring).onReachEnd(() => {
            if (this.vm.pagingError.length === 0) { this.vm.load(this.context(), true); }
          })
        }.refreshOffset(PULL_REFRESH_OFFSET)
        .onStateChange((state: RefreshStatus) => {
          this.pullRefreshDragging = state === RefreshStatus.Drag || state === RefreshStatus.OverDrag;
        }).layoutWeight(1).onRefreshing(async () => {
          // 用户明确下拉重试：允许强制换一次图片缓存键。
          await this.vm.refresh(this.context(), true); this.refreshing = false;
        })
      }.width('100%').height('100%').padding({ top: this.statusBarH }).backgroundColor(AppTheme.BG)
      // 只记"这一页真的出现在屏幕上"，用来区分状态已发布与用户已看到。
      .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, ratio: number): void => {
        if (isVisible && ratio > 0) { avatarTrace('page-visible', 0, 'page=user'); }
      })
    }.hideTitleBar(true)
    .onShown(() => {
      if (authSession.isLoggedIn() && this.routeParams?.uid === authSession.snapshot.uid) {
        void authSession.refreshOwnAvatarOnEntry(this.context());
      }
    })
  }

  @Builder
  ProfileCard() {
    Column({ space: 18 }) {
      Row({ space: 16 }) {
        AvatarComponent({ url: this.avatarUrl(),
          avatarSize: 72, fallbackName: this.name(), traceTag: this.ownAvatarTraceTag() })
        Column({ space: 8 }) {
          Text(this.name()).fontSize(23).fontWeight(FontWeight.Bold).fontColor(AppTheme.TEXT_MAIN)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.vm.profileLoaded) {
            Text(`贴吧 ID ${this.vm.profile.uid}${this.vm.profile.tbAge ? ` · 吧龄 ${this.vm.profile.tbAge}` : ''}`)
              .fontSize(12).fontColor(AppTheme.TEXT_SUB)
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        if (this.vm.profileLoaded || this.vm.profileError.length > 0) {
          FollowButton({ kind: 'user', targetId: this.vm.profile.uid || this.routeParams?.uid || 0,
            portrait: this.vm.profile.portrait || this.routeParams?.portrait || '', targetName: this.name() })
        }
      }.width('100%')
      if (this.vm.profile.intro.length > 0) {
        Text(this.vm.profile.intro).fontSize(14).fontColor(AppTheme.TEXT_SUB).lineHeight(22)
      }
      Row() {
        this.Stat('获赞', 0, (): void => {})
        this.Stat('关注', 1, (): void => { this.openSocial('following'); })
        this.Stat('粉丝', 2, (): void => { this.openSocial('fans'); })
        this.Stat('关注吧', 3, (): void => {
          this.vm.selectTab(this.context(), 2);
        })
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).padding(20)
    .backgroundColor(AppTheme.CARD).borderRadius(AppTheme.CARD_RADIUS)
  }

  @Builder
  Stat(label: string, index: number, onTap: () => void) {
    Column({ space: 6 }) {
      Text(this.statCount(index)).fontSize(20).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT_MAIN)
      Text(label).fontSize(12).fontColor(AppTheme.TEXT_SUB)
    }.layoutWeight(1).padding({ top: 6, bottom: 6 }).onClick(onTap)
  }

  @Builder
  PostCard(item: UserPostItem) {
    Column({ space: 12 }) {
      if (item.title.length > 0) {
        Text(item.title).fontSize(17).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT_MAIN).maxLines(3)
      }
      if (item.pieces.length > 0) {
        Text() {
          PostContentInline({ pieces: item.pieces, emojiSize: 18, textColor: AppTheme.TEXT_MAIN,
            accentColor: AppTheme.ACCENT_DARK,
            onActivate: (piece: ContentPiece): void => { openContentPiece(piece, this.getUIContext()); } })
        }.fontSize(14).lineHeight(22).maxLines(5).width('100%')
      } else if (item.content.length > 0) {
        Text(item.content).fontSize(14).fontColor(AppTheme.TEXT_SUB).maxLines(4).lineHeight(22)
      }
      Row() {
        Text(item.forumName ? (item.forumName.endsWith('吧') ? item.forumName : `${item.forumName}吧`) : '帖子').fontSize(12).fontColor(AppTheme.ACCENT_DARK)
          .onClick(() => {
            if (item.forumName.length > 0) { NavigationService.openForum({ forumName: item.forumName }); }
          })
        Blank()
        Text(item.createTimeMs > 0 ? new Date(item.createTimeMs).toLocaleDateString() : '')
          .fontSize(12).fontColor(AppTheme.TEXT_SUB)
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).padding(18)
    .backgroundColor(AppTheme.CARD).borderRadius(AppTheme.CARD_RADIUS)
    .onClick(() => { this.openPost(item); })
  }
}
