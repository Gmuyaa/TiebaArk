/** 关于页的第三方库致谢与反馈渠道纯逻辑数据。 */

export const GITHUB_REPO_URL: string = 'https://github.com/Gm0201/TiebaArk';
export const GITHUB_ISSUES_URL: string = 'https://github.com/Gm0201/TiebaArk/issues';
export const QQ_GROUP_URL: string = 'https://qm.qq.com/q/BbZHnivdza';

export interface ThirdPartyLibrary {
  id: string;
  name: string;
  version: string;
  description: string;
  author: string;
  license: string;
  url: string;
}

export interface DeveloperContact {
  id: string;
  label: string;
  url: string;
}

export interface SupportGroup {
  id: string;
  label: string;
  url: string;
}

export function thirdPartyLibraries(): ThirdPartyLibrary[] {
  return [
    {
      id: 'aiotieba',
      name: 'aiotieba',
      version: '协议参考',
      description: '提供贴吧接口端点、请求参数签名与数据结构等协议参考。',
      author: '维护者：Starry-OvO 及社区贡献者',
      license: 'Unlicense',
      url: 'https://github.com/Starry-OvO/aiotieba'
    },
    {
      id: 'tbclient-protobuf',
      name: 'tbclient.protobuf',
      version: '字段参考',
      description: '提供贴吧移动端 Protobuf 消息字段号与结构定义参考。',
      author: '维护者：clb-128258 / n0099',
      license: '仓库随附协议为准',
      url: 'https://github.com/clb-128258/tbclient.protobuf'
    },
    {
      id: 'tiebalite',
      name: 'TiebaLite',
      version: '行为参考',
      description: '提供第三方贴吧客户端功能组织与交互流程参考。',
      author: '作者：HuanCheng65 及社区贡献者',
      license: 'GNU General Public License v3.0',
      url: 'https://github.com/HuanCheng65/TiebaLite'
    },
    {
      id: 'ohos-hypium',
      name: '@ohos/hypium',
      version: '1.0.25',
      description: 'HarmonyOS 原生单元测试框架，用于开发与测试阶段断言校验。',
      author: '维护者：OpenHarmony',
      license: 'Apache License 2.0',
      url: 'https://ohpm.openharmony.cn/#/cn/detail/@ohos%2Fhypium'
    }
  ];
}

export function developerContacts(): DeveloperContact[] {
  return [
    {
      id: 'github_issues',
      label: 'GitHub Issues',
      url: GITHUB_ISSUES_URL
    }
  ];
}

export function supportGroups(): SupportGroup[] {
  return [
    {
      id: 'qq_group_1',
      label: 'QQ群',
      url: QQ_GROUP_URL
    }
  ];
}
