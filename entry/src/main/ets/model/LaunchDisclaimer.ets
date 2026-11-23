/** 首次启动提示与免责声明的文案与版本真值源；供启动弹窗与设置「关于贴吧Ark」共用。 */

/** 声明版本号；仅当免责或数据边界有实质变化时递增，以重新向用户确认。 */
export const DISCLAIMER_VERSION: number = 1;

export const DISCLAIMER_TITLE: string = '使用提示与免责声明';
export const DISCLAIMER_SUBTITLE: string = '贴吧Ark（TiebaArk）· 使用前请阅读';
export const DISCLAIMER_FOOTER_HINT: string =
  '后续可在「设置 → 关于贴吧Ark → 免责声明」与「屏蔽与隐私 → 数据使用说明」查看。';

export interface DisclaimerSection {
  title: string;
  paragraphs: string[];
}

export function disclaimerSections(): DisclaimerSection[] {
  return [
    {
      title: '免责声明',
      paragraphs: [
        '本应用为个人开发的第三方客户端，与百度及贴吧无任何官方关联，仅限学习与技术交流。',
        '使用第三方客户端可能触发平台风控，存在验证码、限流、冻结或封禁等风险；请在知悉风险后自行决定使用，并遵守法律法规与平台规则。',
        '软件按现状提供，不保证持续可用或无误；法律允许范围内，开发者不承担因使用本应用产生的账号、数据或其他损失。'
      ]
    },
    {
      title: '数据与隐私',
      paragraphs: [
        '同意后会在本机生成匿名设备标识，所有请求直连贴吧服务端，不经过开发者服务器。',
        '登录凭据仅存于系统安全存储，退出即清除；浏览历史与偏好设置均保存在本机。'
      ]
    }
  ];
}

export function normalizeDisclaimerVersion(raw: number): number {
  return Number.isSafeInteger(raw) && raw > 0 ? raw : 0;
}

export function isDisclaimerAccepted(acceptedVersion: number,
  requiredVersion: number = DISCLAIMER_VERSION): boolean {
  return normalizeDisclaimerVersion(acceptedVersion) >= requiredVersion;
}
