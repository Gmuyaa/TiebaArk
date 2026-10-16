

import { util } from '@kit.ArkTS';

const UTF8: string = 'utf-8';

export function encodeUtf8(text: string): Uint8Array {
  const encoder: util.TextEncoder = new util.TextEncoder();
  const encoded: Uint8Array | undefined = encoder.encodeInto(text);
  if (encoded === undefined) {
    return new Uint8Array(0);
  }
  return encoded;
}

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
