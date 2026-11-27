/** 私信本地历史库（账号隔离持久化）；属用户数据，不纳入应用文件缓存清理。 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import {
  CHAT_HISTORY_MAX_ACCOUNTS, CHAT_HISTORY_MAX_GROUPS, CHAT_HISTORY_MAX_MESSAGES_PER_GROUP
} from '../model/CachePolicy';
import { ChatGroup, ChatMessage, ChatPeer } from '../model/Chat';

const STORE_NAME: string = 'tieba_chat_history';
const KEY_SNAPSHOT: string = 'snapshot_v1';

let writeQueue: Promise<void> = Promise.resolve();
function enqueueChatWrite<T>(work: () => Promise<T>): Promise<T> {
  const pending: Promise<T> = writeQueue.then(work, work);
  writeQueue = pending.then((): void => {}, (): void => {});
  return pending;
}

class StoredChatMsg implements RawStoredMsg {
  msgIdText: string = '';
  recordIdText: string = '';
  groupIdText: string = '';
  rawGroupIdText: string = '';
  msgType: number = 1;
  fromSelf: boolean = false;
  peerUidText: string = '';
  peerName: string = '';
  peerNameShow: string = '';
  peerPortrait: string = '';
  toUidText: string = '';
  content: string = '';
  createTimeMs: number = 0;
}

class StoredChatGroup {
  groupIdText: string = '';
  rawGroupIdText: string = '';
  name: string = '';
  peerUidText: string = '';
  peerName: string = '';
  peerNameShow: string = '';
  peerPortrait: string = '';
  lastMsgIdText: string = '';
  lastMsgTimeMs: number = 0;
  unread: number = 0;
  pinned: boolean = false;
  messages: StoredChatMsg[] = [];
}

class StoredChatAccount {
  owner: string = '';
  updatedAt: number = 0;
  groups: StoredChatGroup[] = [];
}

export class RestoredChatHistory {
  groups: ChatGroup[] = [];
  messages: Map<string, ChatMessage[]> = new Map<string, ChatMessage[]>();
}

interface RawStoredMsg {
  msgIdText?: string;
  recordIdText?: string;
  groupIdText?: string;
  rawGroupIdText?: string;
  msgType?: number;
  fromSelf?: boolean;
  peerUidText?: string;
  peerName?: string;
  peerNameShow?: string;
  peerPortrait?: string;
  toUidText?: string;
  content?: string;
  createTimeMs?: number;
}

interface RawStoredGroup {
  groupIdText?: string;
  rawGroupIdText?: string;
  name?: string;
  peerUidText?: string;
  peerName?: string;
  peerNameShow?: string;
  peerPortrait?: string;
  lastMsgIdText?: string;
  lastMsgTimeMs?: number;
  unread?: number;
  pinned?: boolean;
  messages?: RawStoredMsg[];
}

interface RawStoredAccount {
  owner?: string;
  updatedAt?: number;
  groups?: RawStoredGroup[];
}

function parseBigIntSafe(text: string | undefined): bigint {
  if (text === undefined || text.length === 0 || !/^\d+$/.test(text)) { return BigInt(0); }
  try {
    return BigInt(text);
  } catch {
    return BigInt(0);
  }
}

function toStoredMsg(msg: ChatMessage): StoredChatMsg {
  const out: StoredChatMsg = new StoredChatMsg();
  out.msgIdText = msg.msgIdText;
  out.recordIdText = msg.recordIdText;
  out.groupIdText = msg.groupIdText;
  out.rawGroupIdText = msg.groupId > BigInt(0) ? msg.groupId.toString() : '';
  out.msgType = msg.msgType;
  out.fromSelf = msg.fromSelf;
  out.peerUidText = msg.peer.uidText;
  out.peerName = msg.peer.userName;
  out.peerNameShow = msg.peer.userNameShow;
  out.peerPortrait = msg.peer.portrait;
  out.toUidText = msg.toUidText;
  out.content = msg.content;
  out.createTimeMs = msg.createTimeMs;
  return out;
}

function fromStoredMsg(raw: RawStoredMsg): ChatMessage | undefined {
  const groupIdText: string = typeof raw.groupIdText === 'string' ? raw.groupIdText : '';
  if (groupIdText.length === 0) { return undefined; }
  const msg: ChatMessage = new ChatMessage();
  msg.groupIdText = groupIdText;
  msg.groupId = parseBigIntSafe(raw.rawGroupIdText);
  msg.msgIdText = typeof raw.msgIdText === 'string' ? raw.msgIdText : '';
  msg.msgId = parseBigIntSafe(msg.msgIdText);
  msg.recordIdText = typeof raw.recordIdText === 'string' ? raw.recordIdText : '';
  msg.recordId = parseBigIntSafe(msg.recordIdText);
  if (msg.msgId <= BigInt(0) && msg.recordId <= BigInt(0)) { return undefined; }
  msg.msgType = typeof raw.msgType === 'number' ? raw.msgType : 1;
  msg.fromSelf = raw.fromSelf === true;
  msg.peer = new ChatPeer();
  msg.peer.uidText = typeof raw.peerUidText === 'string' ? raw.peerUidText : '';
  msg.peer.uid = parseBigIntSafe(msg.peer.uidText);
  msg.peer.userName = typeof raw.peerName === 'string' ? raw.peerName : '';
  msg.peer.userNameShow = typeof raw.peerNameShow === 'string' ? raw.peerNameShow : '';
  msg.peer.portrait = typeof raw.peerPortrait === 'string' ? raw.peerPortrait : '';
  msg.toUidText = typeof raw.toUidText === 'string' ? raw.toUidText : '';
  msg.toUid = parseBigIntSafe(msg.toUidText);
  msg.content = typeof raw.content === 'string' ? raw.content : '';
  msg.createTimeMs = typeof raw.createTimeMs === 'number' && raw.createTimeMs > 0 ? raw.createTimeMs : 0;
  msg.sendState = 'sent';
  return msg;
}

function parseRawAccounts(rawText: string): StoredChatAccount[] {
  if (rawText.length === 0) { return []; }
  try {
    const parsed: RawStoredAccount[] = JSON.parse(rawText) as RawStoredAccount[];
    if (!Array.isArray(parsed)) { return []; }
    const accounts: StoredChatAccount[] = [];
    for (const item of parsed) {
      if (item === null || item === undefined || typeof item.owner !== 'string' || item.owner.length === 0) {
        continue;
      }
      const acc: StoredChatAccount = new StoredChatAccount();
      acc.owner = item.owner;
      acc.updatedAt = typeof item.updatedAt === 'number' ? item.updatedAt : 0;
      if (Array.isArray(item.groups)) {
        for (const rg of item.groups) {
          if (rg === null || rg === undefined || typeof rg.groupIdText !== 'string' || rg.groupIdText.length === 0) {
            continue;
          }
          const g: StoredChatGroup = new StoredChatGroup();
          g.groupIdText = rg.groupIdText;
          g.rawGroupIdText = typeof rg.rawGroupIdText === 'string' ? rg.rawGroupIdText : '';
          g.name = typeof rg.name === 'string' ? rg.name : '';
          g.peerUidText = typeof rg.peerUidText === 'string' ? rg.peerUidText : '';
          g.peerName = typeof rg.peerName === 'string' ? rg.peerName : '';
          g.peerNameShow = typeof rg.peerNameShow === 'string' ? rg.peerNameShow : '';
          g.peerPortrait = typeof rg.peerPortrait === 'string' ? rg.peerPortrait : '';
          g.lastMsgIdText = typeof rg.lastMsgIdText === 'string' ? rg.lastMsgIdText : '';
          g.lastMsgTimeMs = typeof rg.lastMsgTimeMs === 'number' ? rg.lastMsgTimeMs : 0;
          g.unread = typeof rg.unread === 'number' && rg.unread > 0 ? Math.floor(rg.unread) : 0;
          g.pinned = rg.pinned === true;
          if (Array.isArray(rg.messages)) {
            for (const rm of rg.messages) {
              if (rm === null || rm === undefined) { continue; }
              const m: ChatMessage | undefined = fromStoredMsg(rm);
              if (m !== undefined) { g.messages.push(toStoredMsg(m)); }
            }
            if (g.messages.length > CHAT_HISTORY_MAX_MESSAGES_PER_GROUP) {
              g.messages = g.messages.slice(g.messages.length - CHAT_HISTORY_MAX_MESSAGES_PER_GROUP);
            }
          }
          acc.groups.push(g);
        }
        if (acc.groups.length > CHAT_HISTORY_MAX_GROUPS) {
          acc.groups = acc.groups.slice(0, CHAT_HISTORY_MAX_GROUPS);
        }
      }
      accounts.push(acc);
    }
    accounts.sort((a: StoredChatAccount, b: StoredChatAccount): number => b.updatedAt - a.updatedAt);
    return accounts.slice(0, CHAT_HISTORY_MAX_ACCOUNTS);
  } catch {
    return [];
  }
}

async function readAccounts(context: common.UIAbilityContext): Promise<StoredChatAccount[]> {
  try {
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
    const raw: string = (await store.get(KEY_SNAPSHOT, '')) as string;
    return parseRawAccounts(raw);
  } catch {
    return [];
  }
}

export async function loadChatHistory(context: common.UIAbilityContext,
  owner: string): Promise<RestoredChatHistory> {
  const out: RestoredChatHistory = new RestoredChatHistory();
  if (owner.length === 0) { return out; }
  const accounts: StoredChatAccount[] = await readAccounts(context);
  for (const acc of accounts) {
    if (acc.owner !== owner) { continue; }
    for (const sg of acc.groups) {
      const group: ChatGroup = new ChatGroup();
      group.groupIdText = sg.groupIdText;
      group.groupId = parseBigIntSafe(sg.rawGroupIdText);
      group.name = sg.name;
      group.peer = new ChatPeer();
      group.peer.uidText = sg.peerUidText;
      group.peer.uid = parseBigIntSafe(sg.peerUidText);
      group.peer.userName = sg.peerName;
      group.peer.userNameShow = sg.peerNameShow;
      group.peer.portrait = sg.peerPortrait;
      group.lastMsgIdText = sg.lastMsgIdText;
      group.lastMsgId = parseBigIntSafe(sg.lastMsgIdText);
      group.lastMsgTimeMs = sg.lastMsgTimeMs;
      group.unread = sg.unread;
      group.pinned = sg.pinned;

      const msgs: ChatMessage[] = [];
      for (const sm of sg.messages) {
        const msg: ChatMessage | undefined = fromStoredMsg(sm);
        if (msg !== undefined) { msgs.push(msg); }
      }
      if (msgs.length > 0) {
        group.lastMessage = msgs[msgs.length - 1];
        if (group.lastMsgTimeMs <= 0) {
          group.lastMsgTimeMs = group.lastMessage.createTimeMs;
        }
        out.messages.set(group.groupIdText, msgs);
      }
      out.groups.push(group);
    }
    break;
  }
  return out;
}

export async function saveChatHistory(context: common.UIAbilityContext, owner: string,
  groups: ChatGroup[], messages: Map<string, ChatMessage[]>): Promise<void> {
  if (owner.length === 0) { return; }
  const sorted: ChatGroup[] = groups
    .filter((g: ChatGroup): boolean => !g.container && g.groupIdText.length > 0)
    .sort((a: ChatGroup, b: ChatGroup): number => b.sortKey() - a.sortKey())
    .slice(0, CHAT_HISTORY_MAX_GROUPS);

  const storedGroups: StoredChatGroup[] = [];
  for (const g of sorted) {
    const sg: StoredChatGroup = new StoredChatGroup();
    sg.groupIdText = g.groupIdText;
    sg.rawGroupIdText = g.groupId > BigInt(0) ? g.groupId.toString() : '';
    sg.name = g.name;
    sg.peerUidText = g.peer.uidText;
    sg.peerName = g.peer.userName;
    sg.peerNameShow = g.peer.userNameShow;
    sg.peerPortrait = g.peer.portrait;
    sg.lastMsgIdText = g.lastMsgIdText;
    sg.lastMsgTimeMs = g.lastMsgTimeMs;
    sg.unread = g.unread;
    sg.pinned = g.pinned;
    const rawList: ChatMessage[] = messages.get(g.groupIdText) ?? [];
    const sentList: ChatMessage[] = rawList.filter((m: ChatMessage): boolean => m.sendState === 'sent');
    const trimmed: ChatMessage[] = sentList.length > CHAT_HISTORY_MAX_MESSAGES_PER_GROUP
      ? sentList.slice(sentList.length - CHAT_HISTORY_MAX_MESSAGES_PER_GROUP)
      : sentList;
    for (const m of trimmed) {
      sg.messages.push(toStoredMsg(m));
    }
    storedGroups.push(sg);
  }

  return enqueueChatWrite(async (): Promise<void> => {
    const accounts: StoredChatAccount[] = await readAccounts(context);
    const filtered: StoredChatAccount[] = accounts.filter((a: StoredChatAccount): boolean => a.owner !== owner);
    const nextAcc: StoredChatAccount = new StoredChatAccount();
    nextAcc.owner = owner;
    nextAcc.updatedAt = Date.now();
    nextAcc.groups = storedGroups;
    filtered.unshift(nextAcc);
    const capped: StoredChatAccount[] = filtered.slice(0, CHAT_HISTORY_MAX_ACCOUNTS);
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
      await store.put(KEY_SNAPSHOT, JSON.stringify(capped));
      await store.flush();
    } catch {
      // 本地历史写盘失败不阻塞消息收发
    }
  });
}
