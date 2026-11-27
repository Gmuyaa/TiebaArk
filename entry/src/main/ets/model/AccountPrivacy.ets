/**
 * 账号全局隐私设置（关注与粉丝列表、关注的吧、谁可以评论我的贴子）。
 * 读通道复用 GetPrivateInfo（303016），写通道走 /c/c/friend/setprivate（不带 tid）。
 */
import { ProtoReader, WireType } from '../proto/ProtoWire';

export type AccountPrivacyField = 'follow' | 'like' | 'reply';

export interface AccountPrivacyOption {
  value: number;
  label: string;
}

export const PRIVACY_VISIBILITY_OPTIONS: AccountPrivacyOption[] = [
  { value: 1, label: '完全公开' },
  { value: 2, label: '仅好友可见' },
  { value: 3, label: '仅自己可见' }
];

export const PRIVACY_REPLY_OPTIONS: AccountPrivacyOption[] = [
  { value: 1, label: '所有人' },
  { value: 5, label: '我的粉丝' },
  { value: 6, label: '我关注的人' }
];

export class AccountPrivacy {
  code: number = -1;
  message: string = '';
  /** 关注与粉丝列表：1=完全公开，2=仅好友可见，3=仅自己可见，-1=未确认 */
  follow: number = -1;
  /** 关注的吧：1=完全公开，2=仅好友可见，3=仅自己可见，-1=未确认 */
  like: number = -1;
  /** 谁可以评论我的贴子：1=所有人，5=我的粉丝，6=我关注的人，7=仅自己，-1=未确认 */
  reply: number = -1;

  fieldValue(field: AccountPrivacyField): number {
    if (field === 'follow') { return this.follow; }
    if (field === 'like') { return this.like; }
    return this.reply;
  }
}

export function validAccountPrivacy(field: AccountPrivacyField, value: number): boolean {
  if (field === 'follow' || field === 'like') {
    return value === 1 || value === 2 || value === 3;
  }
  return value === 1 || value === 5 || value === 6;
}

export function accountPrivacyOptions(field: AccountPrivacyField): AccountPrivacyOption[] {
  return field === 'reply' ? PRIVACY_REPLY_OPTIONS : PRIVACY_VISIBILITY_OPTIONS;
}

export function accountPrivacyOptionLabels(field: AccountPrivacyField): string[] {
  return accountPrivacyOptions(field).map((item: AccountPrivacyOption): string => item.label);
}

export function accountPrivacyOptionIndex(field: AccountPrivacyField, value: number): number {
  const options: AccountPrivacyOption[] = accountPrivacyOptions(field);
  for (let i: number = 0; i < options.length; i++) {
    if (options[i].value === value) { return i; }
  }
  return -1;
}

export function accountPrivacyOptionValue(field: AccountPrivacyField, index: number): number {
  const options: AccountPrivacyOption[] = accountPrivacyOptions(field);
  if (index < 0 || index >= options.length) { return -1; }
  return options[index].value;
}

export function accountPrivacyLabel(field: AccountPrivacyField, value: number): string {
  if (field === 'follow' || field === 'like') {
    if (value === 1) { return '完全公开'; }
    if (value === 2) { return '仅好友可见'; }
    if (value === 3) { return '仅自己可见'; }
    return '未确认';
  }
  if (value === 1) { return '所有人'; }
  if (value === 5) { return '我的粉丝'; }
  if (value === 6) { return '我关注的人'; }
  if (value === 7) { return '仅自己'; }
  return '未确认';
}

/** 解析 GetPrivateInfoResIdl（data=1, error=2）中的 like(3)、reply(8)、follow(11)。 */
export function parseAccountPrivacy(bytes: Uint8Array): AccountPrivacy {
  const result: AccountPrivacy = new AccountPrivacy();
  let dataSeen: boolean = false;
  let errorSeen: boolean = false;
  try {
    const reader: ProtoReader = new ProtoReader(bytes);
    while (reader.hasMore()) {
      const tag: number = reader.readTag();
      if (tag === 1 && reader.wireType === WireType.LENGTH_DELIMITED) {
        dataSeen = true;
        const data: ProtoReader = reader.readMessageView();
        while (data.hasMore()) {
          const field: number = data.readTag();
          if (field === 3 && data.wireType === WireType.VARINT) {
            const value: number = data.readInt32();
            result.like = value === 1 || value === 2 || value === 3 ? value : -1;
          } else if (field === 8 && data.wireType === WireType.VARINT) {
            const value: number = data.readInt32();
            // 官方 ql8.w() 将 0 归为 1（所有人）；未知值不猜默认。
            if (value === 0) {
              result.reply = 1;
            } else if (value === 1 || value === 5 || value === 6 || value === 7) {
              result.reply = value;
            } else {
              result.reply = -1;
            }
          } else if (field === 11 && data.wireType === WireType.VARINT) {
            const value: number = data.readInt32();
            result.follow = value === 1 || value === 2 || value === 3 ? value : -1;
          } else {
            data.skipField();
          }
        }
      } else if (tag === 2 && reader.wireType === WireType.LENGTH_DELIMITED) {
        const error: ProtoReader = reader.readMessageView();
        while (error.hasMore()) {
          const field: number = error.readTag();
          if (field === 1 && error.wireType === WireType.VARINT) {
            result.code = error.readInt32();
            errorSeen = true;
          } else if (field === 2 && error.wireType === WireType.LENGTH_DELIMITED) {
            result.message = error.readString();
          } else {
            error.skipField();
          }
        }
      } else {
        reader.skipField();
      }
    }
    if (!errorSeen || (result.code === 0 && !dataSeen)) {
      result.code = -1;
      result.message = '隐私设置响应未确认';
    }
  } catch (err) {
    result.code = -1;
    result.message = '隐私设置响应格式无效';
  }
  if (result.code !== 0) {
    result.follow = -1;
    result.like = -1;
    result.reply = -1;
  }
  return result;
}
