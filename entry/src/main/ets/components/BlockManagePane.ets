

import { common } from '@kit.AbilityKit';
import { authSession } from '../auth/AuthSession';
import { AppTheme } from '../theme/Theme';
import { BlockedUser, HiddenThread } from '../model/ThreadBlock';
import { threadBlockStore } from '../utils/ThreadBlockStore';
import { threadBlockActions } from '../viewmodel/ThreadBlockActions';
import {
  SettingsCard, SettingsEntryRow, SettingsGroupTitle, SettingsInfoRow, SettingsNote,
  SettingsStatusKind, SettingsStatusLine
} from './SettingsComponents';

@ComponentV2
export struct BlockManagePane {
  @Param hiddenThreads: boolean = false;
  @Local actionBusy: boolean = false;

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    void this.reload();
  }

  private async reload(): Promise<void> {
    if (this.actionBusy) { return; }
    await threadBlockStore.reload(this.context());
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  private async confirmUnblock(user: BlockedUser): Promise<void> {
    if (this.actionBusy || threadBlockStore.reading || threadBlockStore.saving) { return; }
    this.actionBusy = true;
    const owner: string = authSession.sessionKey();
    try {
      const who: string = user.name.length > 0 ? user.name : `用户 ${user.uid}`;
      const confirm = await this.getUIContext().getPromptAction().showDialog({
        title: '解除拉黑',
        message: `解除后 ${who} 的内容会重新出现；该操作会同步到服务端。`,
        buttons: [{ text: '取消', color: AppTheme.TEXT_SUB },
          { text: '解除', color: AppTheme.ACCENT_DARK }]
      });
      if (confirm.index !== 1) { return; }
      if (owner !== authSession.sessionKey()) { this.toast('账号已变化，请重新读取'); return; }
      const message: string = await threadBlockActions.unblockAuthor(this.context(), user.uid);
      this.toast(message.length > 0 ? message : `已解除对 ${who} 的拉黑`);
    } catch (err) { this.toast('操作未完成，请重试'); }
    finally { this.actionBusy = false; }
  }

  private async confirmUnhide(item: HiddenThread): Promise<void> {
    if (this.actionBusy || threadBlockStore.reading || threadBlockStore.saving) { return; }
    this.actionBusy = true;
    const owner: string = authSession.sessionKey();
    try {
      const what: string = item.title.length > 0 ? item.title : `帖子 ${item.tid}`;
      const confirm = await this.getUIContext().getPromptAction().showDialog({
        title: '恢复该贴',
        message: `恢复后「${what}」会重新出现在本机列表中。`,
        buttons: [{ text: '取消', color: AppTheme.TEXT_SUB },
          { text: '恢复', color: AppTheme.ACCENT_DARK }]
      });
      if (confirm.index !== 1) { return; }
      if (owner !== authSession.sessionKey()) { this.toast('账号已变化，请重新读取'); return; }
      await threadBlockStore.unhide(this.context(), item.tid);
      if (owner !== authSession.sessionKey()) { this.toast('账号已变化，请重新读取'); return; }
      if (threadBlockStore.hiddenSaveError.length > 0) { this.toast(threadBlockStore.hiddenSaveError); return; }
      this.toast(threadBlockStore.isHidden(item.tid) ? '恢复未完成，请重新读取后重试' : '已恢复该贴');
    } catch (err) { this.toast('操作未完成，请重试'); }
    finally { this.actionBusy = false; }
  }

  build() {
    Column() {
      if (this.hiddenThreads) {
        this.HiddenSection()
      } else {
        this.UsersSection()
      }
      if (threadBlockStore.readError.length > 0) {
        SettingsStatusLine({
          kind: SettingsStatusKind.ERROR, message: threadBlockStore.readError,
          retryLabel: '重新读取', onRetry: (): void => { void this.reload(); }
        })
      }
      if ((this.hiddenThreads ? threadBlockStore.hiddenSaveError : threadBlockStore.usersSaveError).length > 0) {
        SettingsStatusLine({ kind: SettingsStatusKind.ERROR,
          message: this.hiddenThreads ? threadBlockStore.hiddenSaveError : threadBlockStore.usersSaveError })
      }
    }
    .width('100%')
  }

  @Builder
  UsersSection() {
    SettingsGroupTitle({ title: '拉黑的用户' })
    SettingsCard({
      content: (): void => { this.UserRows() }
    }).enabled(!this.actionBusy && !threadBlockStore.reading && !threadBlockStore.saving)
    SettingsNote({
      text: '仅显示在本应用内拉黑的用户，不含官方客户端的记录。解除拉黑会同步到贴吧账号。'
    })
  }

  @Builder
  UserRows() {
    if (threadBlockStore.blockedUsers.length === 0) {
      if (threadBlockStore.reading || (!threadBlockStore.loaded && threadBlockStore.readError.length === 0)) {
        SettingsInfoRow({ label: '正在读取…', showDivider: false })
      } else if (threadBlockStore.loaded) {
        SettingsInfoRow({ label: '本应用暂无拉黑的用户', showDivider: false })
      }
    } else {
      ForEach(threadBlockStore.blockedUsers, (user: BlockedUser, index: number) => {
        SettingsEntryRow({
          label: user.name.length > 0 ? user.name : `用户 ${user.uid}`,
          summary: '点击解除拉黑',
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
    }).enabled(!this.actionBusy && !threadBlockStore.reading && !threadBlockStore.saving)
    SettingsNote({
      text: '仅在本机隐藏，点击可恢复。'
    })
  }

  @Builder
  HiddenRows() {
    if (threadBlockStore.hidden.length === 0) {
      if (threadBlockStore.reading || (!threadBlockStore.loaded && threadBlockStore.readError.length === 0)) {
        SettingsInfoRow({ label: '正在读取…', showDivider: false })
      } else if (threadBlockStore.loaded) {
        SettingsInfoRow({ label: '本机暂无隐藏的帖子', showDivider: false })
      }
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

  /** 隐藏记录的副标题：吧名 + 作者（都拿不到时留空，行会退回单行高度） */
  private hiddenSummary(item: HiddenThread): string {
    const parts: string[] = [];
    if (item.forumName.length > 0) { parts.push(`${item.forumName}吧`); }
    if (item.authorName.length > 0) { parts.push(item.authorName); }
    return parts.join(' · ');
  }
}
