import { common } from '@kit.AbilityKit';
import { TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { FollowForumItem } from '../model/FollowForum';
import { ForumSearchItem } from '../model/ForumSearch';
import { HotTopicItem } from '../model/HotTopic';
import { BrowseItem, loadBrowseHistory } from '../utils/BrowseHistory';
import { readFollowForumsShared } from './ForumReadCache';

export class ComposeForumOption {
  id: number = 0;
  name: string = '';
  avatar: string = '';
  level: number = 0;
  followers: string = '';
  posts: string = '';
  source: string = '';
}

export function composeFollowOptions(items: FollowForumItem[]): ComposeForumOption[] {
  return items.map((item: FollowForumItem): ComposeForumOption => {
    const out = new ComposeForumOption();
    out.id = item.fid; out.name = item.fname; out.avatar = item.avatar; out.level = item.level;
    out.followers = item.concernNum; out.posts = item.postNum; out.source = '你的关注';
    return out;
  }).filter((item: ComposeForumOption): boolean => item.name.length > 0);
}

export function composeRecentOptions(items: BrowseItem[], followed: ComposeForumOption[]): ComposeForumOption[] {
  const result: ComposeForumOption[] = [];
  const seen: Set<string> = new Set<string>();
  for (const item of items.slice().sort((a: BrowseItem, b: BrowseItem): number => b.timeMs - a.timeMs)) {
    const name: string = item.forumName.trim();
    if (item.isDeleted || name.length === 0 || seen.has(name)) { continue; }
    seen.add(name);
    const match = followed.find((value: ComposeForumOption): boolean => value.name === name);
    const option = new ComposeForumOption();
    option.id = match?.id ?? 0; option.name = name; option.avatar = match?.avatar || item.forumAvatar;
    option.level = match?.level ?? 0; option.followers = match?.followers ?? ''; option.posts = match?.posts ?? '';
    option.source = '最近在逛'; result.push(option);
  }
  return result;
}

@ObservedV2
export class ComposeOptionsVM {
  @Trace recent: ComposeForumOption[] = [];
  @Trace followed: ComposeForumOption[] = [];
  @Trace forumsLoading: boolean = false;
  @Trace forumError: string = '';
  @Trace forumTab: number = 0;
  @Trace query: string = '';
  @Trace searchRows: ComposeForumOption[] = [];
  @Trace searchLoading: boolean = false;
  @Trace searchError: string = '';
  @Trace searched: boolean = false;
  @Trace searchMore: boolean = false;
  @Trace topics: HotTopicItem[] = [];
  @Trace topicsLoading: boolean = false;
  @Trace topicError: string = '';
  @Trace allTopics: boolean = false;
  private alive: boolean = true;
  private forumEpoch: number = 0;
  private searchEpoch: number = 0;
  private topicEpoch: number = 0;
  private searchPage: number = 0;
  private api: TiebaApi = new TiebaApi();

  dispose(): void {
    this.alive = false; this.forumEpoch++; this.searchEpoch++; this.topicEpoch++;
  }

  async loadForums(context: common.UIAbilityContext): Promise<void> {
    if (!this.alive) { return; }
    const epoch: number = ++this.forumEpoch;
    const owner: string = authSession.sessionKey();
    this.forumsLoading = true; this.forumError = ''; this.recent = []; this.followed = [];
    let history: BrowseItem[] = [];
    const current = (): boolean => this.alive && epoch === this.forumEpoch;
    const publish = (): void => {
      if (!current()) { return; }
      if (owner !== authSession.sessionKey()) {
        this.recent = []; this.followed = []; this.forumError = '登录状态已变化，请重新打开'; return;
      }
      this.recent = composeRecentOptions(history, this.followed);
    };
    const recentRead: Promise<void> = loadBrowseHistory(context).then((items: BrowseItem[]): void => {
      history = items; publish();
    }).catch((): void => { if (current()) { this.forumError = '最近浏览读取失败，请重试'; } });
    const followRead: Promise<void> = (async (): Promise<void> => {
      if (!authSession.isLoggedIn()) { if (current()) { this.forumError = '登录后可查看我的关注'; } return; }
      try {
        const result = await readFollowForumsShared(context);
        if (!current()) { return; }
        if (owner !== authSession.sessionKey()) { publish(); return; }
        this.followed = composeFollowOptions(result.items); publish();
      } catch (err) {
        if (current()) { this.forumError = '我的关注读取失败，请重试'; }
      }
    })();
    await Promise.all([recentRead, followRead]);
    if (current()) { publish(); this.forumsLoading = false; }
  }

  changeQuery(value: string): void {
    this.query = value; this.searchEpoch++; this.searchRows = []; this.searchError = '';
    this.searchLoading = false; this.searched = false; this.searchMore = false; this.searchPage = 0;
  }

  async search(next: boolean = false): Promise<void> {
    if (!this.alive || this.searchLoading || this.query.trim().length === 0 || (next && !this.searchMore)) { return; }
    const epoch: number = ++this.searchEpoch;
    const query: string = this.query.trim();
    const page: number = next ? this.searchPage + 1 : 1;
    this.searchLoading = true; this.searchError = ''; this.searched = true;
    try {
      const response = await this.api.searchForums(query, page, 30);
      if (!this.alive || epoch !== this.searchEpoch) { return; }
      if (!response.ok) { this.searchError = response.describeFailure(); return; }
      if (response.data.page !== page) { this.searchError = '搜索页码不匹配，请重试'; return; }
      const base: ComposeForumOption[] = next ? this.searchRows.slice() : [];
      const seen: Set<string> = new Set<string>(base.map((item: ComposeForumOption): string => item.name));
      const before: number = base.length;
      for (const item of response.data.items) {
        if (item.forumName.trim().length === 0 || seen.has(item.forumName)) { continue; }
        const row: ComposeForumOption = this.searchOption(item);
        seen.add(row.name); base.push(row);
      }
      this.searchRows = base; this.searchPage = page;
      this.searchMore = response.data.hasMore && base.length > before && page < 100;
    } catch (err) {
      if (this.alive && epoch === this.searchEpoch) { this.searchError = '搜索失败，请重试'; }
    } finally {
      if (this.alive && epoch === this.searchEpoch) { this.searchLoading = false; }
    }
  }

  private searchOption(item: ForumSearchItem): ComposeForumOption {
    const row = new ComposeForumOption();
    row.id = item.forumId; row.name = item.forumName; row.avatar = item.avatar;
    row.followers = item.concernNum; row.posts = item.postNum;
    const followed = this.followed.find((entry: ComposeForumOption): boolean => entry.name === row.name);
    row.level = followed?.level ?? 0; row.source = followed === undefined ? '' : '你的关注';
    return row;
  }

  async loadTopics(): Promise<void> {
    if (!this.alive || this.topicsLoading) { return; }
    const epoch: number = ++this.topicEpoch;
    this.topicsLoading = true; this.topicError = '';
    try {
      const response = await this.api.fetchHotTopics();
      if (!this.alive || epoch !== this.topicEpoch) { return; }
      if (!response.ok) { this.topicError = response.describeFailure(); return; }
      const seen: Set<number> = new Set<number>();
      this.topics = response.data.filter((item: HotTopicItem): boolean => {
        if (item.id <= 0 || item.name.trim().length === 0 || seen.has(item.id)) { return false; }
        seen.add(item.id); return true;
      });
    } catch (err) {
      if (this.alive && epoch === this.topicEpoch) { this.topicError = '热榜读取失败，请重试'; }
    } finally {
      if (this.alive && epoch === this.topicEpoch) { this.topicsLoading = false; }
    }
  }
}
