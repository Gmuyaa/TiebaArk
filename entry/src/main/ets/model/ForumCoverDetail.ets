/** 仅收紧高度时使用的保守判定；不识字，不把均值相近等同于没有内容。 */
export class ForumCoverDetail {
  compact: boolean = false;
  samples: number = 0;
  deviation: number = 0;
  spread: number = 0;
  edge: number = 0;
  localDeviation: number = 0;
}

export const FORUM_COVER_SAMPLE_WIDTH: number = 768;
export const FORUM_COVER_SAMPLE_PIXELS: number = FORUM_COVER_SAMPLE_WIDTH * 512;

/** RGBA/BGRA顺序不影响三个通道的最大值；行跨度与透明留边均显式处理。 */
export function forumCoverDetail(bytes: Uint8Array, width: number, height: number, stride: number): ForumCoverDetail {
  const result: ForumCoverDetail = new ForumCoverDetail();
  if (!Number.isInteger(width) || !Number.isInteger(height) || width < 8 || height < 4 ||
    width * height > FORUM_COVER_SAMPLE_PIXELS || !Number.isInteger(stride) || stride < width * 4 ||
    bytes.length < (height - 1) * stride + width * 4) { return result; }
  const sums: number[] = [0, 0, 0];
  const squares: number[] = [0, 0, 0];
  const minima: number[] = [255, 255, 255];
  const maxima: number[] = [0, 0, 0];
  let left: number = width;
  let right: number = -1;
  let top: number = height;
  let bottom: number = -1;
  let brightnessEdge: number = 0;
  for (let y: number = 0; y < height; y++) {
    for (let x: number = 0; x < width; x++) {
      const offset: number = y * stride + x * 4;
      // Contain产生的透明外沿不参与均值；不透明样本必须覆盖完整矩形，透明图不冒充纯色。
      if (bytes[offset + 3] < 250) { continue; }
      result.samples++;
      left = Math.min(left, x); right = Math.max(right, x);
      top = Math.min(top, y); bottom = Math.max(bottom, y);
      for (let channel: number = 0; channel < 3; channel++) {
        const value: number = bytes[offset + channel];
        sums[channel] += value; squares[channel] += value * value;
        minima[channel] = Math.min(minima[channel], value);
        maxima[channel] = Math.max(maxima[channel], value);
        if (x > 0 && bytes[offset - 1] >= 250) {
          result.edge = Math.max(result.edge, Math.abs(value - bytes[offset - 4 + channel]));
        }
        if (y > 0 && bytes[offset - stride + 3] >= 250) {
          result.edge = Math.max(result.edge, Math.abs(value - bytes[offset - stride + channel]));
        }
      }
      const brightness: number = coverBrightness(bytes, offset);
      if (x > 0 && bytes[offset - 1] >= 250) {
        brightnessEdge = Math.max(brightnessEdge, Math.abs(brightness - coverBrightness(bytes, offset - 4)));
      }
      if (y > 0 && bytes[offset - stride + 3] >= 250) {
        brightnessEdge = Math.max(brightnessEdge, Math.abs(brightness - coverBrightness(bytes, offset - stride)));
      }
    }
  }
  if (result.samples < 32 || result.samples !== (right - left + 1) * (bottom - top + 1)) { return result; }
  for (let channel: number = 0; channel < 3; channel++) {
    const mean: number = sums[channel] / result.samples;
    result.deviation = Math.max(result.deviation, Math.sqrt(Math.max(0, squares[channel] / result.samples - mean * mean)));
    result.spread = Math.max(result.spread, maxima[channel] - minima[channel]);
  }
  // 检查全部采样像素及邻接差异：少量小字不能被全图平均值稀释。
  if (result.deviation <= 1.25 && result.spread <= 4 && result.edge <= 4) { result.compact = true; return result; }
  // 平滑渐变可能跨越很大色域，不能用全图色差否决；检查局部明暗和色彩边缘。
  // 近黑通道容许小幅JPEG色度量化噪声，其余通道保留原来的细节门槛。
  if (result.edge > 16 || brightnessEdge >= 6 || right - left < 16 || bottom - top < 16) { return result; }
  for (let y: number = top; y <= bottom; y++) {
    for (let x: number = left; x <= right; x++) {
      const offset: number = y * stride + x * 4;
      if (bytes[offset + 3] < 250) { return result; }
      let brightnessResidual: number = 0;
      for (let channel: number = 0; channel < 3; channel++) {
        const horizontal: number = smoothReference(bytes, offset, channel, 4, x - left, right - x);
        const vertical: number = smoothReference(bytes, offset, channel, stride, y - top, bottom - y);
        if (!Number.isFinite(horizontal) || !Number.isFinite(vertical)) { return result; }
        const reference: number = (horizontal + vertical) / 2;
        const residual: number = bytes[offset + channel] - reference;
        result.localDeviation = Math.max(result.localDeviation, Math.abs(residual));
        if (result.localDeviation > 16) { return result; }
        if (Math.abs(residual) > 6 && Math.min(bytes[offset + channel], reference) >= 32) { return result; }
        brightnessResidual += residual * (channel === 1 ? 0.5 : 0.25);
      }
      if (Math.abs(brightnessResidual) >= 4) { return result; }
    }
  }
  result.compact = true;
  return result;
}

/** 绿色通道位置在RGBA/BGRA中相同；对两种布局使用一致的近似明暗值。 */
function coverBrightness(bytes: Uint8Array, offset: number): number {
  return (bytes[offset] + 2 * bytes[offset + 1] + bytes[offset + 2]) / 4;
}

/** 中间用对称邻点，边缘用线性外推，不把图外透明留边当作内容差异。 */
function smoothReference(bytes: Uint8Array, offset: number, channel: number, step: number,
  before: number, after: number): number {
  let a: number;
  let b: number;
  if (before >= 8 && after >= 8) {
    a = offset - 8 * step; b = offset + 8 * step;
    if (bytes[a + 3] < 250 || bytes[b + 3] < 250) { return NaN; }
    return (bytes[a + channel] + bytes[b + channel]) / 2;
  }
  const direction: number = after >= 16 ? 1 : before >= 16 ? -1 : 0;
  if (direction === 0) { return NaN; }
  a = offset + direction * 8 * step; b = offset + direction * 16 * step;
  if (bytes[a + 3] < 250 || bytes[b + 3] < 250) { return NaN; }
  return 2 * bytes[a + channel] - bytes[b + channel];
}
