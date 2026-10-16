

import { common } from '@kit.AbilityKit';
import { BlockedUser, HiddenThread } from '../model/ThreadBlock';
import { threadBlockStore } from '../utils/ThreadBlockStore';
import { threadBlockActions } from '../viewmodel/ThreadBlockActions';
import {
  SettingsCard, SettingsEntryRow, SettingsGroupTitle, SettingsInfoRow, SettingsNote
} from './SettingsComponents';

@ComponentV2
export struct BlockManagePane {

  @Param refreshSeq: number = 0;

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    void this.reload();
  }

  @Monitor('refreshSeq')
  onRefreshRequested(): void {
    if (this.refreshSeq > 0) {
      void this.reload();
    }
  }

  private async reload(): Promise<void> {
    await threadBlockStore.load(this.context());
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  private async confirmUnblock(user: BlockedUser): Promise<void> {
    const who: string = user.name.length > 0 ? user.name : `用户 ${user.uid}`;
    const confirm = await this.getUIContext().getPromptAction().showDialog({
      title: '解除拉黑',
      message: `解除后 ${who} 的内容会重新出现；该操作会同步到服务端。`,
      buttons: [{ text: '取消', color: $r('app.color.detail_text_secondary') },
        { text: '解除', color: $r('app.color.detail_accent') }]
    });
    if (confirm.index !== 1) { return; }
    const message: string = await threadBlockActions.unblockAuthor(this.context(), user.uid);
    this.toast(message.length > 0 ? message : `已解除对 ${who} 的拉黑`);
  }

  private async confirmUnhide(item: HiddenThread): Promise<void> {
    const what: string = item.title.length > 0 ? item.title : `帖子 ${item.tid}`;
    const confirm = await this.getUIContext().getPromptAction().showDialog({
      title: '恢复该贴',
      message: `恢复后「${what}」会重新出现在列表里（本机操作，不涉及服务端）。`,
      buttons: [{ text: '取消', color: $r('app.color.detail_text_secondary') },
        { text: '恢复', color: $r('app.color.detail_accent') }]
    });
    if (confirm.index !== 1) { return; }
    await threadBlockStore.unhide(this.context(), item.tid);
    this.toast('已恢复该贴');
  }

  build() {
    Column() {
      this.UsersSection()
      this.HiddenSection()
    }
    .width('100%')
  }

  @Builder
  UsersSection() {
    SettingsGroupTitle({ title: '拉黑的用户' })
    SettingsCard({
      content: (): void => { this.UserRows() }
    })
    SettingsNote({
      text: '服务端没有"已拉黑用户"的 HTTP 列表接口（官方那个黑名单页走的是长连接通道，'
        + '本应用还没接），这里只列出在本应用里拉黑过的用户；在官方客户端拉黑的用户不会'
        + '出现在这里。点一行可解除拉黑（会同步服务端）。'
    })
  }

  @Builder
  UserRows() {
    if (threadBlockStore.blockedUsers.length === 0) {
      SettingsInfoRow({ label: '本应用暂无拉黑的用户', showDivider: false })
    } else {
      ForEach(threadBlockStore.blockedUsers, (user: BlockedUser, index: number) => {
        SettingsEntryRow({
          label: user.name.length > 0 ? user.name : `用户 ${user.uid}`,
          summary: `uid ${user.uid} · 点击解除拉黑`,
          showDivider: index < threadBlockStore.blockedUsers.length - 1,
          onTap: (): void => { void this.confirmUnblock(user); }
        })
      }, (user: BlockedUser) => `u${user.uid}`)
    }
  }

  @Builder
  HiddenSection() {
    SettingsGroupTitle({ title: '隐藏的帖子' })
    SettingsCard({
      content: (): void => { this.HiddenRows() }
    })
    SettingsNote({
      text: '隐藏只作用于本机（服务端没有帖子级隐藏接口）。点一行即可恢复。'
    })
  }

  @Builder
  HiddenRows() {
    if (threadBlockStore.hidden.length === 0) {
      SettingsInfoRow({ label: '本机暂无隐藏的帖子', showDivider: false })
    } else {
      ForEach(threadBlockStore.hidden, (item: HiddenThread, index: number) => {
        SettingsEntryRow({
          label: item.title.length > 0 ? item.title : `帖子 ${item.tid}`,
          summary: this.hiddenSummary(item),
          showDivider: index < threadBlockStore.hidden.length - 1,
          onTap: (): void => { void this.confirmUnhide(item); }
        })
      }, (item: HiddenThread) => `t${item.tid}`)
    }
  }

  private hiddenSummary(item: HiddenThread): string {
    const parts: string[] = [];
    if (item.forumName.length > 0) { parts.push(`${item.forumName}吧`); }
    if (item.authorName.length > 0) { parts.push(item.authorName); }
    return parts.join(' · ');
  }
}
