/**
 * wire（原始 JSON）取值兜底：`JSON.parse` 的响应字段可能缺失或为 `null`。
 *
 * 唯一判定口径：**类型不符就当没有**，不把 `null` 当 string/number 往下传。
 */

export function wireString(value: string | undefined): string {
  return typeof value === 'string' ? value : '';
}

export function wireNumber(value: number | undefined): number {
  return typeof value === 'number' ? value : 0;
}
