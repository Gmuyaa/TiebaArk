/** 登录页：官方网页登录主路径与 Cookie / BDUSS 导入模式切换。 */

import { common } from '@kit.AbilityKit';
import { authSession } from '../auth/AuthSession';
import { LoginResult } from '../auth/AuthModel';
import {
  CredentialInputPreview, LoginGuideStep, cookieGuideSteps, inspectCredentialInput
} from '../auth/LoginHelper';
import { GlassBackButton } from '../components/GlassBackButton';
import { MotionEffect } from '../common/appearance/MotionConfig';
import { motionEdgeEffect } from '../common/appearance/MotionPolicy';
import { motionStore } from '../common/appearance/MotionStore';
import { SettingsLayout } from '../common/appearance/SettingsLayout';
import { AppTheme } from '../theme/Theme';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';

enum LoginMode {
  WEB = 0,
  COOKIE = 1
}

const CONTENT_MAX_WIDTH: number = 480;
const SEGMENT_HEIGHT: number = 46;
const PRIMARY_BUTTON_HEIGHT: number = 50;
const WEB_CAPABILITIES: string[] = ['短信验证', '账号密码', '邮箱登录'];

@Entry
@ComponentV2
struct LoginPage {
  @Local loginMode: LoginMode = LoginMode.WEB;
  @Local bdussInput: string = '';
  @Local reveal: boolean = false;
  @Local submitting: boolean = false;
  @Local errorText: string = '';
  @Local guideExpanded: boolean = false;
  @Local addingAccount: boolean = false;
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;

  private initialSessionRevision: number = 0;
  private autoClosing: boolean = false;
  private readonly guideSteps: LoginGuideStep[] = cookieGuideSteps();

  aboutToAppear(): void {
    this.initialSessionRevision = authSession.sessionRevision;
    this.addingAccount = authSession.isLoggedIn();
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    readStatusBarVp(context).then((vp: number) => {
      this.statusBarH = vp;
    }).catch(() => {});
  }

  onPageShow(): void {
    // 从百度网页登录成功返回时直接闭环退回原来源页，避免滞留在登录界面。
    if (!this.autoClosing && authSession.sessionRevision !== this.initialSessionRevision &&
      authSession.isLoggedIn()) {
      this.autoClosing = true;
      try {
        this.getUIContext().getRouter().back();
      } catch (_) {}
    }
  }

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    this.errorText = '';
    this.submitting = true;
    try {
      const result: LoginResult = await authSession.loginWithUserInput(this.bdussInput);
      if (result.ok) {
        this.bdussInput = '';
        this.autoClosing = true;
        const withStoken: boolean = authSession.session().stoken.length > 0;
        try {
          this.getUIContext().getPromptAction().showToast({
            message: withStoken
              ? '登录成功，全部功能已可用'
              : '登录成功，但未检测到 STOKEN，部分写操作可能受限',
            duration: withStoken ? 1800 : 3600
          });
        } catch (_) {}
        try {
          this.getUIContext().getRouter().back();
        } catch (_) {}
        return;
      }
      this.errorText = result.message;
    } finally {
      this.submitting = false;
    }
  }

  private openWebLogin(): void {
    try {
      void this.getUIContext().getRouter().pushUrl({ url: 'pages/WebLogin' });
    } catch (_) {}
  }

  private credentialPreview(): CredentialInputPreview {
    return inspectCredentialInput(this.bdussInput);
  }

  private canSubmitCookie(): boolean {
    return !this.submitting && this.bdussInput.trim().length > 0;
  }

  pageTransition() {
    if (!motionStore.isOn(MotionEffect.MOVE)) {
      PageTransitionEnter({ duration: 0, curve: Curve.Linear })
      PageTransitionExit({ duration: 0, curve: Curve.Linear })
    }
  }

  build() {
    Column() {
      this.TopBar()

      Scroll() {
        Column() {
          Column() {
            this.BrandHero()
            this.ModeSwitcher()
            if (this.loginMode === LoginMode.WEB) {
              this.WebLoginCard()
            } else {
              this.CookieLoginCard()
              this.CookieGuideCard()
            }
            this.SecurityFooter()
          }
          .width('100%')
          .constraintSize({ maxWidth: CONTENT_MAX_WIDTH })
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .padding({
          left: SettingsLayout.PAGE_GUTTER,
          right: SettingsLayout.PAGE_GUTTER,
          top: 8,
          bottom: SettingsLayout.PAGE_BOTTOM_GAP
        })
        .alignItems(HorizontalAlign.Center)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .edgeEffect(motionEdgeEffect())
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG)
  }

  @Builder
  TopBar() {
    Row() {
      GlassBackButton({
        onTap: (): void => {
          try {
            this.getUIContext().getRouter().back();
          } catch (_) {}
        }
      })
    }
    .width('100%')
    .padding({
      left: SettingsLayout.PAGE_GUTTER,
      right: SettingsLayout.PAGE_GUTTER,
      top: this.statusBarH + 8,
      bottom: 4
    })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  BrandHero() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Image($r('app.media.app_icon'))
          .width(58)
          .height(58)
          .borderRadius(15)
          .objectFit(ImageFit.Cover)
          .accessibilityLevel('no')
      }
      .width(74)
      .height(74)
      .borderRadius(22)
      .backgroundColor(AppTheme.ACCENT_LIGHT)

      Text(this.addingAccount ? '添加贴吧账号' : '登录贴吧Ark')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.TEXT_MAIN)
        .textAlign(TextAlign.Center)
        .margin({ top: 6 })

      Text(this.addingAccount
        ? '新账号将与现有账号独立共存，随时快速切换'
        : '连接你的百度贴吧账号，开启互动与多端同步')
        .fontSize(13.5)
        .fontColor(AppTheme.TEXT_SUB)
        .textAlign(TextAlign.Center)
        .lineHeight(20)
    }
    .width('100%')
    .padding({ top: 10, bottom: 4, left: 12, right: 12 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  ModeTab(mode: LoginMode, symbol: Resource, label: string, id: string) {
    Row({ space: 6 }) {
      SymbolGlyph(symbol)
        .fontSize(16)
        .maxFontScale(1)
        .fontColor([this.loginMode === mode ? AppTheme.ACCENT : AppTheme.TEXT_SUB])
      Text(label)
        .fontSize(14)
        .fontWeight(this.loginMode === mode ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.loginMode === mode ? AppTheme.TEXT_MAIN : AppTheme.TEXT_SUB)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height('100%')
    .borderRadius((SEGMENT_HEIGHT - 8) / 2)
    .backgroundColor(this.loginMode === mode ? AppTheme.CARD : Color.Transparent)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 10, right: 10 })
    .accessibilityGroup(true)
    .accessibilityText(label)
    .accessibilitySelected(this.loginMode === mode)
    .id(id)
    .onClick((): void => {
      if (this.submitting) {
        return;
      }
      this.loginMode = mode;
    })
  }

  @Builder
  ModeSwitcher() {
    Row({ space: 4 }) {
      this.ModeTab(LoginMode.WEB, $r('sys.symbol.person_shield'), '官方网页登录', 'login-mode-web')
      this.ModeTab(LoginMode.COOKIE, $r('sys.symbol.key_shield'), 'Cookie 导入', 'login-mode-cookie')
    }
    .width('100%')
    .height(SEGMENT_HEIGHT)
    .padding(4)
    .borderRadius(SEGMENT_HEIGHT / 2)
    .backgroundColor(AppTheme.SURFACE_MUTED)
    .margin({ top: 22 })
  }

  @Builder
  TrustRow(symbol: Resource, badgeBg: Resource, badgeFg: Resource, title: string, desc: string) {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(symbol)
          .fontSize(17)
          .maxFontScale(1)
          .fontColor([badgeFg])
      }
      .width(34)
      .height(34)
      .borderRadius(10)
      .backgroundColor(badgeBg)

      Column({ space: 2 }) {
        Text(title)
          .fontSize(14.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_MAIN)
        Text(desc)
          .fontSize(12.5)
          .fontColor(AppTheme.TEXT_SUB)
          .lineHeight(18)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  WebLoginCard() {
    Column({ space: 18 }) {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Text('安全快捷登录')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.TEXT_MAIN)
          Text('推荐')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.ACCENT_DARK)
            .backgroundColor(AppTheme.ACCENT_LIGHT)
            .borderRadius(6)
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(WEB_CAPABILITIES, (cap: string) => {
            Text(cap)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.MSG_BADGE_BLUE_FG)
              .backgroundColor(AppTheme.MSG_BADGE_BLUE_BG)
              .borderRadius(8)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .margin({ right: 8, bottom: 4 })
          }, (cap: string): string => cap)
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Divider()
        .color(AppTheme.DIVIDER)
        .strokeWidth(0.5)

      Column({ space: 14 }) {
        this.TrustRow(
          $r('sys.symbol.checkmark_shield'),
          AppTheme.MSG_BADGE_BLUE_BG,
          AppTheme.MSG_BADGE_BLUE_FG,
          '百度官方页面直连',
          '账号密码与验证码仅提交给百度官方'
        )
        this.TrustRow(
          $r('sys.symbol.person_badge_checkmark'),
          AppTheme.MSG_BADGE_GREEN_BG,
          AppTheme.MSG_BADGE_GREEN_FG,
          '自动同步完整凭据',
          '自动获取 BDUSS 与 STOKEN，支持互动与发帖'
        )
        this.TrustRow(
          $r('sys.symbol.lock_shield'),
          AppTheme.MSG_BADGE_ORANGE_BG,
          AppTheme.MSG_BADGE_ORANGE_FG,
          '无痕隔离与自动清理',
          '独立无痕环境登录，完成后自动清除痕迹'
        )
      }
      .width('100%')

      Button({ type: ButtonType.Capsule, stateEffect: true }) {
        Row({ space: 6 }) {
          Text('前往百度官方登录')
            .fontSize(15.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.ON_ACCENT)
          SymbolGlyph($r('sys.symbol.arrow_right'))
            .fontSize(16)
            .maxFontScale(1)
            .fontColor([AppTheme.ON_ACCENT])
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height(PRIMARY_BUTTON_HEIGHT)
      .backgroundColor(AppTheme.ACCENT)
      .margin({ top: 4 })
      .id('login-open-web-btn')
      .onClick((): void => {
        this.openWebLogin();
      })
    }
    .width('100%')
    .padding(20)
    .backgroundColor(AppTheme.CARD)
    .borderRadius(SettingsLayout.CARD_RADIUS)
    .margin({ top: 16 })
  }

  @Builder
  StatusChip(ready: boolean, label: string) {
    Row({ space: 4 }) {
      SymbolGlyph(ready ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.exclamationmark_circle'))
        .fontSize(13)
        .maxFontScale(1)
        .fontColor([ready ? AppTheme.MSG_BADGE_GREEN_FG : AppTheme.MSG_BADGE_ORANGE_FG])
      Text(label)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(ready ? AppTheme.MSG_BADGE_GREEN_FG : AppTheme.MSG_BADGE_ORANGE_FG)
    }
    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
    .borderRadius(8)
    .backgroundColor(ready ? AppTheme.MSG_BADGE_GREEN_BG : AppTheme.MSG_BADGE_ORANGE_BG)
    .margin({ right: 8, bottom: 4 })
  }

  @Builder
  CookieLoginCard() {
    Column({ space: 14 }) {
      Row({ space: 6 }) {
        Text('BDUSS 或整条 Cookie')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_MAIN)
          .layoutWeight(1)

        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph(this.reveal ? $r('sys.symbol.eye') : $r('sys.symbol.eye_slash'))
            .fontSize(18)
            .maxFontScale(1)
            .fontColor([AppTheme.ICON])
        }
        .width(34)
        .height(34)
        .borderRadius(17)
        .accessibilityGroup(true)
        .accessibilityText(this.reveal ? '隐藏输入内容' : '显示输入内容')
        .onClick((): void => {
          this.reveal = !this.reveal;
        })

        if (this.bdussInput.length > 0 && !this.submitting) {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
              .fontSize(18)
              .maxFontScale(1)
              .fontColor([AppTheme.TEXT_MUTED])
          }
          .width(34)
          .height(34)
          .borderRadius(17)
          .accessibilityGroup(true)
          .accessibilityText('清空输入')
          .onClick((): void => {
            this.bdussInput = '';
            this.errorText = '';
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      TextInput({ text: this.bdussInput, placeholder: '粘贴 BDUSS 的值，或整条 Cookie' })
        .type(this.reveal ? InputType.Normal : InputType.Password)
        .showPasswordIcon(false)
        .fontSize(14)
        .fontColor(AppTheme.TEXT_MAIN)
        .placeholderColor(AppTheme.TEXT_MUTED)
        .caretColor(AppTheme.ACCENT)
        .selectedBackgroundColor(AppTheme.SELECTION_BACKGROUND)
        .width('100%')
        .height(50)
        .padding({ left: 14, right: 14 })
        .backgroundColor(AppTheme.SURFACE_MUTED)
        .borderRadius(14)
        .enabled(!this.submitting)
        .id('login-cookie-input')
        .onChange((value: string) => {
          this.bdussInput = value;
          if (this.errorText.length > 0) {
            this.errorText = '';
          }
        })
        .onSubmit((): void => {
          if (this.canSubmitCookie()) {
            void this.submit();
          }
        })

      if (this.credentialPreview().hasInput) {
        Flex({ wrap: FlexWrap.Wrap }) {
          this.StatusChip(
            this.credentialPreview().bdussReady,
            this.credentialPreview().bdussReady ? 'BDUSS 格式正常' : '未识别到有效 BDUSS'
          )
          this.StatusChip(
            this.credentialPreview().stokenReady,
            this.credentialPreview().stokenReady ? '含 STOKEN' : '未含 STOKEN（部分写操作受限）'
          )
        }
        .width('100%')
      }

      if (this.errorText.length > 0) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(15)
            .maxFontScale(1)
            .fontColor([AppTheme.DANGER_TEXT])
          Text(this.errorText)
            .fontSize(12.5)
            .fontColor(AppTheme.DANGER_TEXT)
            .lineHeight(18)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .borderRadius(12)
        .backgroundColor(AppTheme.MSG_BADGE_RED_BG)
        .alignItems(VerticalAlign.Top)
      }

      Button({ type: ButtonType.Capsule, stateEffect: true }) {
        Row({ space: 8 }) {
          if (this.submitting) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(AppTheme.ON_ACCENT)
          }
          Text(this.submitting ? '正在校验凭据…' : '验证并登录')
            .fontSize(15.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.canSubmitCookie() || this.submitting ? AppTheme.ON_ACCENT : AppTheme.TEXT_MUTED)
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height(PRIMARY_BUTTON_HEIGHT)
      .backgroundColor(this.canSubmitCookie() || this.submitting ? AppTheme.ACCENT : AppTheme.SURFACE_MUTED)
      .opacity(this.submitting ? 0.85 : 1)
      .enabled(this.canSubmitCookie())
      .margin({ top: 2 })
      .id('login-cookie-submit-btn')
      .onClick((): void => {
        void this.submit();
      })
    }
    .width('100%')
    .padding(20)
    .backgroundColor(AppTheme.CARD)
    .borderRadius(SettingsLayout.CARD_RADIUS)
    .margin({ top: 16 })
  }

  @Builder
  CookieGuideCard() {
    Column() {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.questionmark_circle'))
          .fontSize(18)
          .maxFontScale(1)
          .fontColor([AppTheme.ACCENT])
        Text('如何从浏览器获取 Cookie？')
          .fontSize(14.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_MAIN)
          .layoutWeight(1)
        SymbolGlyph(this.guideExpanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(15)
          .maxFontScale(1)
          .fontColor([AppTheme.CHEVRON_TINT])
      }
      .width('100%')
      .constraintSize({ minHeight: 54 })
      .padding({ left: 18, right: 18, top: 14, bottom: 14 })
      .alignItems(VerticalAlign.Center)
      .accessibilityGroup(true)
      .accessibilityText(this.guideExpanded ? '收起获取 Cookie 指引' : '展开获取 Cookie 指引')
      .id('login-guide-toggle')
      .onClick((): void => {
        this.guideExpanded = !this.guideExpanded;
      })

      if (this.guideExpanded) {
        Divider()
          .color(AppTheme.DIVIDER)
          .strokeWidth(0.5)
          .margin({ left: 18, right: 18 })

        Column({ space: 12 }) {
          ForEach(this.guideSteps, (step: LoginGuideStep) => {
            Row({ space: 10 }) {
              Text(step.stepNo)
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppTheme.MSG_BADGE_BLUE_FG)
                .textAlign(TextAlign.Center)
                .width(24)
                .height(24)
                .borderRadius(7)
                .backgroundColor(AppTheme.MSG_BADGE_BLUE_BG)
              Column({ space: 2 }) {
                Text(step.title)
                  .fontSize(13.5)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(AppTheme.TEXT_MAIN)
                Text(step.detail)
                  .fontSize(12.5)
                  .fontColor(AppTheme.NOTE_TEXT)
                  .lineHeight(18)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }, (step: LoginGuideStep): string => step.stepNo)

          Text('STOKEN 仅在百度 passport 登录时下发，无法由 BDUSS 单独换取；缺少 STOKEN 仍可登录，但部分写操作会不生效。')
            .fontSize(12)
            .fontColor(AppTheme.TEXT_MUTED)
            .lineHeight(18)
            .width('100%')
            .margin({ top: 2 })
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 14, bottom: 18 })
      }
    }
    .width('100%')
    .backgroundColor(AppTheme.CARD)
    .borderRadius(SettingsLayout.CARD_RADIUS)
    .margin({ top: SettingsLayout.GROUP_GAP })
  }

  @Builder
  SecurityFooter() {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.lock_shield'))
        .fontSize(13)
        .maxFontScale(1)
        .fontColor([AppTheme.TEXT_MUTED])
      Text('凭据仅加密存于本机系统安全存储，不经任何第三方')
        .fontSize(12)
        .fontColor(AppTheme.TEXT_MUTED)
        .lineHeight(17)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .margin({ top: 22 })
    .padding({ left: 12, right: 12 })
  }
}
