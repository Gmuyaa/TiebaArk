
import { ProtoReader, WireType } from '../proto/ProtoWire';
import { normalizeForumName } from './ThreadBlock';

export class ForbiddenForum {
  id: string = '';
  name: string = '';

  avatar: string = '';
}

export class ForbiddenForums {
  code: number = -1;
  message: string = '';
  items: ForbiddenForum[] = [];
  hasMore: boolean = false;
  page: number = 0;
}

export function mergeForbiddenForums(before: ForbiddenForum[], incoming: ForbiddenForum[]): ForbiddenForum[] {
  const result: ForbiddenForum[] = [];
  const ids: Set<string> = new Set<string>();
  for (const item of before.concat(incoming)) {
    if (!ids.has(item.id)) { ids.add(item.id); result.push(item); }
  }
  return result;
}

export function forbiddenForumsContain(items: ForbiddenForum[], forumId: number,
  forumName: string): boolean {
  const id: string = Number.isSafeInteger(forumId) && forumId > 0 ? String(forumId) : '';
  const name: string = normalizeForumName(forumName);
  for (const item of items) {
    if (id.length > 0 && item.id === id) { return true; }
    if (name.length > 0 && normalizeForumName(item.name) === name) { return true; }
  }
  return false;
}

function readForum(reader: ProtoReader): ForbiddenForum {
  const item: ForbiddenForum = new ForbiddenForum();
  while (reader.hasMore()) {
    const tag: number = reader.readTag();
    if (tag === 1 && reader.wireType === WireType.VARINT) {
      const id: bigint = reader.readUint64();
      if (id <= BigInt(0) || id > BigInt('9223372036854775807')) { throw new Error('屏蔽吧标识无效'); }
      item.id = id.toString();
    } else if (tag === 2 && reader.wireType === WireType.LENGTH_DELIMITED) { item.name = reader.readString(); }
    else if (tag === 3 && reader.wireType === WireType.LENGTH_DELIMITED) { item.avatar = reader.readString(); }
    else { reader.skipField(); }
  }
  if (item.id.length === 0) { throw new Error('屏蔽吧标识缺失'); }
  return item;
}

export function parseForbiddenForums(bytes: Uint8Array): ForbiddenForums {
  const result: ForbiddenForums = new ForbiddenForums();
  let errorSeen: boolean = false;
  let dataSeen: boolean = false;
  try {
    const reader: ProtoReader = new ProtoReader(bytes);
    while (reader.hasMore()) {
      const tag: number = reader.readTag();
      if (tag === 1 && reader.wireType === WireType.LENGTH_DELIMITED) {
        const error: ProtoReader = reader.readMessageView();
        while (error.hasMore()) {
          const field: number = error.readTag();
          if (field === 1 && error.wireType === WireType.VARINT) { result.code = error.readInt32(); errorSeen = true; }
          else if (field === 2 && error.wireType === WireType.LENGTH_DELIMITED) { result.message = error.readString(); }
          else { error.skipField(); }
        }
      } else if (tag === 2 && reader.wireType === WireType.LENGTH_DELIMITED) {
        dataSeen = true;
        const data: ProtoReader = reader.readMessageView();
        while (data.hasMore()) {
          const field: number = data.readTag();
          if (field === 1 && data.wireType === WireType.LENGTH_DELIMITED) { result.items.push(readForum(data.readMessageView())); }
          else if (field === 2 && data.wireType === WireType.VARINT) {
            const value: number = data.readInt32();
            if (value !== 0 && value !== 1) { throw new Error('屏蔽吧续页状态无效'); }
            result.hasMore = value === 1;
          } else if (field === 3 && data.wireType === WireType.VARINT) {
            result.page = data.readInt32();
            if (result.page < 0) { throw new Error('屏蔽吧页码无效'); }
          } else { data.skipField(); }
        }
      } else { reader.skipField(); }
    }
    if (!errorSeen || (result.code === 0 && !dataSeen)) { result.code = -1; result.message = '屏蔽吧读取响应未确认'; }
  } catch (err) { result.code = -1; result.message = '屏蔽吧响应格式无效'; }
  if (result.code !== 0) { result.items = []; result.hasMore = false; result.page = 0; }
  else { result.items = mergeForbiddenForums([], result.items); }
  return result;
}
