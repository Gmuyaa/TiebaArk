/** 当前话题列表缺失信息的两槽补取；不持久化，回写保留卡片对象。 */
import { HotTopicCardInfo } from '../model/HotTopicCard';
import { ThreadBrief } from '../model/ThreadList';

export type HotTopicCardFetcher = (tid: number) => Promise<HotTopicCardInfo | undefined>;

@ObservedV2
export class HotTopicCardsVM {
  @Trace revision: number = 0;
  private fetcher: HotTopicCardFetcher | undefined = undefined;
  private current: ThreadBrief[] = [];
  private attempted: Set<ThreadBrief> = new Set();
  private queue: ThreadBrief[] = [];
  private inflight: number = 0;
  private epoch: number = 0;

  reset(fetcher?: HotTopicCardFetcher): void {
    this.epoch++;
    this.fetcher = fetcher;
    this.current = [];
    this.attempted = new Set();
    this.queue = [];
  }

  sync(items: ThreadBrief[]): void {
    this.current = items;
    // 首屏补充和后续分页共用当前列表内已确认的吧头像，不逐帖等待网络。
    const avatars: Map<string, string> = new Map();
    for (const item of items) {
      if (item.sourceForum.length > 0 && item.sourceForumAvatar.length > 0) {
        avatars.set(item.sourceForum, item.sourceForumAvatar);
      }
    }
    let changed: boolean = false;
    for (const item of items) {
      const avatar: string | undefined = avatars.get(item.sourceForum);
      if (item.sourceForumAvatar.length === 0 && avatar !== undefined) {
        item.sourceForumAvatar = avatar;
        item.avatarStamp++;
        changed = true;
      }
    }
    if (changed) { this.revision++; }
    const retained: Set<ThreadBrief> = new Set(items);
    this.queue = this.queue.filter((item: ThreadBrief): boolean => retained.has(item));
    const attempted: Set<ThreadBrief> = new Set();
    for (const item of this.attempted) {
      if (retained.has(item)) { attempted.add(item); }
    }
    this.attempted = attempted;
    for (const item of items) {
      if (this.fetcher !== undefined && !this.attempted.has(item) && this.needsSupplement(item)) {
        this.attempted.add(item);
        this.queue.push(item);
      }
    }
    this.pump();
  }

  private needsSupplement(item: ThreadBrief): boolean {
    return item.postedMs <= 0 || item.authorId <= 0 || item.authorName.length === 0 ||
      item.agreeCount < 0 || item.shareCount < 0 ||
      (item.sourceForum.length > 0 && (item.sourceForumId <= 0 || item.sourceForumAvatar.length === 0));
  }

  private pump(): void {
    while (this.inflight < 2 && this.queue.length > 0 && this.fetcher !== undefined) {
      const item: ThreadBrief = this.queue.shift()!;
      if (!this.needsSupplement(item)) { continue; }
      const fetcher: HotTopicCardFetcher = this.fetcher;
      const epoch: number = this.epoch;
      this.inflight++;
      void this.fetch(item, fetcher, epoch);
    }
  }

  private async fetch(item: ThreadBrief, fetcher: HotTopicCardFetcher, epoch: number): Promise<void> {
    try {
      const info: HotTopicCardInfo | undefined = await fetcher(item.tid);
      if (epoch !== this.epoch || !this.current.includes(item) || info === undefined || info.tid !== item.tid) { return; }
      if (Number.isSafeInteger(info.agreeCount) && info.agreeCount >= 0) { item.agreeCount = info.agreeCount; }
      if (Number.isSafeInteger(info.shareCount) && info.shareCount >= 0) { item.shareCount = info.shareCount; }
      if (info.postedMs > 0) { item.postedMs = info.postedMs; }
      if (Number.isSafeInteger(info.authorId) && info.authorId > 0) {
        const sameAuthor: boolean = item.authorId === info.authorId;
        item.authorId = info.authorId;
        if (!sameAuthor || info.authorName.length > 0) { item.authorName = info.authorName; }
        if (!sameAuthor || info.authorAvatar.length > 0) { item.authorAvatar = info.authorAvatar; }
      }
      if (info.forumName.length > 0 && info.forumName === item.sourceForum) {
        for (const target of this.current) {
          if (target.sourceForum === info.forumName) {
            if (target.sourceForumId <= 0 && Number.isSafeInteger(info.forumId) && info.forumId > 0) {
              target.sourceForumId = info.forumId;
            }
            if (target.sourceForumAvatar.length === 0 && info.forumAvatar.length > 0) {
              target.sourceForumAvatar = info.forumAvatar;
              target.avatarStamp++;
            }
          }
        }
      }
      this.revision++;
    } catch (_) {
      // 补充失败仍保留原列表；显式刷新创建的新对象可以重试，不冒充零或加载成功。
    } finally {
      this.inflight--;
      this.pump();
    }
  }
}
