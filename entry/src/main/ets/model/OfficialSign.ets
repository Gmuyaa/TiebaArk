import { SignStats } from './SignStats';

interface SignError { errno?: number | string; err_no?: number | string; errmsg?: string; usermsg?: string; }
interface SignEntry {
  forum_id?: number | string;
  signed?: number | string;
  sign_day_count?: number | string;
  error?: SignError;
}
interface SignEnvelope {
  error?: SignError;
  error_code?: number | string;
  error_msg?: string;
  is_timeout?: number | string;
  timeout_notice?: string;
  sign_notice?: string;
  info?: SignEntry[];
  level?: number | string;
  forum_info?: CapabilityEntry[];
  can_use?: number | string;
}
interface CapabilityEntry { forum_id?: number | string; user_level?: number | string; }

export class OfficialSignEligibility {
  fid: string = '';
  level: number = -1;
}
export class OfficialSignCapability {
  minimumLevel: number = -1;
  canUseAll: boolean = false;
  forums: OfficialSignEligibility[] = [];
  error: string = '';
  schema: string = '';
}

export class OfficialSignItem {
  fid: string = '';
  signed: boolean = false;
  confirmed: boolean = false;
  stats: SignStats = new SignStats();
}

export class OfficialSignResult {
  items: OfficialSignItem[] = [];
  error: string = '';
  notice: string = '';
  /** 仅固定字段类型/数值状态，不包含账号、吧 ID 或原始响应。 */
  schema: string = '';
}

function integer(value: number | string | undefined): number {
  if (typeof value !== 'number' && (typeof value !== 'string' || !/^\d+$/.test(value))) { return -1; }
  const n: number = Number(value);
  return Number.isSafeInteger(n) && n >= 0 ? n : -1;
}
function message(value: string | undefined): string { return typeof value === 'string' ? value : ''; }
function itemErrorCode(error: SignError | undefined): number {
  if (error === undefined) { return 0; }
  if (error.errno === undefined && error.err_no === undefined) { return -1; }
  const codes: number[] = [];
  if (error.errno !== undefined) { codes.push(integer(error.errno)); }
  if (error.err_no !== undefined) { codes.push(integer(error.err_no)); }
  if (codes.some((value: number): boolean => value < 0)) { return -1; }
  return codes.find((value: number): boolean => value > 0) ?? 0;
}

/** 当前 22.11 upe/vpe/mpe：根 error.errno 与 error_code、逐项 signed/error 分开裁决。 */
export function parseOfficialSign(source: string): OfficialSignResult {
  const result: OfficialSignResult = new OfficialSignResult();
  try {
    const raw: SignEnvelope = JSON.parse(source) as SignEnvelope;
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) { throw new Error('invalid envelope'); }
    const nested: number = integer(raw.error?.errno);
    const top: number = integer(raw.error_code);
    result.schema = `error:${typeof raw.error};errno:${nested};code:${top};timeout:${integer(raw.is_timeout)};info:${Array.isArray(raw.info) ? raw.info.length : -1};keys:${Object.keys(raw).filter((key: string): boolean => /^[a-z_]{1,32}$/.test(key)).join(',')}`;
    // JSON 客户端通道允许顶层 error_code；所有出现的错误层都必须显式成功，不能默认缺失为 0。
    if ((raw.error === undefined && raw.error_code === undefined) ||
      (raw.error !== undefined && nested !== 0) || (raw.error_code !== undefined && top !== 0)) {
      const code: number = nested > 0 ? nested : top;
      result.error = message(raw.error?.usermsg) || message(raw.error?.errmsg) || message(raw.error_msg) ||
        (code > 0 ? `官方签到返回错误 ${code}` : '官方签到返回错误或结果未确认');
      return result;
    }
    if (raw.is_timeout !== undefined && integer(raw.is_timeout) !== 0) {
      result.error = message(raw.timeout_notice) || '官方签到超时，请刷新确认结果'; return result;
    }
    if (!Array.isArray(raw.info)) { result.error = '官方签到未返回逐项结果，请刷新确认'; return result; }
    result.notice = typeof raw.sign_notice === 'string' ? raw.sign_notice : '';
    const seen: Set<string> = new Set();
    const duplicates: Set<string> = new Set();
    for (const entry of raw.info) {
      if (!entry || typeof entry !== 'object') { continue; }
      const fid: number = integer(entry.forum_id);
      if (fid <= 0) { continue; }
      const id: string = String(fid);
      if (seen.has(id)) { duplicates.add(id); continue; }
      seen.add(id);
      const item: OfficialSignItem = new OfficialSignItem(); item.fid = id;
      const itemCode: number = itemErrorCode(entry.error);
      item.confirmed = (integer(entry.signed) === 0 || integer(entry.signed) === 1) &&
        itemCode >= 0;
      item.signed = integer(entry.signed) === 1 && itemCode === 0;
      // sign_day_count 是官方本次响应的连续天数；不据此推算累计次数或经验。
      const days: number = integer(entry.sign_day_count);
      if (item.signed && days >= 0 && days <= 4294967295) { item.stats.continuousCount = days; }
      result.items.push(item);
    }
    result.items = result.items.filter((item: OfficialSignItem): boolean => !duplicates.has(item.fid));
  } catch (_) { result.error = '官方签到响应格式异常，请刷新确认结果'; }
  return result;
}

/** getforumlist 仅用于条件预检查，不以该响应替换完整关注列表或冒充分页已完整。 */
export function parseOfficialSignCapability(source: string): OfficialSignCapability {
  const result: OfficialSignCapability = new OfficialSignCapability();
  try {
    const raw: SignEnvelope = JSON.parse(source) as SignEnvelope;
    const checked: OfficialSignResult = parseOfficialSign(source);
    result.schema = checked.schema;
    // 读取接口没有 info；单独检查已出现的错误层及明确成功码。
    if (!raw || (raw.error === undefined && raw.error_code === undefined) ||
      (raw.error !== undefined && integer(raw.error?.errno) !== 0) ||
      (raw.error_code !== undefined && integer(raw.error_code) !== 0)) {
      result.error = message(raw?.error?.usermsg) || message(raw?.error?.errmsg) || message(raw?.error_msg) || '官方签到条件读取失败'; return result;
    }
    result.minimumLevel = integer(raw.level);
    result.canUseAll = integer(raw.can_use) === 1;
    if (result.minimumLevel < 0 || !Array.isArray(raw.forum_info)) {
      result.error = '服务端未返回官方签到条件，未发送签到请求'; return result;
    }
    const seen: Set<string> = new Set();
    for (const forum of raw.forum_info) {
      if (!forum || typeof forum !== 'object') { continue; }
      const id: number = integer(forum.forum_id);
      if (id <= 0) { continue; }
      const item: OfficialSignEligibility = new OfficialSignEligibility(); item.fid = String(id); item.level = integer(forum.user_level);
      if (seen.has(item.fid)) { result.error = '官方签到条件含重复吧，未发送签到请求'; return result; }
      seen.add(item.fid); result.forums.push(item);
    }
  } catch (_) { result.error = '官方签到条件格式异常，未发送签到请求'; }
  return result;
}
