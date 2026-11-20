/**
 * 私信 IM 通道的密码学原语。
 *
 * 依据（官方 APK `com.baidu.tbadk.TiebaIMConfig`）：
 * - RSA 公钥与该类内置的同一把；
 * - 会话密钥由客户端生成 31 字节随机数，RSA/PKCS#1 v1.5 加密后随 UpdateClientInfo(1001) 上送；
 * - 帧体 AES-256-ECB/PKCS7，密钥 = PBKDF2-HMAC-SHA1(ws_sec_key, salt, 5 次, 32 字节)。
 *
 * 只做字节进、字节出，不持有账号状态；不记录密钥、不打印明文。
 */

import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

/** 官方 IM 通道 RSA 公钥（DER/SubjectPublicKeyInfo 的 Base64；与 APK TiebaIMConfig 内置值一致）。 */
const RSA_PUBLIC_KEY_B64: string =
  'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwQpwBZxXJV/JVRF/uNfyMSdu7YWwRNLM8+2xbniGp2iIQHOikPpTYQjlQgMi1uvq1kZpJ32rHo3hkwjy2l0lFwr3u4Hk2Wk7vnsqYQjAlYlK0TCzjpmiI+OiPOUNVtbWHQiLiVqFtzvpvi4AU7C1iKGvc/4IS45WjHxeScHhnZZ7njS4S1UgNP/GflRIbzgbBhyZ9kEW5/OO5YfG1fy6r4KSlDJw4o/mw5XhftyIpL+5ZBVBC6E1EIiP/dd9AbK62VV1PByfPMHMixpxI3GM2qwcmFsXcCcgvUXJBa9k6zP8dDQ3csCM2QNT+CQAOxthjtp/TFWaD7MzOdsIYb3THwIDAQAB';

/** PBKDF2 盐值（官方固定常量）。 */
const KDF_SALT: Uint8Array = new Uint8Array([0xa4, 0x0b, 0xc8, 0x34, 0xd6, 0x95, 0xf3, 0x13]);

/** 会话密钥长度：官方 31 字节。 */
export const WS_SEC_KEY_LEN: number = 31;
/** 派生出的 AES 密钥长度：32 字节（AES-256）。 */
const AES_KEY_LEN: number = 32;
const KDF_ITERATIONS: number = 5;

const RSA_KEY_ALG: string = 'RSA2048';
const RSA_CIPHER: string = 'RSA2048|PKCS1';
const AES_CIPHER: string = 'AES256|ECB|PKCS7';
const AES_KEY_ALG: string = 'AES256';

export class ImCrypto {
  /** 生成 n 字节随机数；系统随机源失败时抛错，不退回 Math.random。 */
  static randomBytes(length: number): Uint8Array {
    const random: cryptoFramework.Random = cryptoFramework.createRandom();
    const blob: cryptoFramework.DataBlob = random.generateRandomSync(length);
    return blob.data;
  }

  /** 用官方公钥做 RSA/PKCS#1 v1.5 加密（上送会话密钥用）。 */
  static async rsaEncrypt(plain: Uint8Array): Promise<Uint8Array> {
    const generator: cryptoFramework.AsyKeyGenerator =
      cryptoFramework.createAsyKeyGenerator(RSA_KEY_ALG);
    const der: Uint8Array = new util.Base64Helper().decodeSync(RSA_PUBLIC_KEY_B64);
    const keyPair: cryptoFramework.KeyPair = await generator.convertKey({ data: der }, null);
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher(RSA_CIPHER);
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, keyPair.pubKey, null);
    const out: cryptoFramework.DataBlob = await cipher.doFinal({ data: plain });
    return out.data;
  }

  /**
   * 由会话密钥派生 AES-256 密钥。
   *
   * 规范是 PBKDF2-HMAC-SHA1（5 轮、32 字节），但系统 `createKdf('PBKDF2|SHA1')` 在本机 SDK 上
   * 直接报 `build context fail.`（SHA1 不被支持），所以这里按 RFC 2898 用 HMAC-SHA1 自己展开。
   */
  static async deriveAesKey(secKey: Uint8Array): Promise<Uint8Array> {
    const blockCount: number = Math.ceil(AES_KEY_LEN / 20);
    const full: Uint8Array = new Uint8Array(blockCount * 20);
    for (let block = 1; block <= blockCount; block++) {
      const seed: Uint8Array = new Uint8Array(KDF_SALT.length + 4);
      seed.set(KDF_SALT, 0);
      seed[KDF_SALT.length] = (block >>> 24) & 0xff;
      seed[KDF_SALT.length + 1] = (block >>> 16) & 0xff;
      seed[KDF_SALT.length + 2] = (block >>> 8) & 0xff;
      seed[KDF_SALT.length + 3] = block & 0xff;
      let u: Uint8Array = await ImCrypto.hmacSha1(secKey, seed);
      const t: Uint8Array = u.slice();
      for (let round = 1; round < KDF_ITERATIONS; round++) {
        u = await ImCrypto.hmacSha1(secKey, u);
        for (let i = 0; i < t.length; i++) { t[i] = t[i] ^ u[i]; }
      }
      full.set(t, (block - 1) * 20);
    }
    return full.slice(0, AES_KEY_LEN);
  }

  /** HMAC-SHA1（系统 MAC API；SHA1 在 KDF 里不支持，但在 MAC 里可用）。 */
  static async hmacSha1(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
    const mac: cryptoFramework.Mac = cryptoFramework.createMac('SHA1');
    const symKey: cryptoFramework.SymKey =
      await cryptoFramework.createSymKeyGenerator('HMAC').convertKey({ data: key });
    await mac.init(symKey);
    await mac.update({ data: data });
    const out: cryptoFramework.DataBlob = await mac.doFinal();
    return out.data;
  }

  static async aesEncrypt(key: Uint8Array, plain: Uint8Array): Promise<Uint8Array> {
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher(AES_CIPHER);
    const symKey: cryptoFramework.SymKey =
      await cryptoFramework.createSymKeyGenerator(AES_KEY_ALG).convertKey({ data: key });
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, null);
    const out: cryptoFramework.DataBlob = await cipher.doFinal({ data: plain });
    return out.data;
  }

  static async aesDecrypt(key: Uint8Array, encrypted: Uint8Array): Promise<Uint8Array> {
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher(AES_CIPHER);
    const symKey: cryptoFramework.SymKey =
      await cryptoFramework.createSymKeyGenerator(AES_KEY_ALG).convertKey({ data: key });
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, null);
    const out: cryptoFramework.DataBlob = await cipher.doFinal({ data: encrypted });
    return out.data;
  }
}
