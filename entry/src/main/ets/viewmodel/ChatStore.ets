/**
 * 私信会话与消息的账号作用域内存库。
 *
 * 职责边界：
 * - 只管「当前账号」的会话/消息/游标，不做落盘（暂不引入新缓存，见 `docs/架构/缓存管理规范.md`）；
 * - 网络与加解密委托给 `net/ImSocket.ets`，这里只拼业务请求、合并结果、维护发送态；
 * - 换账号立即清空；异步结果回来时若账号已变，直接丢弃。
 */

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { authSession } from '../auth/AuthSession';
import { CHAT_HISTORY_MAX_MESSAGES_PER_GROUP } from '../model/CachePolicy';
import { RestoredChatHistory, loadChatHistory, saveChatHistory } from '../utils/ChatHistoryStore';
import { loggedInSessionKey } from './SessionOwner';
import { imSocket } from '../net/ImSocket';
import { chatLocalPrefs } from './ChatLocalPrefsStore';
import { HttpClient, HttpResult } from '../net/HttpClient';
import { decodeUtf8 } from '../utils/TextCodec';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { TiebaDevice } from '../net/TiebaParams';
import { ImCmd, ImGroupCursor, ImGroupSyncParams, ImReadParams, ImRequest, ImSendParams } from '../net/ImParams';
import {
  ChatContact, ChatContactPage, ChatGroup, ChatMessage, ChatPeer, GROUP_TYPE_PRIVATE, ImGroupSeed,
  ImInitInfo, ImPushNotify, ImReadAck, ImSendAck, ImSyncGroup, ImSyncResult, MSG_TYPE_READED,
  distinctPeerCount, dedupeChatMessages, encodeChatImageContent, matchContactGroup, mergeChatMessages,
  parseChatContacts, parseImPushNotify, parseImReadAck, parseImSendAck, parseImSync, peerThreadKey
} from '../model/Chat';

const DOMAIN: number = 0x0000;
const TAG: string = 'ChatStore';
const MAX_MESSAGES_PER_GROUP: number = CHAT_HISTORY_MAX_MESSAGES_PER_GROUP;

type ChatListener = () => void;

export class ChatStore {
  private owner: string = '';
  private selfUid: bigint = BigInt(0);
  private groups: Map<string, ChatGroup> = new Map<string, ChatGroup>();
  private messages: Map<string, ChatMessage[]> = new Map<string, ChatMessage[]>();
  private listeners: ChatListener[] = [];
  private loginTask: Promise<string> | undefined = undefined;
  private hydratedOwner: string = '';
  private persistTimer: number = -1;
  private reconnecting: boolean = false;

  /** 订阅数据变化（UI 层用它刷新 @Trace 快照）。 */
  watch(listener: ChatListener): void {
    if (this.listeners.indexOf(listener) < 0) { this.listeners.push(listener); }
  }

  unwatch(listener: ChatListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) { this.listeners.splice(index, 1); }
  }

  private notify(): void {
    for (let i = 0; i < this.listeners.length; i++) { this.listeners[i](); }
  }

  ready(): boolean {
    return this.owner.length > 0 && this.owner === loggedInSessionKey();
  }

  selfUserId(): bigint {
    return this.selfUid;
  }

  /** 会话列表快照（已按最后消息时间倒序）。 */
  groupList(): ChatGroup[] {
    // 容器组只承载 groupId 与同步游标，不进会话列表
    const out: ChatGroup[] = Array.from(this.groups.values())
      .filter((group: ChatGroup): boolean => !group.container);
    out.sort((a: ChatGroup, b: ChatGroup): number => b.sortKey() - a.sortKey());
    return out;
  }

  /** 所有私信会话的未读总数（供底栏「消息」角标合并展示）。 */
  totalUnread(): number {
    let sum: number = 0;
    this.groups.forEach((group: ChatGroup): void => {
      if (!group.container && group.unread > 0) {
        sum += group.unread;
      }
    });
    return sum;
  }

  /** 置顶/取消置顶：只影响本地排序，没有服务端接口。 */
  async togglePin(context: common.UIAbilityContext, groupIdText: string): Promise<void> {
    const group: ChatGroup | undefined = this.groups.get(groupIdText);
    if (group === undefined) { return; }
    const next: boolean = !group.pinned;
    group.pinned = next;
    this.notify();
    this.schedulePersist();
    await chatLocalPrefs.setPinned(context, groupIdText, next);
  }

  /** 删除会话（本地）：从列表移除，并记住 key，重建会话时不再自动回来。 */
  async removeGroup(context: common.UIAbilityContext, groupIdText: string): Promise<void> {
    const group: ChatGroup | undefined = this.groups.get(groupIdText);
    const uidKey: string = group !== undefined && group.peer.uid > BigInt(0)
      ? `uid:${group.peer.uidText}` : '';
    const removed: boolean = this.groups.delete(groupIdText);
    this.messages.delete(groupIdText);
    if (removed) {
      this.notify();
      this.schedulePersist();
    }
    await chatLocalPrefs.setRemoved(context, groupIdText, true);
    // contacts 会用 `u:<uid>` 把同一个会话重建出来，所以按 uid 也记一份
    if (uidKey.length > 0) {
      await chatLocalPrefs.setRemoved(context, uidKey, true);
    }
  }

  group(groupIdText: string): ChatGroup | undefined {
    return this.groups.get(groupIdText);
  }

  /**
   * 把一条消息归属到会话 key：先按对端 uid 找（自己发的用 `toUid`，收到的用 `userInfo.userId`）；
   * 找不到再看消息自带的 groupId——如果那个组是"容器"（多条私信共用一个组），就落到
   * `p:<组id>:<uid>` 这条对端会话上，绝不按组 id 存（那会把几个人的消息串在一起）。
   */
  private groupKeyForMessage(msg: ChatMessage): string {
    const peerUid: bigint = msg.fromSelf ? msg.toUid : msg.peer.uid;
    const peerText: string = msg.fromSelf ? msg.toUidText : msg.peer.uidText;
    if (peerUid > BigInt(0)) {
      const existing: string | undefined = this.keyForPeer(peerUid);
      if (existing !== undefined) { return existing; }
    }
    if (msg.groupIdText.length > 0) {
      const group: ChatGroup | undefined = this.groups.get(msg.groupIdText);
      if (group !== undefined && group.container) {
        if (peerUid <= BigInt(0)) { return ''; }
        return peerThreadKey(msg.groupIdText, peerText.length > 0 ? peerText : peerUid.toString());
      }
      return msg.groupIdText;
    }
    return peerUid > BigInt(0) ? `u:${peerText.length > 0 ? peerText : peerUid.toString()}` : '';
  }

  private keyForPeer(uid: bigint): string | undefined {
    if (uid <= BigInt(0)) { return undefined; }
    const keys: string[] = Array.from(this.groups.keys());
    for (let i = 0; i < keys.length; i++) {
      const group: ChatGroup | undefined = this.groups.get(keys[i]);
      if (group !== undefined && group.peer.uid === uid) { return keys[i]; }
    }
    return undefined;
  }

  /**
   * 从个人主页发起私聊时用：没有会话就先建一条本地直聊会话（groupId 暂时为 0）。首次发送只带
   * `toUid`，服务端回执带回真实 groupId；后续握手/同步按 uid 合并到同一条，不会出现两个会话。
   */
  directConversation(peerUidText: string, peerName: string, peerPortrait: string): ChatGroup | undefined {
    if (!authSession.isLoggedIn()) { return undefined; }
    let uid: bigint = BigInt(0);
    try { uid = BigInt(peerUidText); } catch (err) { return undefined; }
    if (uid <= BigInt(0)) { return undefined; }
    const owner: string = loggedInSessionKey();
    if (this.owner !== owner) {
      this.reset();
      this.owner = owner;
    }
    const key: string | undefined = this.keyForPeer(uid);
    if (key !== undefined) {
      const existing: ChatGroup | undefined = this.groups.get(key);
      if (existing !== undefined) { return existing; }
    }
    const group: ChatGroup = new ChatGroup();
    group.groupIdText = `u:${peerUidText}`;
    group.peer.uid = uid;
    group.peer.uidText = peerUidText;
    group.peer.userNameShow = peerName;
    group.peer.portrait = peerPortrait;
    this.groups.set(group.groupIdText, group);
    this.notify();
    return group;
  }

  messagesOf(groupIdText: string): ChatMessage[] {
    const list: ChatMessage[] | undefined = this.messages.get(groupIdText);
    return list === undefined ? [] : list.slice();
  }

  reset(): void {
    this.clearPersistTimer();
    this.owner = '';
    this.hydratedOwner = '';
    this.selfUid = BigInt(0);
    this.lastRecordId = BigInt(0);
    this.groups.clear();
    this.messages.clear();
    this.loginTask = undefined;
    this.notify();
  }

  private clearPersistTimer(): void {
    if (this.persistTimer >= 0) {
      clearTimeout(this.persistTimer);
      this.persistTimer = -1;
    }
  }

  private schedulePersist(): void {
    const ctx: common.UIAbilityContext | undefined = this.appContext;
    const owner: string = this.owner;
    if (ctx === undefined || owner.length === 0) { return; }
    this.clearPersistTimer();
    this.persistTimer = setTimeout((): void => {
      this.persistTimer = -1;
      if (this.owner !== owner || this.appContext === undefined) { return; }
      void saveChatHistory(this.appContext, owner, Array.from(this.groups.values()), this.messages);
    }, 500);
  }

  private async hydrateFromDisk(context: common.UIAbilityContext, owner: string): Promise<void> {
    if (this.hydratedOwner === owner) { return; }
    this.hydratedOwner = owner;
    await chatLocalPrefs.load(context);
    const restored: RestoredChatHistory = await loadChatHistory(context, owner);
    if (this.owner !== owner) { return; }
    let changed: boolean = false;
    for (const group of restored.groups) {
      if (chatLocalPrefs.isRemoved(group.groupIdText)) { continue; }
      if (group.peer.uid > BigInt(0) && chatLocalPrefs.isRemoved(`uid:${group.peer.uidText}`)) { continue; }
      if (chatLocalPrefs.isPinned(group.groupIdText)) { group.pinned = true; }
      const existing: ChatGroup | undefined = this.groups.get(group.groupIdText);
      if (existing === undefined) {
        this.groups.set(group.groupIdText, group);
        changed = true;
      } else {
        if (existing.peer.uid <= BigInt(0) && group.peer.uid > BigInt(0)) {
          existing.peer = group.peer;
          changed = true;
        }
        if (existing.lastMessage === undefined && group.lastMessage !== undefined) {
          existing.lastMessage = group.lastMessage;
          existing.lastMsgTimeMs = group.lastMsgTimeMs;
          changed = true;
        }
      }
      const diskMsgs: ChatMessage[] | undefined = restored.messages.get(group.groupIdText);
      if (diskMsgs !== undefined && diskMsgs.length > 0) {
        const current: ChatMessage[] = this.messages.get(group.groupIdText) ?? [];
        const merged: ChatMessage[] = mergeChatMessages(diskMsgs, current);
        const trimmed: ChatMessage[] = merged.length > MAX_MESSAGES_PER_GROUP
          ? merged.slice(merged.length - MAX_MESSAGES_PER_GROUP) : merged;
        this.messages.set(group.groupIdText, dedupeChatMessages(trimmed));
        const target: ChatGroup | undefined = this.groups.get(group.groupIdText);
        if (target !== undefined && trimmed.length > 0) {
          const tail: ChatMessage = trimmed[trimmed.length - 1];
          if (target.lastMessage === undefined || tail.createTimeMs >= target.lastMsgTimeMs) {
            target.lastMessage = tail;
            target.lastMsgTimeMs = tail.createTimeMs;
          }
        }
        changed = true;
      }
    }
    if (changed) { this.notify(); }
  }

  /** 应用回前台时保活重连并同步增量；未进入过私信或未登录时不做额外建连。 */
  async syncOnForeground(context: common.UIAbilityContext): Promise<void> {
    this.appContext = context;
    if (!authSession.isLoggedIn()) {
      if (this.owner.length > 0) { this.reset(); }
      return;
    }
    const owner: string = loggedInSessionKey();
    if (owner.length === 0 || this.owner !== owner) { return; }
    if (!imSocket.isReady()) {
      await this.syncAll(context);
    }
  }

  private async reconnectOnDrop(): Promise<void> {
    if (this.reconnecting) { return; }
    const ctx: common.UIAbilityContext | undefined = this.appContext;
    if (ctx === undefined || !authSession.isLoggedIn()) { return; }
    const owner: string = loggedInSessionKey();
    if (owner.length === 0 || owner !== this.owner) { return; }
    this.reconnecting = true;
    try {
      await this.syncAll(ctx);
    } finally {
      this.reconnecting = false;
    }
  }

  /** 保证连接与握手就绪。返回空串表示成功，否则是可直接展示给用户的失败原因。 */
  async ensure(context: common.UIAbilityContext): Promise<string> {
    this.appContext = context;
    if (!authSession.isLoggedIn()) { return '登录后查看私信'; }
    const owner: string = loggedInSessionKey();
    if (owner.length === 0) { return '登录后查看私信'; }
    if (this.owner !== owner) {
      this.reset();
      this.owner = owner;
    }
    await this.hydrateFromDisk(context, owner);
    if (this.owner !== owner) { return ''; }
    if (this.loginTask !== undefined) { return this.loginTask; }
    const task: Promise<string> = this.doLogin(owner, context);
    this.loginTask = task;
    try {
      return await task;
    } finally {
      if (this.loginTask === task) { this.loginTask = undefined; }
    }
  }

  private async doLogin(owner: string, context: common.UIAbilityContext): Promise<string> {
    try {
      // full 握手（真实设备串 + STOKEN）能降低私信被风控判「涉嫌违规」的概率；
      // 拿不到设备身份时退回最小握手，不影响连通性。
      let device: TiebaDevice | undefined = undefined;
      try {
        device = await DeviceIdentity.ensure(context);
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'device identity unavailable, fell back to minimal handshake');
      }
      // 先读本地置顶/删除偏好，applySeeds 要用它过滤
      await chatLocalPrefs.load(context);
      const info: ImInitInfo = await imSocket.login(authSession.session(), owner, device);
      if (this.owner !== owner) { return ''; }
      this.selfUid = info.userId;
      this.applySeeds(info.groups);
      this.bindPush();
      this.notify();
      // 私信组的 `GroupInfo.authorId` 是自己（不是对端），拿不到对端 uid；
      // 先用 web contacts 异步补，补不上就保持 uid=0（发送会被拦下，不会发错人）。
      void this.loadContacts(owner);
      return '';
    } catch (err) {
      const message: string = err instanceof Error ? (err as Error).message : '私信通道连接失败';
      hilog.warn(DOMAIN, TAG, 'login failed: %{public}s', message);
      return message;
    }
  }

  private contactsLoading: boolean = false;
  private pushBound: boolean = false;
  /** 推送 handler 里没有 context，登录时留一份，用来清 removed 记录。 */
  private appContext: common.UIAbilityContext | undefined = undefined;

  /**
   * 订阅 202006 新消息推送：只带会话 id 与最新消息 id，收到后按「最新-1」拉该会话增量。
   *
   * 游标必须是 `newestMsgId - 1`：202003 不接受 0，也不接受“最新”（都返回 0 条），只有给一个
   * 比它小的真实 id 才会返回它之后的消息。
   */
  private bindPush(): void {
    if (this.pushBound) { return; }
    this.pushBound = true;
    imSocket.onReconnectNeeded((): void => {
      void this.reconnectOnDrop();
    });
    imSocket.onPush(ImCmd.PUSH_NOTIFY, (body: Uint8Array): void => {
      const notify: ImPushNotify | undefined = parseImPushNotify(body);
      if (notify === undefined) {
        // 打前 48 字节的十六进制：用于判断推送体到底是 JSON 还是 protobuf
        let hex: string = '';
        const limit: number = Math.min(body.length, 48);
        for (let i = 0; i < limit; i++) {
          const byte: number = body[i];
          hex += byte < 16 ? `0${byte.toString(16)}` : byte.toString(16);
        }
        hilog.warn(DOMAIN, TAG, 'push notify parse failed len=%{public}d hex=%{public}s',
          body.length, hex);
        return;
      }
      hilog.info(DOMAIN, TAG, 'push notify gid=%{public}s groupType=%{public}d newest=%{public}s',
        notify.groupIdText.length > 0 ? notify.groupIdText : '(none)',
        notify.groupType, notify.newestMsgIdText.length > 0 ? notify.newestMsgIdText : '(none)');
      if (notify.groupType !== GROUP_TYPE_PRIVATE || notify.groupId <= BigInt(0)) { return; }
      if (notify.newestMsgId <= BigInt(0)) { return; }
      void this.onPushed(notify);
    });
  }

  private async onPushed(notify: ImPushNotify): Promise<void> {
    const owner: string = this.owner;
    const key: string = notify.groupIdText;
    const group: ChatGroup | undefined = this.groups.get(key);
    if (group === undefined) {
      // 本地没有这个会话（首次来信，或会话被删过）：按推送的 groupId 拉一次，
      // applySync 会把会话建出来；否则"没有消息框就永远收不到消息"。
      const ctx: common.UIAbilityContext | undefined = this.appContext;
      if (ctx !== undefined && chatLocalPrefs.isRemoved(key)) {
        await chatLocalPrefs.setRemoved(ctx, key, false);
      }
      await this.pullGroupFromPush(notify);
      // 重建出来的会话也要算一条未读，否则回来是回来了、却没有红点
      const created: ChatGroup | undefined = this.groups.get(key);
      if (created !== undefined) {
        created.unread += 1;
        this.notify();
      }
      return;
    }
    // 推送即未读：进会话页 / 上报已读时清零
    group.unread += 1;
    this.notify();
    const cursor: ImGroupCursor = new ImGroupCursor();
    cursor.groupId = notify.groupId;
    cursor.groupIdText = key;
    cursor.lastMsgId = notify.newestMsgId > BigInt(1) ? notify.newestMsgId - BigInt(1) : BigInt(0);
    cursor.lastMsgIdText = cursor.lastMsgId.toString();
    await this.syncWith([cursor]);
    if (this.owner !== owner) { return; }
  }

  /** 推送里的未知会话：按 groupId + newestMsgId 拉一次增量，applySync 会把会话建出来。 */
  private async pullGroupFromPush(notify: ImPushNotify): Promise<void> {
    const cursor: ImGroupCursor = new ImGroupCursor();
    cursor.groupId = notify.groupId;
    cursor.groupIdText = notify.groupIdText;
    cursor.lastMsgId = notify.newestMsgId > BigInt(1) ? notify.newestMsgId - BigInt(1) : BigInt(1);
    cursor.lastMsgIdText = cursor.lastMsgId.toString();
    await this.syncWith([cursor]);
  }

  /**
   * 拉 web `getContacts` 补对端身份。WS 的 `GroupInfo` 只有 `authorId`（值为自己）、组名、组头像，
   * 没有对端 uid；没有 uid 就没法填 205001 的 `toUid`（填错会把消息发成「别人发给我」）。
   * 失败时保持 uid=0，发送入口会拒绝并提示刷新。
   */
  private async loadContacts(owner: string): Promise<void> {
    if (this.contactsLoading) { return; }
    this.contactsLoading = true;
    try {
      const session = authSession.session();
      if (session.bduss.length === 0) { return; }
      const client: HttpClient = new HttpClient();
      client.userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        + ' (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
      const cookie: string = `BDUSS=${session.bduss}; STOKEN=${session.stoken}`;
      const url: string = `https://tieba.baidu.com/im/pcmsg/query/getContacts?offset=0&_=${Date.now()}`;
      const res: HttpResult = await client.getWithCookie(url, cookie, {
        'Referer': 'https://tieba.baidu.com/im/pcmsg',
        'X-Requested-With': 'XMLHttpRequest'
      });
      if (this.owner !== owner) { return; }
      if (!res.ok) {
        hilog.warn(DOMAIN, TAG, 'contacts http=%{public}d', res.code);
        return;
      }
      const page: ChatContactPage = parseChatContacts(decodeUtf8(res.bytes));
      if (page.errno !== 0) {
        hilog.warn(DOMAIN, TAG, 'contacts errno=%{public}d', page.errno);
        return;
      }
      this.applyContacts(page.contacts);
      this.notify();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'contacts failed: %{public}s',
        err instanceof Error ? (err as Error).message : 'unknown');
    } finally {
      this.contactsLoading = false;
    }
  }

  /** 把 contacts 里的 uid/昵称/头像/未读贴到已有会话上；对不上的按 `u:<uid>` 新建。 */
  private applyContacts(contacts: ChatContact[]): void {
    for (let i = 0; i < contacts.length; i++) {
      const contact: ChatContact = contacts[i];
      const uid: bigint = BigInt(contact.uid);
      if (uid <= BigInt(0) || uid === this.selfUid) { continue; }
      const target: ChatGroup | undefined = matchContactGroup(this.groupList(), uid, contact.portrait,
        BigInt(contact.lastMsgId));
      const group: ChatGroup | undefined = target !== undefined ? target : this.contactOnlyGroup(contact);
      if (group === undefined) { continue; }
      if (group.peer.uid > BigInt(0) && group.peer.uid !== uid) {
        // 这条会话已经是别人的：不能拿另一条 contact 的昵称头像去覆盖，否则标题和收件人就会分家。
        hilog.warn(DOMAIN, TAG, 'contact %{public}s skipped: group %{public}s belongs to %{public}s',
          String(contact.uid), group.groupIdText, group.peer.uid.toString());
        continue;
      }
      if (!group.peerFromMessage) {
        group.peer.uid = uid;
        group.peer.uidText = String(contact.uid);
        group.peerFromContact = true;
        if (target !== undefined) {
          hilog.info(DOMAIN, TAG, 'contact identity: group=%{public}s uid=%{public}s',
            group.groupIdText, String(contact.uid));
        }
      }
      if (group.peer.uid === uid) { this.dedupeByPeer(uid, group.groupIdText); }
      if (contact.showNickname.length > 0) { group.peer.userNameShow = contact.showNickname; }
      if (contact.uname.length > 0 && contact.uname !== String(contact.uid)) {
        group.peer.userName = contact.uname;
      }
      if (contact.portrait.length > 0) { group.peer.portrait = contact.portrait; }
      group.unread = contact.unread;
      if (contact.lastMsgId > 0 && BigInt(contact.lastMsgId) > group.lastMsgId) {
        group.lastMsgId = BigInt(contact.lastMsgId);
        group.lastMsgIdText = String(contact.lastMsgId);
      }
    }
    let withUid: number = 0;
    const keys: string[] = Array.from(this.groups.keys());
    for (let i = 0; i < keys.length; i++) {
      const one: ChatGroup | undefined = this.groups.get(keys[i]);
      if (one !== undefined && one.peer.uid > BigInt(0)) { withUid++; }
    }
    hilog.info(DOMAIN, TAG, 'contacts applied: contacts=%{public}d groups=%{public}d withUid=%{public}d',
      contacts.length, this.groups.size, withUid);
  }

  /** 没有可信对应关系的 contact：按 uid 建/取一条只带身份的本地会话；本机删过的会话不再建回来。 */
  private contactOnlyGroup(contact: ChatContact): ChatGroup | undefined {
    if (chatLocalPrefs.isRemoved(`uid:${contact.uid}`)) { return undefined; }
    const key: string = `u:${contact.uid}`;
    const existing: ChatGroup | undefined = this.groups.get(key);
    if (existing !== undefined) { return existing; }
    const created: ChatGroup = new ChatGroup();
    created.groupIdText = key;
    created.pinned = chatLocalPrefs.isPinned(key);
    this.groups.set(key, created);
    return created;
  }

  /**
   * 用一条收到的消息确定对端身份：消息发送者是权威来源，确定后 contacts 不再改写。
   * 之前若被 contacts 猜成别人，这里纠正并清掉旧昵称头像，等 contacts 重新补。
   */
  private adoptPeerFromMessage(group: ChatGroup, uid: bigint, uidText: string, userName: string,
    userNameShow: string, portrait: string, source: string): void {
    if (uid <= BigInt(0) || group.multiPeer) { return; }
    if (group.peer.uid !== uid) {
      if (group.peerFromMessage) {
        hilog.warn(DOMAIN, TAG, 'peer conflict: group=%{public}s keep=%{public}s msg=%{public}s',
          group.groupIdText, group.peer.uid.toString(), uid.toString());
        return;
      }
      group.peer.userName = '';
      group.peer.userNameShow = '';
      group.peer.portrait = '';
      hilog.info(DOMAIN, TAG, 'peer corrected by %{public}s: group=%{public}s from=%{public}s to=%{public}s',
        source, group.groupIdText, group.peer.uid.toString(), uid.toString());
    }
    group.peer.uid = uid;
    group.peer.uidText = uidText.length > 0 ? uidText : uid.toString();
    group.peerFromMessage = true;
    group.peerFromContact = false;
    if (userName.length > 0) { group.peer.userName = userName; }
    if (userNameShow.length > 0) { group.peer.userNameShow = userNameShow; }
    if (portrait.length > 0) { group.peer.portrait = portrait; }
    this.dedupeByPeer(uid, group.groupIdText);
  }

  /**
   * 组里出现第二个发送者就判定为群聊：清掉猜出来的对端身份（它只会是"某一个成员"），
   * 界面改显示组名，发送由 `send()` 拦下。
   */
  private markMultiPeer(group: ChatGroup, messages: ChatMessage[]): void {
    if (group.multiPeer || distinctPeerCount(messages) <= 1) { return; }
    group.multiPeer = true;
    group.peer = new ChatPeer();
    group.peerFromMessage = false;
    group.peerFromContact = false;
    hilog.warn(DOMAIN, TAG, 'multi-peer group: %{public}s — peer identity cleared', group.groupIdText);
  }

  /** 某个真实 groupId 对应的容器组：只存组身份与同步游标，不出现在会话列表。 */
  private containerFor(gid: string, groupId: bigint, groupType: number, name: string): ChatGroup {
    let group: ChatGroup | undefined = this.groups.get(gid);
    if (group === undefined) {
      group = new ChatGroup();
      group.groupIdText = gid;
      this.groups.set(gid, group);
    }
    group.container = true;
    group.groupType = groupType === 0 ? GROUP_TYPE_PRIVATE : groupType;
    if (group.groupId <= BigInt(0) && groupId > BigInt(0)) { group.groupId = groupId; }
    if (group.name.length === 0 && name.length > 0) { group.name = name; }
    return group;
  }

  /** 容器组里某个对端的会话；身份来自消息发送者，昵称头像等 contacts 补齐。 */
  private threadFor(container: ChatGroup, uid: bigint, uidText: string,
    peer: ChatPeer | undefined): ChatGroup {
    const text: string = uidText.length > 0 ? uidText : uid.toString();
    const key: string = peerThreadKey(container.groupIdText, text);
    let thread: ChatGroup | undefined = this.groups.get(key);
    if (thread === undefined) {
      thread = new ChatGroup();
      thread.groupIdText = key;
      this.groups.set(key, thread);
      hilog.info(DOMAIN, TAG, 'peer thread: %{public}s uid=%{public}s', key, text);
    }
    if (thread.groupId <= BigInt(0) && container.groupId > BigInt(0)) { thread.groupId = container.groupId; }
    thread.groupType = container.groupType;
    thread.peer.uid = uid;
    thread.peer.uidText = text;
    thread.peerFromMessage = true;
    thread.peerFromContact = false;
    if (peer !== undefined) {
      if (thread.peer.userName.length === 0) { thread.peer.userName = peer.userName; }
      if (thread.peer.userNameShow.length === 0) { thread.peer.userNameShow = peer.userNameShow; }
      if (thread.peer.portrait.length === 0) { thread.peer.portrait = peer.portrait; }
    }
    this.dedupeByPeer(uid, thread.groupIdText);
    return thread;
  }

  /**
   * 一个对端只保留一条会话：身份确认后，把重复的本地会话（`u:<uid>`，或者先建成后来才对上号的那条）
   * 并进**有真实 groupId** 的那条，再删掉多余的 key。不并会同时出现两行同名会话，消息也会分家。
   */
  private dedupeByPeer(uid: bigint, keepKey: string): void {
    if (uid <= BigInt(0)) { return; }
    const keys: string[] = Array.from(this.groups.keys());
    let canonical: string = keepKey;
    let canonicalGroup: ChatGroup | undefined = this.groups.get(canonical);
    for (let i = 0; i < keys.length; i++) {
      const group: ChatGroup | undefined = this.groups.get(keys[i]);
      if (group === undefined || group.peer.uid !== uid) { continue; }
      if (canonicalGroup === undefined || (group.groupId > BigInt(0) && canonicalGroup.groupId <= BigInt(0))) {
        canonical = keys[i];
        canonicalGroup = group;
      }
    }
    if (canonicalGroup === undefined) { return; }
    for (let i = 0; i < keys.length; i++) {
      const otherKey: string = keys[i];
      if (otherKey === canonical) { continue; }
      const other: ChatGroup | undefined = this.groups.get(otherKey);
      if (other === undefined || other.peer.uid !== uid) { continue; }
      const merged: ChatMessage[] = mergeChatMessages(this.messages.get(canonical) ?? [],
        this.messages.get(otherKey) ?? []);
      this.messages.set(canonical, merged);
      this.messages.delete(otherKey);
      if (other.pinned) { canonicalGroup.pinned = true; }
      if (canonicalGroup.peer.userNameShow.length === 0) {
        canonicalGroup.peer.userNameShow = other.peer.userNameShow;
      }
      if (canonicalGroup.peer.userName.length === 0) { canonicalGroup.peer.userName = other.peer.userName; }
      if (canonicalGroup.peer.portrait.length === 0) { canonicalGroup.peer.portrait = other.peer.portrait; }
      if (other.lastMsgId > canonicalGroup.lastMsgId) {
        canonicalGroup.lastMsgId = other.lastMsgId;
        canonicalGroup.lastMsgIdText = other.lastMsgIdText;
      }
      this.groups.delete(otherKey);
      hilog.info(DOMAIN, TAG, 'peer dedupe: uid=%{public}s keep=%{public}s drop=%{public}s',
        uid.toString(), canonical, otherKey);
    }
  }

  /** 握手返回的会话种子：只收私信组，保留已有消息与本地发送态。 */
  private applySeeds(seeds: ImGroupSeed[]): void {
    for (let i = 0; i < seeds.length; i++) {
      const seed: ImGroupSeed = seeds[i];
      if (seed.groupType !== GROUP_TYPE_PRIVATE) { continue; }
      if (chatLocalPrefs.isRemoved(seed.groupIdText)) { continue; }
      let key: string = seed.groupIdText;
      let existing: ChatGroup | undefined = this.groups.get(key);
      if (existing === undefined) {
        const byPeer: string | undefined = this.keyForPeer(seed.peer.uid);
        if (byPeer !== undefined) {
          key = byPeer;
          existing = this.groups.get(byPeer);
        }
      }
      if (existing === undefined) {
        const group: ChatGroup = new ChatGroup();
        group.groupId = seed.groupId;
        group.groupIdText = key;
        group.groupType = seed.groupType;
        group.name = seed.name;
        group.peer = seed.peer;
        // 种子只知道组、不知道对端（authorId 是自己）：先当容器，消息到了再按发送者拆出对端会话
        group.container = true;
        group.lastMsgId = seed.lastMsgId;
        group.lastMsgIdText = seed.lastMsgIdText;
        group.lastMsgTimeMs = seed.lastMsgTimeMs;
        group.pinned = chatLocalPrefs.isPinned(key);
        this.groups.set(key, group);
        continue;
      }
      // 已有会话：直聊会话借这次握手补上真实 groupId；其余只补空字段，不覆盖本地已知的最后一条消息
      if (existing.groupId <= BigInt(0) && seed.groupId > BigInt(0)) {
        existing.groupId = seed.groupId;
      }
      if (existing.peer.uid <= BigInt(0) && seed.peer.uid > BigInt(0)) { existing.peer = seed.peer; }
      if (existing.peer.userName.length === 0 && seed.peer.userName.length > 0) {
        existing.peer.userName = seed.peer.userName;
      }
      if (existing.peer.userNameShow.length === 0 && seed.peer.userNameShow.length > 0) {
        existing.peer.userNameShow = seed.peer.userNameShow;
      }
      if (existing.name.length === 0) { existing.name = seed.name; }
      if (seed.lastMsgId > existing.lastMsgId) {
        existing.lastMsgId = seed.lastMsgId;
        existing.lastMsgIdText = seed.lastMsgIdText;
      }
    }
  }

  /** 这个真实组是否已经有拆出来的对端会话（有就不用从头拉历史）。 */
  private hasThreadOf(container: ChatGroup): boolean {
    const keys: string[] = Array.from(this.groups.keys());
    for (let i = 0; i < keys.length; i++) {
      const group: ChatGroup | undefined = this.groups.get(keys[i]);
      if (group === undefined || group.container) { continue; }
      if (group.groupId === container.groupId && group.groupId > BigInt(0)) { return true; }
    }
    return false;
  }

  /** 拉取全部会话增量；返回空串表示成功。 */
  async syncAll(context: common.UIAbilityContext): Promise<string> {
    const failure: string = await this.ensure(context);
    if (failure.length > 0) { return failure; }
    // 同步按"真实组"发：容器组各持一个真实 groupId 与游标；对端会话共享同一个 groupId，不能各发一次。
    const all: ChatGroup[] = Array.from(this.groups.values());
    const cursors: ImGroupCursor[] = [];
    for (let i = 0; i < all.length; i++) {
      // 没有真实 groupId 的本地直聊会话不发同步（服务端不认 groupId=0）
      if (!all[i].container || all[i].groupId <= BigInt(0)) { continue; }
      // 还没有任何对端消息时要“从头拉”：用组的最新 lastMsgId 当游标只会拿到增量，历史永远不出现
      const fresh: boolean = !this.hasThreadOf(all[i]);
      cursors.push(ChatStore.cursorOf(all[i], fresh || all[i].lastMsgId <= BigInt(0)));
    }
    if (cursors.length === 0) { return ''; }
    return this.syncWith(cursors);
  }

  /** 打开单会话：本地还没有消息时按 lastMsgId=0 拉最近一批。 */
  async openConversation(context: common.UIAbilityContext, groupIdText: string): Promise<string> {
    const failure: string = await this.ensure(context);
    if (failure.length > 0) { return failure; }
    const group: ChatGroup | undefined = this.groups.get(groupIdText);
    if (group === undefined) { return '会话不存在'; }
    // 个人主页刚开的本地直聊会话还没有真实 groupId，同步请求不能拿 0 去问服务端。
    if (group.groupId <= BigInt(0)) { return ''; }
    const existing: ChatMessage[] = this.messages.get(groupIdText) ?? [];
    if (existing.length > 0) { return ''; }
    return this.syncWith([ChatStore.cursorOf(group, true)]);
  }

  /** 连续已读回执合并成一条：服务端会为每条被读消息各推一条 type=22。 */
  private static dedupReaded(list: ChatMessage[]): ChatMessage[] {
    const out: ChatMessage[] = [];
    for (let i = 0; i < list.length; i++) {
      const cur: ChatMessage = list[i];
      if (cur.msgType === MSG_TYPE_READED && i + 1 < list.length
        && list[i + 1].msgType === MSG_TYPE_READED) {
        continue;
      }
      out.push(cur);
    }
    return out;
  }

  private static cursorOf(group: ChatGroup, fromZero: boolean): ImGroupCursor {
    const cursor: ImGroupCursor = new ImGroupCursor();
    cursor.groupId = group.groupId;
    cursor.groupIdText = group.groupIdText;
    /*
     * 首次拉传 **1** 而不是 0：202003 把 0 当成“没有游标”（返回 0 条），传最新 id 也只回到最新
     * 那一条。所以“从头发”用 1，“增量”用已知的最后一条 msgId。
     */
    cursor.lastMsgId = fromZero ? BigInt(1) : group.lastMsgId;
    cursor.lastMsgIdText = cursor.lastMsgId.toString();
    return cursor;
  }

  private async syncWith(cursors: ImGroupCursor[]): Promise<string> {
    if (cursors.length === 0) { return ''; }
    const owner: string = this.owner;
    try {
      const req: ImRequest = ImGroupSyncParams.build(cursors);
      const body: Uint8Array = await imSocket.request(req);
      if (this.owner !== owner) { return ''; }
      const result: ImSyncResult = parseImSync(body, this.selfUid);
      if (result.code !== 0) { return result.message.length > 0 ? result.message : '私信同步失败'; }
      await this.applySync(result);
      this.notify();
      this.schedulePersist();
      return '';
    } catch (err) {
      const message: string = err instanceof Error ? (err as Error).message : '私信同步失败';
      hilog.warn(DOMAIN, TAG, 'sync failed: %{public}s', message);
      return message;
    }
  }

  private async applySync(result: ImSyncResult): Promise<void> {
    for (let i = 0; i < result.groups.length; i++) {
      const incoming: ImSyncGroup = result.groups[i];
      if (incoming.groupType !== 0 && incoming.groupType !== GROUP_TYPE_PRIVATE) { continue; }
      const gid: string = incoming.groupIdText;
      // 既没有组身份又没有消息的增量无法归属到任何会话，丢弃而不是建 ghost 行
      if (gid.length === 0) { continue; }
      // 服务端会把多条私信塞进同一个组（实测「我的私聊」里有 4 个发送者）。
      // 组本身只当容器/同步游标，消息按对端拆进 `p:<组id>:<uid>`，一条会话只属于一个人。
      const container: ChatGroup = this.containerFor(gid, incoming.groupId, incoming.groupType, incoming.name);
      if (distinctPeerCount(incoming.messages) > 1) { container.multiPeer = true; }
      let batchLast: bigint = incoming.lastMsgId;
      for (let j = 0; j < incoming.messages.length; j++) {
        const msg: ChatMessage = incoming.messages[j];
        const peerUid: bigint = msg.fromSelf ? msg.toUid : msg.peer.uid;
        const peerText: string = msg.fromSelf ? msg.toUidText : msg.peer.uidText;
        if (peerUid <= BigInt(0)) { continue; }
        const thread: ChatGroup = this.threadFor(container, peerUid, peerText,
          msg.fromSelf ? undefined : msg.peer);
        // 归属改写成对端会话 key：去重键用的是 groupIdText，留着容器 id 会把同一条消息算成两条
        msg.groupIdText = thread.groupIdText;
        const merged: ChatMessage[] = mergeChatMessages(this.messages.get(thread.groupIdText) ?? [], [msg]);
        const trimmed: ChatMessage[] = merged.length > MAX_MESSAGES_PER_GROUP
          ? merged.slice(merged.length - MAX_MESSAGES_PER_GROUP) : merged;
        this.messages.set(thread.groupIdText, dedupeChatMessages(ChatStore.dedupReaded(trimmed)));
        thread.lastMessage = msg;
        thread.lastMsgTimeMs = msg.createTimeMs;
        if (msg.msgId > thread.lastMsgId) {
          thread.lastMsgId = msg.msgId;
          thread.lastMsgIdText = msg.msgIdText;
        }
        if (msg.msgId > batchLast) { batchLast = msg.msgId; }
      }
      if (batchLast > container.lastMsgId) {
        container.lastMsgId = batchLast;
        container.lastMsgIdText = batchLast.toString();
      }
    }
    // data.userMsg(3)：私聊消息可能只在这里，按消息自带 groupId 归组
    if (result.userMessages.length > 0) {
      const byGroup: Map<string, ChatMessage[]> = new Map<string, ChatMessage[]>();
      for (let i = 0; i < result.userMessages.length; i++) {
        const msg: ChatMessage = result.userMessages[i];
        const gid: string = this.groupKeyForMessage(msg);
        if (gid.length === 0) { continue; }
        const list: ChatMessage[] = byGroup.get(gid) ?? [];
        list.push(msg);
        byGroup.set(gid, list);
      }
      const groupIds: string[] = Array.from(byGroup.keys());
      for (let i = 0; i < groupIds.length; i++) {
        const gid: string = groupIds[i];
        const incoming: ChatMessage[] = byGroup.get(gid) ?? [];
        let group: ChatGroup | undefined = this.groups.get(gid);
        if (group === undefined) {
          group = new ChatGroup();
          group.groupId = incoming.length > 0 ? incoming[0].groupId : BigInt(0);
          group.groupIdText = gid;
          if (incoming.length > 0) {
            const first: ChatMessage = incoming[0];
            if (first.fromSelf && first.toUid > BigInt(0)) {
              group.peer.uid = first.toUid;
              group.peer.uidText = first.toUidText;
            } else if (first.peer.uid > BigInt(0)) {
              group.peer = first.peer;
            }
          }
          this.groups.set(gid, group);
        }
        const incomingForGroup: ChatMessage[] = incoming;
        for (let k = 0; k < incomingForGroup.length; k++) { incomingForGroup[k].groupIdText = gid; }
        const merged: ChatMessage[] = mergeChatMessages(this.messages.get(gid) ?? [], incomingForGroup);
        this.markMultiPeer(group, incoming);
        const trimmed: ChatMessage[] = merged.length > MAX_MESSAGES_PER_GROUP
          ? merged.slice(merged.length - MAX_MESSAGES_PER_GROUP) : merged;
        const visible: ChatMessage[] = ChatStore.dedupReaded(trimmed);
        this.messages.set(gid, dedupeChatMessages(visible));
        if (visible.length > 0) {
          const last: ChatMessage = visible[visible.length - 1];
          group.lastMessage = last;
          group.lastMsgTimeMs = last.createTimeMs;
          if (last.msgId > group.lastMsgId) {
            group.lastMsgId = last.msgId;
            group.lastMsgIdText = last.msgIdText;
          }
          if (last.fromSelf) {
            if (group.peer.uid <= BigInt(0) && last.toUid > BigInt(0)) {
              group.peer.uid = last.toUid;
              group.peer.uidText = last.toUidText;
              this.dedupeByPeer(last.toUid, group.groupIdText);
            }
          } else {
            this.adoptPeerFromMessage(group, last.peer.uid, last.peer.uidText, last.peer.userName,
              last.peer.userNameShow, last.peer.portrait, 'userMsg');
          }
        }
      }
    }
    // 新消息到达：本地删除过的会话要能回来（清掉 removed），否则删了就永远收不到
    const ctx: common.UIAbilityContext | undefined = this.appContext;
    if (ctx === undefined) { return; }
    for (let i = 0; i < result.groups.length; i++) {
      const gid: string = result.groups[i].groupIdText;
      if (gid.length === 0) { continue; }
      if (chatLocalPrefs.isRemoved(gid)) {
        await chatLocalPrefs.setRemoved(ctx, gid, false);
      }
      const group: ChatGroup | undefined = this.groups.get(gid);
      const uid: string = group !== undefined ? group.peer.uidText : '';
      if (uid.length > 0 && chatLocalPrefs.isRemoved(`uid:${uid}`)) {
        await chatLocalPrefs.setRemoved(ctx, `uid:${uid}`, false);
      }
    }
  }

  /**
   * 发送文字私信。先本地乐观插入（sending），回执到达后替换为服务端 msgId；失败保留消息并置
   * failed，不自动重发。`onEnqueued` 仅在通过前置校验并写入本地气泡后触发。
   */
  async send(context: common.UIAbilityContext, groupIdText: string, text: string,
    onEnqueued?: () => void): Promise<string> {
    const content: string = text.trim();
    if (content.length === 0) { return ''; }
    return this.sendPayload(context, groupIdText, content, ImSendParams.MSG_TYPE_TEXT, onEnqueued);
  }

  /** 发送图片私信（msgType=2，官方 PicMessageData JSON 数组）。 */
  async sendImage(context: common.UIAbilityContext, groupIdText: string, imageUrl: string,
    width: number, height: number, onEnqueued?: () => void, bigUrl: string = ''): Promise<string> {
    const payload: string = encodeChatImageContent(imageUrl, width, height, bigUrl);
    if (payload.length === 0) { return '图片地址无效'; }
    return this.sendPayload(context, groupIdText, payload, ImSendParams.MSG_TYPE_IMAGE, onEnqueued);
  }

  private async sendPayload(context: common.UIAbilityContext, groupIdText: string, content: string,
    msgType: number, onEnqueued?: () => void): Promise<string> {
    const failure: string = await this.ensure(context);
    if (failure.length > 0) { return failure; }
    const group: ChatGroup | undefined = this.groups.get(groupIdText);
    if (group === undefined) { return '会话不存在'; }
    if (group.multiPeer) {
      // 组里有多个发送者：没有唯一收件人。猜一个成员发出去，就是给别人发错消息。
      hilog.warn(DOMAIN, TAG, 'refuse send: multi-peer group=%{public}s', groupIdText);
      return '这个会话里有多个成员，私信暂不支持群发';
    }
    const peerUid: bigint = group.peer.uid;
    if (peerUid <= BigInt(0)) { return '还没识别出对方账号，先刷新会话列表'; }
    if (this.selfUid > BigInt(0) && peerUid === this.selfUid) {
      // 事故防线：曾把 GroupInfo.authorId（=自己）当成对端，toUid 填成自己，服务端把消息记成
      // 「别人发给我」。这里直接拦死。
      hilog.error(DOMAIN, TAG, 'refuse send: peer==self');
      return '对方账号识别有误，已阻止发送';
    }
    const owner: string = this.owner;
    // recordId 按官方实现的口径生成（小数值、单调）：`max(上一条本地号, 该会话 lastMsgId*100)+1`。
    // 不用时间戳：时间戳量级的 recordId 发出后服务端没有回包。
    const recordId: bigint = this.nextRecordId(group);
    const local: ChatMessage = new ChatMessage();
    local.groupId = group.groupId;
    local.groupIdText = groupIdText;
    local.recordId = recordId;
    local.recordIdText = recordId.toString();
    local.peer = group.peer;
    local.content = content;
    local.msgType = msgType;
    local.fromSelf = true;
    local.createTimeMs = Date.now();
    local.sendState = 'sending';
    this.appendLocal(groupIdText, local);
    this.notify();
    if (onEnqueued !== undefined) { onEnqueued(); }
    try {
      const req: ImRequest = ImSendParams.build(peerUid, content, recordId, msgType,
        group.groupId);
      const body: Uint8Array = await imSocket.request(req);
      if (this.owner !== owner) { return ''; }
      const ack: ImSendAck = parseImSendAck(body);
      if (ack.code !== 0) {
        // 服务端风控/内容拦截时把码打出来：不记正文，只记码与文案
        hilog.warn(DOMAIN, TAG, 'send rejected: code=%{public}d msg=%{public}s', ack.code, ack.message);
        this.markSendState(groupIdText, recordId, 'failed');
        return ack.message.length > 0 ? ack.message : '发送失败';
      }
      this.applySendAck(groupIdText, local, ack);
      this.notify();
      this.schedulePersist();
      return '';
    } catch (err) {
      this.markSendState(groupIdText, recordId, 'failed');
      const message: string = err instanceof Error ? (err as Error).message : '发送失败';
      return message;
    }
  }

  private lastRecordId: bigint = BigInt(0);

  /** 生成本地消息号：小数值、跨会话单调，避免超大会话号被服务端丢弃。 */
  private nextRecordId(group: ChatGroup): bigint {
    const base: bigint = group.lastMsgId > BigInt(0) ? group.lastMsgId * BigInt(100) : BigInt(0);
    const next: bigint = base > this.lastRecordId ? base + BigInt(1) : this.lastRecordId + BigInt(1);
    this.lastRecordId = next;
    return next;
  }

  private appendLocal(groupIdText: string, message: ChatMessage): void {
    const list: ChatMessage[] = this.messages.get(groupIdText) ?? [];
    list.push(message);
    const trimmed: ChatMessage[] = list.length > MAX_MESSAGES_PER_GROUP
      ? list.slice(list.length - MAX_MESSAGES_PER_GROUP) : list;
    this.messages.set(groupIdText, trimmed);
    const group: ChatGroup | undefined = this.groups.get(groupIdText);
    if (group !== undefined) {
      group.lastMessage = message;
      group.lastMsgTimeMs = message.createTimeMs;
    }
  }

  private markSendState(groupIdText: string, recordId: bigint, state: 'sending' | 'failed'): void {
    const list: ChatMessage[] = this.messages.get(groupIdText) ?? [];
    for (let i = 0; i < list.length; i++) {
      if (list[i].recordId === recordId && list[i].msgId <= BigInt(0)) {
        list[i].sendState = state;
        return;
      }
    }
  }

  private applySendAck(groupIdText: string, local: ChatMessage, ack: ImSendAck): void {
    const list: ChatMessage[] = this.messages.get(groupIdText) ?? [];
    for (let i = 0; i < list.length; i++) {
      if (list[i].recordId !== local.recordId) { continue; }
      list[i].msgId = ack.msgId;
      list[i].msgIdText = ack.msgId.toString();
      list[i].sendState = 'sent';
      if (ack.groupId > BigInt(0)) {
        list[i].groupId = ack.groupId;
      }
      // 回执把 key 从 `r<recordId>` 换成 msgId：如果同步副本已经先到，这里会撞成同一条，必须合并掉
      const deduped: ChatMessage[] = dedupeChatMessages(list);
      this.messages.set(groupIdText, deduped);
      const group: ChatGroup | undefined = this.groups.get(groupIdText);
      if (group !== undefined) {
        if (ack.groupId > BigInt(0) && group.groupId <= BigInt(0)) { group.groupId = ack.groupId; }
        const tail: ChatMessage = deduped.length > 0 ? deduped[deduped.length - 1] : list[i];
        group.lastMessage = tail;
        group.lastMsgTimeMs = tail.createTimeMs;
        if (ack.msgId > group.lastMsgId) {
          group.lastMsgId = ack.msgId;
          group.lastMsgIdText = tail.msgIdText;
        }
      }
      return;
    }
  }

  /** 重试一条失败消息：移除本地副本后按原内容重发，避免出现两个气泡。 */
  async resend(context: common.UIAbilityContext, groupIdText: string, recordId: bigint): Promise<string> {
    const list: ChatMessage[] = this.messages.get(groupIdText) ?? [];
    let index: number = -1;
    for (let i = 0; i < list.length; i++) {
      if (list[i].recordId === recordId && list[i].sendState !== 'sent') { index = i; break; }
    }
    if (index < 0) { return '这条消息已不在本地，无法重试'; }
    const content: string = list[index].content;
    const msgType: number = list[index].msgType > 0 ? list[index].msgType : ImSendParams.MSG_TYPE_TEXT;
    list.splice(index, 1);
    this.messages.set(groupIdText, list);
    this.notify();
    return this.sendPayload(context, groupIdText, content, msgType);
  }

  /** 把对端发来的最后一条私信上报已读；失败只记日志，不影响页面。 */
  async markRead(context: common.UIAbilityContext, groupIdText: string): Promise<void> {
    const group: ChatGroup | undefined = this.groups.get(groupIdText);
    if (group === undefined) { return; }
    // 用户已经打开这个会话：未读角标立即清零，不等服务端回执
    if (group.unread !== 0) {
      group.unread = 0;
      this.notify();
      this.schedulePersist();
    }
    if (group.groupId <= BigInt(0)) { return; }
    // 对端 uid 没识别出来时不要上报，否则 205006 的 toUid 会填 0/自己
    if (group.peer.uid <= BigInt(0)) { return; }
    if (this.selfUid > BigInt(0) && group.peer.uid === this.selfUid) { return; }
    const list: ChatMessage[] = this.messages.get(groupIdText) ?? [];
    let last: ChatMessage | undefined = undefined;
    for (let i = list.length - 1; i >= 0; i--) {
      if (!list[i].fromSelf && list[i].msgId > BigInt(0)) { last = list[i]; break; }
    }
    if (last === undefined) { return; }
    // 205006 的 msgType 必须传「已读」(22)，不是被读那条消息的类型；传消息类型服务端回「系统错误」。
    const req: ImRequest = ImReadParams.build(group.groupId, group.peer.uid, last.msgId,
      MSG_TYPE_READED, 0);
    try {
      const body: Uint8Array = await imSocket.request(req);
      const ack: ImReadAck = parseImReadAck(body);
      if (ack.code !== 0) {
        hilog.info(DOMAIN, TAG, 'mark read rejected: %{public}s', ack.message);
      }
    } catch (err) {
      hilog.info(DOMAIN, TAG, 'mark read failed');
    }
  }
}

/** 同步游标的对外形态（避免 UI 层直接构造 `bigint`）。 */
export const chatStore: ChatStore = new ChatStore();
