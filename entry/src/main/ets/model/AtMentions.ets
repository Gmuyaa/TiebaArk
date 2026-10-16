import { NotifyItem, NotifyResult } from './Notify';
import { portraitUrl } from './ThreadDetail';

interface AtAuthor { id?: string | number; name?: string; name_show?: string; portrait?: string; }
interface AtRow {
  thread_id?: string | number; post_id?: string | number; replyer?: AtAuthor;
  title?: string; content?: string; quote_content?: string; fname?: string;
  time?: number | string; is_floor?: number; hide_fname?: number | string;
}
interface AtPage { has_more?: number | string; current_page?: number | string; }
interface AtEnvelope {
  error_code?: number | string; error_msg?: string;
  at_list?: AtRow[]; reply_list?: AtRow[]; page?: AtPage;
}

function idText(value: string | number | undefined, required: boolean): string {
  if (!required && (value === undefined || value === '' || value === '0' || value === 0)) { return ''; }
  const text: string = typeof value === 'string' ? value :
    typeof value === 'number' && Number.isSafeInteger(value) ? String(value) : '';
  if (!/^[1-9]\d*$/.test(text) || BigInt(text) > BigInt('9223372036854775807')) { throw new Error('通知标识无效'); }
  return text;
}
function safeId(text: string): number { const value: number = Number(text); return Number.isSafeInteger(value) ? value : 0; }
function stringValue(value: string | undefined): string { return typeof value === 'string' ? value : ''; }

export function parseAtMentions(text: string): NotifyResult {
  const out: NotifyResult = new NotifyResult();
  try {
    const raw: AtEnvelope = JSON.parse(text) as AtEnvelope;
    if (raw.error_code !== 0 && raw.error_code !== '0') {
      if (typeof raw.error_code === 'number' && Number.isSafeInteger(raw.error_code)) { out.code = raw.error_code; }
      else if (typeof raw.error_code === 'string' && /^\d+$/.test(raw.error_code) && Number.isSafeInteger(Number(raw.error_code))) { out.code = Number(raw.error_code); }
      out.message = stringValue(raw.error_msg) || '@我的响应未确认'; return out;
    }

    const rows: AtRow[] | undefined = raw.reply_list !== undefined ? raw.reply_list : raw.at_list;
    if (!Array.isArray(rows) || raw.page === undefined || raw.page === null) { throw new Error('通知列表或分页缺失'); }
    if (raw.page.has_more !== 0 && raw.page.has_more !== '0' && raw.page.has_more !== 1 && raw.page.has_more !== '1') { throw new Error('分页未确认'); }
    if (raw.page.current_page !== undefined) {
      if (typeof raw.page.current_page !== 'number' && typeof raw.page.current_page !== 'string') { throw new Error('页码无效'); }
      const page: number = Number(raw.page.current_page);
      if (!Number.isSafeInteger(page) || page < 1) { throw new Error('页码无效'); }
      out.page = page;
    }
    const seen: Set<string> = new Set<string>();
    for (const row of rows) {
      const item: NotifyItem = new NotifyItem(); item.kind = 'at';
      item.threadIdText = idText(row.thread_id, true); item.postIdText = idText(row.post_id, false);
      item.userIdText = idText(row.replyer?.id, false);
      item.threadId = safeId(item.threadIdText); item.postId = safeId(item.postIdText); item.userId = safeId(item.userIdText);
      item.title = stringValue(row.title); item.excerpt = stringValue(row.content); item.quoteContent = stringValue(row.quote_content);
      if (row.hide_fname !== undefined && row.hide_fname !== 0 && row.hide_fname !== '0' && row.hide_fname !== 1 && row.hide_fname !== '1') { throw new Error('吧名隐藏状态无效'); }
      item.forumName = row.hide_fname === 1 || row.hide_fname === '1' ? '' : stringValue(row.fname);
      item.userName = stringValue(row.replyer?.name); item.nameShow = stringValue(row.replyer?.name_show);
      item.portrait = stringValue(row.replyer?.portrait); item.avatar = portraitUrl(item.portrait);
      item.isFloor = row.is_floor === 1 ? 1 : 0;
      if (row.time !== undefined) {
        if (typeof row.time !== 'number' && typeof row.time !== 'string') { throw new Error('时间无效'); }
        const seconds: number = Number(row.time);
        if (!Number.isSafeInteger(seconds) || seconds < 0 || !Number.isSafeInteger(seconds * 1000)) { throw new Error('时间无效'); }
        item.timeMs = seconds * 1000;
      }
      const key: string = `${item.threadIdText}:${item.postIdText}:${item.userIdText}:${item.timeMs}`;
      if (!seen.has(key)) { seen.add(key); out.items.push(item); }
    }
    out.hasMore = raw.page.has_more === 1 || raw.page.has_more === '1'; out.code = 0;
  } catch (err) { out.code = -1; out.message = '@我的响应格式无效'; out.items = []; out.hasMore = false; out.page = 0; }
  return out;
}
