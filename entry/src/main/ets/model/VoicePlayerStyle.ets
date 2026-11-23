/** 帖子与回复中语音条的展示与交互样式；稳定值不随中文文案变化。 */
export enum VoicePlayerStyle {
  SLIDER = 0,
  WAVEFORM = 1,
  BUBBLE = 2
}

export const ALL_VOICE_PLAYER_STYLES: VoicePlayerStyle[] = [
  VoicePlayerStyle.SLIDER,
  VoicePlayerStyle.WAVEFORM,
  VoicePlayerStyle.BUBBLE
];

const WAVE_PATTERN: number[] = [
  0.25, 0.52, 0.86, 0.40, 1.00, 0.66, 0.25, 0.82,
  0.96, 0.46, 0.28, 0.90, 0.62, 0.25, 0.78, 0.50,
  0.28, 0.84, 0.56, 0.25, 0.72, 0.44, 0.30, 0.60
];

/** 未写入或无法识别的存储值回退滑块条，读取侧另行提示非法值。 */
export function normalizeVoicePlayerStyle(value: number): VoicePlayerStyle {
  if (value === VoicePlayerStyle.WAVEFORM) { return VoicePlayerStyle.WAVEFORM; }
  if (value === VoicePlayerStyle.BUBBLE) { return VoicePlayerStyle.BUBBLE; }
  return VoicePlayerStyle.SLIDER;
}

export function voicePlayerStyleLabel(value: number): string {
  if (value === VoicePlayerStyle.SLIDER) { return '滑块条'; }
  if (value === VoicePlayerStyle.WAVEFORM) { return '波形条'; }
  if (value === VoicePlayerStyle.BUBBLE) { return '气泡条'; }
  return '未确认';
}

export function formatVoiceClock(seconds: number): string {
  const safe: number = Number.isFinite(seconds) ? Math.max(0, Math.floor(seconds)) : 0;
  return `${Math.floor(safe / 60)}:${(safe % 60).toString().padStart(2, '0')}`;
}

/** 滑块条时间文案：始终展示当前时长/总时长；durationMs<=0 如实提示未确认。 */
export function formatVoiceSliderTime(positionMs: number, durationMs: number): string {
  if (!Number.isFinite(durationMs) || durationMs <= 0) { return '时长未确认'; }
  const totalSec: number = Math.max(1, Math.round(durationMs / 1000));
  const useClock: boolean = totalSec >= 60;
  const posSec: number = Number.isFinite(positionMs) && positionMs > 0
    ? (positionMs >= durationMs ? totalSec : Math.min(totalSec, Math.floor(positionMs / 1000)))
    : 0;
  const posText: string = useClock ? formatVoiceClock(posSec) : `${posSec}"`;
  const totalText: string = useClock ? formatVoiceClock(totalSec) : `${totalSec}"`;
  return `${posText}/${totalText}`;
}

/** 波形条时间文案：未播放显示总时长，播放/拖动时仅显示当前时长。 */
export function formatVoiceWaveformTime(positionMs: number, durationMs: number, showPosition: boolean): string {
  if (!Number.isFinite(durationMs) || durationMs <= 0) { return '时长未确认'; }
  const totalSec: number = Math.max(1, Math.round(durationMs / 1000));
  const useClock: boolean = totalSec >= 60;
  if (!showPosition) { return useClock ? formatVoiceClock(totalSec) : `${totalSec}"`; }
  const posSec: number = Number.isFinite(positionMs) && positionMs > 0
    ? (positionMs >= durationMs ? totalSec : Math.min(totalSec, Math.floor(positionMs / 1000)))
    : 0;
  return useClock ? formatVoiceClock(posSec) : `${posSec}"`;
}

/** 气泡条时间文案：仅显示总时长；短于 1 分钟用秒引号，1 分钟及以上用 M:SS。 */
export function formatVoiceBubbleTime(durationMs: number): string {
  if (!Number.isFinite(durationMs) || durationMs <= 0) { return '语音'; }
  const totalSec: number = Math.max(1, Math.round(durationMs / 1000));
  return totalSec >= 60 ? formatVoiceClock(totalSec) : `${totalSec}"`;
}

export function voiceProgressRatio(positionMs: number, durationMs: number): number {
  if (!Number.isFinite(durationMs) || durationMs <= 0 || !Number.isFinite(positionMs) || positionMs <= 0) {
    return 0;
  }
  return Math.max(0, Math.min(1, positionMs / durationMs));
}

function durationWidthRatio(durationMs: number): number {
  const seconds: number = Math.max(1, durationMs / 1000);
  if (seconds >= 60) { return 1; }
  // 前 10 秒平缓起步，10–30 秒中段增长，30–60 秒缓步封顶，贴近贴吧/QQ/抖音语音条比例。
  if (seconds <= 10) { return (seconds - 1) / 9 * 0.30; }
  if (seconds <= 30) { return 0.30 + (seconds - 10) / 20 * 0.40; }
  return 0.70 + (seconds - 30) / 30 * 0.30;
}

/** 滑块条按时长伸展（vp）：1 秒 136vp，60 秒及以上封顶 192vp。 */
export function voiceBarWidthVp(durationMs: number): number {
  if (!Number.isFinite(durationMs) || durationMs <= 0) { return 144; }
  return Math.round(136 + durationWidthRatio(durationMs) * 56);
}

/** 气泡条按时长伸展（vp）：1 秒 74vp、13 秒约 102vp、26 秒约 122vp、60 秒封顶 152vp。 */
export function voiceBubbleWidthVp(durationMs: number): number {
  if (!Number.isFinite(durationMs) || durationMs <= 0) { return 84; }
  return Math.round(74 + durationWidthRatio(durationMs) * 78);
}

/** 波形条按时长决定紧密排列的音柱数（4–24 柱，固定间距不拉伸）。 */
export function voiceWaveformBarCount(durationMs: number): number {
  if (!Number.isFinite(durationMs) || durationMs <= 0) { return 8; }
  return Math.round(4 + durationWidthRatio(durationMs) * 20);
}

/** 按语音标识确定性生成的装饰音柱高度权重（[0.34, 1.0]），避免重渲染抖动。 */
export function voiceWaveformWeights(voiceId: string, count: number): number[] {
  const safeCount: number = Number.isInteger(count) && count > 0 ? count : 0;
  let hash: number = 0;
  for (let i = 0; i < voiceId.length; i++) {
    hash = (hash * 31 + voiceId.charCodeAt(i)) % WAVE_PATTERN.length;
  }
  const weights: number[] = [];
  for (let i = 0; i < safeCount; i++) {
    weights.push(WAVE_PATTERN[(i + hash) % WAVE_PATTERN.length]);
  }
  return weights;
}

/** 轨道局部横坐标换算为 [0, durationMs] 的整型定位毫秒。 */
export function voiceSeekPositionFromX(localX: number, trackWidth: number, durationMs: number): number {
  if (!Number.isFinite(localX) || !Number.isFinite(trackWidth) || trackWidth <= 0 ||
    !Number.isFinite(durationMs) || durationMs <= 0) {
    return 0;
  }
  const ratio: number = Math.max(0, Math.min(1, localX / trackWidth));
  return Math.round(ratio * durationMs);
}
