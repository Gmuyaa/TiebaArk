
import { ProtoReader, WireType } from '../proto/ProtoWire';

export type PrivacyMarkField = 'bazhu_show_inside' | 'bazhu_show_outside';
export function validPrivacyMark(field: PrivacyMarkField, value: number): boolean {
  return (field === 'bazhu_show_inside' || field === 'bazhu_show_outside') && (value === 1 || value === 3);
}

interface PrivacyWriteEnvelope { error_code?: number | string; }
export function privacyWriteConfirmed(text: string): boolean {
  try {
    const raw: PrivacyWriteEnvelope = JSON.parse(text) as PrivacyWriteEnvelope;
    return raw.error_code === 0 || raw.error_code === '0';
  } catch (err) { return false; }
}

export class PrivacyMarks {
  code: number = -1;
  message: string = '';
  inside: number = -1;
  outside: number = -1;
}

export function privacyMarkLabel(value: number): string {
  if (value === 1) { return '显示'; }
  if (value === 3) { return '隐藏'; }
  return '未确认';
}

export function parsePrivacyMarks(bytes: Uint8Array): PrivacyMarks {
  const result: PrivacyMarks = new PrivacyMarks();
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
          if ((field === 9 || field === 10) && data.wireType === WireType.VARINT) {
            const value: number = data.readInt32();
            const confirmed: number = value === 1 || value === 3 ? value : -1;
            if (field === 9) { result.inside = confirmed; } else { result.outside = confirmed; }
          } else { data.skipField(); }
        }
      } else if (tag === 2 && reader.wireType === WireType.LENGTH_DELIMITED) {
        const error: ProtoReader = reader.readMessageView();
        while (error.hasMore()) {
          const field: number = error.readTag();
          if (field === 1 && error.wireType === WireType.VARINT) { result.code = error.readInt32(); errorSeen = true; }
          else if (field === 2 && error.wireType === WireType.LENGTH_DELIMITED) { result.message = error.readString(); }
          else { error.skipField(); }
        }
      } else { reader.skipField(); }
    }
    if (!errorSeen || (result.code === 0 && !dataSeen)) { result.code = -1; result.message = '隐私标记响应未确认'; }
  } catch (err) { result.code = -1; result.message = '隐私标记响应格式无效'; }
  if (result.code !== 0) { result.inside = -1; result.outside = -1; }
  return result;
}
