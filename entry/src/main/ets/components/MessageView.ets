/** 消息页的通知列表与登录引导。 */

import { RootPageHeader } from './PageHeader';
import { PageState } from './PageState';
import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { authSession } from '../auth/AuthSession';
import { LoginEmptyView } from './LoginEmptyView';
import { NavigationService } from '../navigation/AppNavigation';
import { AppTheme } from '../theme/Theme';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';

/** 通知页一行分类的静态描述 */
interface NotifyRow {
  icon: Resource;
  title: string;
  subtitle: string;

  bg: ResourceColor;
  /** 图标颜色 */
  fg: ResourceColor;
  /** 点击行为：'agree' | 'reply' = 打开对应通知列表；'' = 暂未开放（toast） */
  action: string;
}

/** 顶部页签的静态描述 */
interface MsgTab {
  label: string;
}

const NOTIFY_ROWS: NotifyRow[] = [
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
    subtitle: '暂未开放',
    bg: AppTheme.MSG_BADGE_BLUE_BG,
    fg: AppTheme.MSG_BADGE_BLUE_FG,
    action: ''
  }
];

@ComponentV2
export struct MessageView {
  /** 顶部页签：0 = 通知，1 = 聊天（⚠️ 不能叫 tabIndex，与 ArkUI 内置属性 .tabIndex() 冲突） */
  @Local msgTabIndex: number = 0;
  /** 状态栏高度（vp），见 SafeArea.ets */
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;

  private msgTabs: MsgTab[] = [
    { label: '通知' },
    { label: '聊天' }
  ];

  aboutToAppear(): void {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    readStatusBarVp(context).then((vp: number) => {
      this.statusBarH = vp;
    }).catch(() => {
      // 拿不到就保持兜底值
    });
  }

  build() {
    if (!authSession.snapshot.isLoggedIn()) {
      // 未登录：与「关注」Tab 同一引导模式（登录返回后切 Tab 重建自然刷新）
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
        // ── 页头：大标题（页面贴顶，自己让出状态栏，见 SafeArea.ets）──
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
    Column() {
      ForEach(NOTIFY_ROWS, (row: NotifyRow) => {
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
            if (row.subtitle.length > 0) {
              Text(row.subtitle).fontSize(13).fontColor(AppTheme.TEXT_SUB)
            }
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
          if (row.action.length > 0) {
            NavigationService.openNotifyList({ kind: row.action });
            return;
          }
          promptAction.showToast({ message: `${row.title}暂未开放`, duration: 2000 });
        })
      }, (row: NotifyRow) => row.title)
    }
    .width('100%')
    .layoutWeight(1)
    // 底部留白：给悬浮胶囊让位（与其他列表页同一常量）
    .padding({ bottom: AppTheme.BAR_TOTAL_H })
  }

  /** 聊天页：空态占位（私信端点尚未移植，不给假入口） */
  @Builder
  chatEmpty() {
    PageState({ fillRemaining: true, title: '聊天暂未开放' })
      .layoutWeight(1)
  }
}
