
export type MessageSettingField = 'maskType' | 'pushType';

interface RawMessageSettings {
  error_code?: number | string;
  error_msg?: string;
  data?: number | string;
  need_push?: number | string;
}

export class MessageSettings {
  maskType: number = -1;
  pushType: number = -1;
}

export function validMessageSetting(field: MessageSettingField, value: number): boolean {
  return field === 'maskType' ? value === 0 || value === 1 || value === 3 : value === 1 || value === 2;
}

function settingNumber(raw: number | string | undefined): number {
  if (typeof raw === 'number') { return Number.isInteger(raw) ? raw : -1; }
  if (typeof raw === 'string' && /^\d+$/.test(raw)) { return Number(raw); }
  return -1;
}

export function parseMessageSettings(text: string): MessageSettings {
  const result: MessageSettings = new MessageSettings();
  try {
    const raw: RawMessageSettings = JSON.parse(text) as RawMessageSettings;

    if (settingNumber(raw.error_code) !== 0) { return result; }
    const mask: number = settingNumber(raw.data);
    const push: number = settingNumber(raw.need_push);
    if (validMessageSetting('maskType', mask)) { result.maskType = mask; }
    if (validMessageSetting('pushType', push)) { result.pushType = push; }
  } catch (err) {  }
  return result;
}

export function messageMaskLabel(value: number): string {
  if (value === 0) { return '接收全部私信'; }
  if (value === 1) { return '拒收陌生人私信'; }
  if (value === 3) { return '拒收全部私信'; }
  return '未确认';
}

export function messagePushLabel(value: number): string {
  if (value === 1) { return '开启'; }
  if (value === 2) { return '关闭'; }
  return '未确认';
}
