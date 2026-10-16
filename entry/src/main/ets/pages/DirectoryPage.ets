import { PageState, ListFooter } from '../components/PageState';
import { PullRefreshHeader, PULL_REFRESH_OFFSET } from '../components/RefreshSpinner';
import { FollowButton } from '../components/FollowButton';
import { followChanges } from '../viewmodel/FollowActionVM';
import { authSession } from '../auth/AuthSession';
/** 吧资料/吧规/吧务团队/关注/粉丝：同一共享导航栈中的独立内容页面。 */
import { common } from '@kit.AbilityKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { PageHeader } from '../components/PageHeader';
import { AvatarComponent } from '../components/AvatarComponent';
import { ForumAvatarImage, forumAvatarRadius } from '../components/ForumAvatarImage';
import { PostContentInline } from '../components/PostContentInline';
import { DirectoryKind, DirectoryRoleGroup, DirectoryUser, ForumRuleSection, groupUsersByRole } from '../model/PageDirectory';
import { ContentKind, ContentPiece } from '../model/ThreadDetail';
import { formatCount } from '../model/UserProfile';
import { DirectoryPageParams, NavigationService } from '../navigation/AppNavigation';
import { openContentPiece } from '../navigation/ContentNavigation';
import { DirectoryVM } from '../viewmodel/DirectoryVM';
import { AppTheme } from '../theme/Theme';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';

@ComponentV2
export struct DirectoryPage {
  @Local pullRefreshDragging: boolean = false;
  @Param routeParams: DirectoryPageParams | undefined = undefined;
  @Local vm: DirectoryVM = new DirectoryVM();
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;
  @Local refreshing: boolean = false;

  private changes = followChanges;
  private relationshipRefreshPending: boolean = false;
  @Monitor('changes.users')
  refreshRelationships(): void {
    if ((this.kind() === 'fans' || this.kind() === 'following') && this.routeParams?.id === authSession.snapshot.uid) {
      this.relationshipRefreshPending = true;
      this.applyRelationshipRefresh();
    }
  }
  @Monitor('vm.loading', 'vm.loadingMore')
  applyRelationshipRefresh(): void {
    if (!this.relationshipRefreshPending || this.vm.loading || this.vm.loadingMore) { return; }
    this.relationshipRefreshPending = false;
    this.reload();
  }
  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }
  private kind(): DirectoryKind { return this.routeParams?.kind ?? 'forum'; }
  private title(): string {
    if (this.routeParams?.title) { return this.routeParams.title; }
    if (this.kind() === 'rules') { return '吧规'; }
    if (this.kind() === 'team') { return '吧务团队'; }
    if (this.kind() === 'fans') { return '粉丝'; }
    if (this.kind() === 'following') { return '关注的人'; }
    return '吧资料';
  }
  aboutToAppear(): void {
    readStatusBarVp(this.context()).then((vp: number) => { this.statusBarH = vp; }).catch(() => {});
    this.reload();
  }
  private async reload(more: boolean = false): Promise<void> {
    await this.vm.load(this.context(), this.kind(), this.routeParams?.id ?? 0, more);
  }
  private openForumPart(kind: DirectoryKind): void {
    NavigationService.openDirectory({ kind, id: this.routeParams?.id ?? 0,
      forumName: this.vm.data.forum.name || this.routeParams?.forumName });
  }
  private roleLabel(role: string): string {
    if (role === 'manager') { return '吧主'; }
    if (role === 'assist') { return '小吧主'; }
    if (role === 'forum_helper') { return '贴吧助手'; }
    return /^[A-Za-z_]+$/.test(role) ? '吧务成员' : role;
  }
  private openUser(user: DirectoryUser): void {
    if (user.uid <= 0 && user.portrait.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '没有取得用户身份' }); return;
    }
    NavigationService.openUser({ uid: user.uid, portrait: user.portrait, name: user.name });
  }

  @Builder
  PullHeader() { PullRefreshHeader({ active: this.refreshing || this.pullRefreshDragging }) }

  build() {
    HdsNavDestination() {
      Column() {
        PageHeader({ title: this.title(), onBack: (): void => { NavigationService.back(); } })
        Refresh({ refreshing: $$this.refreshing, builder: (): void => { this.PullHeader(); } }) {
          List({ space: 12 }) {
            if (this.vm.error.length > 0) {
              ListItem() {
                PageState({ compact: true, title: '加载失败', message: this.vm.error, actionLabel: '重试',
                  onAction: (): void => { void this.reload(); } })
              }
            }
            if (!this.vm.loaded && this.vm.loading) {
              ListItem() { PageState({ loading: true, message: '正在加载…' }) }
            } else if (this.vm.loaded) {
              if (this.kind() === 'forum' && this.vm.data.forum.id > 0) {
                ListItem() { this.ForumCard() }
                ListItem() { this.EntryRow('吧规', (): void => { this.openForumPart('rules'); }) }
                ListItem() { this.EntryRow('吧务团队', (): void => { this.openForumPart('team'); }) }
                ListItem() {
                  this.EntryRow('进入吧页', (): void => {
                    NavigationService.openForum({ forumName: this.vm.data.forum.name });
                  })
                }
              } else if (this.kind() === 'rules') {
                if (this.vm.data.title.length > 0 || this.vm.data.preface.length > 0) {
                  ListItem() {
                    Column({ space: 10 }) {
                      Text(this.vm.data.title).fontSize(19).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT_MAIN)
                      Text(this.vm.data.preface).fontSize(14).fontColor(AppTheme.TEXT_SUB)
                    }.alignItems(HorizontalAlign.Start).width('100%').padding(18)
                  }
                }
                ForEach(this.vm.data.rules, (rule: ForumRuleSection) => {
                  ListItem() { this.RuleCard(rule) }
                })
                if (this.vm.data.rules.length === 0 && this.vm.error.length === 0) {
                  ListItem() { PageState({ message: '该吧暂未公布吧规' }) }
                }
              } else if (this.kind() === 'team') {

                ForEach(groupUsersByRole(this.vm.data.users), (group: DirectoryRoleGroup) => {
                  ListItem() {
                    Text(this.roleLabel(group.role)).fontSize(17).fontWeight(FontWeight.Medium)
                      .fontColor(AppTheme.TEXT_MAIN).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%').padding({ left: 4, top: 6, bottom: 2 })
                  }
                  ForEach(group.users, (user: DirectoryUser) => {
                    ListItem() { this.UserRow(user) }
                  }, (user: DirectoryUser) => `${user.uid}-${user.portrait}`)
                }, (group: DirectoryRoleGroup) => this.roleLabel(group.role))
                if (this.vm.data.users.length === 0 && this.vm.error.length === 0) {
                  ListItem() { PageState({ message: '暂无可展示的内容' }) }
                }
              } else if (this.kind() !== 'forum') {
                if (this.vm.data.preface.length > 0) {
                  ListItem() { Text(this.vm.data.preface).fontColor(AppTheme.TEXT_SUB).fontSize(13).padding(16) }
                }
                ForEach(this.vm.data.users, (user: DirectoryUser) => {
                  ListItem() { this.UserRow(user) }
                }, (user: DirectoryUser) => `${user.uid}-${user.portrait}-${user.role}`)
                if (this.vm.data.users.length === 0 && this.vm.error.length === 0) {
                  ListItem() { PageState({ message: '暂无可展示的内容' }) }
                }
                if (this.kind() === 'fans' || this.kind() === 'following') {
                  ListItem() {
                    ListFooter({ loading: this.vm.loadingMore, error: this.vm.pagingError,
                      hasMore: this.vm.data.hasMore, endText: '已显示全部可见用户',
                      onRetry: (): void => { void this.reload(true); } })
                  }
                }
              }
            }

          }.width('100%').height('100%').padding({ left: 12, right: 12, top: 8 })
          .edgeEffect(EdgeEffect.Spring).onReachEnd(() => {
            if (this.vm.pagingError.length === 0) { this.reload(true); }
          })
        }.refreshOffset(PULL_REFRESH_OFFSET)
        .onStateChange((state: RefreshStatus) => {
          this.pullRefreshDragging = state === RefreshStatus.Drag || state === RefreshStatus.OverDrag;
        }).layoutWeight(1).onRefreshing(async () => {
          await this.reload(); this.refreshing = false;
        })
      }.width('100%').height('100%').padding({ top: this.statusBarH }).backgroundColor(AppTheme.BG)
    }.hideTitleBar(true)
  }

  @Builder
  EntryRow(label: string, onTap: () => void) {
    Row() {
      Text(label).fontSize(15).fontColor(AppTheme.TEXT_MAIN).layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([AppTheme.ARROW_ROW])
    }.width('100%').padding(20).borderRadius(AppTheme.CARD_RADIUS).backgroundColor(AppTheme.CARD)
    .onClick(onTap)
  }

  @Builder
  ForumCard() {
    Column({ space: 16 }) {
      Row({ space: 14 }) {
        ForumAvatarImage({ url: this.vm.data.forum.avatar, forumName: this.vm.data.forum.name,
          avatarSize: 64, radius: forumAvatarRadius(64) })
        Column({ space: 8 }) {
          Text(this.vm.data.forum.name.endsWith('吧') ? this.vm.data.forum.name : `${this.vm.data.forum.name}吧`).fontSize(22).fontWeight(FontWeight.Bold).fontColor(AppTheme.TEXT_MAIN)
          Text(this.vm.data.forum.category).fontSize(12).fontColor(AppTheme.TEXT_SUB)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        FollowButton({ kind: 'forum', targetId: this.vm.data.forum.id, targetName: this.vm.data.forum.name })
      }.width('100%')
      Text(`关注 ${formatCount(this.vm.data.forum.members)} · 主题 ${formatCount(this.vm.data.forum.threads)}`)
        .fontSize(13).fontColor(AppTheme.TEXT_SUB)
      if (this.vm.data.forum.slogan.length > 0) {
        Text(this.vm.data.forum.slogan).fontSize(16).fontColor(AppTheme.TEXT_MAIN)
      }
      if (this.vm.data.forum.description.length > 0) {
        if (this.vm.data.forum.descriptionPieces.length > 0) {
          Text() {
            PostContentInline({ pieces: this.vm.data.forum.descriptionPieces, emojiSize: 18,
              textColor: AppTheme.TEXT_SUB, accentColor: AppTheme.ACCENT_DARK,
              onActivate: (piece: ContentPiece): void => { openContentPiece(piece, this.getUIContext()); } })
          }.fontSize(14).lineHeight(23)
        } else {
          Text(this.vm.data.forum.description).fontSize(14).fontColor(AppTheme.TEXT_SUB).lineHeight(23)
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(20)
    .borderRadius(AppTheme.CARD_RADIUS).backgroundColor(AppTheme.CARD)
  }

  @Builder
  UserRow(user: DirectoryUser) {
    Row({ space: 14 }) {
      AvatarComponent({ url: user.avatar, avatarSize: 46, fallbackName: user.name })
      Column({ space: 7 }) {
        Text(user.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT_MAIN)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (user.role.length > 0 || user.intro.length > 0) {
          Text(this.roleLabel(user.role) || user.intro).fontSize(12).fontColor(AppTheme.TEXT_SUB).maxLines(2)
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([AppTheme.ARROW_ROW])
    }.width('100%').padding(16).borderRadius(AppTheme.CARD_RADIUS).backgroundColor(AppTheme.CARD)
    .onClick(() => { this.openUser(user); })
  }

  @Builder
  RuleCard(rule: ForumRuleSection) {
    Column({ space: 12 }) {
      if (rule.title.length > 0) {
        Text(rule.title).fontSize(17).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT_MAIN)
      }
      ForEach(rule.paragraphs, (pieces: ContentPiece[]) => {
        Text() {
          PostContentInline({ pieces, emojiSize: 18, textColor: AppTheme.TEXT_MAIN,
            accentColor: AppTheme.ACCENT_DARK,
            onActivate: (piece: ContentPiece): void => { openContentPiece(piece, this.getUIContext()); } })
        }.fontSize(14).lineHeight(23).width('100%')
        ForEach(pieces.filter((piece: ContentPiece) => piece.kind === ContentKind.IMAGE), (piece: ContentPiece) => {
          Image(piece.imageUrl).width('100%').objectFit(ImageFit.Contain)
        })
      })
    }.width('100%').alignItems(HorizontalAlign.Start).padding(18)
    .borderRadius(AppTheme.CARD_RADIUS).backgroundColor(AppTheme.CARD)
  }
}
