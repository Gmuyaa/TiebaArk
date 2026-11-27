/**
 * 消息页「聊天」tab 的会话列表状态。
 *
 * 数据来源是 `ChatStore` 的账号作用域内存库；本 VM 只负责把库里的快照暴露成
 * 可订阅字段，并把网络失败原因如实带到界面（不把失败显示成"没有会话"）。
 */

import { common } from '@kit.AbilityKit';
import { ChatGroup } from '../model/Chat';
import { chatStore } from './ChatStore';

@ObservedV2
export class ChatListVM {
  @Trace groups: ChatGroup[] = [];
  @Trace unreadTotal: number = 0;
  @Trace loading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace error: string = '';
  @Trace connecting: boolean = false;

  private listener: () => void = (): void => { this.pull(); };

  constructor() {
    chatStore.watch(this.listener);
  }

  /** 页面销毁时解除订阅，避免旧页面继续被通知。 */
  dispose(): void {
    chatStore.unwatch(this.listener);
  }

  private pull(): void {
    this.groups = chatStore.groupList();
    this.unreadTotal = chatStore.totalUnread();
  }

  async refresh(context: common.UIAbilityContext): Promise<void> {
    if (this.loading) { return; }
    this.loading = true;
    this.connecting = !chatStore.ready();
    try {
      const failure: string = await chatStore.syncAll(context);
      this.error = failure;
      this.pull();
      this.loaded = true;
    } finally {
      this.loading = false;
      this.connecting = false;
    }
  }

  /** 只重读内存快照（发送/已读后由 store 通知触发）。 */
  reload(): void {
    this.pull();
  }
}

export const chatListVM: ChatListVM = new ChatListVM();
