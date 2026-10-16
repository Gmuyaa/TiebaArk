import { RawContentItem } from '../api/RawThreadPage';

export class VoiceClip {
  id: string = '';

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

export function voiceClipLabel(clip: VoiceClip | undefined): string {
  if (clip === undefined) { return '[语音信息不可用]'; }
  if (clip.durationMs <= 0) { return '[语音]'; }
  return `[语音 ${clip.durationMs / 1000}秒]`;
}

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
