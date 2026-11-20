/** PC 网页端的搜索签名，与 app 侧的 SignSalt 通道无关；算法参考 lumina37/aiotieba 的 search_global/_api.py（Unlicense）。 */

import { CryptoUtil, SignParam } from '../utils/CryptoUtil';

/** PC 网页端专属签名密钥（逆向 PC 网页端 js 所得，非 app 签名密钥） */
const PC_SIGN_SECRET: string = '36770b1f34c9bbf2e7d1a99d2b82fa9e';

/** 搜吧/搜帖 web 端点要求的 Referer（缺失时可能触发风控） */
export const PC_SEARCH_REFERER: string = 'https://tieba.baidu.com/f/search/res';

export class WebPcSign {
  /** sign 项不该出现在入参里（出现也会被排除）；`SignParam` 只是 key/value 对，与 app 签名无关。 */
  static async sign(params: SignParam[]): Promise<string> {
    const sorted: SignParam[] = params
      .filter((p: SignParam): boolean => p.key !== 'sign' && p.key !== 'sig')
      .sort((a: SignParam, b: SignParam): number => {
        if (a.key < b.key) {
          return -1;
        }
        return a.key > b.key ? 1 : 0;
      });
    let raw: string = '';
    for (const p of sorted) {
      raw += `${p.key}=${p.value}`;
    }
    return CryptoUtil.md5(raw + PC_SIGN_SECRET);
  }
}
