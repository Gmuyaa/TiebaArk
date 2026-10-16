

import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { authSession } from '../auth/AuthSession';
import { LoginResult } from '../auth/AuthModel';
import { AppTheme } from '../theme/Theme';
import { GlassBackButton } from '../components/GlassBackButton';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';

@Entry
@ComponentV2
struct LoginPage {

  @Local bdussInput: string = '';

  @Local reveal: boolean = false;

  @Local submitting: boolean = false;

  @Local errorText: string = '';

  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;

  aboutToAppear(): void {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    readStatusBarVp(context).then((vp: number) => {
      this.statusBarH = vp;
    }).catch(() => {

    });
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

        const withStoken: boolean = authSession.session().stoken.length > 0;
        promptAction.showToast({
          message: withStoken
            ? '登录成功，写操作已可用（含 STOKEN）'
            : '登录成功，但没解析到 STOKEN —— 请把 Cookie 里 STOKEN=… 那一项也一起复制',
          duration: withStoken ? 1800 : 4000
        });
        router.back();
        return;
      }
      this.errorText = result.message;
    } finally {
      this.submitting = false;
    }
  }

  build() {
    Column() {
      this.TitleBar()

      Scroll() {
        Column({ space: 14 }) {
          this.Intro()

          Column({ space: 8 }) {
            Text('BDUSS 或整条 Cookie')
              .fontSize(13)
              .fontColor(AppTheme.TEXT_SUB)
              .width('100%')

            Row({ space: 8 }) {
              TextInput({ text: this.bdussInput, placeholder: '粘贴 BDUSS 的值，或整条 Cookie' })
                .type(this.reveal ? InputType.Normal : InputType.Password)
                .fontSize(14)
                .height(46)
                .layoutWeight(1)
                .backgroundColor(AppTheme.SURFACE_MUTED)
                .borderRadius(10)
                .enabled(!this.submitting)
                .onChange((value: string) => {
                  this.bdussInput = value;

                  if (this.errorText.length > 0) {
                    this.errorText = '';
                  }
                })

              Text(this.reveal ? '隐藏' : '显示')
                .fontSize(13)
                .fontColor(AppTheme.ACCENT_DARK)
                .width(48)
                .height(46)
                .textAlign(TextAlign.Center)
                .onClick(() => {
                  this.reveal = !this.reveal;
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            if (this.errorText.length > 0) {
              Text(this.errorText)
                .fontSize(12)
                .fontColor(AppTheme.ACCENT_DARK)
                .width('100%')
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Button(this.submitting ? '正在校验…' : '登录')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .width('100%')
            .height(46)
            .borderRadius(AppTheme.PILL_RADIUS)
            .backgroundColor(this.submitting ? AppTheme.TEXT_MUTED : AppTheme.ACCENT)
            .fontColor(Color.White)
            .enabled(!this.submitting && this.bdussInput.length > 0)
            .onClick(() => {
              this.submit();
            })

          Row({ space: 10 }) {
            Divider().layoutWeight(1).color(AppTheme.SURFACE_MUTED)
            Text('或')
              .fontSize(12)
              .fontColor(AppTheme.TEXT_MUTED)
            Divider().layoutWeight(1).color(AppTheme.SURFACE_MUTED)
          }
          .width('100%')
          .margin({ top: 6, bottom: 6 })

          Button('百度网页登录')
            .fontSize(15)
            .width('100%')
            .height(46)
            .borderRadius(AppTheme.PILL_RADIUS)
            .backgroundColor(AppTheme.SURFACE_MUTED)
            .fontColor(AppTheme.ACCENT_DARK)
            .onClick(() => {
              router.pushUrl({ url: 'pages/WebLogin' });
            })

          this.HelpCard()
        }
        .width('100%')
        .padding({ left: AppTheme.PAGE_GUTTER, right: AppTheme.PAGE_GUTTER, top: 16, bottom: 32 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG)
  }

  @Builder
  TitleBar() {
    Row({ space: 10 }) {

      GlassBackButton({
        onTap: (): void => {
          router.back();
        }
      })

      Text('登录')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_MAIN)
        .layoutWeight(1)
    }
    .width('100%')
    .height(56 + this.statusBarH)
    .padding({ left: 4, right: 16, top: this.statusBarH })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(AppTheme.CARD)
  }

  @Builder
  Intro() {
    Column({ space: 6 }) {
      Text('用 BDUSS 登录')
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.TEXT_MAIN)
      Text('登录后可点赞。凭据只保存在本机系统级安全存储里，不会上传到任何第三方。')
        .fontSize(13)
        .fontColor(AppTheme.TEXT_SUB)
        .lineHeight(19)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  HelpCard() {
    Column({ space: 8 }) {
      Text('怎么拿到 BDUSS / STOKEN')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_MAIN)
      Text('1. 在浏览器登录 tieba.baidu.com\n'
        + '2. 开发者工具 → Application/存储 → Cookies\n'
        + '3. **必须包含 STOKEN 那一项**（它的域是 `.baidu.com`，\n'
        + '   不在 tieba.baidu.com 分组里时切到 `.baidu.com` 分组找）\n'
        + '4. 复制 BDUSS 与 STOKEN 两项（或整条 Cookie）一起粘进来')
        .fontSize(12)
        .fontColor(AppTheme.TEXT_SUB)
        .lineHeight(19)
      Text('为什么要整条 Cookie：STOKEN 只在登录那一刻由 passport 域下发，'
        + '光有 BDUSS 换不出来（本项目已在设备上实测确认）。'
        + '只粘 BDUSS 也能登录成功，**但没有 STOKEN**，部分写操作会不生效。')
        .fontSize(12)
        .fontColor(AppTheme.TEXT_MUTED)
        .lineHeight(18)
    }
    .width('100%')
    .padding(14)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(AppTheme.CARD)
    .borderRadius(AppTheme.CARD_RADIUS)
  }
}
