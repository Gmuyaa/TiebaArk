import { RootPageHeader } from './PageHeader';
import { PageState } from './PageState';
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
  /** 列表**尾部占位项**高度（= 悬浮底栏最坏占位 `AppTheme.BAR_TOTAL_H`）：列表本身铺满整页，只让内容末尾留出这段。 */
  @Param bottomBarOcclusion: number = 0;
  @Local vm: FollowVM = new FollowVM();
  @Local auth: AuthSession = authSession;
  @Local signStrategy: SignStrategyStore = signStrategyStore;
  @Monitor('auth.snapshot')
  onAccountChanged(): void { void this.vm.load(this.hostContext()); }
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
  aboutToDisappear(): void { this.vm.dispose(); }

  build() {
    if (!authSession.snapshot.isLoggedIn()) {
      // 未登录：沿用 Index 原空态的引导组件（登录返回后切 Tab 重建自然刷新）
      LoginEmptyView({
        icon: $r('app.media.icon_follow'),
        title: '关注列表是空的',
        subtitle: '登录后可查看关注的吧；关注吧的帖子在首页关注频道查看',
        onLogin: (): void => {
          router.pushUrl({ url: 'pages/Login' });
        }
      })
    } else {
      this.FollowPage()
    }
  }

  /** 头部：左「我的关注」标题 + 右侧沉浸光感「签」圆按钮。 */
  @Builder
  HeaderActions() {
        GlassCircleButton({
          label: this.vm.signingAll ? '…' : '签', diameter: 40, iconSize: 22, iconOffsetX: -2.5, labelOffsetY: 0.5,
          accessibilityLabel: this.vm.signingAll ? '正在签到' :
            (this.signStrategy.strategy === 1 ? '官方签到，暂不可用' : '一键签到'),
          onTap: (): void => {
            this.vm.signInAll(this.hostContext()).then((message: string) => {
              if (message.length > 0) {
                promptAction.showToast({ message: message, duration: 2400 });
              }
            });
          }
        }).enabled(!this.vm.signingAll && this.vm.forums.length > 0)
  }

  @Builder
  FollowPage() {
    Column() {
      RootPageHeader({ title: '我的关注', actions: (): void => { this.HeaderActions(); } })

      if (this.vm.loading && !this.vm.loadedOnce) {
        PageState({ fillRemaining: true, loading: true, message: '正在加载关注的吧…' }).layoutWeight(1)
      } else if (this.vm.forums.length === 0 && this.vm.errorText.length > 0) {
        PageState({ fillRemaining: true, title: '加载失败', message: this.vm.errorText, actionLabel: '重试',
          onAction: (): void => { void this.vm.load(this.hostContext(), true); } }).layoutWeight(1)
      } else if (this.vm.forums.length === 0) {
        PageState({ fillRemaining: true, message: '还没有关注任何吧' }).layoutWeight(1)
      } else {
        if (this.vm.errorText.length > 0) {
          PageState({ compact: true, message: '更新失败，正在显示上次数据', actionLabel: '重试',
            onAction: (): void => { void this.vm.load(this.hostContext(), true); } })
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
      }
    }
    .width('100%')
    .layoutWeight(1)
    .clip(true)
    .scrollBar(BarState.Off)
    .divider({
      strokeWidth: 0.5,
      color: AppTheme.DIVIDER,
      startMargin: 80,
      endMargin: 16
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
          ForumLevelBadge({ level: item.level, levelName: item.levelName }).flexShrink(0)
          if (item.continuousCount >= 0 || item.totalCount >= 0) {
            Text((item.continuousCount >= 0 ? `连签 ${item.continuousCount} 天` : '') +
              (item.continuousCount >= 0 && item.totalCount >= 0 ? ' · ' : '') +
              (item.totalCount >= 0 ? `累计 ${item.totalCount} 次` : ''))
              .fontSize(10).fontColor(AppTheme.TEXT_SUB)
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
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
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

  /** 签到按钮：未签到可点（真实写操作），已签到变灰不可点 */
  @Builder
  SignButton(item: FollowForumItem) {
    Text(!item.signKnown ? '读取中…' : item.isSigned ? '已签到'
      : (this.vm.signingFname === item.fname ? '签到中…' : '签到'))
      .fontSize(13)
      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ minHeight: 40, minWidth: 64, maxWidth: 96 }).flexShrink(0)
      .textAlign(TextAlign.Center)
      .fontColor(item.isSigned ? AppTheme.TEXT_MUTED : AppTheme.ACCENT_DARK)
      .backgroundColor(item.isSigned ? Color.Transparent : AppTheme.ACCENT_LIGHT)
      .border({ width: item.isSigned ? 0.5 : 0, color: AppTheme.DIVIDER })
      .borderRadius(14)
      .padding({
        left: 12,
        right: 12,
        top: 5,
        bottom: 5
      })
      .onClick(() => {
        if (!item.signKnown) { void this.vm.load(this.hostContext(), true); return; }
        // 写操作防连点在 VM 内部（signingFname 占位）；结果用 toast 反馈
        this.vm.signIn(this.hostContext(), item).then((message: string) => {
          if (message.length > 0) {
            promptAction.showToast({ message: message, duration: 2000 });
          }
        });
      })
  }
}
