

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
  /** 三个动作互斥：菜单可以连点，但不并发打同一批接口 */
  private busy: boolean = false;

  /** 屏蔽这个帖子所在的吧（服务端；未确认时退回本机并把实情说出来） */
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
      /*
       * 服务端没有确认（或请求就失败了）：仍然按用户的意思在本机屏蔽，
       * 但**必须说清哪一半生效了** —— 不能把"本机屏蔽"说成"服务端已屏蔽"。
       */
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

  /** 屏蔽这个帖子的作者（服务端拉黑） */
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
        // VM 没报错但状态也没变成"已拉黑" → 不宣称成功
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

  /** 隐藏这一条帖子（纯本机，可在 设置 → 隐私设置 → 拉黑与隐藏 恢复） */
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

  /**
   * 解除拉黑（设置页用）。服务端写成功后**才**从本机名单里删掉。
   *
   * 为什么要能解除：设置页那份名单是本机记录（服务端没有全量列表可读），
   * 如果这里不能解除，误拉黑就只能在官方客户端里救了。
   */
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

  /** 只是给调用方一个"当前是否登录"的判断，避免界面重复 import 会话 */
  loggedIn(): boolean {
    return authSession.isLoggedIn();
  }
}

export const threadBlockActions: ThreadBlockActions = new ThreadBlockActions();
