/** D-03 当前 APK AtListActivity/emf/BaseMetaData；账号名与展示昵称分别保留。 */
export type AtCandidateKind = 'search';
export class AtCandidate {
  id: string = '';
  name: string = '';
  displayName: string = '';
  portrait: string = '';
}
/** 当前原生普通@：编辑显示、保存文本和发送文本不同；不代表服务端已通知成功。 */
export class AtEditorMention {
  readonly id: string;
  readonly displayText: string;
  readonly draftText: string;
  readonly serverText: string;
  constructor(id: string, portrait: string, displayName: string) {
    this.id = id;
    this.displayText = `@${displayName} `;
    // um6.s/x保留UID；um6.t（SpanGroupManager.E）发送时不带UID。
    this.draftText = `#(at, ${portrait}, ${displayName}, ${id}) `;
    this.serverText = `#(at, ${portrait}, ${displayName}) `;
  }
}
/** 只为普通搜索候选准备；字段不能注入逗号/括号或控制字符，不猜转义规则。 */
export function prepareAtMention(candidate: AtCandidate): AtEditorMention | undefined {
  if (!/^[1-9]\d*$/.test(candidate.id) || candidate.id.length > 19 ||
    BigInt(candidate.id) > BigInt('9223372036854775807')) { return undefined; }
  if (candidate.portrait.length === 0 || candidate.portrait.length > 1024 ||
    /[\s,()\u0000-\u001f\u007f]/.test(candidate.portrait)) { return undefined; }
  if (candidate.displayName.trim().length === 0 || candidate.displayName.length > 256 ||
    /[,()\u0000-\u001f\u007f]/.test(candidate.displayName)) { return undefined; }
  // 快照三个字符串；账号名不能替代展示昵称，ID不经Number。
  return new AtEditorMention(candidate.id, candidate.portrait, candidate.displayName);
}
export class AtCandidates {
  code: number = -1;
  message: string = '';
  items: AtCandidate[] = [];
}
interface RawAtUser { id?: string | number; name?: string; name_show?: string; portrait?: string; }
interface RawAtResponse { error_code?: number | string; error_msg?: string; user_list?: RawAtUser[]; }
export function validAtKind(kind: AtCandidateKind): boolean {
  return kind === 'search';
}
export function parseAtCandidates(text: string): AtCandidates {
  const result: AtCandidates = new AtCandidates();
  try {
    const raw: RawAtResponse = JSON.parse(text) as RawAtResponse;
    if (raw.error_code !== 0 && raw.error_code !== '0') {
      if (typeof raw.error_code === 'number' && Number.isInteger(raw.error_code)) { result.code = raw.error_code; }
      else if (typeof raw.error_code === 'string' && /^\d+$/.test(raw.error_code)) { result.code = Number(raw.error_code); }
      result.message = typeof raw.error_msg === 'string' ? raw.error_msg : '选人响应未确认'; return result;
    }
    if (!Array.isArray(raw.user_list)) { result.message = '选人列表缺失'; return result; }
    const seen: Set<string> = new Set<string>();
    for (const row of raw.user_list) {
      let id: string = '';
      if (typeof row.id === 'string' && /^[1-9]\d*$/.test(row.id)) { id = row.id; }
      else if (typeof row.id === 'number' && Number.isSafeInteger(row.id) && row.id > 0) { id = String(row.id); }
      if (id.length === 0 || BigInt(id) > BigInt('9223372036854775807')) { throw new Error('选人标识无效'); }
      if (seen.has(id)) { continue; }
      if (typeof row.name_show !== 'string' || row.name_show.trim().length === 0) { throw new Error('选人昵称缺失'); }
      const item: AtCandidate = new AtCandidate(); item.id = id; item.displayName = row.name_show;
      item.name = typeof row.name === 'string' ? row.name : '';
      item.portrait = typeof row.portrait === 'string' ? row.portrait : '';
      result.items.push(item); seen.add(id);
    }
    result.code = 0;
  } catch (err) { result.code = -1; result.message = '选人响应格式无效'; result.items = []; }
  return result;
}
