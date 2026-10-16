

import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { authSession } from '../auth/AuthSession';
import { AuthSnapshot } from '../auth/AuthModel';
import { AppTheme } from '../theme/Theme';
import { AvatarComponent } from './AvatarComponent';
import { GlassCircleButton } from './GlassCircleButton';
import { ThemeModeIcon } from './ThemeModeIcon';
import { portraitUrl } from '../model/ThreadDetail';
import { formatCount } from '../model/UserProfile';
import { NavigationService } from '../navigation/AppNavigation';
import { avatarTrace } from '../utils/AvatarTrace';
import { themeModeStore } from '../common/appearance/ThemeModeStore';
import { nextThemeModePref, themeModeLabel } from '../common/appearance/ThemeMode';

import { SettingsLayout } from '../common/appearance/SettingsLayout';

const HEADER_BUTTON: number = 44;
const HEADER_ICON: number = 22;

const HEADER_GAP: number = 12;

const SETTINGS_ICON_OFFSET: number = -1;

const ROW_HEIGHT: number = 60;

interface ProfileRow {

  symbol?: Resource;

  icon?: Resource;
  label: string;

  kind: string;
}

@ComponentV2
export struct ProfileView {

  @Param rows: ProfileRow[] = [
    {
      symbol: $r('sys.symbol.clock'), icon: $r('app.media.icon_history'), label: '浏览历史',
      kind: 'history'
    },
    {
      symbol: $r('sys.symbol.star'), icon: $r('app.media.icon_star'), label: '我的收藏',
      kind: 'fav'
    },
    {
      symbol: $r('sys.symbol.doc_text'), icon: $r('app.media.icon_doc'),
      label: '我的帖子', kind: 'thread'
    },
    {
      symbol: $r('sys.symbol.message'), icon: $r('app.media.icon_message'), label: '我的回复',
      kind: 'reply'
    }
  ];

  private accountTitle(snapshot: AuthSnapshot): string {
    if (!snapshot.isLoggedIn()) {
      return '未登录';
    }
    if (snapshot.nickname.length > 0) {
      return snapshot.nickname;
    }
    if (snapshot.userName.length > 0) {
      return snapshot.userName;
    }
    return '贴吧用户';
  }

  private avatarUrl(): string {
    return portraitUrl(authSession.snapshot.portrait, authSession.avatarRevision);
  }

  private accountIdLine(snapshot: AuthSnapshot): string {
    const parts: string[] = [];
    if (snapshot.uid > 0) {
      parts.push(`uid ${snapshot.uid}`);
    }
    if (snapshot.tbAge.length > 0) {
      parts.push(`吧龄 ${snapshot.tbAge}`);
    }
    return parts.join(' · ');
  }

  private noteLine(snapshot: AuthSnapshot): string {
    if (snapshot.isLoggedIn()) {
      return '';
    }
    if (snapshot.expiredReason.length > 0) {
      return snapshot.expiredReason;
    }
    return '登录后可点赞并使用写操作';
  }

  private countText(snapshot: AuthSnapshot, value: number): string {
    return snapshot.socialLoaded ? formatCount(value) : '—';
  }

  private levelText(snapshot: AuthSnapshot): string {
    if (!snapshot.socialLoaded) {
      return '—';
    }
    return `Lv.${snapshot.levelId}`;
  }

  @Builder
  appearanceIcon() {
    ThemeModeIcon({ mode: themeModeStore.pref, iconSize: HEADER_ICON })
  }

  private cycleThemeMode(): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    themeModeStore.setMode(nextThemeModePref(themeModeStore.pref), context);
  }

  build() {
    Scroll() {
      Column() {
        Row({ space: HEADER_GAP }) {
          Text('我的')
            .fontSize(29)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.TEXT_MAIN)
          Blank()

          GlassCircleButton({
            diameter: HEADER_BUTTON,
            iconSize: HEADER_ICON,
            useCustomIcon: true,
            customIcon: (): void => { this.appearanceIcon() },
            onTap: (): void => { this.cycleThemeMode(); }
          })
            .accessibilityText('外观：' + themeModeLabel(themeModeStore.pref))

          GlassCircleButton({
            symbol: $r('sys.symbol.gearshape'),
            diameter: HEADER_BUTTON,
            iconSize: HEADER_ICON,
            iconOffsetX: SETTINGS_ICON_OFFSET,
            onTap: (): void => { router.pushUrl({ url: 'pages/Settings' }); }
          })
            .accessibilityText('设置')
        }
        .width('100%')
        .constraintSize({ minHeight: 56 })
        .padding({ top: 6, bottom: 6 })

        Row({ space: 16 }) {
          AvatarComponent({
            url: this.avatarUrl(),
            avatarSize: 72,
            fallbackName: this.accountTitle(authSession.snapshot),
            traceTag: 'self'
          })
          Column({ space: 7 }) {
            Text(this.accountTitle(authSession.snapshot))
              .fontSize(21)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.TEXT_MAIN)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.accountIdLine(authSession.snapshot).length > 0) {
              Text(this.accountIdLine(authSession.snapshot))
                .fontSize(12)
                .fontColor(AppTheme.TEXT_SUB)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            if (this.noteLine(authSession.snapshot).length > 0) {
              Text(this.noteLine(authSession.snapshot))
                .fontSize(12)
                .fontColor(AppTheme.TEXT_SUB)
                .maxLines(2)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (!authSession.snapshot.isLoggedIn()) {
            Button('登录')
              .fontSize(13)
              .height(34)
              .borderRadius(17)
              .backgroundColor(AppTheme.ACCENT)
              .fontColor(Color.White)
              .onClick(() => { router.pushUrl({ url: 'pages/Login' }); })
          }
        }
        .width('100%')
        .constraintSize({ minHeight: 84 })
        .padding({ top: 6, bottom: 6 })
        .margin({ top: 16 })
        .onClick(() => {
          if (authSession.snapshot.isLoggedIn()) {
            NavigationService.openUser({ uid: authSession.snapshot.uid,
              portrait: authSession.snapshot.portrait, name: this.accountTitle(authSession.snapshot) });
          }
        })

        if (authSession.snapshot.isLoggedIn()) {
          Row() {
            this.StatCell('关注', this.countText(authSession.snapshot, authSession.snapshot.concernNum))
            Divider().vertical(true).height(30).color(AppTheme.DIVIDER)
            this.StatCell('粉丝', this.countText(authSession.snapshot, authSession.snapshot.fansNum))
            Divider().vertical(true).height(30).color(AppTheme.DIVIDER)
            this.StatCell('等级', this.levelText(authSession.snapshot))
            Divider().vertical(true).height(30).color(AppTheme.DIVIDER)
            this.StatCell('关注吧', this.countText(authSession.snapshot, authSession.snapshot.likeForumNum))
          }
          .width('100%')
          .constraintSize({ minHeight: ROW_HEIGHT })
          .padding({ left: 6, right: 6, top: 8, bottom: 8 })
          .borderRadius(SettingsLayout.CARD_RADIUS)
          .backgroundColor(AppTheme.CARD)
          .margin({ top: 20 })
        }

        Column({ space: SettingsLayout.ROW_GAP }) {
          this.FeatureRow(this.rows[0])
          this.FeatureRow(this.rows[1])
          this.FeatureRow(this.rows[2])
          this.FeatureRow(this.rows[3])
        }
        .width('100%')

        .margin({ top: SettingsLayout.ROW_GAP })

        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(23)
            .fontColor([AppTheme.ICON])
          Text('设置')
            .fontSize(15)
            .fontColor(AppTheme.TEXT_ROW)
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(15)
            .fontColor([AppTheme.ARROW_ROW])
        }
        .width('100%')
        .constraintSize({ minHeight: ROW_HEIGHT })
        .padding({
          left: SettingsLayout.ROW_PAD_L, right: SettingsLayout.ROW_PAD_R,
          top: 8, bottom: 8
        })
        .borderRadius(SettingsLayout.CARD_RADIUS)
        .backgroundColor(AppTheme.CARD)

        .margin({ top: SettingsLayout.ROW_GAP })
        .onClick(() => { router.pushUrl({ url: 'pages/Settings' }); })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      .padding({
        left: SettingsLayout.PAGE_GUTTER, right: SettingsLayout.PAGE_GUTTER,
        top: 12, bottom: AppTheme.BAR_TOTAL_H + 24
      })
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG)

    .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, ratio: number): void => {
      if (isVisible && ratio > 0) { avatarTrace('page-visible', 0, 'page=mine'); }
    })
  }

  @Builder
  StatCell(label: string, value: string) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(19)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_MAIN)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(label)
        .fontSize(11)
        .fontColor(AppTheme.TEXT_SUB)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      const uid: number = authSession.snapshot.uid;
      if (label === '关注' || label === '粉丝') {
        if (uid <= 0) {
          this.getUIContext().getPromptAction().showToast({ message: '用户资料尚未加载，请稍后重试' });
          return;
        }
        NavigationService.openDirectory({ kind: label === '关注' ? 'following' : 'fans', id: uid });
      } else if (label === '关注吧') {
        NavigationService.openUser({ uid, portrait: authSession.snapshot.portrait,
          name: this.accountTitle(authSession.snapshot), tab: 2 });
      }
    })
  }

  @Builder
  FeatureRow(row: ProfileRow) {
    Row({ space: 10 }) {
      if (row.symbol !== undefined) {
        SymbolGlyph(row.symbol)
          .fontSize(22)
          .fontColor([AppTheme.ICON])
      } else {
        Image(row.icon)
          .width(22)
          .height(22)
          .fillColor(AppTheme.ICON)
      }
      Text(row.label)
        .fontSize(14)
        .fontColor(AppTheme.TEXT_ROW)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([AppTheme.ARROW_ROW])
    }
    .width('100%')
    .constraintSize({ minHeight: ROW_HEIGHT })

    .padding({
      left: SettingsLayout.ROW_PAD_L, right: SettingsLayout.ROW_PAD_R,
      top: 8, bottom: 8
    })
    .borderRadius(SettingsLayout.CARD_RADIUS)
    .backgroundColor(AppTheme.CARD)
    .onClick(() => { NavigationService.openMyList({ kind: row.kind }); })
  }
}
