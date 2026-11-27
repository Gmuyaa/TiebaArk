/** 登录页纯逻辑辅助：本地实时识别凭据形态（不透出原文）与获取步骤数据。 */

import {
  CredentialBundle, credentialsFromUserInput, looksLikeCookieText, validateBduss
} from './AuthModel';

export class CredentialInputPreview {
  hasInput: boolean = false;
  isCookieText: boolean = false;
  bdussReady: boolean = false;
  stokenReady: boolean = false;
}

export class LoginGuideStep {
  stepNo: string = '';
  title: string = '';
  detail: string = '';

  constructor(stepNo: string, title: string, detail: string) {
    this.stepNo = stepNo;
    this.title = title;
    this.detail = detail;
  }
}

/** 仅返回凭据各字段的形态就绪态，绝不返回或记录任何凭据原文。 */
export function inspectCredentialInput(rawInput: string): CredentialInputPreview {
  const preview: CredentialInputPreview = new CredentialInputPreview();
  const raw: string = rawInput.trim();
  if (raw.length === 0) {
    return preview;
  }
  preview.hasInput = true;
  preview.isCookieText = looksLikeCookieText(raw);
  const bundle: CredentialBundle = credentialsFromUserInput(raw);
  preview.bdussReady = bundle.bduss.length > 0 && validateBduss(bundle.bduss).length === 0;
  preview.stokenReady = bundle.stoken.length > 0;
  return preview;
}

export function cookieGuideSteps(): LoginGuideStep[] {
  return [
    new LoginGuideStep('01', '登录网页版贴吧', '在浏览器中打开 tieba.baidu.com 并登录百度账号'),
    new LoginGuideStep('02', '打开 Cookies 列表', '打开开发者工具，进入 Application / 存储 → Cookies'),
    new LoginGuideStep('03', '找到两项关键凭据', '复制 BDUSS 与 STOKEN（STOKEN 位于 .baidu.com 域分组下）'),
    new LoginGuideStep('04', '粘贴整条 Cookie', '直接粘贴到上方输入框，系统会自动提取所需字段')
  ];
}
