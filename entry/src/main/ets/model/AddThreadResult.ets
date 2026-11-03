/**
 * 发主题帖 `/c/c/thread/add`（表单通道）的响应解析。
 *
 * 纯逻辑，不 import `@kit.*`：Node 校验与真机跑同一份（见 `tools/verify/check-compose-publish.mjs`）。
 *
 * 协议形态来自参考实现（`references/code-audit-2026-10-11/ref-audit/t137458`
 * 的 `api/TiebaAPI.ets` `addThread`）：网页通道回 JSON，判定只看 `error_code`。
 * 这里的解析**比参考实现宽一点**，但不伪造成功：
 * - 结果码依次尝试 `error_code` → `no`；两者都没有算"响应不可判定"，不当成成功；
 * - `tid`/`pid` 只是锦上添花（拿来跳转新帖），取不到不影响发布判定；
 * - 超过 2^53-1 的 id 保留原文不转 number，交给调用方显示，避免静默丢精度。
 */

/** 本地解析失败码，与 `ApiResult` 的本地失败区间一致。 */
export const ADD_THREAD_LOCAL: number = -1;

interface RawAddThreadData {
  tid?: number | string;
  thread_id?: number | string;
  pid?: number | string;
  post_id?: number | string;
  /** 部分通道回 `forum_id`；本项目不依赖它，保留给排查 */
  forum_id?: number | string;
}

interface RawAddThreadResponse {
  error_code?: number | string;
  error_msg?: string;
  /** 网页通道常见形态之一 */
  no?: number | string;
  error?: string;
  data?: RawAddThreadData;
  tid?: number | string;
  thread_id?: number | string;
  pid?: number | string;
  post_id?: number | string;
}

export class AddThreadResult {
  /** 服务端结果码；0 = 受理。解析不出结果码时为 `ADD_THREAD_LOCAL` */
  code: number = ADD_THREAD_LOCAL;
  /** 服务端文案或本地解析说明 */
  message: string = '';
  /** 新帖 id；0 = 响应里没有或不可安全转换 */
  tid: number = 0;
  /** 新帖首楼 id；0 = 响应里没有或不可安全转换 */
  pid: number = 0;
  /** 原样保留的 id 文本（大整数不丢精度） */
  tidText: string = '';
  pidText: string = '';

  accepted(): boolean { return this.code === 0; }

  describeFailure(): string {
    if (this.accepted()) { return ''; }
    if (this.code === ADD_THREAD_LOCAL) { return this.message.length > 0 ? this.message : '发布响应无法判定'; }
    return `贴吧返回错误 ${this.code}：${this.message}`;
  }
}

/** 结果码：数字或纯数字串才算数，其它形态一律视为不可判定（不退化成"成功"）。 */
function readCode(raw: number | string | undefined): number | undefined {
  if (raw === undefined || raw === null) { return undefined; }
  if (typeof raw === 'number') {
    return Number.isInteger(raw) ? raw : undefined;
  }
  if (typeof raw !== 'string') { return undefined; }
  const text: string = raw.trim();
  if (!/^-?\d+$/.test(text)) { return undefined; }
  const value: number = Number(text);
  return Number.isSafeInteger(value) ? value : undefined;
}

/**
 * id 文本归一：字符串原样、数字转字符串。
 * 只有能安全落进 number 的才给出数值，否则数值留 0，文本照留 —— 不静默截断。
 */
function readId(raw: number | string | undefined): string {
  if (raw === undefined || raw === null) { return ''; }
  if (typeof raw === 'number') {
    return Number.isSafeInteger(raw) && raw > 0 ? String(raw) : '';
  }
  if (typeof raw !== 'string') { return ''; }
  const text: string = raw.trim();
  return /^\d+$/.test(text) && text !== '0' ? text : '';
}

function idNumber(text: string): number {
  if (text.length === 0) { return 0; }
  const value: number = Number(text);
  return Number.isSafeInteger(value) ? value : 0;
}

/** 先取 id 文本，再按需降级成 number。 */
function pickFirstId(primary: number | string | undefined,
  secondary: number | string | undefined): string {
  const first: string = readId(primary);
  return first.length > 0 ? first : readId(secondary);
}

/** 解析 `/c/c/thread/add` 的响应文本。 */
export function parseAddThreadResponse(text: string): AddThreadResult {
  const result: AddThreadResult = new AddThreadResult();
  if (text.length === 0) {
    result.message = '发布响应为空';
    return result;
  }

  let raw: RawAddThreadResponse;
  try {
    raw = JSON.parse(text) as RawAddThreadResponse;
  } catch (err) {
    result.message = '发布响应不是合法 JSON';
    return result;
  }
  if (raw === null || typeof raw !== 'object') {
    result.message = '发布响应结构异常';
    return result;
  }

  const hasCode: boolean = raw.error_code !== undefined || raw.no !== undefined;
  const code: number | undefined = raw.error_code !== undefined ? readCode(raw.error_code) : readCode(raw.no);
  if (code === undefined) {
    result.message = hasCode ? '发布响应结果码无效' : '发布响应缺少可判定的结果码';
    return result;
  }
  result.code = code;
  if (raw.error_msg !== undefined && typeof raw.error_msg === 'string') { result.message = raw.error_msg; }
  else if (raw.error !== undefined && typeof raw.error === 'string') { result.message = raw.error; }

  const data: RawAddThreadData | undefined = raw.data !== null && typeof raw.data === 'object' &&
    !Array.isArray(raw.data) ? raw.data : undefined;
  result.tidText = pickFirstId(data !== undefined ? (data.tid !== undefined ? data.tid : data.thread_id) : undefined,
    raw.tid !== undefined ? raw.tid : raw.thread_id);
  result.pidText = pickFirstId(data !== undefined ? (data.pid !== undefined ? data.pid : data.post_id) : undefined,
    raw.pid !== undefined ? raw.pid : raw.post_id);
  result.tid = idNumber(result.tidText);
  result.pid = idNumber(result.pidText);
  return result;
}
