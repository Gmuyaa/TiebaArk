import { common } from '@kit.AbilityKit';
import { TiebaApi, ForumSquareResponse } from '../api/TiebaApi';
import { SquareCategory, SquareForum } from '../model/ForumSquare';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { authSession } from '../auth/AuthSession';
import { applyForumFollowing } from './ForumStateStore';

@ObservedV2
export class ForumSquareVM {
  @Trace categories: SquareCategory[] = [];
  @Trace forums: SquareForum[] = [];
  @Trace selected: string = '推荐';
  @Trace subcategories: string[] = [];
  @Trace selectedSub: string = '全部';
  @Trace loading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace error: string = '';
  @Trace hasMore: boolean = false;
  private page: number = 0;
  private sequence: number = 0;
  private api: TiebaApi = new TiebaApi();

  dispose(): void { this.sequence++; }

  async reset(context: common.UIAbilityContext): Promise<void> {
    this.sequence++; this.categories = []; this.subcategories = [];
    this.selected = '推荐'; this.selectedSub = '全部';
    this.forums = []; this.loaded = false; this.hasMore = false; this.page = 0;
    await this.load(context);
  }

  async select(context: common.UIAbilityContext, id: string): Promise<void> {
    if (this.selected === id && (this.loading || this.loaded)) { return; }
    this.selected = id;
    this.selectedSub = '全部'; this.subcategories = [];
    this.forums = []; this.loaded = false; this.hasMore = false; this.page = 0;
    await this.load(context);
  }

  async selectSub(context: common.UIAbilityContext, name: string): Promise<void> {
    if (this.selectedSub === name || !this.subcategories.includes(name)) { return; }
    this.selectedSub = name;
    this.forums = []; this.loaded = false; this.hasMore = false; this.page = 0;
    await this.load(context);
  }

  async load(context: common.UIAbilityContext, more: boolean = false): Promise<void> {
    if (more && (this.loading || !this.hasMore)) { return; }
    const sequence: number = ++this.sequence;
    const category: string = this.selected;
    const subcategory: string = this.selectedSub;
    const owner: string = authSession.sessionKey();
    const page: number = more ? this.page + 1 : 1;
    this.loading = true; this.error = '';
    try {
      const device = await DeviceIdentity.ensure(context);
      if (sequence !== this.sequence || owner !== authSession.sessionKey()) { return; }
      const response: ForumSquareResponse = await this.api.fetchForumSquare(device, authSession.session(), category, subcategory, page);
      if (sequence !== this.sequence || owner !== authSession.sessionKey()) { return; }
      if (!response.ok) { this.error = response.describeFailure(); return; }
      for (const item of response.data.forums) {
        applyForumFollowing(item.followId(), item.name, item.following);
      }
      if (this.categories.length === 0) { this.categories = response.data.categories; }
      if (!more) {
        this.selected = response.data.category;
        this.subcategories = response.data.subcategories;
      }
      const seen: Set<string> = new Set(more ? this.forums.map((item: SquareForum): string => item.id) : []);
      const added: SquareForum[] = response.data.forums.filter((item: SquareForum): boolean => !seen.has(item.id));
      this.forums = more ? this.forums.concat(added) : response.data.forums;
      this.hasMore = response.data.hasMore && (!more || added.length > 0);
      this.page = page; this.loaded = true;
    } catch (_) {
      if (sequence === this.sequence) { this.error = '加载失败，请重试'; }
    } finally {
      if (sequence === this.sequence) { this.loading = false; }
    }
  }
}
