import { motionEdgeEffect } from '../common/appearance/MotionPolicy';
/** 消息页的通知列表与登录引导。 */

import { RootPageHeader } from './PageHeader';
import { GlassCircleButton } from './GlassCircleButton';
import { PageState } from './PageState';
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { authSession, AuthSession } from '../auth/AuthSession';
import { LoginEmptyView } from './LoginEmptyView';
import { NavigationService } from '../navigation/AppNavigation';
import { AppTheme } from '../theme/Theme';
import { visualThemeStore } from '../common/appearance/VisualThemeStore';
import { NotifyUnreadKind } from '../model/NotifyUnread';
import { NotifyUnreadVM, notifyUnreadVM } from '../viewmodel/NotifyUnreadVM';
import { PullRefreshHeader, PULL_REFRESH_OFFSET } from './RefreshSpinner';

/** 通知页一行分类的静态描述 */
interface NotifyRow {
  icon: Resource;
  title: string;
  subtitle: string;

  bg: ResourceColor;
  /** 图标颜色 */
  fg: ResourceColor;
  /** 通知列表或当前账号的粉丝列表。 */
  action: NotifyUnreadKind;
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
  @Local unread: NotifyUnreadVM = notifyUnreadVM;
  @Local refreshing: boolean = false;
  @Local pullRefreshDragging: boolean = false;
  @Local readDialogPending: boolean = false;
  private refreshRevision: number = 0;
  private viewRevision: number = 0;

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  @Monitor('active', 'msgTabIndex', 'auth.snapshot')
  onVisibleChanged(): void {
    if (this.active && this.msgTabIndex === 0 && authSession.isLoggedIn()) { void this.reload(); }
    else { this.viewRevision++; this.finishRefreshing(); }
  }

  @Monitor('unread.marking')
  onMarkingChanged(): void {
    if (this.unread.marking) { this.finishRefreshing(); }
  }

  private finishRefreshing(): void {
    this.refreshRevision++; this.refreshing = false;
  }

  private async reload(): Promise<void> {
    const revision: number = ++this.refreshRevision;
    try {
      await this.unread.refresh(this.context());
    } finally { if (revision === this.refreshRevision) { this.refreshing = false; } }
  }

  private preview(row: NotifyRow): string {
    const text: string = this.unread.previews.text(row.action);
    if (text.length > 0) { return `上次查看：${text}`; }
    return this.unread.counts.count(row.action) > 0 ? '有新消息，点击查看' : '点击查看最近消息';
  }

  private async confirmMarkAllRead(): Promise<void> {
    if (this.readDialogPending || this.unread.marking) { return; }
    this.readDialogPending = true;
    const revision: number = this.viewRevision;
    const account: string = authSession.isLoggedIn() ? authSession.sessionKey() : '';
    const target: NotifyUnreadVM = this.unread;
    try {
      const confirm = await this.getUIContext().getPromptAction().showDialog({
        title: '全部标记为已读',
        message: '将点赞、回复、@我的和粉丝消息全部标记为已读？',
        buttons: [{ text: '取消', color: AppTheme.TEXT_SUB }, { text: '全部已读', color: AppTheme.ACCENT }]
      });
      if (confirm.index !== 1 || revision !== this.viewRevision || !this.active || this.msgTabIndex !== 0 ||
        account !== authSession.sessionKey()) { return; }
      const message: string = await target.markAllRead(this.context(), account);
      if (message.length > 0 && this.active && account === authSession.sessionKey()) {
        this.getUIContext().getPromptAction().showToast({ message });
      }
    } catch (err) { /* 系统取消或关闭弹窗，不发起已读操作。 */ }
    finally { this.readDialogPending = false; }
  }

  @Builder
  ReadAction() {
    if (this.msgTabIndex === 0) {
      Row() {
        if (this.unread.marking) {
          LoadingProgress().width(24).height(24).color(AppTheme.ACCENT)
        } else {
          GlassCircleButton({ symbol: $r('sys.symbol.envelope_open'), iconWeight: FontWeight.Regular,
            accessibilityLabel: '将消息全部标记为已读', onTap: (): void => { void this.confirmMarkAllRead(); } })
        }
      }.width(40).height(40).justifyContent(FlexAlign.Center)
      .id('message-mark-all-read').enabled(!this.readDialogPending && !this.unread.marking)
    }
  }

  private msgTabs: MsgTab[] = [
    { label: '通知' },
    { label: '聊天' }
  ];

  aboutToAppear(): void {
    this.onVisibleChanged();
  }

  aboutToDisappear(): void {
    this.viewRevision++; this.finishRefreshing();
  }

  @Builder
  PullHeader() { PullRefreshHeader({ active: this.refreshing || this.pullRefreshDragging }) }

  build() {
    if (!this.auth.snapshot.isLoggedIn()) {
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
        RootPageHeader({ title: '消息', actions: (): void => { this.ReadAction(); } })

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
            .constraintSize({ minHeight: 48 })
            .padding({ top: 8, bottom: 8 })
            .justifyContent(FlexAlign.Center)
            .accessibilityText(tab.label)
            .accessibilitySelected(this.msgTabIndex === idx)
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
      List({ space: 10 }) {
        if (this.unread.error.length > 0) {
          ListItem() {
            PageState({ compact: true,
              message: this.unread.loaded ? '提醒刷新失败，数字为上次结果' : '提醒读取失败',
              actionLabel: '重试', onAction: (): void => { void this.reload(); } })
          }
        } else if (!this.unread.loaded && this.unread.loading) {
          ListItem() { PageState({ compact: true, loading: true, message: '正在读取提醒…' }) }
        }
        ForEach(notifyRows(), (row: NotifyRow) => {
          ListItem() {
            Row({ space: 14 }) {
              // 彩色圆底 + 白色单色图标（本项目图标都是 SVG，fillColor 可染）
              Stack({ alignContent: Alignment.Center }) {
                Image(row.icon).width(24).height(24).fillColor(row.fg)
              }
              .width(48).height(48).backgroundColor(row.bg).borderRadius(24)
              .flexShrink(0).accessibilityLevel('no')

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

              if (this.unread.counts.count(row.action) > 0) {
                Badge({ count: this.unread.counts.count(row.action), maxCount: 99, position: { x: 0, y: 0 },
                  style: { badgeSize: 20, fontSize: 12, fontWeight: FontWeight.Medium,
                    badgeColor: AppTheme.NOTIFY_BADGE_BACKGROUND, color: AppTheme.NOTIFY_BADGE_TEXT } }) {
                  Row().width(0).height(20)
                }.width(this.unread.counts.count(row.action) > 99 ? 34 : this.unread.counts.count(row.action) > 9 ? 28 : 20)
                .height(20).flexShrink(0).accessibilityLevel('no')
              }

              // 右箭头：复用返回图标旋转 180°，避免新增资源
              if (row.action.length > 0) {
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).maxFontScale(1)
                  .fontColor([AppTheme.ARROW_LIST])
                  .flexShrink(0).accessibilityLevel('no')
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .borderRadius(AppTheme.CARD_RADIUS)
            .backgroundColor(AppTheme.CARD)
            .clip(true)
            .accessibilityGroup(true)
            .accessibilityText(row.title + '，' + this.preview(row) +
              (this.unread.counts.count(row.action) > 0 ? `，${this.unread.counts.count(row.action)} 条未读` : ''))
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
      .padding({ left: 16, right: 16, top: 12 })
      .layoutWeight(1)
      .edgeEffect(motionEdgeEffect()).scrollBar(BarState.Off)
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
