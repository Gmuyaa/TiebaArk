

import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { authSession } from '../auth/AuthSession';
import { LoginEmptyView } from './LoginEmptyView';
import { NavigationService } from '../navigation/AppNavigation';
import { AppTheme } from '../theme/Theme';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';

interface NotifyRow {
  icon: Resource;
  title: string;
  subtitle: string;

  bg: ResourceColor;

  fg: ResourceColor;

  action: string;
}

interface MsgTab {
  label: string;
}

const NOTIFY_ROWS: NotifyRow[] = [
  {
    icon: $r('app.media.icon_like'),
    title: '点赞',
    subtitle: '没有最新消息',
    bg: AppTheme.MSG_BADGE_RED_BG,
    fg: AppTheme.MSG_BADGE_RED_FG,
    action: 'agree'
  },
  {
    icon: $r('app.media.icon_message'),
    title: '回复',
    subtitle: '没有最新消息',
    bg: AppTheme.MSG_BADGE_ORANGE_BG,
    fg: AppTheme.MSG_BADGE_ORANGE_FG,
    action: 'reply'
  },
  {
    icon: $r('app.media.icon_tag'),
    title: '@我的',
    subtitle: '查看提到我的通知',
    bg: AppTheme.MSG_BADGE_GREEN_BG,
    fg: AppTheme.MSG_BADGE_GREEN_FG,
    action: 'at'
  },
  {
    icon: $r('app.media.icon_person'),
    title: '粉丝',
    subtitle: '暂无新粉丝',
    bg: AppTheme.MSG_BADGE_BLUE_BG,
    fg: AppTheme.MSG_BADGE_BLUE_FG,
    action: ''
  }
];

@ComponentV2
export struct MessageView {

  @Local msgTabIndex: number = 0;

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

    });
  }

  build() {
    if (!authSession.snapshot.isLoggedIn()) {

      LoginEmptyView({
        icon: $r('app.media.icon_message'),
        title: '还没有消息',
        subtitle: '登录后可查看回复、@提醒与私信',
        onLogin: (): void => {
          router.pushUrl({ url: 'pages/Login' });
        }
      })
    } else {
      Column() {

        Text('消息')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT_MAIN)
          .width('100%')
          .padding({ left: AppTheme.PAGE_GUTTER + 4, top: this.statusBarH + 8, bottom: 10 })

        Row() {
          ForEach(this.msgTabs, (tab: MsgTab, idx: number) => {
            Column({ space: 5 }) {
              Text(tab.label)
                .fontSize(16)
                .fontWeight(this.msgTabIndex === idx ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.msgTabIndex === idx ? AppTheme.TEXT_MAIN : AppTheme.TEXT_SUB)

              Row()
                .width(24)
                .height(3)
                .borderRadius(1.5)
                .backgroundColor(this.msgTabIndex === idx ? AppTheme.ACCENT : Color.Transparent)
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.msgTabIndex = idx;
            })
          }, (tab: MsgTab) => tab.label)
        }
        .width('100%')
        .height(44)
        .border({ width: { bottom: 0.5 }, color: AppTheme.DIVIDER })

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

  @Builder
  notifyList() {
    Column() {
      ForEach(NOTIFY_ROWS, (row: NotifyRow) => {
        Row({ space: 14 }) {

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
            Text(row.subtitle)
              .fontSize(13)
              .fontColor(AppTheme.TEXT_SUB)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Image($r('app.media.icon_back'))
            .width(16)
            .height(16)
            .fillColor(AppTheme.ARROW_LIST)
            .rotate({ angle: 180 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
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

    .padding({ bottom: AppTheme.BAR_TOTAL_H })
  }

  @Builder
  chatEmpty() {
    Column({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Image($r('app.media.icon_message'))
          .width(34)
          .height(34)
          .fillColor(AppTheme.ACCENT)
      }
      .width(72)
      .height(72)
      .backgroundColor(AppTheme.ACCENT_LIGHT)
      .borderRadius(36)

      Text('暂无聊天')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_MAIN)
      Text('私信功能暂未开放')
        .fontSize(13)
        .fontColor(AppTheme.TEXT_SUB)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }
}
