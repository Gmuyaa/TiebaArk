

import { getForumAvatar, markForumAvatarFetched, putForumAvatar } from './ForumAvatarStore';

const MAX_INFLIGHT: number = 2;

const COOLDOWN_MS: number = 60000;

export type ForumAvatarFetcher = (forumName: string) => Promise<string>;

export type ForumAvatarDone = (avatarUrl: string) => void;

export class ForumAvatarQueue {
  private readonly fetcher: ForumAvatarFetcher;
  private readonly nowFn: () => number;

  private readonly pending: Set<string> = new Set();

  private readonly queue: string[] = [];

  private readonly refreshQueue: string[] = [];

  private readonly callbacks: Map<string, ForumAvatarDone[]> = new Map();

  private readonly failedAt: Map<string, number> = new Map();

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

  queueLength(): number {
    return this.queue.length;
  }

  refreshQueueLength(): number {
    return this.refreshQueue.length;
  }

  inflightCount(): number {
    return this.inflight;
  }

  isCoolingDown(forumName: string): boolean {
    const failed: number | undefined = this.failedAt.get(forumName.trim());
    return failed !== undefined && this.nowFn() - failed < COOLDOWN_MS;
  }

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

    markForumAvatarFetched(name);
    if (waiting !== undefined) {
      for (let i: number = 0; i < waiting.length; i++) {
        waiting[i](avatarUrl);
      }
    }
    this.pump();
  }
}
