/**
 * 全工程唯一的时间文案（2026-11-14 持有者定，审计 B1）。
 *
 * 统一前有 5 处各写一套：帖子列表侧补零带日期、楼层不补零只给时分、主帖头再一份、
 * 帮助卡片一份「N分钟前」、通知列表一份「当天只给时分」。同一个帖子在列表和详情里
 * 会显示成两个样子（`11-02 09:05` vs `11-2 09:05`），而且两个同名同签名的
 * `formatPostTime` 分居两个模块，导错一个就静默换口径。现在只保留本函数。
 *
 * 规则（按**本地日历日**判定，不是按「是否在 24 小时内」）：
 * - 今天 → `今天 HH:mm`
 * - 昨天 → `昨天 HH:mm`
 * - 同年其它 → `MM-DD HH:mm`（月/日/时/分补零）
 * - 跨年 → `YYYY-MM-DD`（补零）
 * - 时间戳非法（`<= 0` 或非有限值）→ 空串，界面据此不显示时间，不伪造 1970
 *
 * 楼层（主楼与楼中楼）也用它：持有者 2026-11-14 明确「楼层也一起换」，
 * 不再保留「回复只看时分」的例外，窄列由布局自己吸收。
 *
 * 纯函数，可在 Node 用例里固定 `nowMs` 断言。
 */

/** 两位补零（月/日/时/分） */
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
