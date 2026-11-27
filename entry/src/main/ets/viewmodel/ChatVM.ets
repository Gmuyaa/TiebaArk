/**
 * 单个私信会话页的状态。页面拿 `ChatVM` 的 `@Trace` 字段渲染；消息数组来自 `ChatStore` 的账号
 * 作用域内存库。打开会话时若本地没有消息，按 lastMsgId=0 拉最近一批；之后发送/刷新都走同一个库。
 */

import { common } from '@kit.AbilityKit';
import { ChatGroup, ChatMessage, dedupeChatMessages } from '../model/Chat';
import { chatStore } from './ChatStore';

const HISTORY_PAGE_SIZE: number = 30;

@ObservedV2
export class ChatVM {
  @Trace messages: ChatMessage[] = [];
  @Trace hasOlderHistory: boolean = false;
  @Trace title: string = '';
  @Trace portrait: string = '';
  @Trace uidText: string = '';
  @Trace loading: boolean = false;
  @Trace error: string = '';
  @Trace sending: boolean = false;
  @Trace exists: boolean = true;

  private groupIdText: string = '';
  private visibleLimit: number = HISTORY_PAGE_SIZE;
  /** 进入会话时路由声明的对端 uid：发送前用它核对，防止组身份被改写后消息发到另一个人。 */
  private expectedPeerUidText: string = '';
  private listener: () => void = (): void => { this.pull(); };
  private opened: boolean = false;

  constructor() {
    chatStore.watch(this.listener);
  }

  dispose(): void {
    chatStore.unwatch(this.listener);
  }

  /**
   * 进入会话：读内存快照，必要时拉最近一批消息，成功后上报已读。
   *
   * `groupIdText` 为空时，用 `peerUidText` 从个人主页发起会话（本地直聊，groupId 待首条回执补齐）。
   */
  async open(context: common.UIAbilityContext, groupIdText: string, peerUidText: string = '',
    peerName: string = '', peerPortrait: string = ''): Promise<void> {
    this.expectedPeerUidText = peerUidText.trim();
    if (groupIdText.length === 0) {
      const direct: ChatGroup | undefined = chatStore.directConversation(peerUidText, peerName, peerPortrait);
      if (direct === undefined) {
        this.exists = false;
        this.error = '缺少会话标识';
        return;
      }
      groupIdText = direct.groupIdText;
    }
    this.groupIdText = groupIdText;
    this.visibleLimit = HISTORY_PAGE_SIZE;
    this.opened = true;
    this.pull();
    this.loading = this.messages.length === 0;
    this.error = '';
    try {
      // 本地直聊会话还没有真实 groupId 时，先握手/同步把它补齐
      const failure: string = await chatStore.openConversation(context, groupIdText);
      this.error = failure;
      this.pull();
    } finally {
      this.loading = false;
    }
    if (this.error.length === 0 && this.vmHasRealGroup()) {
      void chatStore.markRead(context, groupIdText);
    }
  }

  private vmHasRealGroup(): boolean {
    const group: ChatGroup | undefined = chatStore.group(this.groupIdText);
    return group !== undefined && group.groupId > BigInt(0);
  }

  uploadGroupId(): string {
    const group: ChatGroup | undefined = chatStore.group(this.groupIdText);
    return group !== undefined && group.groupId > BigInt(0) ? group.groupId.toString() : '1';
  }

  /** 下拉刷新：重拉增量（不清空本地消息）。 */
  async refresh(context: common.UIAbilityContext): Promise<void> {
    if (this.loading || !this.opened) { return; }
    this.loading = true;
    try {
      this.error = await chatStore.openConversation(context, this.groupIdText);
      this.pull();
    } finally {
      this.loading = false;
    }
  }

  /** 发送文字；返回空串表示已入队（不代表服务端已确认，发送态在消息上）。 */
  async send(context: common.UIAbilityContext, text: string, onEnqueued?: () => void): Promise<string> {
    if (this.sending) { return '正在发送，请稍候'; }
    if (text.trim().length === 0) { return ''; }
    const mismatch: string = this.identityMismatch();
    if (mismatch.length > 0) { return mismatch; }
    this.sending = true;
    try {
      return await chatStore.send(context, this.groupIdText, text, onEnqueued);
    } finally {
      this.sending = false;
      this.pull();
    }
  }

  async sendImage(context: common.UIAbilityContext, imageUrl: string, width: number, height: number,
    onEnqueued?: () => void, bigUrl: string = ''): Promise<string> {
    if (this.sending) { return '正在发送，请稍候'; }
    const mismatch: string = this.identityMismatch();
    if (mismatch.length > 0) { return mismatch; }
    this.sending = true;
    try {
      return await chatStore.sendImage(context, this.groupIdText, imageUrl, width, height, onEnqueued, bigUrl);
    } finally {
      this.sending = false;
      this.pull();
    }
  }

  /**
   * 发送前的身份闸门：会话当前认定的对端必须和进来时路由声明的那个一致。
   * 对不上说明组身份被改写或尚未确认——宁可发不出去，也不能把消息送给另一个人。
   */
  private identityMismatch(): string {
    const group: ChatGroup | undefined = chatStore.group(this.groupIdText);
    if (group === undefined) { return '会话不存在'; }
    if (group.multiPeer) { return '这个会话里有多个成员，私信暂不支持群发'; }
    if (group.peer.uid <= BigInt(0)) { return '还没确认对方账号，请刷新会话列表'; }
    if (this.expectedPeerUidText.length === 0) { return ''; }
    const actual: string = group.peer.uidText.length > 0 ? group.peer.uidText : group.peer.uid.toString();
    if (actual !== this.expectedPeerUidText) { return '会话身份已变化，请返回列表重新进入'; }
    return '';
  }

  /** 重试一条发送失败的消息：先移除本地副本再重发，避免重复气泡。 */
  async retry(context: common.UIAbilityContext, message: ChatMessage): Promise<string> {
    const failure: string = await chatStore.resend(context, this.groupIdText, message.recordId);
    this.pull();
    return failure;
  }

  /** 从本地持久化历史库向上展开一页更早消息，返回新增条数。 */
  loadOlder(): number {
    if (!this.opened || !this.hasOlderHistory) { return 0; }
    const before: number = this.messages.length;
    this.visibleLimit += HISTORY_PAGE_SIZE;
    this.pull();
    return Math.max(0, this.messages.length - before);
  }

  private pull(): void {
    if (!this.opened) { return; }
    const group: ChatGroup | undefined = chatStore.group(this.groupIdText);
    this.exists = group !== undefined;
    if (group !== undefined) {
      this.title = group.title();
      this.portrait = group.peer.portrait;
      this.uidText = group.peer.uidText;
    }
    const all: ChatMessage[] = dedupeChatMessages(chatStore.messagesOf(this.groupIdText));
    if (all.length > this.visibleLimit) {
      this.hasOlderHistory = true;
      this.messages = all.slice(all.length - this.visibleLimit);
    } else {
      this.hasOlderHistory = false;
      this.messages = all;
    }
  }
}
