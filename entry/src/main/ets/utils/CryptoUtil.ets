/** 客户端签名使用 MD5(按 key 排序拼接 key=value + salt)，参数间无分隔符；按端点选择 salt，摘要由系统 cryptoFramework 计算。 */

import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { encodeUtf8 } from './TextCodec';

/** 发起签名计算前必须先确定使用哪一组 salt */
export enum SignSalt {
  APP = 0,
  PC = 1,
  MISC = 2
}

const APP_SALT: string = 'tiebaclient!!!';
const PC_SALT: string = '36770b1f34c9bbf2e7d1a99d2b82fa9e';
const MISC_SALT: string = '0039d79dc3cc2075129745a30237a3c4';

/**
 * MD5 对空字节流的摘要。
 * 这不是"补丁值"——MD5 对空输入的输出是算法定义的常量；
 * 写在这里是因为 cryptoFramework 的 update() 拒收空数据（真机实测报 "update failed"，
 * 见 ohosTest 的 Platform.probe_empty_digest），没法走正常流程得到它。
 */
const MD5_EMPTY: string = 'd41d8cd98f00b204e9800998ecf8427e';

/** 一个待签名参数。用显式类型而非 Map，避免 ArkTS 下迭代器与动态键访问的限制。 */
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

  /** MD5 摘要，返回 32 位小写十六进制 */
  static async md5(input: string): Promise<string> {
    return CryptoUtil.md5OfBytes(encodeUtf8(input));
  }

  /** MD5 摘要（二进制输入），返回 32 位小写十六进制 */
  static async md5OfBytes(input: Uint8Array): Promise<string> {
    // 空输入走常量：cryptoFramework 的 update() 不接受空数据
    if (input.length === 0) {
      return MD5_EMPTY;
    }
    const md: cryptoFramework.Md = cryptoFramework.createMd('MD5');
    await md.update({ data: input });
    const digest: cryptoFramework.DataBlob = await md.digest();
    return CryptoUtil.toHex(digest.data);
  }

  /**
   * 计算签名。传入的参数列表会被本地排序，调用方无需预先排好。
   * 传入列表本身不会被修改——需要带 sign 参数的完整列表请用 appendSign。
   */
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

  /**
   * 计算签名并把 sign 追加到参数列表末尾（原地修改）。
   * 这是构造请求体的常用入口。
   */
  static async appendSign(params: SignParam[], salt: SignSalt = SignSalt.APP): Promise<SignParam[]> {
    const sign: string = await CryptoUtil.computeSign(params, salt);
    const result: SignParam[] = params.slice();
    result.push(new SignParam('sign', sign));
    return result;
  }
}
