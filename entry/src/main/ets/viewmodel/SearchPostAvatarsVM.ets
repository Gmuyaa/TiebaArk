/** 搜帖卡片按需补图；只保留当前查询的内存结果，不新增落盘缓存。 */
export type SearchForumAvatarDone = (forumName: string, avatarUrl: string) => void;
export type SearchAvatarFetcher = (name: string, forum: boolean, tid: number, pid: number,
  onForumAvatar: SearchForumAvatarDone) => Promise<string>;

class AvatarTask {
  name: string;
  forum: boolean;
  key: string;
  epoch: number;
  tid: number;
  pid: number;
  /** 吧图等待关联作者；同吧首个作者结束仍缺图便立即独立回退。 */
  afterAuthorKey: string;
  constructor(name: string, forum: boolean, epoch: number, tid: number, pid: number,
    afterAuthorKey: string = '') {
    this.name = name; this.forum = forum; this.epoch = epoch;
    this.tid = tid; this.pid = pid;
    this.key = forum ? `forum:${name}` : `author:${tid}:${pid}`;
    this.afterAuthorKey = afterAuthorKey;
  }
}

@ObservedV2
export class SearchPostAvatarsVM {
  @Trace urls: Map<string, string> = new Map();
  private fetcher: SearchAvatarFetcher | undefined = undefined;
  private epoch: number = 0;
  private inflight: number = 0;
  private queue: AvatarTask[] = [];
  private pending: Set<string> = new Set();
  private failedAt: Map<string, number> = new Map();

  reset(fetcher?: SearchAvatarFetcher): void {
    this.epoch++;
    this.fetcher = fetcher;
    this.queue = []; this.pending = new Set(); this.failedAt = new Map();
    this.urls = new Map();
  }

  /** cachedForumAvatar 仅接受调用方已校正的会话缓存，不能传入未经校正的历史地址。 */
  request(tid: number, pid: number, forumName: string, cachedForumAvatar: string = ''): void {
    const forumKey: string = `forum:${forumName.trim()}`;
    if (this.fetcher !== undefined && forumName.trim().length > 0 && cachedForumAvatar.length > 0
      && !this.urls.has(forumKey)) {
      const next: Map<string, string> = new Map(this.urls);
      next.set(forumKey, cachedForumAvatar);
      this.urls = next;
    }
    if (Number.isSafeInteger(tid) && tid > 0 && Number.isSafeInteger(pid) && pid > 0) {
      this.enqueue(forumName, false, tid, pid);
    }
    const authorKey: string = `author:${tid}:${pid}`;
    this.enqueue(forumName, true, 0, 0, this.pending.has(authorKey) ? authorKey : '');
    this.pump();
  }

  private enqueue(name: string, forum: boolean, tid: number, pid: number, afterAuthorKey: string = ''): void {
    const clean: string = name.trim();
    if ((forum && clean.length === 0) || this.fetcher === undefined) { return; }
    const task: AvatarTask = new AvatarTask(clean, forum, this.epoch, tid, pid, afterAuthorKey);
    const failed: number | undefined = this.failedAt.get(task.key);
    if (this.urls.has(task.key) || this.pending.has(task.key)
      || (failed !== undefined && Date.now() - failed < 60000)) { return; }
    this.pending.add(task.key); this.queue.push(task);
  }

  /** 先用两槽读作者；首次详情仍缺吧图，回退优先使用下一个空槽，不再等整吧作者队列。 */
  private pump(): void {
    while (this.inflight < 2 && this.queue.length > 0 && this.fetcher !== undefined) {
      let index: number = this.queue.findIndex((task: AvatarTask): boolean =>
        task.forum && task.afterAuthorKey.length === 0);
      if (index < 0) {
        index = this.queue.findIndex((task: AvatarTask): boolean => !task.forum);
      }
      if (index < 0) { break; }
      const task: AvatarTask = this.queue.splice(index, 1)[0];
      if (this.urls.has(task.key)) {
        this.pending.delete(task.key);
        continue;
      }
      const fetcher: SearchAvatarFetcher = this.fetcher;
      this.inflight++;
      void this.run(task, fetcher);
    }
  }

  private acceptForumAvatar(task: AvatarTask, name: string, url: string): void {
    if (task.epoch !== this.epoch || task.forum || task.name.length === 0
      || task.name !== name.trim() || url.length === 0) { return; }
    const next: Map<string, string> = new Map(this.urls);
    next.set(`forum:${task.name}`, url);
    this.urls = next;
  }

  private async run(task: AvatarTask, fetcher: SearchAvatarFetcher): Promise<void> {
    let url: string = '';
    try {
      url = await fetcher(task.name, task.forum, task.tid, task.pid,
        (name: string, avatar: string): void => { this.acceptForumAvatar(task, name, avatar); });
    } catch (_) { /* 保留文字兜底并进入冷却。 */ }
    this.inflight--;
    if (task.epoch === this.epoch) {
      this.pending.delete(task.key);
      if (!task.forum) {
        for (const queued of this.queue) {
          if (queued.forum && (queued.afterAuthorKey === task.key || queued.name === task.name)) {
            queued.afterAuthorKey = '';
          }
        }
      }
      if (url.length > 0) {
        const next: Map<string, string> = new Map(this.urls);
        next.set(task.key, url); this.urls = next;
      } else { this.failedAt.set(task.key, Date.now()); }
    }
    this.pump();
  }
}
