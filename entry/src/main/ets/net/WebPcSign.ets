/* 协议参考：lumina37/aiotieba（Unlicense）。 */

import { CryptoUtil, SignParam } from '../utils/CryptoUtil';

const PC_SIGN_SECRET: string = '36770b1f34c9bbf2e7d1a99d2b82fa9e';

export const PC_SEARCH_REFERER: string = 'https://tieba.baidu.com/f/search/res';

export class WebPcSign {

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
