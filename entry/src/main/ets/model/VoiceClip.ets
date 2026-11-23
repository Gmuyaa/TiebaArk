import { RawContentItem } from './RawThreadPage';

/** 当前 APK gn7.g(10)→512→TbRichTextVoiceInfo；资源标识不等于音频 URL。 */
export class VoiceClip {
  id: string = '';
  /** 保留服务端毫秒，不将 1500ms 提前截成 1 秒。-1 为缺失或无效。 */
  durationMs: number = -1;
}

export function parseVoiceClip(raw: RawContentItem): VoiceClip | undefined {
  if (raw.type !== 10 || typeof raw.voice_md5 !== 'string' || raw.voice_md5.trim().length === 0 ||
    /[\u0000-\u001f\u007f]/.test(raw.voice_md5)) { return undefined; }
  const clip: VoiceClip = new VoiceClip(); clip.id = raw.voice_md5;
  if (typeof raw.during_time === 'number' ||
    (typeof raw.during_time === 'string' && /^\d+$/.test(raw.during_time))) {
    const millis: number = Number(raw.during_time);
    if (Number.isSafeInteger(millis) && millis >= 0 && millis <= 4294967295) { clip.durationMs = millis; }
  }
  return clip;
}

/** 行内预览只描述已读元数据；块级正文的播放控件由 VoicePlayer 提供。 */
export function voiceClipLabel(clip: VoiceClip | undefined): string {
  if (clip === undefined) { return '[语音信息不可用]'; }
  if (clip.durationMs <= 0) { return '[语音]'; }
  return `[语音 ${clip.durationMs / 1000}秒]`;
}

/** 已知长度内存数据源：按 SDK 指定的随机位置复制，EOF=-1，非法请求=-2。 */
export function readVoiceBytes(bytes: Uint8Array, buffer: ArrayBuffer, length: number, pos?: number): number {
  if (pos === undefined || !Number.isSafeInteger(pos) || pos < 0 || !Number.isSafeInteger(length) || length < 0) { return -2; }
  if (pos >= bytes.length) { return -1; }
  if (length === 0) { return 0; }
  if (buffer.byteLength === 0) { return -2; }
  const count: number = Math.min(length, buffer.byteLength, bytes.length - pos);
  new Uint8Array(buffer).set(bytes.subarray(pos, pos + count)); return count;
}

export function voicePayloadError(bytes: Uint8Array): string {
  if (bytes.length === 0) { return '语音响应为空'; }
  let pos: number = 0;
  while (pos < bytes.length && (bytes[pos] === 32 || bytes[pos] === 9 || bytes[pos] === 13 || bytes[pos] === 10)) { pos++; }
  if (pos >= bytes.length || bytes[pos] === 123 || bytes[pos] === 91 || bytes[pos] === 60) { return '服务器未返回音频数据'; }
  return '';
}

const AMR_NB_MAGIC: number[] = [0x23, 0x21, 0x41, 0x4d, 0x52, 0x0a];
const AMR_WB_MAGIC: number[] = [0x23, 0x21, 0x41, 0x4d, 0x52, 0x2d, 0x57, 0x42, 0x0a];
// RFC 4867 每帧净荷字节数（不含 1 字节帧头）；每帧固定 20ms，-1 为保留/无效模式。
const AMR_NB_PAYLOAD_BYTES: number[] = [12, 13, 15, 17, 19, 20, 26, 31, 5, -1, -1, -1, -1, -1, -1, 0];
const AMR_WB_PAYLOAD_BYTES: number[] = [17, 23, 32, 36, 40, 46, 50, 58, 60, 5, -1, -1, -1, -1, 0, 0];

function startsWithBytes(bytes: Uint8Array, prefix: number[]): boolean {
  if (bytes.length < prefix.length) { return false; }
  for (let i = 0; i < prefix.length; i++) {
    if (bytes[i] !== prefix[i]) { return false; }
  }
  return true;
}

/** 精确按帧计算 AMR-NB / AMR-WB 毫秒时长，避免 AVPlayer dataSrc 变码率估算偏差；非 AMR 或损坏返回 -1。 */
export function measureAmrDurationMs(bytes: Uint8Array): number {
  let offset: number = 0;
  let table: number[] = AMR_NB_PAYLOAD_BYTES;
  if (startsWithBytes(bytes, AMR_NB_MAGIC)) {
    offset = AMR_NB_MAGIC.length;
    table = AMR_NB_PAYLOAD_BYTES;
  } else if (startsWithBytes(bytes, AMR_WB_MAGIC)) {
    offset = AMR_WB_MAGIC.length;
    table = AMR_WB_PAYLOAD_BYTES;
  } else {
    return -1;
  }
  let frames: number = 0;
  while (offset < bytes.length) {
    const mode: number = (bytes[offset] >> 3) & 0x0f;
    const payload: number = table[mode];
    if (payload < 0) { return -1; }
    offset += 1 + payload;
    if (offset > bytes.length) { return -1; }
    frames++;
  }
  return frames > 0 ? frames * 20 : -1;
}
