/**
 * wire（原始 JSON）取值兜底：把 `undefined`/`null`/类型不符统一收敛成安全的空值。
 *
 * 这些值都来自 `JSON.parse` 的原始响应，字段可能缺失或为 `null`；各 model 文件过去各写一份，
 * 判定方式还不统一（`=== undefined` 与 `typeof === 'string'`），这里只留一种：
 * **类型不符就当没有**，不会把 `null` 当成 string/number 往下传。
 */

/** 只接受字符串，其余（缺失 / null / 数字）一律空串。 */
export function wireString(value: string | undefined): string {
  return typeof value === 'string' ? value : '';
}

/** 只接受数字，其余（缺失 / null / 字符串）一律 0。 */
export function wireNumber(value: number | undefined): number {
  return typeof value === 'number' ? value : 0;
}
