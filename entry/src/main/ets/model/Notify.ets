/** 回复和提及通知的解析、去重与分页信息。接口无权访问或读取失败时不生成空成功结果。 */
import { ProtoReader, WireType } from '../proto/ProtoWire';
import { portraitUrl } from './ThreadDetail';

/** 通知列表的种类 */
export type NotifyKind = 'reply' | 'agree' | 'at';

/**
 * 游标：reply 用页码（pn 从 1 起、翻页 +1），agree 用上一批最后一条的 id。
 * 用一个类统一承载，VM 与页面不感知两种分页方式的差异。
 */
export class NotifyCursor {
  page: number = 1;
  agreeId: number = 0;
}

/** 解析结果 */
export class NotifyResult {
  /** JSON @我服务端返回的当前页；缺失为 0，不伪造。 */
  page: number = 0;
  /** 0 = 成功；-1 = 解析失败（**不能伪装成"没有通知"**） */
  code: number = -1;
  message: string = '';
  items: NotifyItem[] = [];

  hasMore: boolean = false;
  /** agree：游标（最后一条的 id；0 = 无） */
  nextAgreeId: number = 0;
  /** agree：服务端是否声明还有更多 */
  agreeHasMore: boolean = false;
}

/** 一条通知（两类 kind 的展示并集；不用的字段保持空值，页面按 kind 取用） */
export class NotifyItem {
  /** @我 JSON 的精确 ID；超出当前 number 导航范围时仍保留且禁止舍入跳转。 */
  threadIdText: string = '';
  postIdText: string = '';
  userIdText: string = '';
  kind: NotifyKind = 'reply';
  /** 谁做的动作 */
  userId: number = 0;
  userName: string = '';
  nameShow: string = '';
  portrait: string = '';
  avatar: string = '';
  /** 被操作的帖子/楼层 */
  threadId: number = 0;
  postId: number = 0;
  /** 帖子标题（回复我=被回复的帖；赞我=被赞的帖/楼） */
  title: string = '';
  /** 吧名 */
  forumName: string = '';
  /** 对方说的话：回复=回复内容；赞=被赞的正文片段（quote/content 里取） */
  excerpt: string = '';
  /** 被回复对象说的话（回复我才有：你当时写的内容） */
  quoteContent: string = '';
  /** 楼层标记：1 = 楼中楼回复（决定详情定位方式） */
  isFloor: number = 0;
  /** 秒级时间戳（模型统一乘 1000 存毫秒） */
  timeMs: number = 0;

  /** 展示名：优先 name_show，退 name，最后兜底（与全站"贴吧用户"口径一致） */
  displayName(): string {
    if (this.nameShow.length > 0) { return this.nameShow; }
    if (this.userName.length > 0) { return this.userName; }
    return '贴吧用户';
  }

  /** 页面主文案（不编造：各字段有什么画什么） */
  headline(): string {
    if (this.kind === 'at') { return this.title.length > 0 ? this.title : '提到了你'; }
    if (this.kind === 'reply') {
      return this.title.length > 0 ? this.title : '回复了你的帖子';
    }
    return this.title.length > 0 ? this.title : '赞了你的内容';
  }
}

/** 读 `Error`：errorno=1、errmsg=2、usermsg=3（优先展示非空 usermsg） */
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

/** 读 `User` 的展示三件套：id=2(int64)、name=3、name_show=4、portrait=5 */
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

/**
 * 读一条 `ReplyList`（字段号见 `proto/ReplyMe/ReplyList.proto`；探针已逐字段核对）。
 * 只取展示需要的字段；`thread_id`/`post_id`/`quote_pid` 都是 uint64，**按 64 位读**。
 */
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

/** 读 `DataRes{ page=1, reply_list=2 }` */
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

/**
 * 读一条 `AgreeList`（字段号见 `proto/AgreeList.proto`；探针实测条目形如
 * `f1(ThreadInfo) f4(time) f5(is_del) f6(type) f7(id) f8(agreeer) f9(Post) f12`）。
 * `id=7` 是**游标**；被赞内容在 `thread_info`（主题帖被赞）或 `post_info`（楼层被赞）里。
 */
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
      // AgreeList 顶层 time：ThreadInfo.create_time 没给时用它兜底
      if (item.timeMs === 0) { item.timeMs = reader.readInt32() * 1000; }
    } else if (tag === 7 && reader.wireType === WireType.VARINT) {
      // AgreeList.id = 游标（uint64）。暂存在 postId，parseNotifyAgree 末尾统一搬进 nextAgreeId
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

/** 读 `AgreeMe DataRes{ has_more=1, agree_list=2 }` */
function readAgreeData(reader: ProtoReader, out: NotifyResult): void {
  while (reader.hasMore()) {
    const tag: number = reader.readTag();
    if (tag === 1 && reader.wireType === WireType.VARINT) {
      out.agreeHasMore = reader.readInt32() === 1;
    } else if (tag === 2 && reader.wireType === WireType.LENGTH_DELIMITED) {
      // readAgreeItem 会把 AgreeList.id（游标）暂存在 item.postId 里，由 parseNotifyAgree 统一取
      out.items.push(readAgreeItem(reader.readMessageView()));
    } else {
      reader.skipField();
    }
  }
}

/**
 * 解析 replyme（`ReplyMeResIdl{ error=1, data=2 }`）。
 * 解析失败回 `code = -1`，由调用方按业务错误如实提示。
 */
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

/**
 * 解析 agreeme（`AgreeMeResIdl{ error=1, data=2 }`）。
 * 返回的 `nextAgreeId` 是下一页游标（最后一条的 `AgreeList.id`）。
 */
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
  // 游标 = 最后一条的 AgreeList.id（readAgreeItem 把它暂存在 postId 里）
  for (let i = out.items.length - 1; i >= 0; i--) {
    const candidate: number = out.items[i].postId;
    if (candidate > 0) {
      out.nextAgreeId = candidate;
      break;
    }
  }
  // 展示层不需要这个暂存值，清掉
  for (let i = 0; i < out.items.length; i++) {
    out.items[i].postId = 0;
  }
  return out;
}
