
import { ProtoReader, WireType } from '../proto/ProtoWire';

export class TailItem {
  id: number = 0;
  content: string = '';
  selected: number = -1;
  fontColor: string = '';
  fontKeyName: string = '';
}

export class TailList {
  code: number = -1;
  message: string = '';
  items: TailItem[] = [];
  colors: string[] = [];
  defaultColor: string = '';
}

export type TailAction = 'add' | 'update' | 'set' | 'delete';

export class TailChange {
  action: TailAction = 'add';
  id: number = 0;
  content: string = '';
  fontColor: string = '';
  fontKeyName: string = '';
  type: number = -1;
}

export class TailWriteResult {
  code: number = -1;
  message: string = '';

  id: string = '';
}

export function validTailId(id: number): boolean {
  return Number.isInteger(id) && id > 0 && id <= 4294967295;
}

export function tailChangeError(change: TailChange): string {
  if (change.action !== 'add' && change.action !== 'update' && change.action !== 'set' && change.action !== 'delete') {
    return '不支持的小尾巴操作';
  }
  if (change.action !== 'add' && !validTailId(change.id)) { return '小尾巴标识无效'; }
  if (change.action === 'set' && change.type !== 0 && change.type !== 1) { return '小尾巴启用状态无效'; }
  if (change.action === 'add' || change.action === 'update') {
    if (change.content.trim().length === 0) { return '小尾巴内容不能为空'; }
    if (tailContentLength(change.content) > 50) { return '小尾巴内容最多 50 个字符，表情按一个字符计'; }
    if (/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(change.content)) { return '小尾巴内容含无效字符'; }
    if (change.fontColor.length > 0 && tailColor(change.fontColor).length === 0) { return '小尾巴颜色无效'; }
  }
  return '';
}

export function tailContentLength(content: string): number {
  return content.replace(/#\([^#)(]+\)/g, ' ').length;
}

export function parseTailWrite(bytes: Uint8Array): TailWriteResult {
  const result: TailWriteResult = new TailWriteResult();
  let errorSeen: boolean = false;
  try {
    const reader: ProtoReader = new ProtoReader(bytes);
    while (reader.hasMore()) {
      const field: number = reader.readTag();
      if (field === 1 && reader.wireType === WireType.LENGTH_DELIMITED) {
        const data: ProtoReader = reader.readMessageView();
        while (data.hasMore()) {
          const tag: number = data.readTag();
          if (tag === 1 && data.wireType === WireType.VARINT) {
            const id: bigint = data.readUint64();
            if (id > BigInt('18446744073709551615')) { throw new Error('小尾巴写响应标识越界'); }
            result.id = id.toString();
          }
          else { data.skipField(); }
        }
      } else if (field === 2 && reader.wireType === WireType.LENGTH_DELIMITED) {
        const error: ProtoReader = reader.readMessageView();
        while (error.hasMore()) {
          const tag: number = error.readTag();
          if (tag === 1 && error.wireType === WireType.VARINT) { result.code = error.readInt32(); errorSeen = true; }
          else if (tag === 2 && error.wireType === WireType.LENGTH_DELIMITED) { result.message = error.readString(); }
          else { error.skipField(); }
        }
      } else { reader.skipField(); }
    }
    if (!errorSeen) { result.code = -1; result.message = '小尾巴提交响应未确认'; }
  } catch (err) { result.code = -1; result.message = '小尾巴提交响应解析失败'; }
  if (result.code !== 0) { result.id = ''; }
  return result;
}

export function tailColor(value: string): string {
  return /^#?[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?$/.test(value)
    ? (value.startsWith('#') ? value : `#${value}`) : '';
}

export function tailSelectionLabel(value: number): string {
  return value === 1 ? '已启用' : value === 0 ? '未启用' : '状态未确认';
}

function readTail(reader: ProtoReader): TailItem {
  const item: TailItem = new TailItem();
  while (reader.hasMore()) {
    const field: number = reader.readTag();
    if (field === 1 && reader.wireType === WireType.VARINT) {
      const id: bigint = reader.readUint64();
      if (id <= BigInt(0) || id > BigInt('4294967295')) { throw new Error('小尾巴标识无效'); }
      item.id = Number(id);
    } else if (field === 2 && reader.wireType === WireType.VARINT) {
      const value: bigint = reader.readUint64();
      item.selected = value === BigInt(0) ? 0 : value === BigInt(1) ? 1 : -1;
    } else if (field === 3 && reader.wireType === WireType.LENGTH_DELIMITED) {
      item.content = reader.readString();
    } else if (field === 4 && reader.wireType === WireType.LENGTH_DELIMITED) {
      item.fontColor = reader.readString();
    } else if (field === 5 && reader.wireType === WireType.LENGTH_DELIMITED) {
      item.fontKeyName = reader.readString();
    } else { reader.skipField(); }
  }
  if (item.id === 0) { throw new Error('小尾巴标识未返回'); }
  return item;
}

function readData(reader: ProtoReader, result: TailList): void {
  const seen: Set<number> = new Set<number>();
  while (reader.hasMore()) {
    const field: number = reader.readTag();
    if (field === 1 && reader.wireType === WireType.LENGTH_DELIMITED) {
      const item: TailItem = readTail(reader.readMessageView());
      if (!seen.has(item.id)) { result.items.push(item); seen.add(item.id); }
    } else if (field === 2 && reader.wireType === WireType.LENGTH_DELIMITED) {
      const color: ProtoReader = reader.readMessageView();
      while (color.hasMore()) {
        const tag: number = color.readTag();
        if (tag === 1 && color.wireType === WireType.LENGTH_DELIMITED) {
          const value: string = color.readString();
          if (tailColor(value).length > 0 && !result.colors.includes(value)) { result.colors.push(value); }
        } else { color.skipField(); }
      }
    } else if (field === 3 && reader.wireType === WireType.LENGTH_DELIMITED) {
      const value: string = reader.readString();
      result.defaultColor = tailColor(value).length > 0 ? value : '';
    } else { reader.skipField(); }
  }
}

export function parseTails(bytes: Uint8Array): TailList {
  const result: TailList = new TailList();
  let dataSeen: boolean = false;
  let errorSeen: boolean = false;
  try {
    const reader: ProtoReader = new ProtoReader(bytes);
    while (reader.hasMore()) {
      const field: number = reader.readTag();
      if (field === 1 && reader.wireType === WireType.LENGTH_DELIMITED) {
        readData(reader.readMessageView(), result); dataSeen = true;
      } else if (field === 2 && reader.wireType === WireType.LENGTH_DELIMITED) {
        const error: ProtoReader = reader.readMessageView();
        while (error.hasMore()) {
          const tag: number = error.readTag();
          if (tag === 1 && error.wireType === WireType.VARINT) {
            result.code = error.readInt32(); errorSeen = true;
          } else if (tag === 2 && error.wireType === WireType.LENGTH_DELIMITED) {
            result.message = error.readString();
          } else { error.skipField(); }
        }
      } else { reader.skipField(); }
    }
    if (!errorSeen || (result.code === 0 && !dataSeen)) {
      result.code = -1; result.message = '小尾巴响应未确认';
    }
  } catch (err) {
    result.code = -1; result.message = '小尾巴响应解析失败';
  }
  if (result.code !== 0) { result.items = []; result.colors = []; result.defaultColor = ''; }
  return result;
}
