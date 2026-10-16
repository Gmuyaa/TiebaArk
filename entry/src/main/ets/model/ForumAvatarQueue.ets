/** 吧头像按需反查队列，合并同一贴吧的请求并限制并发；回调前检查任务有效性。 */

import { getForumAvatar, markForumAvatarFetched, putForumAvatar } from './ForumAvatarStore';

/** 同时在飞的反查请求数上限。frs/page 是完整列表端点，别放开 */
const MAX_INFLIGHT: number = 2;
/** 反查失败后的冷却窗（毫秒）：冷却内同名入队静默忽略 */
const COOLDOWN_MS: number = 60000;

/** 真机侧注入的取数函数：返回头像 URL；空串 = 这次没拿到（记入冷却） */
export type ForumAvatarFetcher = (forumName: string) => Promise<string>;

/** 反查完成回调（空串 = 失败/没拿到，调用方维持文字头像兜底） */
export type ForumAvatarDone = (avatarUrl: string) => void;

export class ForumAvatarQueue {
  private readonly fetcher: ForumAvatarFetcher;
  private readonly nowFn: () => number;
  /** 已入队未完成的吧名（去重集合，两条队列的镜像） */
  private readonly pending: Set<string> = new Set();
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

  enqueue(forumName: string, onDone: ForumAvatarDone, force: boolean = false): void {
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
    if (this.pending.has(name)) {
      const waiting: ForumAvatarDone[] | undefined = this.callbacks.get(name);
      if (waiting !== undefined) {
        waiting.push(onDone);
      }
      return;
    }
    this.pending.add(name);
    if (force) {
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
      this.inflight++;
      this.fetcher(name).then((url: string): void => {
        this.settle(name, url);
      }).catch((): void => {
        this.settle(name, '');
      });
    }
  }

  /** 单次反查收尾：计数回收、缓存/冷却记账、回调全部派发、继续泵 */
  private settle(name: string, avatarUrl: string): void {
    this.inflight--;
    this.pending.delete(name);
    const waiting: ForumAvatarDone[] | undefined = this.callbacks.get(name);
    this.callbacks.delete(name);
    if (avatarUrl.length > 0) {
      putForumAvatar(name, avatarUrl);
    } else {
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
