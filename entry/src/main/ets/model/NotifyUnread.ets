/** /c/s/msg 的四类未读计数；不从历史列表长度推算，不把缺失字段当成零。 */
import { NotifyItem } from './Notify';
export type NotifyUnreadKind = 'agree' | 'reply' | 'at' | 'fans';

interface RawUnreadMessage {
  agree?: number | string;
  replyme?: number | string;
  atme?: number | string;
  fans?: number | string;
}
interface RawUnreadEnvelope {
  error_code?: number | string;
  message?: RawUnreadMessage;
}

export class NotifyUnreadCounts {
  agree: number = 0;
  reply: number = 0;
  at: number = 0;
  fans: number = 0;

  count(kind: NotifyUnreadKind): number {
    if (kind === 'agree') { return this.agree; }
    if (kind === 'reply') { return this.reply; }
    return kind === 'at' ? this.at : this.fans;
  }

  /** 底栏汇总采用饱和相加，避免合法单项相加后越过安全整数范围。 */
  total(): number {
    let total: number = 0;
    const counts: number[] = [this.agree, this.reply, this.at, this.fans];
    for (const count of counts) {
      if (count > Number.MAX_SAFE_INTEGER - total) { return Number.MAX_SAFE_INTEGER; }
      total += count;
    }
    return total;
  }
}

/** 当前账号会话内仅保留主动查看取得的四条动作摘要，不保存通知正文或落盘。 */
export class NotifyPreviews {
  agree: string = '';
  reply: string = '';
  at: string = '';
  fans: string = '';
  text(kind: NotifyUnreadKind): string {
    if (kind === 'agree') { return this.agree; }
    if (kind === 'reply') { return this.reply; }
    return kind === 'at' ? this.at : this.fans;
  }
}

export function notifyActionPreview(item: NotifyItem | undefined): string {
  if (item === undefined) { return '没有最新消息'; }
  const name: string = item.displayName();
  if (item.kind === 'agree') { return `${name}赞了你的${item.hasPost ? '回复' : '帖子'}`; }
  if (item.kind === 'at') { return `${name}提到了你`; }
  return item.isFloor === 1 ? `${name}回复了你的评论` : `${name}评论了你的帖子`;
}

export function fanActionPreview(name: string | undefined, preface: string = ''): string {
  if (name === undefined && preface.length > 0 && preface !== '仅展示登录粉丝和正常账号') { return preface; }
  return name === undefined ? '没有最新消息' : `${name || '贴吧用户'}关注了你`;
}

export class NotifyUnreadResult {
  code: number = -1;
  message: string = '新消息提醒响应未确认';
  counts: NotifyUnreadCounts = new NotifyUnreadCounts();
}

function countValue(value: number | string | undefined): number {
  if (typeof value !== 'number' && (typeof value !== 'string' || !/^\d+$/.test(value))) {
    throw new Error('未读数缺失或无效');
  }
  const count: number = Number(value);
  if (!Number.isSafeInteger(count) || count < 0) { throw new Error('未读数无效'); }
  return count;
}

export function parseNotifyUnread(text: string): NotifyUnreadResult {
  const out: NotifyUnreadResult = new NotifyUnreadResult();
  try {
    const raw: RawUnreadEnvelope = JSON.parse(text) as RawUnreadEnvelope;
    if (raw.error_code !== 0 && raw.error_code !== '0') { return out; }
    const message: RawUnreadMessage | undefined = raw.message;
    if (message === undefined || message === null || Array.isArray(message)) { return out; }
    const counts: NotifyUnreadCounts = new NotifyUnreadCounts();
    counts.agree = countValue(message.agree);
    counts.reply = countValue(message.replyme);
    counts.at = countValue(message.atme);
    counts.fans = countValue(message.fans);
    out.counts = counts; out.code = 0; out.message = '';
  } catch (err) { /* 保留失败；畸形响应不发布部分计数。 */ }
  return out;
}
