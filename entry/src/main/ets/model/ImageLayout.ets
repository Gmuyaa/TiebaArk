/** 内容图片排布偏好；稳定值不随中文选项名称变化。 */
export enum ImageLayoutMode {
  MODERN = 0,
  CLASSIC = 1
}

/** 未写入或无法识别的存储值使用新版，读取侧另行提示非法值。 */
export function normalizeImageLayoutMode(value: number): ImageLayoutMode {
  return value === ImageLayoutMode.CLASSIC ? ImageLayoutMode.CLASSIC : ImageLayoutMode.MODERN;
}

export function imageLayoutLabel(value: number): string {
  if (value === ImageLayoutMode.MODERN) { return '新版'; }
  if (value === ImageLayoutMode.CLASSIC) { return '旧版'; }
  return '未确认';
}
