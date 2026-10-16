import { ProtoReader, WireType } from '../proto/ProtoWire';

export class OfficialMessageSetting {
  uid: string = '';
  name: string = '';
  state: number = -1;
}
export class OfficialMessageSettings {
  code: number = -1;
  message: string = '';
  items: OfficialMessageSetting[] = [];
}
export function officialMessageStateLabel(state: number): string {
  return state === 1 ? '开启' : state === 0 ? '关闭' : '未确认';
}
/** GetOfficialSwitch: error=1, data=2, official_list=1; 不沿用 protobuf 默认开关。 */
export function parseOfficialMessages(bytes: Uint8Array): OfficialMessageSettings {
  const result: OfficialMessageSettings = new OfficialMessageSettings();
  let errorSeen: boolean = false; let dataSeen: boolean = false; let userMessage: string = '';
  const seen: Set<string> = new Set<string>();
  try {
    const root: ProtoReader = new ProtoReader(bytes);
    while (root.hasMore()) {
      const field: number = root.readTag();
      if (field === 1 && root.wireType === WireType.LENGTH_DELIMITED) {
        const error: ProtoReader = root.readMessageView();
        while (error.hasMore()) {
          const tag: number = error.readTag();
          if (tag === 1 && error.wireType === WireType.VARINT) { result.code = error.readInt32(); errorSeen = true; }
          else if (tag === 2 && error.wireType === WireType.LENGTH_DELIMITED) { result.message = error.readString(); }
          else if (tag === 3 && error.wireType === WireType.LENGTH_DELIMITED) { userMessage = error.readString(); }
          else { error.skipField(); }
        }
      } else if (field === 2 && root.wireType === WireType.LENGTH_DELIMITED) {
        dataSeen = true; const data: ProtoReader = root.readMessageView();
        while (data.hasMore()) {
          const tag: number = data.readTag();
          if (tag !== 1 || data.wireType !== WireType.LENGTH_DELIMITED) { data.skipField(); continue; }
          const reader: ProtoReader = data.readMessageView(); const item: OfficialMessageSetting = new OfficialMessageSetting();
          while (reader.hasMore()) {
            const key: number = reader.readTag();
            if (key === 1 && reader.wireType === WireType.VARINT) {
              const uid: bigint = reader.readInt64();
              if (uid > BigInt(0) && uid <= BigInt('9223372036854775807')) { item.uid = uid.toString(); }
            } else if (key === 2 && reader.wireType === WireType.LENGTH_DELIMITED) { item.name = reader.readString(); }
            else if (key === 3 && reader.wireType === WireType.VARINT) {
              const state: number = reader.readInt32(); item.state = state === 0 || state === 1 ? state : -1;
            } else { reader.skipField(); }
          }
          if (item.uid.length > 0 && !seen.has(item.uid)) { seen.add(item.uid); result.items.push(item); }
        }
      } else { root.skipField(); }
    }
    if (userMessage.length > 0) { result.message = userMessage; }
    if (!errorSeen || (result.code === 0 && !dataSeen)) { result.code = -1; result.message = '官方消息设置响应未确认'; }
  } catch (err) { result.code = -1; result.message = '官方消息设置响应解析失败'; }
  if (result.code !== 0) { result.items = []; }
  return result;
}
