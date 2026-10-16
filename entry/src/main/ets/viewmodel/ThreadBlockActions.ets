

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ForumBlockResponse, TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { HiddenThread, normalizeForumName } from '../model/ThreadBlock';
import { ThreadBrief } from '../model/ThreadList';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { threadBlockStore } from '../utils/ThreadBlockStore';
import { AuthorBlockVM, authorBlockAction } from './AuthorBlockVM';

export class ThreadBlockActions {
  private api: TiebaApi = new TiebaApi();

  private busy: boolean = false;

  async blockForum(context: common.UIAbilityContext, thread: ThreadBrief): Promise<string> {
    if (this.busy) { return '上一个操作还没结束，请稍候'; }
    const name: string = normalizeForumName(thread.sourceForum);
    if (name.length === 0) { return '未取得吧名，无法屏蔽'; }
    if (!authSession.isLoggedIn()) { return '需要登录后才能屏蔽贴吧'; }
    if (thread.sourceForumId <= 0) { return '未取得吧 id，无法屏蔽该吧'; }
    if (thread.tid <= 0) { return '帖子身份无效，无法屏蔽'; }
    this.busy = true;
    const session = authSession.session();
    const owner: string = authSession.sessionKey();
    const current: () => boolean = (): boolean => authSession.matchesSession(session, owner);
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!current()) { return '账号已变化，未继续屏蔽'; }
      const response: ForumBlockResponse = await this.api.blockForum(device, session,
        authSession.snapshot.uid, thread.tid, thread.sourceForumId, thread.sourceForum);
      if (!current()) { return '账号已变化，请在原账号确认屏蔽结果'; }
      if (response.ok && response.confirmed) {
        await threadBlockStore.rememberBlockedForum(context, thread.sourceForum);
        return '';
      }

      hilog.info(0x0, 'ThreadBlock', 'forum block unconfirmed: %{public}s',
        response.describeFailure());
      await threadBlockStore.rememberBlockedForum(context, thread.sourceForum);
      return `${name}吧已在本机屏蔽；服务端未确认（${response.describeFailure()}）`;
    } catch (err) {
      if (!current()) { return '账号已变化，未写入当前账号的屏蔽记录'; }
      const message: string = (err as Error).message;
      await threadBlockStore.rememberBlockedForum(context, thread.sourceForum);
      return `${name}吧已在本机屏蔽；服务端请求失败：${message}`;
    } finally {
      this.busy = false;
    }
  }

  async blockAuthor(context: common.UIAbilityContext, thread: ThreadBrief): Promise<string> {
    if (this.busy) { return '上一个操作还没结束，请稍候'; }
    if (thread.authorId <= 0) { return '未取得作者身份，无法屏蔽'; }
    if (!authSession.isLoggedIn()) { return '需要登录后才能屏蔽用户'; }
    const owner: string = authSession.sessionKey();
    this.busy = true;
    try {
      const vm: AuthorBlockVM = authorBlockAction(thread.authorId);
      const message: string = await vm.set(context, true);
      if (owner !== authSession.sessionKey()) { return '账号已变化，请在原账号确认结果'; }
      if (message.length > 0) {
        return message;
      }
      if (!vm.known || !vm.blocked) {

        return '拉黑状态未确认，请稍后重试';
      }
      await threadBlockStore.rememberBlockedUser(context, thread.authorId, thread.authorName);
      return '';
    } catch (err) {
      return `屏蔽用户失败：${(err as Error).message}`;
    } finally {
      this.busy = false;
    }
  }

  async hideThread(context: common.UIAbilityContext, thread: ThreadBrief): Promise<string> {
    if (thread.tid <= 0) { return '帖子身份无效，无法隐藏'; }
    const item: HiddenThread = new HiddenThread();
    item.tid = thread.tid;
    item.title = thread.title;
    item.forumName = normalizeForumName(thread.sourceForum);
    item.authorName = thread.authorName;
    item.timeMs = Date.now();
    await threadBlockStore.hide(context, item);
    return '';
  }

  async unblockAuthor(context: common.UIAbilityContext, uid: number): Promise<string> {
    if (!Number.isSafeInteger(uid) || uid <= 0) { return '用户身份无效'; }
    if (!authSession.isLoggedIn()) { return '需要登录后才能解除拉黑'; }
    if (this.busy) { return '上一个操作还没结束，请稍候'; }
    const owner: string = authSession.sessionKey();
    this.busy = true;
    try {
      const vm: AuthorBlockVM = authorBlockAction(uid);
      const message: string = await vm.set(context, false);
      if (owner !== authSession.sessionKey()) { return '账号已变化，请在原账号确认结果'; }
      if (message.length > 0) { return message; }
      if (!vm.known || vm.blocked) { return '拉黑状态未确认，请稍后重试'; }
      await threadBlockStore.forgetBlockedUser(context, uid);
      return '';
    } catch (err) {
      return `解除拉黑失败：${(err as Error).message}`;
    } finally {
      this.busy = false;
    }
  }

  loggedIn(): boolean {
    return authSession.isLoggedIn();
  }
}

export const threadBlockActions: ThreadBlockActions = new ThreadBlockActions();
