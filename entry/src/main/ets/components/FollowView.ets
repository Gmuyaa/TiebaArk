import { followChanges } from '../viewmodel/FollowActionVM';

import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { FollowVM } from '../viewmodel/FollowVM';
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

@ComponentV2
export struct FollowView {
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
    for (const item of this.vm.forums) {
      if (this.visibleForums.has(item.fid)) { this.vm.ensureExperience(this.hostContext(), item); }
    }
    if (!this.relationshipRefreshPending) { return; }
    this.relationshipRefreshPending = false;
    this.vm.load(this.hostContext(), true);
  }

  @Param bottomBarOcclusion: number = 0;
  @Local vm: FollowVM = new FollowVM();
  @Local auth: AuthSession = authSession;
  @Local signStrategy: SignStrategyStore = signStrategyStore;
  @Monitor('auth.snapshot')
  onAccountChanged(): void { void this.vm.load(this.hostContext()); }

  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;

  aboutToAppear(): void {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    readStatusBarVp(context).then((vp: number) => {
      this.statusBarH = vp;
    }).catch(() => {

    });

    this.vm.load(context);
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }
  aboutToDisappear(): void { this.vm.dispose(); }

  build() {
    if (!authSession.snapshot.isLoggedIn()) {

      LoginEmptyView({
        icon: $r('app.media.icon_follow'),
        title: '关注列表是空的',
        subtitle: '登录后可查看关注的吧；关注吧的帖子在首页关注频道查看',
        onLogin: (): void => {
          router.pushUrl({ url: 'pages/Login' });
        }
      })
    } else if (this.vm.loading && !this.vm.loadedOnce) {
      Column() {
        Text('正在加载关注的吧…')
          .fontSize(14)
          .fontColor(AppTheme.TEXT_SUB)
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarH })
      .justifyContent(FlexAlign.Center)
    } else if (this.vm.errorText.length > 0 && this.vm.forums.length === 0) {
      Column({ space: 10 }) {
        Text('加载失败')
          .fontSize(15)
          .fontColor(AppTheme.TEXT_MAIN)
        Text(this.vm.errorText)
          .fontSize(12)
          .fontColor(AppTheme.TEXT_SUB)
          .textAlign(TextAlign.Center)
        Text('点击重试')
          .fontSize(13)
          .fontColor(AppTheme.ACCENT_DARK)
          .onClick(() => {
            this.vm.load(this.hostContext(), true);
          })
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarH })
      .justifyContent(FlexAlign.Center)
    } else if (this.vm.forums.length === 0) {
      Column() {
        Text('还没有关注任何吧')
          .fontSize(14)
          .fontColor(AppTheme.TEXT_SUB)
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarH })
      .justifyContent(FlexAlign.Center)
    } else {
      this.FollowPage()
    }
  }

  @Builder
  FollowPage() {
    Column() {
      Row() {
        Text('我的关注')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT_MAIN)

        Blank()

        GlassCircleButton({
          label: '签', diameter: 40, iconSize: 22, iconOffsetX: -2.5, labelOffsetY: 0.5,
          accessibilityLabel: this.vm.signingAll ? '正在签到' :
            (this.signStrategy.strategy === 1 ? '官方签到，暂不可用' : '一键签到'),
          onTap: (): void => {
            this.vm.signInAll(this.hostContext()).then((message: string) => {
              if (message.length > 0) {
                promptAction.showToast({ message: message, duration: 2400 });
              }
            });
          }
        })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: this.statusBarH + 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      if (this.vm.errorText.length > 0) {
        Text('更新失败，显示上次数据；点击重试').fontSize(11).fontColor(AppTheme.TEXT_SUB)
          .padding({ left: 14, right: 14, bottom: 6 })
          .onClick(() => { void this.vm.load(this.hostContext(), true); })
      }
      this.FollowList()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  FollowList() {
    List({ space: 0 }) {
      ForEach(this.vm.forums, (item: FollowForumItem) => {
        ListItem() {
          this.FollowRow(item)
        }

      }, (item: FollowForumItem) => `${item.fid}-${item.fname}-${item.isSigned ? 1 : 0}-${item.signKnown ? 1 : 0}-${item.level}-${item.levelName}-${item.continuousCount}-${item.totalCount}`)

      ListItem() {
        Column().width('100%').height(this.bottomBarOcclusion)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .clip(true)
    .scrollBar(BarState.Off)
    .divider({
      strokeWidth: 0.5,
      color: '#14000000',
      startMargin: 78,
      endMargin: 14
    })
  }

  @Builder
  FollowRow(item: FollowForumItem) {
    Row({ space: 12 }) {

      ForumAvatarImage({ url: item.avatar, forumName: item.fname,
        avatarSize: 52, radius: 52 * 14 / 64 })

      Column({ space: 4 }) {
        Text(item.fname.endsWith('吧') ? item.fname : `${item.fname}吧`)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_MAIN)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 8 }) {
          ForumLevelBadge({ level: item.level, levelName: item.levelName })
          if (item.continuousCount >= 0 || item.totalCount >= 0) {
            Text((item.continuousCount >= 0 ? `连签 ${item.continuousCount} 天` : '') +
              (item.continuousCount >= 0 && item.totalCount >= 0 ? ' · ' : '') +
              (item.totalCount >= 0 ? `累计 ${item.totalCount} 次` : ''))
              .fontSize(10).fontColor(AppTheme.TEXT_SUB)
              .layoutWeight(1)
          }
        }
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      this.SignButton(item)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
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

  @Builder
  SignButton(item: FollowForumItem) {
    Text(!item.signKnown ? '读取中…' : item.isSigned ? '已签到'
      : (this.vm.signingFname === item.fname ? '签到中…' : '签到'))
      .fontSize(13)
      .fontColor(item.isSigned ? AppTheme.TEXT_MUTED : AppTheme.ACCENT_DARK)
      .backgroundColor(item.isSigned ? Color.Transparent : AppTheme.ACCENT_LIGHT)
      .border({ width: item.isSigned ? 0.5 : 0, color: '#1A000000' })
      .borderRadius(14)
      .padding({
        left: 12,
        right: 12,
        top: 5,
        bottom: 5
      })
      .onClick(() => {
        if (!item.signKnown) { void this.vm.load(this.hostContext(), true); return; }

        this.vm.signIn(this.hostContext(), item).then((message: string) => {
          if (message.length > 0) {
            promptAction.showToast({ message: message, duration: 2000 });
          }
        });
      })
  }
}
