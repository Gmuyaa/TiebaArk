

import { util } from '@kit.ArkTS';

const UTF8: string = 'utf-8';

/**
 * 字符串 → UTF-8 字节。
 * 空串返回长度为 0 的数组，绝不返回 undefined。
 */
export function encodeUtf8(text: string): Uint8Array {
  const encoder: util.TextEncoder = new util.TextEncoder();
  const encoded: Uint8Array | undefined = encoder.encodeInto(text);
  if (encoded === undefined) {
    return new Uint8Array(0);
  }
  return encoded;
}

/**
 * UTF-8 字节 → 字符串。
 * 空数组返回空串，不构造解码器。
 */
export function decodeUtf8(bytes: Uint8Array): string {
  if (bytes.length === 0) {
    return '';
  }
  const decoder: util.TextDecoder = util.TextDecoder.create(UTF8);
  if (decoder === undefined) {
    return '';
  }
  return decoder.decodeToString(bytes);
}
