/** 消息页的通知列表与登录引导。 */

import { RootPageHeader } from './PageHeader';
import { PageState } from './PageState';
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { authSession, AuthSession } from '../auth/AuthSession';
import { LoginEmptyView } from './LoginEmptyView';
import { NavigationService } from '../navigation/AppNavigation';
import { AppTheme } from '../theme/Theme';
import { visualThemeStore } from '../common/appearance/VisualThemeStore';
import { NotifyVM } from '../viewmodel/NotifyVM';
import { PullRefreshHeader, PULL_REFRESH_OFFSET } from './RefreshSpinner';
import { ForegroundRefresh, foregroundRefresh } from '../viewmodel/ForegroundRefresh';

/** 通知页一行分类的静态描述 */
interface NotifyRow {
  icon: Resource;
  title: string;
  subtitle: string;

  bg: ResourceColor;
  /** 图标颜色 */
  fg: ResourceColor;
  /** 通知列表或当前账号的粉丝列表。 */
  action: string;
}

/** 顶部页签的静态描述 */
interface MsgTab {
  label: string;
}

/** 每次构建读取语义色，主题切换时不保留模块初始化时的资源。 */
function notifyRows(): NotifyRow[] {
  return [
  {
    icon: $r('app.media.icon_like'),
    title: '点赞',
    subtitle: '',
    bg: AppTheme.MSG_BADGE_RED_BG,
    fg: AppTheme.MSG_BADGE_RED_FG,
    action: 'agree'
  },
  {
    icon: $r('app.media.icon_message'),
    title: '回复',
    subtitle: '',
    bg: AppTheme.MSG_BADGE_ORANGE_BG,
    fg: AppTheme.MSG_BADGE_ORANGE_FG,
    action: 'reply'
  },
  {
    icon: $r('app.media.icon_tag'),
    title: '@我的',
    subtitle: '',
    bg: AppTheme.MSG_BADGE_GREEN_BG,
    fg: AppTheme.MSG_BADGE_GREEN_FG,
    action: 'at'
  },
  {
    icon: $r('app.media.icon_person'),
    title: '粉丝',
    subtitle: '查看全部粉丝',
    bg: AppTheme.MSG_BADGE_BLUE_BG,
    fg: AppTheme.MSG_BADGE_BLUE_FG,
    action: 'fans'
  }
  ];
}

@ComponentV2
export struct MessageView {
  /** 顶部页签：0 = 通知，1 = 聊天（⚠️ 不能叫 tabIndex，与 ArkUI 内置属性 .tabIndex() 冲突） */
  @Local msgTabIndex: number = 0;
  @Param active: boolean = true;
  @Local auth: AuthSession = authSession;
  @Local foreground: ForegroundRefresh = foregroundRefresh;
  @Local replies: NotifyVM = new NotifyVM('reply');
  @Local likes: NotifyVM = new NotifyVM('agree');
  @Local mentions: NotifyVM = new NotifyVM('at');
  @Local refreshing: boolean = false;
  @Local pullRefreshDragging: boolean = false;
  private account: string = '';

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  @Monitor('active', 'foreground.revision', 'auth.snapshot')
  onVisibleChanged(): void {
    const account: string = authSession.isLoggedIn() ? authSession.sessionKey() : '';
    if (account !== this.account) {
      this.account = account;
      this.replies.dispose(); this.likes.dispose(); this.mentions.dispose();
      this.replies = new NotifyVM('reply'); this.likes = new NotifyVM('agree'); this.mentions = new NotifyVM('at');
    }
    if (this.active) { void this.reload(); }
  }

  private async reload(): Promise<void> {
    try {
      await Promise.all([this.replies.refresh(this.context()), this.likes.refresh(this.context()),
        this.mentions.refresh(this.context())]);
    } finally { this.refreshing = false; }
  }

  private preview(row: NotifyRow): string {
    if (row.action === 'fans') { return row.subtitle; }
    const vm: NotifyVM = row.action === 'agree' ? this.likes : row.action === 'at' ? this.mentions : this.replies;
    if (vm.error.length > 0) { return vm.hasItems() ? '刷新失败，点击查看已有通知' : '读取失败，点击重试'; }
    if (vm.hasItems()) {
      const item = vm.items[0];
      return `${item.displayName()}：${item.excerpt || item.title || item.headline()}`;
    }
    return vm.loading ? '正在读取…' : vm.loadedOnce ? '暂无通知' : '点击查看';
  }

  private msgTabs: MsgTab[] = [
    { label: '通知' },
    { label: '聊天' }
  ];

  aboutToAppear(): void {
    this.account = authSession.isLoggedIn() ? authSession.sessionKey() : '';
    this.replies = new NotifyVM('reply'); this.likes = new NotifyVM('agree'); this.mentions = new NotifyVM('at');
    if (this.active) { void this.reload(); }
  }

  aboutToDisappear(): void {
    this.replies.dispose(); this.likes.dispose(); this.mentions.dispose();
  }

  @Builder
  PullHeader() { PullRefreshHeader({ active: this.refreshing || this.pullRefreshDragging }) }

  build() {
    if (!authSession.snapshot.isLoggedIn()) {
      // 登录后由账号状态监听刷新通知摘要。
      LoginEmptyView({
        icon: $r('app.media.icon_message'),
        title: '登录后查看通知',
        subtitle: '查看收到的赞、回复和 @ 提醒',
        onLogin: (): void => {
          router.pushUrl({ url: 'pages/Login' });
        }
      })
    } else {
      Column() {
        // 页头沿用共享状态栏避让。
        RootPageHeader({ title: '消息' })

        // ── 顶部页签「通知 | 聊天」──
        Row() {
          ForEach(this.msgTabs, (tab: MsgTab, idx: number) => {
            Column({ space: 5 }) {
              Text(tab.label)
                .fontSize(16)
                .fontWeight(this.msgTabIndex === idx ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.msgTabIndex === idx ? AppTheme.TEXT_MAIN : AppTheme.TEXT_SUB)
              // 选中指示条：参考底栏强调色，与全局选中态一致
              Row()
                .width(24)
                .height(3)
                .borderRadius(1.5)
                .backgroundColor(this.msgTabIndex === idx ? AppTheme.ACCENT : Color.Transparent)
            }
            .layoutWeight(1)
            .padding({ top: 8, bottom: 8 })
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.msgTabIndex = idx;
            })
          }, (tab: MsgTab) => tab.label)
        }
        .width('100%')
        .constraintSize({ minHeight: 44 })
        .border({ width: { bottom: 0.5 }, color: AppTheme.DIVIDER })

        // ── 内容区 ──
        if (this.msgTabIndex === 0) {
          this.notifyList()
        } else {
          this.chatEmpty()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppTheme.BG)
    }
  }

  /** 通知页：四行分类入口（参考图样式） */
  @Builder
  notifyList() {
    Refresh({ refreshing: $$this.refreshing, builder: (): void => { this.PullHeader(); } }) {
      List() {
        ForEach(notifyRows(), (row: NotifyRow) => {
          ListItem() {
            Row({ space: 14 }) {
              // 彩色圆底 + 白色单色图标（本项目图标都是 SVG，fillColor 可染）
              Stack({ alignContent: Alignment.Center }) {
                Image(row.icon)
                  .width(24)
                  .height(24)
                  .fillColor(row.fg)
              }
              .width(48)
              .height(48)
              .backgroundColor(row.bg)
              .borderRadius(24)

              Column({ space: 3 }) {
                Text(row.title)
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(AppTheme.TEXT_MAIN)
                Text(this.preview(row)).fontSize(13).fontColor(AppTheme.TEXT_SUB)
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              // 右箭头：复用返回图标旋转 180°，避免新增资源
              if (row.action.length > 0) {
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).maxFontScale(1)
                  .fontColor([AppTheme.ARROW_LIST])
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .enabled(row.action.length > 0)
            .onClick(() => {
              if (row.action === 'fans') {
                const uid: number = authSession.snapshot.uid;
                if (!Number.isSafeInteger(uid) || uid <= 0) {
                  this.getUIContext().getPromptAction().showToast({ message: '账号身份尚未准备好，请稍后重试' }); return;
                }
                NavigationService.openDirectory({ kind: 'fans', id: uid, title: '我的粉丝' }); return;
              }
              if (row.action.length > 0) {
                NavigationService.openNotifyList({ kind: row.action });
                return;
              }
            })
          }
        }, (row: NotifyRow) => `${row.title}:${visualThemeStore.theme}`)
      }
      .width('100%')
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring).scrollBar(BarState.Off)
    }.layoutWeight(1).refreshOffset(PULL_REFRESH_OFFSET)
    .onStateChange((state: RefreshStatus): void => {
      this.pullRefreshDragging = state === RefreshStatus.Drag || state === RefreshStatus.OverDrag;
    }).onRefreshing((): void => { void this.reload(); })
  }

  /** 聊天页：空态占位（私信端点尚未移植，不给假入口） */
  @Builder
  chatEmpty() {
    PageState({ fillRemaining: true, title: '聊天暂未开放' })
      .layoutWeight(1)
  }
}
