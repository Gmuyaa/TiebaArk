/** 个人中心：账号资料、内容入口与设置入口。 */

import { RootPageHeader } from './PageHeader';
import { SettingsEntryRow } from './SettingsComponents';
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { authSession } from '../auth/AuthSession';
import { AuthSnapshot } from '../auth/AuthModel';
import { AppTheme } from '../theme/Theme';
import { visualThemeStore } from '../common/appearance/VisualThemeStore';
import { AvatarComponent } from './AvatarComponent';
import { GlassCircleButton } from './GlassCircleButton';
import { ThemeModeIcon } from './ThemeModeIcon';
import { portraitUrl } from '../model/ThreadDetail';
import { formatCount } from '../model/UserProfile';
import { NavigationService } from '../navigation/AppNavigation';
import { avatarTrace } from '../utils/AvatarTrace';
import { themeModeStore } from '../common/appearance/ThemeModeStore';
import { nextThemeModePref, themeModeLabel } from '../common/appearance/ThemeMode';
// 页面边距 / 卡片圆角 / 行内距统一读设置页的同一份真值源，两页同宽同规格
import { SettingsLayout } from '../common/appearance/SettingsLayout';

const HEADER_BUTTON: number = 44;
const HEADER_ICON: number = 22;
/** 两颗按钮之间、以及按钮与标题之间的最小间距（Blank 撑开剩余空间） */

const STAT_MIN_HEIGHT: number = 48;

/** 内容入口描述。`kind` 保持原路由参数，不随展示文案变化。 */
interface ProfileRow {
  /**
   * 官方 Symbol 图标。第一批已 Symbol 化的行（收藏 / 回复）走这里；
   * 其余仍是内联 SVG，通过 `icon` 渲染。两者同尺寸同色，视觉上不分层。
   */
  symbol?: Resource;
  /** 内联 SVG 图标：尚未 Symbol 化的行用它 */
  icon?: Resource;
  label: string;

  kind: string;
}

@ComponentV2
export struct ProfileView {
  /** 四个内容入口按设计稿顺序排列。SVG 保留为未覆盖的 Symbol 回退。 */
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
  /** 主标题按昵称、用户名、兜底文案依次选择。 */
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

  /**
   * "我的"页头像**只来自服务端资料**。
   *
   * 编辑页的本机候选预览不经过这里：待审核/传播延迟期间，本页继续显示服务端当前生效的头像，
   * 不用本地候选图冒充已生效（见 KNOWN_ISSUES #18 的语义修正）。
   */
  private avatarUrl(): string {
    return portraitUrl(authSession.snapshot.portrait, authSession.avatarRevision);
  }

  /** 账号标识行显示用户 ID 与吧龄；缺失字段不拼接占位信息。 */
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

  /** 未登录/失效时的一句话提示；已登录时返回空串（不占用渲染） */
  private noteLine(snapshot: AuthSnapshot): string {
    if (snapshot.isLoggedIn()) {
      return '';
    }
    if (snapshot.expiredReason.length > 0) {
      return snapshot.expiredReason;
    }
    return '登录后可点赞并使用写操作';
  }

  /** 关注/粉丝的显示值：没取到显示 `—`，取到了才显示数字 */
  private countText(snapshot: AuthSnapshot, value: number): string {
    return snapshot.socialLoaded ? formatCount(value) : '—';
  }

  private levelText(snapshot: AuthSnapshot): string {
    if (!snapshot.socialLoaded) {
      return '—';
    }
    return `Lv.${snapshot.levelId}`;
  }

  // 在子节点的更新回调内读取 @Trace，不能把首帧格式化字符串传进 Builder 后固定下来。
  private statValue(label: string): string {
    const snapshot: AuthSnapshot = authSession.snapshot;
    if (label === '等级') { return this.levelText(snapshot); }
    const value: number = label === '关注' ? snapshot.concernNum :
      (label === '粉丝' ? snapshot.fansNum : snapshot.likeForumNum);
    return this.countText(snapshot, value);
  }

  /**
   * 外观切换按钮的图标：当前档位对应的原生图标（太阳 / 月亮 / 左右半实心圆）。
   *
   * 直接读 `themeModeStore.pref` 与 `isDark`（`@Trace`）：档位或系统深浅一变，会重跑这段
   * Builder，图标自动换成新档位那一态 —— 与 `GlassCircleButton` 订阅材质档位同一机制。
   */
  @Builder
  appearanceIcon() {
    ThemeModeIcon({ mode: themeModeStore.pref, isDark: themeModeStore.isDark, iconSize: HEADER_ICON })
  }

  private cycleThemeMode(): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    themeModeStore.setMode(nextThemeModePref(themeModeStore.pref), context);
  }

  @Builder
  HeaderActions() {
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
            onTap: (): void => { router.pushUrl({ url: 'pages/Settings' }); }
          })
            .accessibilityText('设置')
  }

  build() {
    Scroll() {
      Column() {
        RootPageHeader({ title: '我的', gutter: 0,
          actions: (): void => { this.HeaderActions(); } })

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
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.accountIdLine(authSession.snapshot).length > 0) {
              Text(this.accountIdLine(authSession.snapshot))
                .fontSize(SettingsLayout.SUB_SIZE)
                .fontColor(AppTheme.TEXT_SUB)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            if (this.noteLine(authSession.snapshot).length > 0) {
              Text(this.noteLine(authSession.snapshot))
                .fontSize(SettingsLayout.SUB_SIZE)
                .fontColor(AppTheme.TEXT_SUB)
                .maxLines(2)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (!authSession.snapshot.isLoggedIn()) {
            Button('登录')
              .fontSize(SettingsLayout.VALUE_SIZE)
              .constraintSize({ minWidth: 64, minHeight: 48 })
              .borderRadius(AppTheme.PILL_RADIUS)
              .backgroundColor(AppTheme.ACCENT)
              .fontColor(AppTheme.ON_ACCENT)
              .onClick(() => { router.pushUrl({ url: 'pages/Login' }); })
          } else {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(SettingsLayout.CHEVRON_SIZE).maxFontScale(1)
              .fontColor([AppTheme.CHEVRON_TINT])
              .margin({ right: SettingsLayout.CHEVRON_INSET })
          }
        }
        .width('100%')
        .constraintSize({ minHeight: 84 })
        .padding({ top: 6, bottom: 6 })
        .borderRadius(SettingsLayout.CARD_RADIUS)
        .margin({ top: 16 })
        .onClick(() => {
          if (authSession.snapshot.isLoggedIn()) {
            NavigationService.openUser({ uid: authSession.snapshot.uid,
              portrait: authSession.snapshot.portrait, name: this.accountTitle(authSession.snapshot) });
          }
        })

        if (authSession.snapshot.isLoggedIn()) {
          Row() {
            this.StatCell('关注')
            Divider().vertical(true).height(30).color(AppTheme.DIVIDER)
            this.StatCell('粉丝')
            Divider().vertical(true).height(30).color(AppTheme.DIVIDER)
            this.StatCell('等级')
            Divider().vertical(true).height(30).color(AppTheme.DIVIDER)
            this.StatCell('关注吧')
          }
          .width('100%')
          .constraintSize({ minHeight: SettingsLayout.ROW_MIN_H })
          .padding({ left: 6, right: 6, top: 8, bottom: 8 })
          .borderRadius(SettingsLayout.CARD_RADIUS)
          .backgroundColor(visualThemeStore.isPaper ? AppTheme.GOLD_LIGHT : AppTheme.CARD)
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

        SettingsEntryRow({ label: '设置', icon: $r('sys.symbol.gearshape'), showDivider: false,
          onTap: (): void => { router.pushUrl({ url: 'pages/Settings' }); } })
          .backgroundColor(AppTheme.CARD).borderRadius(SettingsLayout.CARD_RADIUS)
          .clip(true)
          .margin({ top: SettingsLayout.ROW_GAP })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      // 当前 HdsNavigation 的 TabContent 从状态栏下沿起排；再加一次状态栏高度会留下双倍空白。
      // 左右边距用设置页的 PAGE_GUTTER（16vp）：两页卡片同宽。
      .padding({
        left: SettingsLayout.PAGE_GUTTER, right: SettingsLayout.PAGE_GUTTER,
        top: 0
      })
    }
    .scrollBar(BarState.Off).align(Alignment.Top)
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG)
    // 只记"我的页真的出现在屏幕上"：页面隐藏期间的状态发布不算用户已看到。
    .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, ratio: number): void => {
      if (isVisible && ratio > 0) { avatarTrace('page-visible', 0, 'page=mine'); }
    })
  }

  /** 四格数据中的缺失值仍用 `—`，避免把取数失败误报为零。 */
  @Builder
  StatCell(label: string) {
    Column({ space: 4 }) {
      Text(this.statValue(label))
        .fontSize(19)
        .fontWeight(FontWeight.Medium)
        .fontColor(visualThemeStore.isPaper ? AppTheme.GOLD : AppTheme.TEXT_MAIN)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(label)
        .fontSize(SettingsLayout.SUB_SIZE)
        .fontColor(AppTheme.TEXT_SUB)
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: STAT_MIN_HEIGHT })
    .justifyContent(FlexAlign.Center)
    .borderRadius(12)
    .accessibilityGroup(true)
    .accessibilityText(label + '，' + this.statValue(label))
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
    SettingsEntryRow({ label: row.label, icon: row.symbol, imageIcon: row.icon, showDivider: false,
      onTap: (): void => { NavigationService.openMyList({ kind: row.kind }); } })
      .backgroundColor(AppTheme.CARD).borderRadius(SettingsLayout.CARD_RADIUS)
      .clip(true)
  }
}
