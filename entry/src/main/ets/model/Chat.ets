/**
 * 私信（IM）数据模型与 protobuf 解析。
 *
 * 契约来自官方 APK 反编译的 protobuf 类（字段号见 `docs/协议/协议证据-私信.md`）：
 * - 握手 `UpdateClientInfoResIdl{error=1, data=2}`
 * - 同步 `GetGroupMsgResIdl{error=1, data=2}`，`data.groupMsg[] = GroupMsg{groupInfo=1, msgList=2, hasMore=3}`
 * - 发送回执 `CommitPersonalMsgResIdl{error=1, data=2}`
 * - 已读回执 `CommitReceivedPmsgResIdl{error=1, data=2}`
 *
 * 解析失败一律 `code = -1`，**不返回"空成功"**（与 `model/Notify.ets` 的 `NotifyResult` 口径一致）；
 * 字段缺失就保持空值，不猜、不补默认业务值。
 */

import { ProtoReader, WireType } from '../proto/ProtoWire';

/** 会话组类型：6 = 私信会话（其余类型暂不展示）。 */
export const GROUP_TYPE_PRIVATE: number = 6;
/** 消息类型：1 = 文本，22 = 已读回执（content 是 JSON），其余暂按占位文本展示。 */
export const MSG_TYPE_TEXT: number = 1;
export const MSG_TYPE_IMAGE: number = 2;
export const MSG_TYPE_READED: number = 22;

export class ChatImageContent {
  src: string = '';
  bigSrc: string = '';
  width: number = 0;
  height: number = 0;
}

interface RawChatPicPayload {
  src?: string;
  big_src?: string;
  bsize?: string;
  type?: string;
}

function validChatImageUrl(raw: string | undefined): string {
  if (typeof raw !== 'string') { return ''; }
  const trimmed: string = raw.trim();
  return /^https?:\/\/[^\s/?#@\\]+(?:[/?#][^\s\\]*)?$/i.test(trimmed) ? trimmed : '';
}

function parseRawChatPicItem(raw: RawChatPicPayload | null | undefined): ChatImageContent | undefined {
  if (raw === undefined || raw === null) { return undefined; }
  const src: string = validChatImageUrl(raw.src);
  const bigSrc: string = validChatImageUrl(raw.big_src);
  const usableSrc: string = src.length > 0 ? src : bigSrc;
  if (usableSrc.length === 0) { return undefined; }
  const out: ChatImageContent = new ChatImageContent();
  out.src = usableSrc;
  out.bigSrc = bigSrc.length > 0 ? bigSrc : usableSrc;
  if (typeof raw.bsize === 'string') {
    const parts: string[] = raw.bsize.split(',');
    if (parts.length >= 2) {
      const w: number = Number(parts[0]);
      const h: number = Number(parts[1]);
      if (Number.isFinite(w) && w > 0 && Number.isFinite(h) && h > 0) {
        out.width = Math.round(w);
        out.height = Math.round(h);
      }
    }
  }
  return out;
}

/** 解析私信图片消息（msgType=2，官方 PicMessageData JSON 数组 `[{src, big_src, bsize, type:"3"}]`，兼容单对象）。 */
export function parseChatImageContent(content: string): ChatImageContent | undefined {
  const trimmed: string = content.trim();
  if (trimmed.length === 0) { return undefined; }
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    const direct: string = validChatImageUrl(trimmed);
    if (direct.length === 0) { return undefined; }
    const out: ChatImageContent = new ChatImageContent();
    out.src = direct;
    out.bigSrc = direct;
    return out;
  }
  if (!trimmed.startsWith('[') && !trimmed.startsWith('{')) { return undefined; }
  try {
    const parsed: Object = JSON.parse(trimmed) as Object;
    if (Array.isArray(parsed)) {
      for (let i: number = 0; i < parsed.length; i++) {
        const hit: ChatImageContent | undefined = parseRawChatPicItem(parsed[i] as RawChatPicPayload);
        if (hit !== undefined) { return hit; }
      }
      return undefined;
    }
    return parseRawChatPicItem(parsed as RawChatPicPayload);
  } catch (_) {
    return undefined;
  }
}

/** 构造官方私信图片消息 JSON 数组（APK `ie7.g`：`[{src, big_src, bsize, type:"3"}]`）。 */
export function encodeChatImageContent(url: string, width: number, height: number, bigUrl: string = ''): string {
  const safeSrc: string = validChatImageUrl(url);
  const safeBig: string = validChatImageUrl(bigUrl);
  const effectiveSrc: string = safeSrc.length > 0 ? safeSrc : safeBig;
  if (effectiveSrc.length === 0) { return ''; }
  const effectiveBig: string = safeBig.length > 0 ? safeBig : effectiveSrc;
  const w: number = Number.isFinite(width) && width > 0 ? Math.round(width) : 0;
  const h: number = Number.isFinite(height) && height > 0 ? Math.round(height) : 0;
  const bsize: string = w > 0 && h > 0 ? `${w},${h}` : '';
  return JSON.stringify([{
    src: effectiveSrc,
    big_src: effectiveBig,
    bsize: bsize,
    type: '3'
  }]);
}

/** 置顶会话的排序偏移：远大于消息时间戳（~1e12），保证置顶永远排最前。 */
const PINNED_OFFSET: number = 1e15;

/** 发送态：服务端确认前不显示"已发送"。 */
export type ChatSendState = 'sent' | 'sending' | 'failed';

/**
 * 会话对端（私信会话里就是对方）。
 *
 * 同样要 `@ObservedV2` + `@Trace`：contacts 补昵称/头像时改的是这里的**字段**，
 * 只给 `ChatGroup.peer` 加 `@Trace` 只管"换对象"，字段变化不会重绘列表
 * （列表还显示旧昵称、点进会话页却是新昵称）。
 */
@ObservedV2
export class ChatPeer {
  @Trace uidText: string = '';
  @Trace uid: bigint = BigInt(0);
  @Trace userName: string = '';
  @Trace userNameShow: string = '';
  @Trace portrait: string = '';

  displayName(): string {
    if (this.userNameShow.length > 0) { return this.userNameShow; }
    if (this.userName.length > 0) { return this.userName; }
    return '贴吧用户';
  }
}

export class ChatMessage {
  msgIdText: string = '';
  msgId: bigint = BigInt(0);
  /** 本地发送时使用 recordId，服务端回执带回来后再换成真实 msgId。 */
  recordIdText: string = '';
  recordId: bigint = BigInt(0);
  groupIdText: string = '';
  groupId: bigint = BigInt(0);
  msgType: number = 0;
  fromSelf: boolean = false;
  peer: ChatPeer = new ChatPeer();
  /** 自己发出的消息：对方 uid（`MsgInfo.toUid`，字段 11）。 */
  toUidText: string = '';
  toUid: bigint = BigInt(0);
  content: string = '';
  /** 秒级时间戳已换算为毫秒。 */
  createTimeMs: number = 0;
  sendState: ChatSendState = 'sent';

  /** 列表与去重键：有 msgId 用 msgId，本地未回执的消息用 recordId。 */
  key(): string {
    if (this.msgId > BigInt(0)) { return `${this.groupIdText}:${this.msgIdText}`; }
    return `${this.groupIdText}:r${this.recordIdText}`;
  }

  /** 气泡展示文本；未知类型保留位置，不丢消息。 */
  text(): string {
    if (this.msgType === MSG_TYPE_TEXT) { return this.content; }
    if (this.msgType === MSG_TYPE_IMAGE) { return '[图片]'; }
    if (this.msgType === MSG_TYPE_READED) { return '已读'; }
    if (this.msgType === 3) { return '[语音]'; }
    if (this.msgType === 33) { return this.content.length > 0 ? `[分享吧] ${this.content}` : '[分享吧]'; }
    if (this.msgType === 34) { return this.structuredCardText(); }
    return '[暂不支持的消息]';
  }

  imageContent(): ChatImageContent | undefined {
    return this.msgType === MSG_TYPE_IMAGE ? parseChatImageContent(this.content) : undefined;
  }

  /** 结构卡 content 形如 `[文本, 类型]`（JSON 数组）；取不到文本就退占位。 */
  private structuredCardText(): string {
    const text: string = this.content.trim();
    if (text.startsWith('[')) {
      try {
        const parsed: Object = JSON.parse(text) as Object;
        if (Array.isArray(parsed) && parsed.length > 0 && typeof parsed[0] === 'string') {
          return String(parsed[0]);
        }
      } catch (err) { /* 落占位 */ }
    }
    return '[卡片消息]';
  }
}

/**
 * 会话列表一行。
 *
 * `@ObservedV2` + `@Trace` 是必须的：会话页拉到新消息后只改这个实例的
 * `lastMessage`，如果它不可观察，返回列表时预览还停在旧值（「还没有聊天记录」）。
 */
/** 202006 推送：某个会话有新消息（只给会话 id 与最新消息 id，不含正文）。 */
export class ImPushNotify {
  type: number = 0;
  groupIdText: string = '';
  groupId: bigint = BigInt(0);
  groupType: number = 0;
  newestMsgIdText: string = '';
  newestMsgId: bigint = BigInt(0);
  content: string = '';
  emitTime: string = '';
  pushTime: number = 0;
}

/**
 * 解析 202006 推送体。
 *
 * 官方 `PushNotifyMessage` 的字段是 public（type/groupId/groupType/newestMsgId/
 * content/emitTime/pushTime），按 JSON 读；解析不出来返回 undefined，
 * 调用方保持"没收到推送"的行为（不猜、不建幽灵会话）。
 */
/**
 * 解析 202006 推送体（protobuf）。
 *
 * 抓包样本（33 字节）：
 * `12 1f 12 1d 08 <groupId> 10 <newestMsgId> 20 00 32 <len> "1794833368" 38 06`
 * 外层套了两层 `field 2`，数据层字段号：1=groupId、2=newestMsgId、4=type、
 * 6=emitTime（十进制秒字符串）、7=groupType（6=私信）。
 * 解析不出来返回 undefined，调用方保持"没收到推送"的行为。
 */
export function parseImPushNotify(bytes: Uint8Array): ImPushNotify | undefined {
  if (bytes.length === 0) { return undefined; }
  try {
    // 剥掉外层 `field 2` 包装（最多两层）
    let current: Uint8Array = bytes;
    for (let depth = 0; depth < 2; depth++) {
      const reader: ProtoReader = new ProtoReader(current);
      let inner: Uint8Array | undefined = undefined;
      let hasOther: boolean = false;
      while (reader.hasMore()) {
        const tag: number = reader.readTag();
        if (tag === 2 && reader.wireType === WireType.LENGTH_DELIMITED) {
          inner = reader.readBytes();
        } else {
          reader.skipField();
          hasOther = true;
        }
      }
      if (inner === undefined || hasOther) { break; }
      current = inner;
    }

    const out: ImPushNotify = new ImPushNotify();
    const data: ProtoReader = new ProtoReader(current);
    while (data.hasMore()) {
      const tag: number = data.readTag();
      if (tag === 1 && data.wireType === WireType.VARINT) {
        out.groupId = data.readInt64();
        out.groupIdText = out.groupId.toString();
      } else if (tag === 2 && data.wireType === WireType.VARINT) {
        out.newestMsgId = data.readInt64();
        out.newestMsgIdText = out.newestMsgId.toString();
      } else if (tag === 4 && data.wireType === WireType.VARINT) {
        out.type = data.readInt32();
      } else if (tag === 6 && data.wireType === WireType.LENGTH_DELIMITED) {
        out.emitTime = data.readString();
      } else if (tag === 7 && data.wireType === WireType.VARINT) {
        out.groupType = data.readInt32();
      } else {
        data.skipField();
      }
    }
    if (out.groupId <= BigInt(0)) { return undefined; }
    return out;
  } catch (err) {
    return undefined;
  }
}

@ObservedV2
export class ChatGroup {
  @Trace groupIdText: string = '';
  @Trace groupId: bigint = BigInt(0);
  @Trace groupType: number = GROUP_TYPE_PRIVATE;
  /** 服务端给的分组名：私信组通常就是对方昵称，缺 author 字段时用它兜底。 */
  @Trace name: string = '';
  @Trace peer: ChatPeer = new ChatPeer();
  @Trace lastMsgIdText: string = '0';
  @Trace lastMsgId: bigint = BigInt(0);
  @Trace lastMsgTimeMs: number = 0;
  /** 未读数，来自 web `getContacts`（WS 组信息里没有）。 */
  @Trace unread: number = 0;
  /** 本机置顶（没有服务端接口，本地记录）。 */
  @Trace pinned: boolean = false;
  @Trace lastMessage: ChatMessage | undefined = undefined;
  /**
   * 对端身份来源。会话的 `peer.uid` 只能有一个答案：
   * - `peerFromMessage`：由组内**收到的消息发送者**确定，最权威，此后 contacts 不得改写；
   * - `peerFromContact`：由 web `getContacts` 按 uid/头像唯一匹配贴上，属于待确认；
   * - 两者都 false：身份未知，禁止发送。
   */
  @Trace peerFromMessage: boolean = false;
  @Trace peerFromContact: boolean = false;
  /**
   * 组里出现过不止一个发送者：这是群聊，或服务端把多条私信放在同一个"我的私聊"组里。
   * 这类组没有唯一对端：消息按发送者拆到各自的对端会话（`peerThreadKey`），组本身只当同步游标。
   */
  @Trace multiPeer: boolean = false;
  /** 只承载 groupId/游标、不需要出现在会话列表里的容器组。 */
  @Trace container: boolean = false;

  /**
   * 展示名：对端昵称优先，其次「贴吧用户」占位。
   *
   * **不用 `name` 兜底**：私信组的 `GroupInfo.name` 是组名（出现过「我的私聊」
   * 这种默认名），拿它当对方昵称会让用户以为消息属于自己。群聊例外——组名就是它的名字。
   */
  title(): string {
    if (this.multiPeer) { return this.name.length > 0 ? this.name : '群聊'; }
    if (this.peer.userNameShow.length > 0) { return this.peer.userNameShow; }
    if (this.peer.userName.length > 0) { return this.peer.userName; }
    return '贴吧用户';
  }

  /** 消息时间：置顶偏移不参与，界面显示时间用它。 */
  timeKey(): number {
    return this.lastMessage !== undefined ? this.lastMessage.createTimeMs : this.lastMsgTimeMs;
  }

  /** 排序键：置顶的永远在前，其余按最后一条消息时间倒序。 */
  sortKey(): number {
    const base: number = this.timeKey();
    return this.pinned ? base + PINNED_OFFSET : base;
  }
}

/**
 * web `getContacts` 的一行。
 *
 * WS 的 `GroupInfo` 拿不到私信对端 uid（`authorId` 是自己），所以对端身份只能从
 * 这里补：`lastMsgId` 与 WS 组的 `lastMsgId` 相等即可认定是同一个会话。
 */
export class ChatContact {
  uid: number = 0;
  uname: string = '';
  showNickname: string = '';
  portrait: string = '';
  unread: number = 0;
  lastReadMsgId: number = 0;
  lastMsgId: number = 0;
}

/** `getContacts` 解析结果（字段名按服务端 snake_case 读）。 */
export class ChatContactPage {
  errno: number = -1;
  errmsg: string = '';
  pageSize: number = 0;
  contacts: ChatContact[] = [];
}

/**
 * 容器组里某个对端的会话 key。
 *
 * 服务端会把多条私信放进同一个组（实测名为「我的私聊」的组里有 4 个发送者），
 * 直接按组存就会让几个人的消息串在一条会话里；按「组 id + 对端 uid」拆开才是正确归属。
 */
export function peerThreadKey(groupIdText: string, uidText: string): string {
  return `p:${groupIdText}:${uidText}`;
}

/**
 * 一批消息里出现过的非自己对端 uid 数量。>1 说明这个组是多人群聊，
 * 没有唯一的"私信对象"——既不能拿某个成员当对方，也不能把它当 1v1 会话发消息。
 */
export function distinctPeerCount(messages: ChatMessage[]): number {
  const seen: Set<string> = new Set<string>();
  for (let i = 0; i < messages.length; i++) {
    const msg: ChatMessage = messages[i];
    if (msg.fromSelf || msg.peer.uid <= BigInt(0)) { continue; }
    seen.add(msg.peer.uid.toString());
  }
  return seen.size;
}

/**
 * 把一条 contacts 记录落到已有会话上；返回 undefined 表示没有可信的对应关系，调用方新建 `u:<uid>`。
 *
 * 只认三种证据，逐级收紧：
 * 1. 已经是这个 uid 的会话（幂等）；
 * 2. **头像唯一匹配**：私信组的组头像就是对端头像，比 lastMsgId 稳得多；
 * 3. `lastMsgId` 唯一匹配：命中多条时宁可不认——认错会把两个人并进同一条会话，
 *    标题和收件人对不上，消息也会串。
 * 已经有对端 uid 的会话不参与 2/3：它不能被另一条 contact 改名换姓。
 */
export function matchContactGroup(groups: ChatGroup[], uid: bigint, portrait: string,
  lastMsgId: bigint): ChatGroup | undefined {
  for (let i = 0; i < groups.length; i++) {
    if (!groups[i].multiPeer && !groups[i].container && groups[i].peer.uid === uid) { return groups[i]; }
  }
  if (portrait.length > 0) {
    let hit: ChatGroup | undefined = undefined;
    let count: number = 0;
    for (let i = 0; i < groups.length; i++) {
      const group: ChatGroup = groups[i];
      if (group.multiPeer || group.container || group.peer.uid > BigInt(0) || group.peer.portrait !== portrait) { continue; }
      hit = group;
      count++;
    }
    if (count === 1) { return hit; }
    if (count > 1) { return undefined; }
  }
  if (lastMsgId <= BigInt(0)) { return undefined; }
  let byLast: ChatGroup | undefined = undefined;
  let lastCount: number = 0;
  for (let i = 0; i < groups.length; i++) {
    const group: ChatGroup = groups[i];
    if (group.multiPeer || group.container || group.peer.uid > BigInt(0) || group.lastMsgId !== lastMsgId) { continue; }
    byLast = group;
    lastCount++;
  }
  return lastCount === 1 ? byLast : undefined;
}

/** 解析 `/im/pcmsg/query/getContacts` 的 JSON 文本。 */
export function parseChatContacts(text: string): ChatContactPage {
  const out: ChatContactPage = new ChatContactPage();
  try {
    const root: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
    out.errno = Number(root['errno'] ?? -1);
    out.errmsg = String(root['errmsg'] ?? '');
    const data: Record<string, Object> | undefined =
      root['data'] as Record<string, Object> | undefined;
    if (data === undefined) { return out; }
    out.pageSize = Number(data['pageSize'] ?? 0);
    const list: Object[] = (data['contacts'] ?? []) as Object[];
    for (let i = 0; i < list.length; i++) {
      const raw: Record<string, Object> = list[i] as Record<string, Object>;
      const one: ChatContact = new ChatContact();
      one.uid = Number(raw['uid'] ?? 0);
      one.uname = String(raw['uname'] ?? '');
      one.showNickname = String(raw['show_nickname'] ?? '');
      one.portrait = String(raw['portrait'] ?? '');
      one.unread = Number(raw['unread'] ?? 0);
      one.lastReadMsgId = Number(raw['lastReadMsgId'] ?? 0);
      one.lastMsgId = Number(raw['lastMsgId'] ?? 0);
      if (one.uid > 0) { out.contacts.push(one); }
    }
  } catch (err) {
    out.errno = -1;
    out.errmsg = 'contacts 解析失败';
  }
  return out;
}

/**
 * 会话信息（`GroupInfo`）解析结果。
 *
 * **私信组（groupType=6）的 `authorId` 是当前登录用户自己**，不是对端
 * （`ws group type=6 id=… author=<self> same=Y`）。所以这里把 author 系列字段
 * 单独存放，**不**当作对端写入 `peer.uid`；对端 uid 只能从消息 `userInfo` 或
 * web `getContacts` 补，补不到就禁止发送（宁可发不出去，也不能把 toUid 填成自己）。
 *
 * 列表展示名先用 `GroupInfo.name`（私信组里是对方昵称），头像用 `portrait`。
 */
export class ImGroupSeed {
  groupIdText: string = '';
  groupId: bigint = BigInt(0);
  groupType: number = 0;
  name: string = '';
  /** 组头像（私信组里是对端头像）。 */
  portrait: string = '';
  /** 组创建者/作者，**私信组是自己**，不要当对端用。 */
  authorUidText: string = '';
  authorUid: bigint = BigInt(0);
  authorName: string = '';
  authorPortrait: string = '';
  peer: ChatPeer = new ChatPeer();
  lastMsgIdText: string = '0';
  lastMsgId: bigint = BigInt(0);
  lastMsgTimeMs: number = 0;
}

export class ImInitInfo {
  code: number = -1;
  message: string = '';
  userIdText: string = '';
  userId: bigint = BigInt(0);
  userName: string = '';
  userNameShow: string = '';
  portrait: string = '';
  groups: ImGroupSeed[] = [];
}

export class ImSyncGroup {
  groupIdText: string = '';
  groupId: bigint = BigInt(0);
  groupType: number = 0;
  name: string = '';
  peer: ChatPeer = new ChatPeer();
  lastMsgIdText: string = '0';
  lastMsgId: bigint = BigInt(0);
  lastMsgTimeMs: number = 0;
  hasMore: boolean = false;
  messages: ChatMessage[] = [];
}

export class ImSyncResult {
  code: number = -1;
  message: string = '';
  groups: ImSyncGroup[] = [];
  /**
   * `data.userMsg`（字段 3）里的私聊消息。
   *
   * 私聊消息可能只出现在这个容器里（`groupMsg[].msgList` 为空），
   * 每条消息自带 `groupId`（字段 2）；不解析它会导致会话有 lastMsgId 却"没有聊天记录"。
   */
  userMessages: ChatMessage[] = [];
}

export class ImSendAck {
  code: number = -1;
  message: string = '';
  msgId: bigint = BigInt(0);
  groupId: bigint = BigInt(0);
  recordId: bigint = BigInt(0);
  toUid: bigint = BigInt(0);
  toUserType: number = 0;
}

export class ImReadAck {
  code: number = -1;
  message: string = '';
  readMsgId: bigint = BigInt(0);
  groupId: bigint = BigInt(0);
  toUid: bigint = BigInt(0);
  toUserType: number = 0;
}

/**
 * 读 `Error{errorno=1, errmsg=2, usermsg=3}`；返回 true 表示有业务错误。
 *
 * 真实服务端在成功时也会回 `errmsg="成功"`（1001 回包），
 * 所以**只有 errno 非 0 才算错误**，不能因为 message 非空就判失败。
 */
function readError(reader: ProtoReader, out: ImInitInfo | ImSyncResult | ImSendAck | ImReadAck): boolean {
  let errno: number = 0;
  let message: string = '';
  let userMsg: string = '';
  while (reader.hasMore()) {
    const tag: number = reader.readTag();
    if (tag === 1 && reader.wireType === WireType.VARINT) {
      errno = reader.readInt32();
    } else if (tag === 2 && reader.wireType === WireType.LENGTH_DELIMITED) {
      message = reader.readString();
    } else if (tag === 3 && reader.wireType === WireType.LENGTH_DELIMITED) {
      userMsg = reader.readString();
    } else {
      reader.skipField();
    }
  }
  if (errno !== 0) {
    out.code = errno;
    out.message = userMsg.length > 0 ? userMsg : (message.length > 0 ? message : '服务端未说明原因');
    return true;
  }
  return false;
}

function readPeerFromUserInfo(reader: ProtoReader, out: ChatPeer): void {
  while (reader.hasMore()) {
    const tag: number = reader.readTag();
    if (tag === 1 && reader.wireType === WireType.VARINT) {
      const v: bigint = reader.readInt64();
      out.uid = v;
      out.uidText = v.toString();
    } else if (tag === 2 && reader.wireType === WireType.LENGTH_DELIMITED) {
      out.userName = reader.readString();
    } else if (tag === 4 && reader.wireType === WireType.LENGTH_DELIMITED) {
      out.portrait = reader.readString();
    } else if (tag === 18 && reader.wireType === WireType.LENGTH_DELIMITED) {
      out.userNameShow = reader.readString();
    } else {
      reader.skipField();
    }
  }
}

/** 读 `GroupInfo`（握手与同步都会带）。字段号见协议证据文档。 */
function readGroupInfo(reader: ProtoReader): ImGroupSeed {
  const seed: ImGroupSeed = new ImGroupSeed();
  while (reader.hasMore()) {
    const tag: number = reader.readTag();
    if (tag === 1 && reader.wireType === WireType.VARINT) {
      seed.groupId = reader.readInt64();
      seed.groupIdText = seed.groupId.toString();
    } else if (tag === 3 && reader.wireType === WireType.LENGTH_DELIMITED) {
      seed.name = reader.readString();
    } else if (tag === 5 && reader.wireType === WireType.LENGTH_DELIMITED) {
      seed.portrait = reader.readString();
    } else if (tag === 14 && reader.wireType === WireType.VARINT) {
      // authorId：私信组是自己，**不能**当对端 uid
      seed.authorUid = reader.readInt64();
      seed.authorUidText = seed.authorUid.toString();
    } else if (tag === 15 && reader.wireType === WireType.LENGTH_DELIMITED) {
      seed.authorName = reader.readString();
    } else if (tag === 16 && reader.wireType === WireType.LENGTH_DELIMITED) {
      seed.authorPortrait = reader.readString();
    } else if (tag === 20 && reader.wireType === WireType.VARINT) {
      seed.groupType = reader.readInt32();
    } else if (tag === 21 && reader.wireType === WireType.VARINT) {
      seed.lastMsgId = reader.readInt64();
      seed.lastMsgIdText = seed.lastMsgId.toString();
    } else if (tag === 30 && reader.wireType === WireType.VARINT) {
      const seconds: number = reader.readInt32();
      if (seconds > 0) { seed.lastMsgTimeMs = seconds * 1000; }
    } else {
      reader.skipField();
    }
  }
  // 展示兜底：私信组 name 是对方昵称，portrait 是对端头像；uid 留空等 contacts/消息补。
  if (seed.name.length > 0) { seed.peer.userName = seed.name; }
  if (seed.portrait.length > 0) { seed.peer.portrait = seed.portrait; }
  return seed;
}

export function parseImInit(bytes: Uint8Array): ImInitInfo {
  const out: ImInitInfo = new ImInitInfo();
  try {
    const root: ProtoReader = new ProtoReader(bytes);
    while (root.hasMore()) {
      const tag: number = root.readTag();
      if (tag === 1 && root.wireType === WireType.LENGTH_DELIMITED) {
        if (readError(root.readMessageView(), out)) { return out; }
      } else if (tag === 2 && root.wireType === WireType.LENGTH_DELIMITED) {
        const data: ProtoReader = root.readMessageView();
        let available: bigint = BigInt(-1);
        while (data.hasMore()) {
          const field: number = data.readTag();
          if (field === 1 && data.wireType === WireType.LENGTH_DELIMITED) {
            const seed: ImGroupSeed = readGroupInfo(data.readMessageView());
            if (seed.groupId > BigInt(0)) { out.groups.push(seed); }
          } else if (field === 2 && data.wireType === WireType.LENGTH_DELIMITED) {
            const user: ChatPeer = new ChatPeer();
            readPeerFromUserInfo(data.readMessageView(), user);
            out.userId = user.uid;
            out.userIdText = user.uidText;
            out.userName = user.userName;
            out.userNameShow = user.userNameShow;
            out.portrait = user.portrait;
          } else if (field === 6 && data.wireType === WireType.VARINT) {
            available = data.readInt64();
          } else {
            data.skipField();
          }
        }
        // 官方公开实现会校验 isUserAvailable == userId，不等说明这次连接其实没登进去。
        if (out.userId <= BigInt(0) || (available >= BigInt(0) && available !== out.userId)) {
          out.code = -1;
          out.message = out.userId <= BigInt(0) ? '登录态未被服务端接受' : '账号校验不一致';
          return out;
        }
        out.code = 0;
        out.message = '';
        return out;
      } else {
        root.skipField();
      }
    }
  } catch (err) { /* 保留失败 */ }
  out.code = -1;
  if (out.message.length === 0) { out.message = '握手响应无法解析'; }
  return out;
}

/** 解析同步回包（202003）。 */
export function parseImSync(bytes: Uint8Array, selfUid: bigint): ImSyncResult {
  const out: ImSyncResult = new ImSyncResult();
  try {
    const root: ProtoReader = new ProtoReader(bytes);
    let dataSeen: boolean = false;
    while (root.hasMore()) {
      const tag: number = root.readTag();
      if (tag === 1 && root.wireType === WireType.LENGTH_DELIMITED) {
        if (readError(root.readMessageView(), out)) { return out; }
      } else if (tag === 2 && root.wireType === WireType.LENGTH_DELIMITED) {
        dataSeen = true;
        const data: ProtoReader = root.readMessageView();
        while (data.hasMore()) {
          const field: number = data.readTag();
          if (field === 1 && data.wireType === WireType.LENGTH_DELIMITED) {
            out.groups.push(readGroupMsg(data.readMessageView(), selfUid));
          } else if (field === 3 && data.wireType === WireType.LENGTH_DELIMITED) {
            out.userMessages.push(readMsgInfo(data.readMessageView(), BigInt(0), '', selfUid));
          } else {
            data.skipField();
          }
        }
      } else {
        root.skipField();
      }
    }
    if (!dataSeen) {
      out.code = -1;
      out.message = '同步响应缺少 data';
      return out;
    }
    out.code = 0;
    out.message = '';
  } catch (err) {
    out.code = -1;
    out.message = '同步响应无法解析';
  }
  return out;
}

function readGroupMsg(reader: ProtoReader, selfUid: bigint): ImSyncGroup {
  const group: ImSyncGroup = new ImSyncGroup();
  while (reader.hasMore()) {
    const tag: number = reader.readTag();
    if (tag === 1 && reader.wireType === WireType.LENGTH_DELIMITED) {
      const info: ImGroupSeed = readGroupInfo(reader.readMessageView());
      group.groupId = info.groupId;
      group.groupIdText = info.groupIdText;
      group.groupType = info.groupType;
      group.name = info.name;
      group.peer = info.peer;
      group.lastMsgId = info.lastMsgId;
      group.lastMsgIdText = info.lastMsgIdText;
      group.lastMsgTimeMs = info.lastMsgTimeMs;
    } else if (tag === 2 && reader.wireType === WireType.LENGTH_DELIMITED) {
      group.messages.push(readMsgInfo(reader.readMessageView(), group.groupId, group.groupIdText, selfUid));
      // 组信息缺 groupId 时，用消息自带的 groupId 补（否则会建出 key 为空的幽灵会话）
      if (group.groupIdText.length === 0 && group.messages.length > 0) {
        const last: ChatMessage = group.messages[group.messages.length - 1];
        if (last.groupId > BigInt(0)) {
          group.groupId = last.groupId;
          group.groupIdText = last.groupIdText;
        }
      }
    } else if (tag === 3 && reader.wireType === WireType.VARINT) {
      group.hasMore = reader.readInt32() !== 0;
    } else {
      reader.skipField();
    }
  }
  return group;
}

function readMsgInfo(reader: ProtoReader, groupId: bigint, groupIdText: string, selfUid: bigint): ChatMessage {
  const msg: ChatMessage = new ChatMessage();
  msg.groupId = groupId;
  msg.groupIdText = groupIdText;
  let userId: bigint = BigInt(0);
  while (reader.hasMore()) {
    const tag: number = reader.readTag();
    if (tag === 1 && reader.wireType === WireType.VARINT) {
      msg.msgId = reader.readInt64();
      msg.msgIdText = msg.msgId.toString();
    } else if (tag === 2 && reader.wireType === WireType.VARINT) {
      // 每条消息自带 groupId：GroupInfo 缺失时靠它把会话身份补回来
      msg.groupId = reader.readInt64();
      msg.groupIdText = msg.groupId.toString();
    } else if (tag === 3 && reader.wireType === WireType.VARINT) {
      msg.msgType = reader.readInt32();
    } else if (tag === 4 && reader.wireType === WireType.VARINT) {
      userId = reader.readInt64();
    } else if (tag === 5 && reader.wireType === WireType.LENGTH_DELIMITED) {
      msg.content = reader.readString();
    } else if (tag === 8 && reader.wireType === WireType.VARINT) {
      const seconds: number = reader.readInt32();
      if (seconds > 0) { msg.createTimeMs = seconds * 1000; }
    } else if (tag === 9 && reader.wireType === WireType.VARINT) {
      msg.recordId = reader.readInt64();
      msg.recordIdText = msg.recordId.toString();
    } else if (tag === 10 && reader.wireType === WireType.LENGTH_DELIMITED) {
      readPeerFromUserInfo(reader.readMessageView(), msg.peer);
    } else if (tag === 11 && reader.wireType === WireType.VARINT) {
      msg.toUid = reader.readInt64();
      msg.toUidText = msg.toUid.toString();
    } else {
      reader.skipField();
    }
  }
  // 只有「别人发的」才用 userId 补对端；自己发的消息 userId 就是 selfUid，补进去会把对端认成自己
  if (msg.peer.uid <= BigInt(0) && userId > BigInt(0) && (selfUid <= BigInt(0) || userId !== selfUid)) {
    msg.peer.uid = userId;
    msg.peer.uidText = userId.toString();
  }
  msg.fromSelf = selfUid > BigInt(0) && userId === selfUid;
  return msg;
}

/** 解析发送回执（205001）。 */
export function parseImSendAck(bytes: Uint8Array): ImSendAck {
  const out: ImSendAck = new ImSendAck();
  try {
    const root: ProtoReader = new ProtoReader(bytes);
    let dataSeen: boolean = false;
    while (root.hasMore()) {
      const tag: number = root.readTag();
      if (tag === 1 && root.wireType === WireType.LENGTH_DELIMITED) {
        if (readError(root.readMessageView(), out)) { return out; }
      } else if (tag === 2 && root.wireType === WireType.LENGTH_DELIMITED) {
        dataSeen = true;
        const data: ProtoReader = root.readMessageView();
        while (data.hasMore()) {
          const t: number = data.readTag();
          if (t === 1 && data.wireType === WireType.VARINT) {
            out.msgId = data.readInt64();
          } else if (t === 2 && data.wireType === WireType.VARINT) {
            out.groupId = data.readInt64();
          } else if (t === 3 && data.wireType === WireType.VARINT) {
            out.recordId = data.readInt64();
          } else if (t === 4 && data.wireType === WireType.VARINT) {
            out.toUid = data.readInt64();
          } else if (t === 5 && data.wireType === WireType.VARINT) {
            out.toUserType = data.readInt32();
          } else if (t === 6 && data.wireType === WireType.LENGTH_DELIMITED) {
            const block: ProtoReader = data.readMessageView();
            let blockErrno: number = 0;
            let blockMessage: string = '';
            while (block.hasMore()) {
              const b: number = block.readTag();
              if (b === 1 && block.wireType === WireType.VARINT) {
                blockErrno = block.readInt32();
              } else if (b === 2 && block.wireType === WireType.LENGTH_DELIMITED) {
                blockMessage = block.readString();
              } else {
                block.skipField();
              }
            }
            if (blockErrno !== 0) {
              out.code = blockErrno;
              out.message = blockMessage.length > 0 ? blockMessage : '消息被拦截';
              return out;
            }
          } else {
            data.skipField();
          }
        }
      } else {
        root.skipField();
      }
    }
    if (!dataSeen || out.msgId <= BigInt(0)) {
      out.code = -1;
      out.message = out.message.length > 0 ? out.message : '发送回执没有 msgId';
      return out;
    }
    out.code = 0;
    out.message = '';
  } catch (err) {
    out.code = -1;
    out.message = '发送回执无法解析';
  }
  return out;
}

/** 解析已读回执（205006）。 */
export function parseImReadAck(bytes: Uint8Array): ImReadAck {
  const out: ImReadAck = new ImReadAck();
  try {
    const root: ProtoReader = new ProtoReader(bytes);
    let dataSeen: boolean = false;
    while (root.hasMore()) {
      const tag: number = root.readTag();
      if (tag === 1 && root.wireType === WireType.LENGTH_DELIMITED) {
        if (readError(root.readMessageView(), out)) { return out; }
      } else if (tag === 2 && root.wireType === WireType.LENGTH_DELIMITED) {
        dataSeen = true;
        const data: ProtoReader = root.readMessageView();
        while (data.hasMore()) {
          const t: number = data.readTag();
          if (t === 1 && data.wireType === WireType.VARINT) {
            out.readMsgId = data.readInt64();
          } else if (t === 2 && data.wireType === WireType.VARINT) {
            out.groupId = data.readInt64();
          } else if (t === 3 && data.wireType === WireType.VARINT) {
            out.toUid = data.readInt64();
          } else if (t === 4 && data.wireType === WireType.VARINT) {
            out.toUserType = data.readInt32();
          } else {
            data.skipField();
          }
        }
      } else {
        root.skipField();
      }
    }
    out.code = dataSeen ? 0 : -1;
    if (!dataSeen) { out.message = '已读回执缺少 data'; }
  } catch (err) {
    out.code = -1;
    out.message = '已读回执无法解析';
  }
  return out;
}

/**
 * 合并消息：按 key 去重、按 msgId 升序（本地未回执的 recordId 排在最后），保留本地发送态。
 * 被合并进来的同 key 新消息以服务端为准，但 `sending`/`failed` 不被覆盖成 `sent` 之外的假状态。
 */
/**
 * 去掉重复消息（同一 `key()` 只留一条）。
 *
 * 发送回执与同步各会带来一份同一条消息：本地副本在回执前 key 是 `r<recordId>`，回执后变成 `msgId`，
 * 一旦与同步副本的 key 对上就必须合并——否则同一条消息会在气泡里出现两次。
 * 保留规则与 `mergeChatMessages` 一致：后到的字段为准，本地发送态不丢。
 */
export function dedupeChatMessages(list: ChatMessage[]): ChatMessage[] {
  return mergeChatMessages([], list);
}

export function mergeChatMessages(existing: ChatMessage[], incoming: ChatMessage[]): ChatMessage[] {
  const byKey: Map<string, ChatMessage> = new Map<string, ChatMessage>();
  const order: string[] = [];
  const put = (msg: ChatMessage): void => {
    const k: string = msg.key();
    const old: ChatMessage | undefined = byKey.get(k);
    if (old === undefined) {
      byKey.set(k, msg);
      order.push(k);
      return;
    }
    // 同 key：保留本地发送态与本地时间，其余字段取新值
    const merged: ChatMessage = msg;
    if (old.sendState !== 'sent' && merged.recordId === old.recordId) {
      merged.sendState = old.sendState;
    }
    byKey.set(k, merged);
  };
  for (let i = 0; i < existing.length; i++) { put(existing[i]); }
  for (let i = 0; i < incoming.length; i++) { put(incoming[i]); }
  const out: ChatMessage[] = [];
  for (let i = 0; i < order.length; i++) {
    const item: ChatMessage | undefined = byKey.get(order[i]);
    if (item !== undefined) { out.push(item); }
  }
  out.sort((a: ChatMessage, b: ChatMessage): number => {
    if (a.msgId > BigInt(0) && b.msgId > BigInt(0)) {
      return a.msgId < b.msgId ? -1 : (a.msgId > b.msgId ? 1 : 0);
    }
    if (a.msgId > BigInt(0)) { return -1; }
    if (b.msgId > BigInt(0)) { return 1; }
    return a.createTimeMs - b.createTimeMs;
  });
  return out;
}
