/**
 * 吧头像按需反查队列：合并同一贴吧的请求并限制并发；回调前检查任务有效性。
 *
 * 2026-11-13（吧头像提速）：并发上限 2 → 4；入队时可带 fid，交给注入的 fetcher
 * 走更轻的 `getforumdetail`（只回吧信息）。首页推荐卡片数据一到达就批量入队，
 * 不再等卡片 `onAppear`——冷启动实测原实现最后一张吧头像要 ~2.4s 才出现。
 * 去重、缺图优先、60s 失败冷却的语义未变。
 */

import { getForumAvatar, markForumAvatarFetched, putForumAvatar } from './ForumAvatarStore';

/**
 * 同时在飞的反查请求数上限。
 * 原值 2 是按"每次反查都拉一整页 frs/page"定的；现在已知 fid 时走 getforumdetail，
 * 与 MyListVM（并发 3）、UserPageVM（并发 4）同量级，取 4。
 */
const MAX_INFLIGHT: number = 4;
/** 反查失败后的冷却窗（毫秒）：冷却内同名入队静默忽略 */
const COOLDOWN_MS: number = 60000;

/** 真机侧注入的取数函数：返回头像 URL；空串 = 这次没拿到（记入冷却）。fid<=0 表示调用方不知道吧 ID。 */
export type ForumAvatarFetcher = (forumName: string, forumId: number) => Promise<string>;

/** 反查完成回调（空串 = 失败/没拿到，调用方维持文字头像兜底） */
export type ForumAvatarDone = (avatarUrl: string) => void;

export class ForumAvatarQueue {
  private readonly fetcher: ForumAvatarFetcher;
  private readonly nowFn: () => number;
  /** 已入队未完成的吧名（去重集合，两条队列的镜像） */
  private readonly pending: Set<string> = new Set();
  /** 待发任务的 fid（可能为 0 = 只知道吧名）；同吧后面带 fid 入队时更新为已知值 */
  private readonly pendingForumId: Map<string, number> = new Map();
  /** 高优先 FIFO：**缺头像**的吧（卡片本来就空，等它上屏） */
  private readonly queue: string[] = [];

  private readonly refreshQueue: string[] = [];
  /** 同名的全部回调：fetch 中新入队的卡也要收到同一次结果 */
  private readonly callbacks: Map<string, ForumAvatarDone[]> = new Map();
  /** 最近一次失败的时刻（毫秒），冷却判定用 */
  private readonly failedAt: Map<string, number> = new Map();
  /** 在飞计数 */
  private inflight: number = 0;

  constructor(fetcher: ForumAvatarFetcher,
    nowFn: () => number = (): number => Date.now()) {
    this.fetcher = fetcher;
    this.nowFn = nowFn;
  }

  /**
   * 入队一次反查。
   *
   * @param forumId 已知的吧 ID（列表数据里带 fid 时传），0 = 只知道吧名。
   *   同吧已在排队时，带 fid 的这次会把排队项从"只知名"升级成"可按 ID 查"。
   */
  enqueue(forumName: string, onDone: ForumAvatarDone, force: boolean = false,
    forumId: number = 0): void {
    const name: string = forumName.trim();
    if (name.length === 0) {
      return;
    }
    if (!force) {
      const cached: string = getForumAvatar(name);
      if (cached.length > 0) {
        onDone(cached);
        return;
      }
    }
    const failed: number | undefined = this.failedAt.get(name);
    if (failed !== undefined && this.nowFn() - failed < COOLDOWN_MS) {
      return;
    }
    const known: number = Number.isSafeInteger(forumId) && forumId > 0 ? forumId : 0;
    if (this.pending.has(name)) {
      // 已在飞/在队：补回调；顺带把后到的 fid 记下来供仍排队的任务使用
      if (known > 0 && (this.pendingForumId.get(name) ?? 0) <= 0) {
        this.pendingForumId.set(name, known);
      }
      const waiting: ForumAvatarDone[] | undefined = this.callbacks.get(name);
      if (waiting !== undefined) {
        waiting.push(onDone);
      }
      return;
    }
    this.pending.add(name);
    if (known > 0) {
      this.pendingForumId.set(name, known);
    } else {
      this.pendingForumId.delete(name);
    }
    // force 只表示绕过旧缓存；首次无地址仍是缺图，不能排到已有头像的刷新后面。
    if (force && getForumAvatar(name).length > 0) {
      this.refreshQueue.push(name);
    } else {
      this.queue.push(name);
    }
    this.callbacks.set(name, [onDone]);
    this.pump();
  }

  /** 当前排队等待的反查数（只算**缺失**通道；诊断 / 测试用） */
  queueLength(): number {
    return this.queue.length;
  }

  /** 当前排队等待的**强制刷新**数（诊断 / 测试用） */
  refreshQueueLength(): number {
    return this.refreshQueue.length;
  }

  /** 当前在飞请求数（诊断 / 测试用） */
  inflightCount(): number {
    return this.inflight;
  }

  /** 该吧是否处于失败冷却期内（测试用） */
  isCoolingDown(forumName: string): boolean {
    const failed: number | undefined = this.failedAt.get(forumName.trim());
    return failed !== undefined && this.nowFn() - failed < COOLDOWN_MS;
  }

  /** 启动在飞：未满就发，**先取缺失通道、空了再取刷新通道**。settle 收尾时会再次调用，链路自续 */
  private pump(): void {
    while (this.inflight < MAX_INFLIGHT) {
      const name: string | undefined = this.queue.length > 0
        ? this.queue.shift() : this.refreshQueue.shift();
      if (name === undefined) {
        break;
      }
      const forumId: number = this.pendingForumId.get(name) ?? 0;
      this.pendingForumId.delete(name);
      this.inflight++;
      this.fetcher(name, forumId).then((url: string): void => {
        this.settle(name, url, forumId);
      }).catch((): void => {
        this.settle(name, '', forumId);
      });
    }
  }

  /** 单次反查收尾：计数回收、缓存/冷却记账、回调全部派发、继续泵 */
  private settle(name: string, avatarUrl: string, forumId: number = 0): void {
    this.inflight--;
    this.pending.delete(name);
    const waiting: ForumAvatarDone[] | undefined = this.callbacks.get(name);
    this.callbacks.delete(name);
    // fid 一次失败也值得记：下次（或别的页面）就能直接按 ID 走轻量端点。
    putForumAvatar(name, avatarUrl, forumId);
    if (avatarUrl.length === 0) {
      this.failedAt.set(name, this.nowFn());
    }
    // 无论成功失败都算"本次会话真查过"：失败由冷却负责，成功则纠正旧值
    markForumAvatarFetched(name);
    if (waiting !== undefined) {
      for (let i: number = 0; i < waiting.length; i++) {
        waiting[i](avatarUrl);
      }
    }
    this.pump();
  }
}
