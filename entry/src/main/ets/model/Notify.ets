
import { ProtoReader, WireType } from '../proto/ProtoWire';
import { portraitUrl } from './ThreadDetail';

export type NotifyKind = 'reply' | 'agree' | 'at';

export class NotifyCursor {
  page: number = 1;
  agreeId: number = 0;
}

export class NotifyResult {

  page: number = 0;

  code: number = -1;
  message: string = '';
  items: NotifyItem[] = [];

  hasMore: boolean = false;

  nextAgreeId: number = 0;

  agreeHasMore: boolean = false;
}

export class NotifyItem {

  threadIdText: string = '';
  postIdText: string = '';
  userIdText: string = '';
  kind: NotifyKind = 'reply';

  userId: number = 0;
  userName: string = '';
  nameShow: string = '';
  portrait: string = '';
  avatar: string = '';

  threadId: number = 0;
  postId: number = 0;

  title: string = '';

  forumName: string = '';

  excerpt: string = '';

  quoteContent: string = '';

  isFloor: number = 0;

  timeMs: number = 0;

  displayName(): string {
    if (this.nameShow.length > 0) { return this.nameShow; }
    if (this.userName.length > 0) { return this.userName; }
    return '贴吧用户';
  }

  headline(): string {
    if (this.kind === 'at') { return this.title.length > 0 ? this.title : '提到了你'; }
    if (this.kind === 'reply') {
      return this.title.length > 0 ? this.title : '回复了你的帖子';
    }
    return this.title.length > 0 ? this.title : '赞了你的内容';
  }
}

function readError(reader: ProtoReader, out: NotifyResult): void {
  let message: string = '';
  while (reader.hasMore()) {
    const tag: number = reader.readTag();
    if (tag === 1 && reader.wireType === WireType.VARINT) {
      out.code = reader.readInt32();
    } else if ((tag === 2 || tag === 3) && reader.wireType === WireType.LENGTH_DELIMITED) {
      const text: string = reader.readString();
      if (text.length > 0 && (tag === 3 || message.length === 0)) { message = text; }
    } else {
      reader.skipField();
    }
  }
  out.message = message;
}

function readUser(reader: ProtoReader, item: NotifyItem): void {
  while (reader.hasMore()) {
    const tag: number = reader.readTag();
    if (tag === 2 && reader.wireType === WireType.VARINT) {
      item.userId = Number(reader.readInt64());
    } else if (tag === 3 && reader.wireType === WireType.LENGTH_DELIMITED) {
      item.userName = reader.readString();
    } else if (tag === 4 && reader.wireType === WireType.LENGTH_DELIMITED) {
      item.nameShow = reader.readString();
    } else if (tag === 5 && reader.wireType === WireType.LENGTH_DELIMITED) {
      item.portrait = reader.readString();
      item.avatar = portraitUrl(item.portrait);
    } else {
      reader.skipField();
    }
  }
}

function readReplyItem(reader: ProtoReader): NotifyItem {
  const item: NotifyItem = new NotifyItem();
  item.kind = 'reply';
  while (reader.hasMore()) {
    const tag: number = reader.readTag();
    if (tag === 1 && reader.wireType === WireType.VARINT) {
      item.threadId = Number(reader.readInt64());
    } else if (tag === 2 && reader.wireType === WireType.VARINT) {
      item.postId = Number(reader.readInt64());
    } else if (tag === 3 && reader.wireType === WireType.VARINT) {
      item.timeMs = reader.readInt32() * 1000;
    } else if (tag === 4 && reader.wireType === WireType.LENGTH_DELIMITED) {
      item.title = reader.readString();
    } else if (tag === 5 && reader.wireType === WireType.LENGTH_DELIMITED) {
      item.forumName = reader.readString();
    } else if (tag === 6 && reader.wireType === WireType.LENGTH_DELIMITED) {
      item.excerpt = reader.readString();
    } else if (tag === 7 && reader.wireType === WireType.VARINT) {
      item.isFloor = reader.readInt32();
    } else if (tag === 8 && reader.wireType === WireType.LENGTH_DELIMITED) {
      item.quoteContent = reader.readString();
    } else if (tag === 9 && reader.wireType === WireType.LENGTH_DELIMITED) {
      readUser(reader.readMessageView(), item);
    } else {
      reader.skipField();
    }
  }
  return item;
}

function readReplyData(reader: ProtoReader, out: NotifyResult): void {
  while (reader.hasMore()) {
    const tag: number = reader.readTag();
    if (tag === 1 && reader.wireType === WireType.LENGTH_DELIMITED) {

      const page: ProtoReader = reader.readMessageView();
      while (page.hasMore()) {
        const f: number = page.readTag();
        if (f === 6 && page.wireType === WireType.VARINT) {
          out.hasMore = page.readInt32() === 1;
        } else {
          page.skipField();
        }
      }
    } else if (tag === 2 && reader.wireType === WireType.LENGTH_DELIMITED) {
      out.items.push(readReplyItem(reader.readMessageView()));
    } else {
      reader.skipField();
    }
  }
}

function readAgreeItem(reader: ProtoReader): NotifyItem {
  const item: NotifyItem = new NotifyItem();
  item.kind = 'agree';
  while (reader.hasMore()) {
    const tag: number = reader.readTag();
    if (tag === 1 && reader.wireType === WireType.LENGTH_DELIMITED) {
      const thread: ProtoReader = reader.readMessageView();
      while (thread.hasMore()) {
        const f: number = thread.readTag();
        if (f === 2 && thread.wireType === WireType.VARINT) {
          item.threadId = Number(thread.readInt64());
        } else if (f === 3 && thread.wireType === WireType.LENGTH_DELIMITED) {
          item.title = thread.readString();
        } else if (f === 28 && thread.wireType === WireType.LENGTH_DELIMITED) {
          item.forumName = thread.readString();
        } else if (f === 45 && thread.wireType === WireType.VARINT) {
          item.timeMs = thread.readInt32() * 1000;
        } else {
          thread.skipField();
        }
      }
    } else if (tag === 4 && reader.wireType === WireType.VARINT) {

      if (item.timeMs === 0) { item.timeMs = reader.readInt32() * 1000; }
    } else if (tag === 7 && reader.wireType === WireType.VARINT) {

      item.postId = Number(reader.readInt64());
    } else if (tag === 8 && reader.wireType === WireType.LENGTH_DELIMITED) {
      readUser(reader.readMessageView(), item);
    } else if (tag === 9 && reader.wireType === WireType.LENGTH_DELIMITED) {
      const post: ProtoReader = reader.readMessageView();
      while (post.hasMore()) {
        const f: number = post.readTag();
        if (f === 2 && post.wireType === WireType.LENGTH_DELIMITED) {
          item.excerpt = post.readString();
        } else {
          post.skipField();
        }
      }
    } else {
      reader.skipField();
    }
  }
  return item;
}

function readAgreeData(reader: ProtoReader, out: NotifyResult): void {
  while (reader.hasMore()) {
    const tag: number = reader.readTag();
    if (tag === 1 && reader.wireType === WireType.VARINT) {
      out.agreeHasMore = reader.readInt32() === 1;
    } else if (tag === 2 && reader.wireType === WireType.LENGTH_DELIMITED) {

      out.items.push(readAgreeItem(reader.readMessageView()));
    } else {
      reader.skipField();
    }
  }
}

export function parseNotifyReply(bytes: Uint8Array): NotifyResult {
  const out: NotifyResult = new NotifyResult();
  try {
    const root: ProtoReader = new ProtoReader(bytes);
    while (root.hasMore()) {
      const field: number = root.readTag();
      if (field === 1 && root.wireType === WireType.LENGTH_DELIMITED) {
        readError(root.readMessageView(), out);
      } else if (field === 2 && root.wireType === WireType.LENGTH_DELIMITED) {
        readReplyData(root.readMessageView(), out);
      } else {
        root.skipField();
      }
    }
  } catch (err) {
    return new NotifyResult();
  }
  return out;
}

export function parseNotifyAgree(bytes: Uint8Array): NotifyResult {
  const out: NotifyResult = new NotifyResult();
  try {
    const root: ProtoReader = new ProtoReader(bytes);
    while (root.hasMore()) {
      const field: number = root.readTag();
      if (field === 1 && root.wireType === WireType.LENGTH_DELIMITED) {
        readError(root.readMessageView(), out);
      } else if (field === 2 && root.wireType === WireType.LENGTH_DELIMITED) {
        readAgreeData(root.readMessageView(), out);
      } else {
        root.skipField();
      }
    }
  } catch (err) {
    return new NotifyResult();
  }

  for (let i = out.items.length - 1; i >= 0; i--) {
    const candidate: number = out.items[i].postId;
    if (candidate > 0) {
      out.nextAgreeId = candidate;
      break;
    }
  }

  for (let i = 0; i < out.items.length; i++) {
    out.items[i].postId = 0;
  }
  return out;
}
