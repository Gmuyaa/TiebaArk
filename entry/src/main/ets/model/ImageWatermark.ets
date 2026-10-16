/** 当前 APK getWatermark 根 data 标量；0 的含义未确认，不作为关闭。 */
interface WatermarkEnvelope { error_code?: number | string; data?: number | string; }
export class ImageWatermark { type: number = -1; }
export function parseImageWatermark(text: string): ImageWatermark {
  const result: ImageWatermark = new ImageWatermark();
  try {
    const raw: WatermarkEnvelope = JSON.parse(text) as WatermarkEnvelope;
    if (raw.error_code !== 0 && raw.error_code !== '0') { return result; }
    const value: number | string | undefined = raw.data;
    if (typeof value !== 'number' && (typeof value !== 'string' || !/^\d+$/.test(value))) { return result; }
    const type: number = Number(value);
    if (Number.isInteger(type) && type >= 0 && type <= 2147483647) { result.type = type; }
  } catch (err) { /* 缺失或格式错误保持未确认。 */ }
  return result;
}
/** 1/2 来自当前 APK 上传参数绑定，实际图片效果仍待验证。 */
export function imageWatermarkLabel(type: number): string {
  if (type === 1) { return '用户名水印'; }
  if (type === 2) { return '吧名水印'; }
  return '未识别的水印类型';
}
