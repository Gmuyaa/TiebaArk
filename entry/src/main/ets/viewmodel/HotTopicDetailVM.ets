/** 原生话题页状态；排序/刷新整体提交，续页失败不推进游标。 */
import { HotTopicDetailApi, HotTopicDetailResponse } from '../api/HotTopicDetailApi';
import { HotTopicDetail } from '../model/HotTopicDetail';
import { ThreadBrief } from '../model/ThreadList';

@ObservedV2
export class HotTopicDetailVM {
  @Trace data: HotTopicDetail = new HotTopicDetail();
  @Trace items: ThreadBrief[] = [];
  @Trace sort: number = 1;
  @Trace loaded: boolean = false;
  @Trace loading: boolean = false;
  @Trace loadingMore: boolean = false;
  @Trace error: string = '';
  @Trace moreError: string = '';
  @Trace hasMore: boolean = false;

  private api: HotTopicDetailApi = new HotTopicDetailApi();
  private topicId: number = 0;
  private topicName: string = '';
  private page: number = 0;
  private lastId: string = '0';
  private epoch: number = 0;
  private alive: boolean = true;
  private failedSort: number = 0;

  async load(topicId: number, topicName: string): Promise<void> {
    if (!this.alive) { return; }
    this.epoch++;
    this.topicId = topicId;
    this.topicName = topicName.trim();
    this.data = new HotTopicDetail();
    this.data.title = this.topicName;
    this.items = [];
    this.sort = 1;
    this.loaded = false;
    this.page = 0;
    this.lastId = '0';
    this.hasMore = false;
    await this.replace(1);
  }

  async refresh(): Promise<void> {
    if (!this.alive || this.loading) { return; }
    await this.replace(this.sort);
  }

  async selectSort(sort: number): Promise<void> {
    if (!this.alive || (sort !== 1 && sort !== 2) || (sort === this.sort && !this.loading)) { return; }
    await this.replace(sort);
  }

  async retry(): Promise<void> {
    if (!this.alive || this.loading) { return; }
    await this.replace(this.failedSort > 0 ? this.failedSort : this.sort);
  }

  private valid(epoch: number): boolean { return this.alive && epoch === this.epoch; }

  private unique(items: ThreadBrief[], previous: ThreadBrief[] = []): ThreadBrief[] {
    const seen: Set<number> = new Set<number>();
    const merged: ThreadBrief[] = [];
    for (const item of previous.concat(items)) {
      if (!Number.isSafeInteger(item.tid) || item.tid <= 0 || seen.has(item.tid)) { continue; }
      seen.add(item.tid);
      merged.push(item);
    }
    return merged;
  }

  private async replace(sort: number): Promise<void> {
    const epoch: number = ++this.epoch;
    this.loading = true;
    this.loadingMore = false;
    this.error = '';
    this.moreError = '';
    this.failedSort = sort;
    try {
      if (!Number.isSafeInteger(this.topicId) || this.topicId <= 0) {
        this.error = '话题地址无效，请返回热榜重新进入';
        return;
      }
      const response: HotTopicDetailResponse =
        await this.api.fetch(this.topicId, this.topicName, sort, 1, '0');
      if (!this.valid(epoch)) { return; }
      if (!response.ok) { this.error = response.describeFailure(); return; }
      const items: ThreadBrief[] = this.unique(response.data.items);
      this.data = response.data.detail;
      this.topicName = this.data.title;
      this.items = items;
      this.sort = sort;
      this.failedSort = 0;
      this.page = 1;
      this.lastId = response.data.lastId;
      this.hasMore = response.data.hasMore && items.length > 0 && this.lastId !== '0';
      this.loaded = true;
    } catch (err) {
      if (this.valid(epoch)) { this.error = '话题加载失败，请稍后重试'; }
    } finally {
      if (this.valid(epoch)) { this.loading = false; }
    }
  }

  async loadMore(): Promise<void> {
    if (!this.alive || !this.loaded || this.loading || this.loadingMore || !this.hasMore) { return; }
    const epoch: number = this.epoch;
    const nextPage: number = this.page + 1;
    const cursor: string = this.lastId;
    this.loadingMore = true;
    this.moreError = '';
    try {
      const response: HotTopicDetailResponse =
        await this.api.fetch(this.topicId, this.topicName, this.sort, nextPage, cursor);
      if (!this.valid(epoch)) { return; }
      if (!response.ok) { this.moreError = response.describeFailure(); return; }
      const merged: ThreadBrief[] = this.unique(response.data.items, this.items);
      const progressed: boolean = merged.length > this.items.length;
      this.items = merged;
      this.page = nextPage;
      this.lastId = response.data.lastId;
      this.hasMore = response.data.hasMore && progressed && this.lastId !== '0' && this.lastId !== cursor;
    } catch (err) {
      if (this.valid(epoch)) { this.moreError = '更多讨论加载失败，请重试'; }
    } finally {
      if (this.valid(epoch)) { this.loadingMore = false; }
    }
  }

  dispose(): void {
    this.alive = false;
    this.epoch++;
    this.items = [];
    this.data = new HotTopicDetail();
    this.loading = false;
    this.loadingMore = false;
  }
}
