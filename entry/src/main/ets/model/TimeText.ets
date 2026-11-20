/**
 * 全工程唯一的时间文案；楼层（主楼与楼中楼）一并用它，窄列由布局自己吸收。
 *
 * 按**本地日历日**判定，不是按「是否在 24 小时内」：
 * - 今天 → `今天 HH:mm`
 * - 昨天 → `昨天 HH:mm`
 * - 同年其它 → `MM-DD HH:mm`（月/日/时/分补零）
 * - 跨年 → `YYYY-MM-DD`（补零）
 * - 时间戳非法（`<= 0` 或非有限值）→ 空串，界面据此不显示时间，不伪造 1970
 *
 * 纯函数，可在 Node 用例里固定 `nowMs` 断言。
 */

function pad2(value: number): string {
  return value < 10 ? `0${value}` : String(value);
}

function sameDay(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

export function formatTimeText(ms: number, nowMs: number): string {
  if (!Number.isFinite(ms) || ms <= 0) { return ''; }
  const at: Date = new Date(ms);
  if (!Number.isFinite(at.getTime())) { return ''; }
  const now: Date = new Date(nowMs);
  const clock: string = `${pad2(at.getHours())}:${pad2(at.getMinutes())}`;
  if (sameDay(at, now)) { return `今天 ${clock}`; }
  // 「昨天」按日历日回退一天再比同一日：跨 23:59 的 20 分钟仍然是昨天，不是今天。
  const yesterday: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
  if (sameDay(at, yesterday)) { return `昨天 ${clock}`; }
  if (at.getFullYear() === now.getFullYear()) {
    return `${pad2(at.getMonth() + 1)}-${pad2(at.getDate())} ${clock}`;
  }
  return `${at.getFullYear()}-${pad2(at.getMonth() + 1)}-${pad2(at.getDate())}`;
}
