import { profilePortrait } from './PageDirectory';
import { cleanTitle } from './SearchPost';
import { portraitUrl } from './ThreadDetail';

/** 公开网页搜人响应。id 属于另一身份空间，不能用作贴吧 uid。 */
interface RawSearchUser {
  tieba_uid?: string | number;
  name?: string;
  user_nickname?: string;
  show_nickname?: string;
  portrait?: string;
  intro?: string;
}
interface RawUserSearchData {
  pn?: number | string;
  has_more?: number | string;
  exactMatch?: RawSearchUser | RawSearchUser[];
  fuzzyMatch?: RawSearchUser[];
}
interface RawUserSearch {
  no?: number | string;
  error?: string;
  data?: RawUserSearchData;
}

function cleanText(value: string | undefined): string {
  return typeof value === 'string' ? cleanTitle(value).trim() : '';
}

function searchPortrait(value: string | undefined): string {
  if (typeof value !== 'string') { return ''; }
  const token: string = profilePortrait(value);
  if (token.length > 0) { return token.split('?')[0]; }
  // 公开搜索当前使用的百度 CDN，提取后统一走已有的头像/用户主页身份通路。
  const match: RegExpMatchArray | null = value.match(
    /^https:\/\/gss0\.bdstatic\.com\/6LZ1dD3d1sgCo2Kml5_Y_D3\/sys\/portrait\/item\/([A-Za-z0-9_.-]+)(?:\?|$)/);
  return match === null ? '' : match[1];
}

export class UserSearchItem {
  /** 原始十进制贴吧 ID 保留字符串，去重不经过有损数值转换。 */
  id: string = '';
  uid: number = 0;
  portrait: string = '';
  avatar: string = '';
  name: string = '';
  intro: string = '';

  key(): string { return this.id.length > 0 ? `uid:${this.id}` : `portrait:${this.portrait}`; }
}

export class UserSearchPage {
  items: UserSearchItem[] = [];
  page: number = 1;
  hasMore: boolean = false;
}

export class UserSearchParseResult {
  ok: boolean = false;
  /** -1 为本地格式异常，其他非零值为服务端业务失败。 */
  errorCode: number = -1;
  error: string = '搜人响应格式异常，请重试';
  data: UserSearchPage = new UserSearchPage();
}

function decimalUid(value: string | number | undefined): string {
  if (typeof value === 'number' && (!Number.isSafeInteger(value) || value <= 0)) { return ''; }
  const text: string = value === undefined ? '' : String(value);
  return /^[1-9][0-9]*$/.test(text) ? text : '';
}

/** 业务成功码和列表结构都必须明确存在；格式异常不能冒充“没有找到用户”。 */
export function parseUserSearch(json: string): UserSearchParseResult {
  const result: UserSearchParseResult = new UserSearchParseResult();
  let raw: RawUserSearch;
  try { raw = JSON.parse(json) as RawUserSearch; } catch (_) { return result; }
  if (raw === null || typeof raw !== 'object' || (typeof raw.no !== 'number' && typeof raw.no !== 'string')) { return result; }
  const code: number = Number(raw.no);
  if (!Number.isInteger(code) || String(raw.no).trim().length === 0) { return result; }
  if (code !== 0) {
    result.errorCode = code;
    result.error = cleanText(raw.error);
    return result;
  }
  const data: RawUserSearchData | undefined = raw.data;
  if (data === undefined || data === null || typeof data !== 'object' || !Array.isArray(data.fuzzyMatch)
    || data.exactMatch === undefined || data.exactMatch === null || typeof data.exactMatch !== 'object') { return result; }
  if (typeof data.pn !== 'number' && typeof data.pn !== 'string') { return result; }
  const page: number = Number(data.pn);
  if (!Number.isInteger(page) || page < 1 || (data.has_more !== 0 && data.has_more !== 1
    && data.has_more !== '0' && data.has_more !== '1')) { return result; }
  const exact: RawSearchUser[] = Array.isArray(data.exactMatch) ? data.exactMatch as RawSearchUser[] : [data.exactMatch];
  const rows: RawSearchUser[] = exact.concat(data.fuzzyMatch);
  const seenIds: Set<string> = new Set<string>();
  const seenPortraits: Set<string> = new Set<string>();
  for (const row of rows) {
    if (row === null || typeof row !== 'object') { continue; }
    const item: UserSearchItem = new UserSearchItem();
    item.id = decimalUid(row.tieba_uid);
    const uid: number = Number(item.id);
    item.uid = Number.isSafeInteger(uid) && uid > 0 ? uid : 0;
    item.portrait = searchPortrait(row.portrait);
    // 不安全的大 ID 仍可用 portrait 解析身份；两者都不可用时不展示不可打开的条目。
    if (item.uid === 0 && item.portrait.length === 0) { continue; }
    item.name = cleanText(row.show_nickname) || cleanText(row.user_nickname) || cleanText(row.name);
    if (item.name.length === 0) { continue; }
    if ((item.id.length > 0 && seenIds.has(item.id))
      || (item.portrait.length > 0 && seenPortraits.has(item.portrait))) { continue; }
    if (item.id.length > 0) { seenIds.add(item.id); }
    if (item.portrait.length > 0) { seenPortraits.add(item.portrait); }
    item.avatar = portraitUrl(item.portrait);
    item.intro = cleanText(row.intro);
    result.data.items.push(item);
  }
  if (rows.length > 0 && result.data.items.length === 0) { return result; }
  result.data.page = page;
  result.data.hasMore = Number(data.has_more) === 1;
  result.ok = true;
  result.errorCode = 0;
  result.error = '';
  return result;
}
