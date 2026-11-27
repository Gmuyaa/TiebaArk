/** 百度网页登录。轮询凭据就绪状态，通过统一认证入口保存；页面离开时停止轮询。 */

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
import { GlassCircleButton } from '../components/GlassCircleButton';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { MotionEffect } from '../common/appearance/MotionConfig';
import { motionStore } from '../common/appearance/MotionStore';
import { UiLayout } from '../common/appearance/UiLayout';

const PAGE_TAG: string = 'WebLogin';
const POLL_INTERVAL_MS: number = 1500;
const POLL_MAX_MS: number = 300000;

/** 官方 wap 登录页：登录后跳回贴吧「我的」页，Cookie 落 .baidu.com 域 */
const LOGIN_URL: string =
  'https://wappass.baidu.com/passport?login&u=https%3A%2F%2Ftieba.baidu.com%2Findex%2Ftbwise%2Fmine';
/** 登录完成的落点页；Cookie 从这里读最稳 */
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
  /** 轮询 CookieStore 的循环句柄；页面销毁必须停 */
  private pollTimer: number = -1;
  private pollStartedAt: number = 0;
  private pollStopped: boolean = false;
  private loggingIn: boolean = false;

  /** 状态行文案（不出现任何凭据内容） */
  @Local statusText: string = '连接百度官方登录页…';
  @Local bdussSeen: boolean = false;
  @Local stokenSeen: boolean = false;
  /** 清理完无痕 Cookie/存储后再挂载 Web，避免读到上一个账号的残留态。 */
  @Local webReady: boolean = false;
  @Local loadProgress: number = 0;
  @Local pageLoading: boolean = true;
  @Local firstPageLoaded: boolean = false;
  @Local canGoBack: boolean = false;
  @Local loadError: boolean = false;
  @Local pollTimedOut: boolean = false;

  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;

  private clearIncognitoWebState(): void {
    try { webview.WebCookieManager.clearAllCookiesSync(true); } catch (_) {}
    try { webview.WebStorage.deleteAllData(true); } catch (_) {}
  }

  aboutToAppear(): void {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    readStatusBarVp(context).then((vp: number) => {
      this.statusBarH = vp;
    }).catch(() => {});

    this.clearIncognitoWebState();
    this.webReady = true;

    AuthStore.load().then((old: CredentialBundle) => {
      hilog.info(0x0000, PAGE_TAG, 'old credentials: bduss[%{public}s] stoken[%{public}s]',
        credPrint(old.bduss), credPrint(old.stoken));
    }).catch(() => {
      hilog.info(0x0000, PAGE_TAG, 'old credentials: none (load failed / not logged in)');
    });
    this.pollStartedAt = Date.now();
    this.scheduleNext();
  }

  aboutToDisappear(): void {
    this.pollStopped = true;
    if (this.pollTimer >= 0) {
      clearTimeout(this.pollTimer);
      this.pollTimer = -1;
    }
    this.clearIncognitoWebState();
  }

  onBackPress(): boolean {
    try {
      if (this.controller.accessBackward()) {
        this.controller.backward();
        this.syncBackState();
        return true;
      }
    } catch (_) {}
    return false;
  }

  private syncBackState(): void {
    try {
      this.canGoBack = this.controller.accessBackward();
    } catch (_) {
      this.canGoBack = false;
    }
  }

  private retrySession(): void {
    this.loadError = false;
    this.pageLoading = true;
    this.loadProgress = 10;
    if (this.pollTimedOut) {
      this.pollTimedOut = false;
      this.pollStartedAt = Date.now();
      this.statusText = '正在重新连接百度官方页面…';
      if (this.pollTimer >= 0) {
        clearTimeout(this.pollTimer);
        this.pollTimer = -1;
      }
      if (!this.pollStopped) {
        this.scheduleNext();
      }
    }
    try {
      this.controller.refresh();
    } catch (_) {
      try { this.controller.loadUrl(LOGIN_URL); } catch (_) {}
    }
  }

  private async pollCookies(): Promise<void> {
    if (this.pollStopped || this.loggingIn) {
      return;
    }
    let proceed: boolean = true;
    try {
      // 无痕模式隔离持久 Cookie/localStorage，轮询也从无痕 CookieStore 读取。
      const mineCookie: string = await webview.WebCookieManager.fetchCookie(MINE_URL, true);
      if (this.pollStopped) { return; }
      const baiduCookie: string = await webview.WebCookieManager.fetchCookie('https://www.baidu.com/', true);
      if (this.pollStopped) { return; }
      const cookieText: string = `${mineCookie}; ${baiduCookie}`;
      const bduss: string = extractBdussFromCookie(cookieText);
      const stoken: string = extractStokenFromCookie(cookieText);
      this.bdussSeen = bduss.length > 0;
      this.stokenSeen = stoken.length > 0;
      if (this.bdussSeen && this.stokenSeen) {
        hilog.info(0x0000, PAGE_TAG, 'web_login bduss=present stoken=present');
        this.statusText = '正在校验凭据…';
        this.finishLogin(bduss, stoken);
        proceed = false;
      } else {
        this.statusText = this.bdussSeen ? '等待 STOKEN…' : '';
      }
    } catch (err) {
      if (this.pollStopped) { return; }
      const e: Error = err as Error;
      hilog.warn(0x0000, PAGE_TAG, 'cookie fetch failed: %{public}s', e.message);
      this.statusText = '读取状态失败，重试中…';
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
      this.pollTimedOut = true;
      this.statusText = '等待超时，点右上角刷新重试';
      hilog.warn(0x0000, PAGE_TAG, 'poll timeout');
      return;
    }
    this.pollTimer = setTimeout(() => this.pollCookies(), POLL_INTERVAL_MS);
  }

  private finishLogin(bduss: string, stoken: string): void {
    if (this.loggingIn || this.pollStopped) {
      return;
    }
    this.loggingIn = true;
    authSession.loginFromWebCookies(bduss, stoken, (): boolean => !this.pollStopped)
      .then((result) => {
        if (this.pollStopped) { return; }
        this.loggingIn = false;
        if (result.ok) {
          hilog.info(0x0000, PAGE_TAG, 'web login ok: authSource=web_login');
          this.clearIncognitoWebState();
          try {
            this.getUIContext().getPromptAction().showToast({ message: '网页登录成功', duration: 1800 });
          } catch (_) {}
          this.pollStopped = true;
          try {
            this.getUIContext().getRouter().back();
          } catch (_) {}
          return;
        }
        // 校验失败如实展示（tbs 不可得 / 凭据被拒），继续轮询让用户重试
        this.statusText = `校验未通过：${result.message}（继续等待网页登录态）`;
        this.loggingIn = false;
        this.scheduleNext();
      })
      .catch((err: object) => {
        if (this.pollStopped) { return; }
        const e: Error = err as Error;
        this.loggingIn = false;
        hilog.warn(0x0000, PAGE_TAG, 'login threw: %{public}s', e.message);
        this.statusText = '登录流程异常，重试中…';
        this.scheduleNext();
      });
  }

  pageTransition() {
    if (!motionStore.isOn(MotionEffect.MOVE)) {
      PageTransitionEnter({ duration: 0, curve: Curve.Linear })
      PageTransitionExit({ duration: 0, curve: Curve.Linear })
    }
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        GlassCircleButton({
          symbol: $r('sys.symbol.xmark'),
          iconWeight: FontWeight.Regular,
          accessibilityLabel: '关闭网页登录',
          onTap: (): void => {
            try { this.getUIContext().getRouter().back(); } catch (_) {}
          }
        })

        Column({ space: 2 }) {
          Text('百度网页登录')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT_MAIN)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          this.HeaderSubtitle()
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        this.HeaderActions()
      }
      .width('100%')
      .constraintSize({ minHeight: UiLayout.HEADER_HEIGHT })
      .padding({
        left: UiLayout.PAGE_GUTTER,
        right: UiLayout.PAGE_GUTTER,
        top: this.statusBarH + 8,
        bottom: 8
      })
      .alignItems(VerticalAlign.Center)

      Stack({ alignContent: Alignment.Top }) {
        if (this.webReady) {
          Web({ src: LOGIN_URL, controller: this.controller, incognitoMode: true })
            .cacheMode(CacheMode.Online)
            .width('100%')
            .height('100%')
            .domStorageAccess(true)
            .javaScriptAccess(true)
            .onPageBegin((): void => {
              this.pageLoading = true;
              this.loadError = false;
            })
            .onProgressChange((event: OnProgressChangeEvent): void => {
              const p: number = event.newProgress;
              this.loadProgress = p;
              if (p >= 85 && !this.firstPageLoaded) {
                this.firstPageLoaded = true;
              }
              if (p >= 100) {
                this.pageLoading = false;
                this.firstPageLoaded = true;
              }
            })
            .onPageEnd((): void => {
              this.pageLoading = false;
              this.firstPageLoaded = true;
              this.syncBackState();
            })
            .onRefreshAccessedHistory((): void => {
              this.syncBackState();
            })
            .onErrorReceive((event: OnErrorReceiveEvent): void => {
              if (event.request.isMainFrame()) {
                this.pageLoading = false;
                this.firstPageLoaded = true;
                this.loadError = true;
              }
            })
        }

        if (this.pageLoading && this.loadProgress > 0 && this.loadProgress < 100 && !this.loadError) {
          Progress({ value: this.loadProgress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(2)
            .color(AppTheme.ACCENT)
            .backgroundColor(Color.Transparent)
            .style({ strokeWidth: 2, enableSmoothEffect: true })
        }

        if (!this.firstPageLoaded && !this.loadError) {
          this.InitialLoadingOverlay()
        }

        if (this.loadError) {
          this.LoadErrorOverlay()
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(AppTheme.CARD)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG)
  }

  @Builder
  HeaderActions() {
    if (this.canGoBack) {
      GlassCircleButton({
        symbol: $r('sys.symbol.chevron_left'),
        iconSize: 22,
        iconWeight: FontWeight.Regular,
        accessibilityLabel: '网页上一页',
        onTap: (): void => {
          try {
            if (this.controller.accessBackward()) {
              this.controller.backward();
            }
          } catch (_) {}
          this.syncBackState();
        }
      })
    }
    GlassCircleButton({
      symbol: $r('sys.symbol.arrow_clockwise'),
      iconSize: 20,
      iconWeight: FontWeight.Regular,
      accessibilityLabel: '刷新网页',
      onTap: (): void => {
        this.retrySession();
      }
    })
  }

  @Builder
  HeaderSubtitle() {
    if (this.pollTimedOut || this.statusText.length > 0) {
      Text(this.statusText)
        .fontSize(11.5)
        .fontColor(this.pollTimedOut ? AppTheme.MSG_BADGE_ORANGE_FG : AppTheme.TEXT_MUTED)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .onClick((): void => {
          if (this.pollTimedOut) {
            this.retrySession();
          }
        })
    } else {
      Row({ space: 10 }) {
        this.TokenDot('BDUSS', this.bdussSeen)
        this.TokenDot('STOKEN', this.stokenSeen)
      }
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  TokenDot(label: string, ready: boolean) {
    Row({ space: 4 }) {
      Circle()
        .width(6)
        .height(6)
        .fill(ready ? AppTheme.MSG_BADGE_GREEN_FG : AppTheme.TEXT_MUTED)
        .opacity(ready ? 1 : 0.45)
      Text(label)
        .fontSize(11.5)
        .fontColor(ready ? AppTheme.MSG_BADGE_GREEN_FG : AppTheme.TEXT_MUTED)
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  InitialLoadingOverlay() {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(34)
        .height(34)
        .color(AppTheme.ACCENT)
      Text('正在连接百度官方登录页…')
        .fontSize(14)
        .fontColor(AppTheme.TEXT_SUB)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(AppTheme.CARD)
  }

  @Builder
  LoadErrorOverlay() {
    Column({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(26)
          .maxFontScale(1)
          .fontColor([AppTheme.MSG_BADGE_ORANGE_FG])
      }
      .width(56)
      .height(56)
      .borderRadius(28)
      .backgroundColor(AppTheme.MSG_BADGE_ORANGE_BG)

      Text('百度登录页加载失败')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_MAIN)

      Text('请检查网络连接后重试，或返回使用 Cookie 导入')
        .fontSize(13)
        .fontColor(AppTheme.TEXT_SUB)
        .textAlign(TextAlign.Center)

      Button('重新加载', { type: ButtonType.Capsule })
        .height(42)
        .padding({ left: 26, right: 26 })
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.ON_ACCENT)
        .backgroundColor(AppTheme.ACCENT)
        .margin({ top: 4 })
        .onClick((): void => {
          this.retrySession();
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 32, right: 32 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(AppTheme.CARD)
  }
}
