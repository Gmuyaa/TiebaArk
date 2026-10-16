import { PageState, ListFooter } from '../components/PageState';
import { ForumLevelBadge } from '../components/ForumLevelBadge';
import { forumLevelStore } from '../common/appearance/ForumLevelStore';
import { PullRefreshHeader, PULL_REFRESH_OFFSET } from '../components/RefreshSpinner';

import { common } from '@kit.AbilityKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { AvatarComponent } from '../components/AvatarComponent';
import { PageHeader } from '../components/PageHeader';
import { ForumMemberGroup, ForumMemberItem, groupTitle, previewNote, roleLabel } from '../model/ForumMember';
import { ForumMemberPageParams, NavigationService } from '../navigation/AppNavigation';
import { AppTheme } from '../theme/Theme';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { ForumMemberVM } from '../viewmodel/ForumMemberVM';

@ComponentV2
export struct ForumMemberPage {
  @Local pullRefreshDragging: boolean = false;
  @Param routeParams: ForumMemberPageParams | undefined = undefined;
  @Local vm: ForumMemberVM = new ForumMemberVM();
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;
  @Local refreshing: boolean = false;

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private title(): string {
    const custom: string | undefined = this.routeParams?.title;
    if (custom !== undefined && custom.length > 0) { return custom; }
    const name: string = this.vm.forumName.length > 0 ? this.vm.forumName
      : (this.routeParams?.forumName ?? '');
    return name.length > 0 ? `${name}吧成员` : '吧成员';
  }

  aboutToAppear(): void {
    readStatusBarVp(this.context()).then((vp: number) => { this.statusBarH = vp; }).catch(() => {});
    void this.reload();
  }

  private async reload(): Promise<void> {
    await this.vm.load(this.context(), this.routeParams?.forumId ?? 0, this.routeParams?.forumName ?? '');
  }

  /** 成员二级行：角色与等级可能有、可能都没有，都没有就不画这一行（不编占位文字） */
  private detailOf(member: ForumMemberItem): string {
    const parts: string[] = [];
    const role: string = roleLabel(member.roleName);
    if (role.length > 0) { parts.push(role); }
    if (member.userLevel > 0) {
      parts.push(member.levelName.length > 0 ? `Lv.${member.userLevel} ${member.levelName}`
        : `Lv.${member.userLevel}`);
    }
    return parts.join(' · ');
  }

  private openUser(member: ForumMemberItem): void {
    if (member.userId <= 0 && member.portrait.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '没有取得用户身份' }); return;
    }
    NavigationService.openUser({ uid: member.userId, portrait: member.portrait, name: member.displayName() });
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
              ForEach(this.vm.groups, (group: ForumMemberGroup) => {
                ListItem() { this.GroupHeader(group) }
                ForEach(group.members, (member: ForumMemberItem) => {
                  ListItem() { this.MemberRow(member) }
                }, (member: ForumMemberItem) => `${group.type}-${member.userId}-${member.portrait}`)
              }, (group: ForumMemberGroup) => group.type)
              if (!this.vm.hasGroups() && this.vm.error.length === 0) {
                ListItem() { PageState({ message: '这个吧暂时没有可展示的成员' }) }
              }
            }

          }.width('100%').height('100%').padding({ left: 12, right: 12, top: 8 })
          .edgeEffect(EdgeEffect.Spring)
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
  GroupHeader(group: ForumMemberGroup) {
    Column({ space: 4 }) {
      Text(groupTitle(group.type)).fontSize(17).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT_MAIN)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      if (previewNote(group.total, group.members.length).length > 0) {
        Text(previewNote(group.total, group.members.length)).fontSize(12).fontColor(AppTheme.TEXT_SUB)
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 4, top: 6, bottom: 2 })
  }

  @Builder
  MemberRow(member: ForumMemberItem) {
    Row({ space: 14 }) {
      AvatarComponent({ url: member.avatar, avatarSize: 46, fallbackName: member.displayName() })
      Column({ space: 7 }) {
        Text(member.displayName()).fontSize(16).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT_MAIN)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (forumLevelStore.style === 1 && member.userLevel > 0) {
          Row({ space: 6 }) {
            if (roleLabel(member.roleName).length > 0) {
              Text(roleLabel(member.roleName)).fontSize(12).fontColor(AppTheme.TEXT_SUB)
            }
            ForumLevelBadge({ level: member.userLevel, levelName: member.levelName })
          }
        } else if (this.detailOf(member).length > 0) {
          Text(this.detailOf(member)).fontSize(12).fontColor(AppTheme.TEXT_SUB).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([AppTheme.ARROW_ROW])
    }.width('100%').padding(16).borderRadius(AppTheme.CARD_RADIUS).backgroundColor(AppTheme.CARD)
    .onClick(() => { this.openUser(member); })
  }
}
