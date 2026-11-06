import { common } from '@kit.AbilityKit';
import { authSession } from '../auth/AuthSession';
import { AgreeObjType, TiebaDevice } from '../net/TiebaParams';
import { TiebaApi } from '../api/TiebaApi';
import { ThreadDetail, ReplySortType } from '../model/ThreadDetail';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { shareWebPage } from '../utils/SystemShare';
import { AgreeActionVM, AgreeState, AgreeTarget } from './AgreeActionVM';

export const CARD_ACTION_DETAIL_LIMIT: number = 16;

/** 列表不猜主帖 pid 或已赞状态，首次操作先读取详情，再走详情页同一写入状态机。 */
@ObservedV2
export class ThreadCardActionState {
  private target: AgreeTarget | undefined = undefined;
  private api: TiebaApi = new TiebaApi();
  private actions: AgreeActionVM = new AgreeActionVM();
  @Trace private agreement: AgreeState | undefined = undefined;
  @Trace private owner: string = '';
  @Trace private preparing: boolean = false;
  private generation: number = 0;

  liked(): boolean {
    return this.owner === authSession.sessionKey() && (this.agreement?.liked() ?? false);
  }

  count(fallback: number): number {
    return this.owner === authSession.sessionKey() ? (this.agreement?.displayCount() ?? fallback) : fallback;
  }

  isPreparing(): boolean {
    return this.owner === authSession.sessionKey() && this.preparing;
  }

  /** 释放可复用的目标身份；轻量赞态仍可接收在途读回，不能丢弃写入。 */
  release(): boolean {
    if (this.preparing || this.agreement?.pending) { return false; }
    this.target = undefined;
    return true;
  }

  async toggleLike(context: common.UIAbilityContext, tid: number, forumName: string): Promise<string> {
    if (!Number.isSafeInteger(tid) || tid <= 0) { return '帖子身份无效，无法点赞'; }
    if (!authSession.isLoggedIn()) { return '需要登录后才能点赞'; }
    const owner: string = authSession.sessionKey();
    if (this.owner !== owner) {
      this.generation++;
      this.owner = owner;
      this.target = undefined;
      this.agreement = undefined;
      this.preparing = false;
    }
    if (this.preparing) { return ''; }
    if (this.target === undefined) {
      const generation: number = ++this.generation;
      this.preparing = true;
      try {
        const device: TiebaDevice = await DeviceIdentity.ensure(context);
        if (owner !== authSession.sessionKey() || generation !== this.generation) { return '账号已变化，未继续点赞'; }
        const response = await this.api.fetchThreadDetail(device, authSession.session(), tid, 1, 30, ReplySortType.ASC);
        if (owner !== authSession.sessionKey() || generation !== this.generation) { return '账号已变化，未继续点赞'; }
        if (!response.ok) { return response.describeFailure(); }
        const main = ThreadDetail.locateMainPost(response.data);
        if (main === undefined) { return '暂未取得主帖，无法点赞'; }
        this.target = { tid: tid, pid: main.pid, forumId: response.data.forumId,
          objType: AgreeObjType.THREAD, parentPid: 0, generation: generation };
        this.agreement = new AgreeState(main.isAgreed, main.agreeCount);
      } catch (err) {
        return '读取点赞状态失败，请稍后重试';
      } finally {
        if (generation === this.generation) { this.preparing = false; }
      }
    }
    if (owner !== authSession.sessionKey()) { return '账号已变化，未继续点赞'; }
    const target: AgreeTarget | undefined = this.target;
    const state: AgreeState | undefined = this.agreement;
    if (target === undefined || state === undefined) { return '暂未取得主帖，无法点赞'; }
    const generation: number = this.generation;
    return this.actions.toggle(context, target, state, (): boolean => generation === this.generation,
      async (current: () => boolean): Promise<void> => {
        const device: TiebaDevice = await DeviceIdentity.ensure(context);
        if (!current()) { return; }
        const response = await this.api.fetchThreadDetail(device, authSession.session(), target.tid, 1, 30, ReplySortType.ASC);
        if (!current() || !response.ok) { return; }
        const main = ThreadDetail.locateMainPost(response.data);
        if (main === undefined || main.pid !== target.pid) { return; }
        state.isAgreed = response.data.mainPostId === target.pid ? response.data.isAgreed : main.isAgreed;
        state.count = response.data.mainPostId === target.pid ? response.data.agreeCount : main.agreeCount;
        state.toggled = false;
      });
  }
}

/** 跟随列表页面生命周期；不写磁盘，只有实际点击过的卡片才读取详情。 */
@ObservedV2
export class ThreadCardActionsVM {
  private states: Map<number, ThreadCardActionState> = new Map();
  private owner: string = '';
  private sharing: boolean = false;

  private trim(protectedTid: number = 0): void {
    for (const entry of this.states) {
      if (this.states.size <= CARD_ACTION_DETAIL_LIMIT) { break; }
      if (entry[0] !== protectedTid && entry[1].release()) { this.states.delete(entry[0]); }
    }
  }

  async toggleLike(state: ThreadCardActionState, context: common.UIAbilityContext,
    tid: number, forumName: string): Promise<string> {
    const owner: string = authSession.sessionKey();
    if (this.owner !== owner) {
      for (const item of this.states.values()) { item.release(); }
      this.states.clear();
      this.owner = owner;
    }
    const previous: ThreadCardActionState | undefined = this.states.get(tid);
    if (previous !== state) { previous?.release(); }
    this.states.delete(tid);
    this.states.set(tid, state);
    this.trim(tid);
    try {
      return await state.toggleLike(context, tid, forumName);
    } finally {
      if (this.owner !== authSession.sessionKey() || this.states.get(tid) !== state) { state.release(); }
      this.trim();
    }
  }

  async share(context: common.UIAbilityContext, tid: number, title: string): Promise<string> {
    if (!Number.isSafeInteger(tid) || tid <= 0) { return '帖子链接暂不可用'; }
    if (this.sharing) { return ''; }
    this.sharing = true;
    try {
      await shareWebPage(context, title.trim().length > 0 ? title.trim() : '贴吧帖子',
        `https://tieba.baidu.com/p/${tid}`);
      return '';
    } catch (err) {
      return '暂时无法打开系统分享，请稍后重试';
    } finally {
      this.sharing = false;
    }
  }
}
