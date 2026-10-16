

import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { encodeUtf8 } from './TextCodec';

export enum SignSalt {
  APP = 0,
  PC = 1,
  MISC = 2
}

const APP_SALT: string = 'tiebaclient!!!';
const PC_SALT: string = '36770b1f34c9bbf2e7d1a99d2b82fa9e';
const MISC_SALT: string = '0039d79dc3cc2075129745a30237a3c4';

const MD5_EMPTY: string = 'd41d8cd98f00b204e9800998ecf8427e';

export class SignParam {
  key: string = '';
  value: string = '';

  constructor(key: string, value: string) {
    this.key = key;
    this.value = value;
  }
}

export class CryptoUtil {

  private static saltOf(salt: SignSalt): string {
    switch (salt) {
      case SignSalt.PC:
        return PC_SALT;
      case SignSalt.MISC:
        return MISC_SALT;
      default:
        return APP_SALT;
    }
  }

  private static toHex(bytes: Uint8Array): string {
    let out: string = '';
    for (let i = 0; i < bytes.length; i++) {
      const b: number = bytes[i];
      out += b < 16 ? `0${b.toString(16)}` : b.toString(16);
    }
    return out;
  }

  static async md5(input: string): Promise<string> {
    return CryptoUtil.md5OfBytes(encodeUtf8(input));
  }

  static async md5OfBytes(input: Uint8Array): Promise<string> {

    if (input.length === 0) {
      return MD5_EMPTY;
    }
    const md: cryptoFramework.Md = cryptoFramework.createMd('MD5');
    await md.update({ data: input });
    const digest: cryptoFramework.DataBlob = await md.digest();
    return CryptoUtil.toHex(digest.data);
  }

  static async computeSign(params: SignParam[], salt: SignSalt = SignSalt.APP): Promise<string> {
    const sorted: SignParam[] = params.slice();
    sorted.sort((a: SignParam, b: SignParam): number => {
      if (a.key < b.key) {
        return -1;
      }
      if (a.key > b.key) {
        return 1;
      }
      return 0;
    });

    let payload: string = '';
    for (let i = 0; i < sorted.length; i++) {
      payload += `${sorted[i].key}=${sorted[i].value}`;
    }
    payload += CryptoUtil.saltOf(salt);
    return CryptoUtil.md5(payload);
  }

  static async appendSign(params: SignParam[], salt: SignSalt = SignSalt.APP): Promise<SignParam[]> {
    const sign: string = await CryptoUtil.computeSign(params, salt);
    const result: SignParam[] = params.slice();
    result.push(new SignParam('sign', sign));
    return result;
  }
}
