
import { AppTheme } from '../theme/Theme';
import { SettingsLayout } from '../common/appearance/SettingsLayout';
import { common } from '@kit.AbilityKit';
import { ApiResult, TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { ForbiddenForum } from '../model/ForbiddenForums';
import { ForbiddenForumsVM } from '../viewmodel/ForbiddenForumsVM';
import { threadBlockStore } from '../utils/ThreadBlockStore';
import { SettingsCard, SettingsEntryRow, SettingsInfoRow, SettingsNote, SettingsStatusKind, SettingsStatusLine } from './SettingsComponents';

@ComponentV2
export struct ForbiddenForumsPane {

  @Param refreshSeq: number = 0;

  @Param loadMoreSeq: number = 0;
  @Event onPageStarted: () => void = (): void => {};
  @Event onPageSettled: () => void = (): void => {};
  @Local vm: ForbiddenForumsVM = new ForbiddenForumsVM();

  @Local unblockingId: string = '';
  private api: TiebaApi = new TiebaApi();

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  aboutToAppear(): void {
    this.reload();
  }

  aboutToDisappear(): void {
    this.vm.dispose();
  }

  private reload(): void {
    this.vm.load(this.context(), false, (): void => {}, this.onPageSettled).then((): void => {
      this.syncMirror();
    });
  }

  private syncMirror(): void {
    if (!this.vm.loaded || this.vm.error.length > 0) { return; }
    const names: string[] = [];
    for (const item of this.vm.items) {
      if (item.name.length > 0) { names.push(item.name); }
    }
    void threadBlockStore.replaceBlockedForums(this.context(), names, !this.vm.hasMore && !this.vm.stalled && this.vm.pagingError.length === 0);
  }

  @Monitor('refreshSeq')
  onRefreshRequested(): void {
    if (this.refreshSeq > 0) {
      this.vm.load(this.context(), false, (): void => {}, this.onPageSettled).then((): void => {
        this.syncMirror();
      });
    }
  }

  @Monitor('loadMoreSeq')
  onLoadMoreRequested(): void {
    if (this.loadMoreSeq > 0) {

      void this.vm.load(this.context(), true, this.onPageStarted, this.onPageSettled).then((): void => { this.syncMirror(); });
    }
  }

  private async confirmUnblock(item: ForbiddenForum): Promise<void> {
    if (this.unblockingId.length > 0) { return; }
    const owner: string = authSession.sessionKey();
    const label: string = item.name.length > 0 ? (item.name.endsWith('吧') ? item.name : `${item.name}吧`) : '该吧';
    const confirm = await this.getUIContext().getPromptAction().showDialog({
      title: '解除屏蔽',
      message: `解除后 ${label} 的帖子会重新出现在推荐与关注列表里（会同步到服务端）。`,
      buttons: [{ text: '取消', color: $r('app.color.detail_text_secondary') },
        { text: '解除', color: $r('app.color.detail_accent') }]
    });
    if (owner !== authSession.sessionKey()) { this.toast('账号已变化，请重新确认'); return; }
    if (confirm.index !== 1) { return; }
    this.unblockingId = item.id;
    try {
      if (!authSession.isLoggedIn()) { this.toast('需要登录后才能解除屏蔽'); return; }
      if (authSession.session().tbs.length === 0) {
        const refreshed = await authSession.refreshTbs(this.context());
        if (!refreshed.ok) { this.toast(refreshed.message); return; }
      }
      const session = authSession.session();
      const device = await DeviceIdentity.ensure(this.context());
      if (!authSession.matchesSession(session, owner)) { this.toast('账号已变化，未继续解除'); return; }
      const result: ApiResult = await this.api.unblockForum(device, session, item.id);
      if (!authSession.matchesSession(session, owner)) { this.toast('账号已变化，请在原账号确认结果'); return; }
      if (!result.ok) { this.toast(result.describeFailure()); return; }
      await threadBlockStore.forgetBlockedForum(this.context(), item.name);
      this.toast(`已解除对 ${label} 的屏蔽`);
      this.reload();
    } catch (err) {
      this.toast(`解除屏蔽失败：${(err as Error).message}`);
    } finally {
      this.unblockingId = '';
    }
  }

  build() {
    Column() {
      SettingsNote({ text: '这里列出账号在服务端屏蔽的吧（读回服务端列表）。点一行可解除屏蔽。' })
      SettingsCard({
        content: (): void => { this.ForumRows() }
      })
      if (this.vm.error.length > 0) {
        SettingsStatusLine({
          kind: SettingsStatusKind.ERROR,
          message: this.vm.error,
          retryLabel: '重试',
          onRetry: (): void => {
            this.reload();
          }
        })
      }
      this.BottomState()
    }
    .width('100%')
  }

  @Builder
  ForumRows() {
    if (this.vm.loading && this.vm.items.length === 0) {
      SettingsInfoRow({ label: '正在读取…', showDivider: false })
    } else if (this.vm.loaded && this.vm.items.length === 0) {
      SettingsInfoRow({ label: '账号暂无屏蔽吧', showDivider: false })
    } else {
      ForEach(this.vm.items, (item: ForbiddenForum, index: number) => {
        SettingsEntryRow({
          label: item.name.length > 0 ? (item.name.endsWith('吧') ? item.name : `${item.name}吧`) : '吧名未返回',
          summary: this.unblockingId === item.id ? '正在解除…' : '点击解除屏蔽',

          avatarUrl: item.avatar, avatarName: item.name,
          showDivider: index < this.vm.items.length - 1,
          onTap: (): void => { void this.confirmUnblock(item); }
        })
      }, (item: ForbiddenForum) => item.id)
    }
  }

  @Builder
  BottomState() {
    if (this.vm.items.length > 0) {
      Row() {
        if (this.vm.loadingMore) {
          Text('正在加载…').fontSize(SettingsLayout.SUB_SIZE).fontColor(AppTheme.NOTE_TEXT)
        } else if (this.vm.pagingError.length > 0) {
          Text('加载失败，点击重试').fontSize(SettingsLayout.SUB_SIZE).fontColor(AppTheme.ACCENT)
            .onClick(() => {

              void this.vm.retryPaging(this.context()).then((): void => { this.syncMirror(); });
            })
        } else if (this.vm.hasMore) {
          Text('点击加载更多').fontSize(SettingsLayout.SUB_SIZE).fontColor(AppTheme.ACCENT)
            .onClick(() => { void this.vm.load(this.context(), true, this.onPageStarted, this.onPageSettled).then((): void => { this.syncMirror(); }); })
        } else if (this.vm.stalled) {
          Text('暂时无法加载更多').fontSize(SettingsLayout.SUB_SIZE).fontColor(AppTheme.NOTE_TEXT)
        } else if (!this.vm.hasMore && this.vm.loaded) {
          Text('已全部加载').fontSize(SettingsLayout.SUB_SIZE).fontColor(AppTheme.NOTE_TEXT)
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 16 })
    }
  }
}
