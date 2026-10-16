/** 搜帖卡片按需补图；只保留当前查询的内存结果，不新增落盘缓存。 */
export type SearchAvatarFetcher = (name: string, forum: boolean) => Promise<string>;

class AvatarTask {
  name: string;
  forum: boolean;
  key: string;
  epoch: number;
  constructor(name: string, forum: boolean, epoch: number) {
    this.name = name; this.forum = forum; this.epoch = epoch;
    this.key = `${forum ? 'forum' : 'author'}:${name}`;
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

  request(account: string, forumName: string): void {
    this.enqueue(account, false);
    this.enqueue(forumName, true);
    this.pump();
  }

  private enqueue(name: string, forum: boolean): void {
    const clean: string = name.trim();
    if (clean.length === 0 || this.fetcher === undefined) { return; }
    const task: AvatarTask = new AvatarTask(clean, forum, this.epoch);
    const failed: number | undefined = this.failedAt.get(task.key);
    if (this.urls.has(task.key) || this.pending.has(task.key)
      || (failed !== undefined && Date.now() - failed < 60000)) { return; }
    this.pending.add(task.key); this.queue.push(task);
  }

  /** 作者与吧共用两个请求槽，列表渲染不等待补图。 */
  private pump(): void {
    while (this.inflight < 2 && this.queue.length > 0 && this.fetcher !== undefined) {
      const task: AvatarTask | undefined = this.queue.shift();
      if (task === undefined) { break; }
      const fetcher: SearchAvatarFetcher = this.fetcher;
      this.inflight++;
      void this.run(task, fetcher);
    }
  }

  private async run(task: AvatarTask, fetcher: SearchAvatarFetcher): Promise<void> {
    let url: string = '';
    try { url = await fetcher(task.name, task.forum); } catch (_) { /* 保留文字兜底并进入冷却。 */ }
    this.inflight--;
    if (task.epoch === this.epoch) {
      this.pending.delete(task.key);
      if (url.length > 0) {
        const next: Map<string, string> = new Map(this.urls);
        next.set(task.key, url); this.urls = next;
      } else { this.failedAt.set(task.key, Date.now()); }
    }
    this.pump();
  }
}
