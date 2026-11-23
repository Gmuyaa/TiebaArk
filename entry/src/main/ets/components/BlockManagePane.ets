/**
 * 设置里的「隐藏的帖子」本机管理面板；数据在 `utils/ThreadBlockStore`。
 */
import { common } from '@kit.AbilityKit';
import { authSession } from '../auth/AuthSession';
import { AppTheme } from '../theme/Theme';
import { HiddenThread } from '../model/ThreadBlock';
import { threadBlockStore } from '../utils/ThreadBlockStore';
import {
  SettingsCard, SettingsEntryRow, SettingsInfoRow,
  SettingsStatusKind, SettingsStatusLine
} from './SettingsComponents';

@ComponentV2
export struct BlockManagePane {
  @Param hiddenThreads: boolean = true;
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
      this.HiddenSection()
      if (threadBlockStore.readError.length > 0) {
        SettingsStatusLine({
          kind: SettingsStatusKind.ERROR, message: threadBlockStore.readError,
          retryLabel: '重新读取', onRetry: (): void => { void this.reload(); }
        })
      }
      if (threadBlockStore.hiddenSaveError.length > 0) {
        SettingsStatusLine({ kind: SettingsStatusKind.ERROR, message: threadBlockStore.hiddenSaveError })
      }
    }
    .width('100%')
  }

  @Builder
  HiddenSection() {
    SettingsCard({
      content: (): void => { this.HiddenRows() }
    }).enabled(!this.actionBusy && !threadBlockStore.reading && !threadBlockStore.saving)
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

  private hiddenSummary(item: HiddenThread): string {
    const parts: string[] = [];
    if (item.forumName.length > 0) { parts.push(`${item.forumName}吧`); }
    if (item.authorName.length > 0) { parts.push(item.authorName); }
    return parts.join(' · ');
  }
}
