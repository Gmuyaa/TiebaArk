import { TiebaApi } from '../api/TiebaApi';
import { UserSearchItem } from '../model/UserSearch';

/** 公开搜人独立状态；按需加载，改词/退出后的迟到响应无效。 */
@ObservedV2
export class SearchUsersVM {
  @Trace items: UserSearchItem[] = [];
  @Trace word: string = '';
  @Trace loading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace loadingMore: boolean = false;
  @Trace error: string = '';
  @Trace pagingError: string = '';
  @Trace hasMore: boolean = false;
  private page: number = 0;
  private epoch: number = 0;
  private disposed: boolean = false;
  private api: TiebaApi = new TiebaApi();

  reset(word: string): void {
    this.epoch++;
    this.word = word.trim();
    this.items = []; this.page = 0; this.loaded = false;
    this.loading = false; this.loadingMore = false; this.hasMore = false;
    this.error = ''; this.pagingError = '';
  }

  async load(retry: boolean = false): Promise<void> {
    if (this.disposed || this.word.length === 0 || this.loading || (this.loaded && !retry)) { return; }
    const epoch: number = ++this.epoch;
    this.loading = true; this.error = ''; this.pagingError = '';
    this.items = []; this.page = 0; this.loaded = false; this.hasMore = false;
    await this.fetch(1, epoch);
    if (this.current(epoch)) { this.loading = false; }
  }

  async loadMore(retry: boolean = false): Promise<void> {
    if (this.disposed || this.loading || this.loadingMore || !this.hasMore || (this.pagingError.length > 0 && !retry)) { return; }
    const epoch: number = this.epoch;
    this.loadingMore = true; this.pagingError = '';
    await this.fetch(this.page + 1, epoch);
    if (this.current(epoch)) { this.loadingMore = false; }
  }

  private current(epoch: number): boolean { return !this.disposed && epoch === this.epoch; }
  private fail(page: number, message: string): void {
    if (page === 1) { this.error = message; } else { this.pagingError = message; }
  }

  private async fetch(page: number, epoch: number): Promise<void> {
    try {
      const response = await this.api.searchUsers(this.word, page, 20);
      if (!this.current(epoch)) { return; }
      if (!response.ok) { this.fail(page, response.describeFailure()); return; }
      if (response.data.page !== page) { this.fail(page, '返回页码不一致，请重试'); return; }
      const next: UserSearchItem[] = page === 1 ? [] : this.items.slice();
      const seen: Set<string> = new Set<string>(next.map((item: UserSearchItem) => item.key()));
      const portraits: Set<string> = new Set<string>(next.map((item: UserSearchItem) => item.portrait)
        .filter((portrait: string) => portrait.length > 0));
      const before: number = next.length;
      for (const item of response.data.items) {
        if (seen.has(item.key()) || (item.portrait.length > 0 && portraits.has(item.portrait))) { continue; }
        seen.add(item.key());
        if (item.portrait.length > 0) { portraits.add(item.portrait); }
        next.push(item);
      }
      this.items = next; this.page = page; this.loaded = true;
      this.hasMore = response.data.hasMore && next.length > before;
    } catch (_) {
      if (this.current(epoch)) { this.fail(page, '搜索失败，请重试'); }
    }
  }

  dispose(): void { this.disposed = true; this.reset(''); }
}
