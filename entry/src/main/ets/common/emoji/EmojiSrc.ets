

const RAW_PROTOCOL: string = 'rawfile://';

export function emojiSrc(src: string): ResourceStr {
  if (src.startsWith(RAW_PROTOCOL)) {
    return $rawfile(src.substring(RAW_PROTOCOL.length));
  }
  return src;
}
