

import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { authSession } from '../auth/AuthSession';
import { AuthStore } from '../auth/AuthStore';
import { CredentialBundle, extractBdussFromCookie, extractStokenFromCookie } from '../auth/AuthModel';
import { sha256Hex } from '../net/RequestOptionsTrace';
import { AppTheme } from '../theme/Theme';
import { GlassBackButton } from '../components/GlassBackButton';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';

const PAGE_TAG: string = 'WebLogin';
const POLL_INTERVAL_MS: number = 1500;
const POLL_MAX_MS: number = 300000;

const LOGIN_URL: string =
  'https://wappass.baidu.com/passport?login&u=https%3A%2F%2Ftieba.baidu.com%2Findex%2Ftbwise%2Fmine';

const MINE_URL: string = 'https://tieba.baidu.com/index/tbwise/mine';

function credPrint(value: string): string {
  if (value.length === 0) {
    return '(empty)';
  }
  return `len=${value.length} sha256=${sha256Hex(value).slice(0, 8)}`;
}

@Entry
@ComponentV2
struct WebLoginPage {
  controller: webview.WebviewController = new webview.WebviewController();

  private pollTimer: number = -1;
  private pollStartedAt: number = 0;
  private pollStopped: boolean = false;
  private loggingIn: boolean = false;

  @Local statusText: string = '正在打开百度官方页面…';
  @Local bdussSeen: boolean = false;
  @Local stokenSeen: boolean = false;

  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;

  aboutToAppear(): void {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    readStatusBarVp(context).then((vp: number) => {
      this.statusBarH = vp;
    }).catch(() => {

    });

    AuthStore.load().then((old: CredentialBundle) => {
      hilog.info(0x0000, PAGE_TAG, 'old credentials: bduss[%{public}s] stoken[%{public}s]',
        credPrint(old.bduss), credPrint(old.stoken));
    }).catch(() => {
      hilog.info(0x0000, PAGE_TAG, 'old credentials: none (load failed / not logged in)');
    });
    this.pollStartedAt = Date.now();
    this.pollCookies();
  }

  aboutToDisappear(): void {
    this.pollStopped = true;
    if (this.pollTimer >= 0) {
      clearTimeout(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private async pollCookies(): Promise<void> {
    if (this.pollStopped || this.loggingIn) {
      return;
    }
    let proceed: boolean = true;
    try {

      const mineCookie: string = await webview.WebCookieManager.fetchCookie(MINE_URL);
      const baiduCookie: string = await webview.WebCookieManager.fetchCookie('https://www.baidu.com/');
      const cookieText: string = `${mineCookie}; ${baiduCookie}`;
      const bduss: string = extractBdussFromCookie(cookieText);
      const stoken: string = extractStokenFromCookie(cookieText);
      this.bdussSeen = bduss.length > 0;
      this.stokenSeen = stoken.length > 0;
      if (this.bdussSeen && this.stokenSeen) {

        hilog.info(0x0000, PAGE_TAG, 'web_login bduss=present stoken=present');
        this.statusText = '已获取登录凭据，正在校验…';
        this.finishLogin(bduss, stoken);
        proceed = false;
      } else {
        this.statusText = this.bdussSeen
          ? '登录状态不完整：已取到 BDUSS，等待 STOKEN（继续在网页里完成登录）'
          : '等待登录…（在上方网页中登录百度账号）';
      }
    } catch (err) {
      const e: Error = err as Error;
      hilog.warn(0x0000, PAGE_TAG, 'cookie fetch failed: %{public}s', e.message);
      this.statusText = '读取登录状态失败，重试中…';
    }
    if (proceed) {
      this.scheduleNext();
    }
  }

  private scheduleNext(): void {
    if (this.pollStopped) {
      return;
    }
    if (Date.now() - this.pollStartedAt > POLL_MAX_MS) {
      this.statusText = '等待超时。可返回重试，或继续用手动粘贴 Cookie 登录。';
      hilog.warn(0x0000, PAGE_TAG, 'poll timeout');
      return;
    }
    this.pollTimer = setTimeout(() => this.pollCookies(), POLL_INTERVAL_MS);
  }

  private finishLogin(bduss: string, stoken: string): void {
    if (this.loggingIn) {
      return;
    }
    this.loggingIn = true;
    authSession.loginFromWebCookies(bduss, stoken)
      .then((result) => {
        this.loggingIn = false;
        if (result.ok) {
          hilog.info(0x0000, PAGE_TAG, 'web login ok: authSource=web_login');
          promptAction.showToast({ message: '网页登录成功', duration: 1800 });
          this.pollStopped = true;
          router.back();
          return;
        }

        this.statusText = `校验未通过：${result.message}（继续等待网页登录态）`;
        this.loggingIn = false;
        this.scheduleNext();
      })
      .catch((err: object) => {
        const e: Error = err as Error;
        this.loggingIn = false;
        hilog.warn(0x0000, PAGE_TAG, 'login threw: %{public}s', e.message);
        this.statusText = '登录流程异常，重试中…';
        this.scheduleNext();
      });
  }

  build() {
    Column() {
      Row({ space: 10 }) {

        GlassBackButton({
          onTap: (): void => {
            router.back();
          }
        })

        Text('百度网页登录')
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

      Text(this.statusText)
        .fontSize(12)
        .fontColor(AppTheme.TEXT_SUB)
        .width('100%')
        .padding({ left: AppTheme.PAGE_GUTTER, right: AppTheme.PAGE_GUTTER, top: 8, bottom: 8 })
        .backgroundColor(AppTheme.SURFACE_MUTED)

      Web({ src: LOGIN_URL, controller: this.controller })
        .layoutWeight(1)
        .domStorageAccess(true)
        .javaScriptAccess(true)
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG)
  }
}
