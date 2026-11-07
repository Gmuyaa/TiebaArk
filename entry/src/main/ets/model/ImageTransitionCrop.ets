import { FeedImageTransform } from './FeedImageLayout';

/** 接近单位缩放时不能用位移除以 1 - scale，避免得到不稳定的远端锚点。 */
const IDENTITY_EPSILON: number = 0.000001;
/** 在单位外框中允许的数值误差；不代表原生转场已经过逐帧验证。 */
const AFFINE_EPSILON: number = 0.00001;

/**
 * 将预览裁切表示为一次绕锚点的缩放。
 * centerX/centerY 是可直接交给 ScaleOptions 的百分比字符串，不是 vp。
 * usable=false 表示调用方必须走 fallback，不能把默认单位变换当成成功转换。
 */
export class ImageTransitionCrop {
  scale: number = 1;
  centerX: string = '50%';
  centerY: string = '50%';
  usable: boolean = false;
  /** 完整正文图片的实际比例；0 保留原有图集/裁切图片的全屏共享框。 */
  contentAspectRatio: number = 0;
}

function percent(center: number): string {
  // 固定小数形式避免极小/极大数变成百分比解析器未必接受的科学计数法。
  // 格式化造成的舍入也会参与后面的等价检查；不会夹取框外的锚点。
  const value: string = (center * 100).toFixed(12).replace(/\.?0+$/, '');
  return Number(value) === 0 ? '0%' : `${value}%`;
}

function safeAxis(scale: number, centerText: string, translationPercent: number): boolean {
  const center: number = Number.parseFloat(centerText) / 100;
  const translation: number = translationPercent / 100;
  const rebuilt: number = (1 - scale) * center;
  if (!Number.isFinite(center) || !Number.isFinite(rebuilt) ||
    Math.abs(rebuilt - translation) > AFFINE_EPSILON) { return false; }

  // 保守检查单精度表示及单位区间两端，拒绝溢出、消减失真和过大的锚点误差。
  // 这里只检查数值条件，不模拟 ArkUI 的布局、时间轴或共享元素采样。
  const nativeScale: number = Math.fround(scale);
  const nativeCenter: number = Math.fround(center);
  const start: number = Math.fround(Math.fround(1 - nativeScale) * nativeCenter);
  const end: number = Math.fround(nativeScale + start);
  const span: number = end - start;
  return Number.isFinite(nativeScale) && nativeScale > 0 && Number.isFinite(nativeCenter) &&
    Number.isFinite(start) && Number.isFinite(end) && span > 0 &&
    Math.abs(nativeScale - scale) <= AFFINE_EPSILON &&
    Math.abs(start - translation) <= AFFINE_EPSILON &&
    Math.abs(end - (scale + translation)) <= AFFINE_EPSILON &&
    Math.abs(span - scale) <= AFFINE_EPSILON * scale;
}

/**
 * 原矩阵为 s * point + (xPercent * width, yPercent * height) / 100。
 * 绕归一化锚点 a 缩放的矩阵为 s * point + (1 - s) * a * size，
 * 因而 a = (percent / 100) / (1 - s)。不改变输入，也不把锚点限制在框内。
 */
export function imageTransitionCrop(transform: FeedImageTransform): ImageTransitionCrop {
  const result: ImageTransitionCrop = new ImageTransitionCrop();
  const scale: number = transform.scale;
  if (!Number.isFinite(scale) || scale <= 0 || !Number.isFinite(transform.xPercent) ||
    !Number.isFinite(transform.yPercent)) { return result; }

  const delta: number = 1 - scale;
  let centerX: number = 0;
  let centerY: number = 0;
  if (Math.abs(delta) <= IDENTITY_EPSILON) {
    // 纯平移无法写成单位缩放；近单位缩放也不以极大锚点勉强表示。
    if (transform.xPercent !== 0 || transform.yPercent !== 0) { return result; }
    // 零平移仍可直接绕原点缩放；完全单位变换选择中心不影响结果。
    centerX = scale === 1 ? 0.5 : 0;
    centerY = centerX;
  } else {
    centerX = (transform.xPercent / 100) / delta;
    centerY = (transform.yPercent / 100) / delta;
  }
  // toFixed 对绝对值 >= 1e21 的数仍使用科学计数法；此时也不适合锚点转换。
  if (!Number.isFinite(centerX) || !Number.isFinite(centerY) ||
    Math.abs(centerX * 100) >= 1e21 || Math.abs(centerY * 100) >= 1e21) { return result; }
  const x: string = percent(centerX);
  const y: string = percent(centerY);
  if (!safeAxis(scale, x, transform.xPercent) || !safeAxis(scale, y, transform.yPercent)) { return result; }

  result.scale = scale;
  result.centerX = x;
  result.centerY = y;
  result.usable = true;
  return result;
}
