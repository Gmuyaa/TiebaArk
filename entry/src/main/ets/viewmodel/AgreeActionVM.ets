import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AgreeResponse, TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { isAgreeSupported, resolveAgreeCount, resolveAgreeLiked, unsupportedAgreeTip } from '../model/ThreadDetail';
import { AgreeObjType, TiebaDevice, TiebaSession } from '../net/TiebaParams';
import { DeviceIdentity } from '../utils/DeviceIdentity';

/** 详情楼层与列表卡片共享的轻量可观察点赞态。 */
@ObservedV2
export class AgreeState {
  @Trace isAgreed: boolean = false;
  @Trace count: number = 0;
  @Trace toggled: boolean = false;
  @Trace pending: boolean = false;

  constructor(agreed: boolean, count: number) { this.isAgreed = agreed; this.count = count; }
  liked(): boolean { return resolveAgreeLiked(this.isAgreed, this.toggled); }
  displayCount(): number { return resolveAgreeCount(this.count, this.isAgreed, this.toggled); }
}

export interface AgreeTarget {
  tid: number;
  pid: number;
  forumId: number;
  objType: AgreeObjType;
  parentPid: number;
  generation: number;
}

class AgreeWriteState {
  owner: string = authSession.sessionKey();
  desired: boolean;
  expected: boolean;
  state: AgreeState;
  generation: number;

  constructor(desired: boolean, expected: boolean, state: AgreeState, generation: number) {
    this.desired = desired; this.expected = expected; this.state = state; this.generation = generation;
  }
}

/** 串行发送同一目标的最后点击意图；读回位置及页面数据同步由调用方提供。 */
export class AgreeActionVM {
  private api: TiebaApi = new TiebaApi();
  private writes: Map<string, AgreeWriteState> = new Map();
  private confirmations: Map<string, number> = new Map();

  async toggle(context: common.UIAbilityContext, target: AgreeTarget, state: AgreeState,
    isCurrent: () => boolean, confirm: (current: () => boolean) => Promise<void>): Promise<string> {
    const session: TiebaSession = authSession.session();
    const owner: string = authSession.sessionKey();
    if (!session.hasBduss()) { return '需要登录后才能点赞'; }
    if (!isAgreeSupported(target.objType)) { return unsupportedAgreeTip(target.objType); }
    if (target.objType === AgreeObjType.SUB_POST && target.parentPid <= 0) { return '暂时无法定位这条回复'; }
    const key: string = `${target.objType}:${target.tid}:${target.pid}`;
    const before: boolean = state.liked();
    const desired: boolean = !before;
    state.toggled = !state.toggled;
    const existing: AgreeWriteState | undefined = this.writes.get(key);
    if (existing !== undefined && existing.state === state && existing.generation === target.generation &&
      existing.owner === owner) {
      existing.desired = desired;
      return '';
    }
    this.confirmations.set(key, (this.confirmations.get(key) ?? 0) + 1);
    const flight: AgreeWriteState = new AgreeWriteState(desired, before, state, target.generation);
    this.writes.set(key, flight);
    state.pending = true;
    const current: () => boolean = (): boolean => isCurrent() && authSession.matchesSession(session, owner);
    let reason: string = '';
    let wrote: boolean = false;
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!current()) { return '账号或帖子已变化，未继续点赞'; }
      while (current() && flight.desired !== flight.expected) {
        const next: boolean = flight.desired;
        wrote = true;
        const response: AgreeResponse = await this.api.agreePost(device, session, target.tid, target.pid,
          next, target.objType, target.objType === AgreeObjType.POST ? target.forumId : 0);
        if (!current()) { return '账号或帖子已变化，请重新读取点赞结果'; }
        if (response.ok) {
          flight.expected = next;
        } else if (flight.desired === next) {
          reason = response.describeFailure();
          state.toggled = state.isAgreed !== flight.expected;
          break;
        }
      }
    } catch (err) {
      reason = `点赞失败：${(err as Error).message}`;
      if (current() && this.writes.get(key) === flight) {
        state.toggled = state.isAgreed !== flight.expected;
      }
    } finally {
      if (this.writes.get(key) === flight) {
        state.pending = false;
        this.writes.delete(key);
      }
      if (wrote && current()) {
        const token: number = (this.confirmations.get(key) ?? 0) + 1;
        this.confirmations.set(key, token);
        const confirmedCurrent: () => boolean = (): boolean => current() && this.confirmations.get(key) === token;
        setTimeout((): void => {
          if (!confirmedCurrent()) { return; }
          confirm(confirmedCurrent).catch((): void => {
            hilog.warn(0x0000, 'AgreeFlow', 'source=confirm-unexpected-error');
          });
        }, 3000);
      }
    }
    return reason;
  }
}
