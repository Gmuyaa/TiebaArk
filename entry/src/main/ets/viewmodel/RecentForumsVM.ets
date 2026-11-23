/** 进吧页「我的足迹」VM：从本地浏览历史聚合最近看过的吧，并复用既有补图通道补齐/自愈头像。 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { FollowForumItem } from '../model/FollowForum';
import {
  forgetCachedForumAvatar, getForumAvatar, getForumAvatarId, putForumAvatar
} from '../model/ForumAvatarStore';
import { buildRecentForums, RECENT_FORUMS_MAX, RecentForumItem } from '../model/RecentForums';
import { TiebaDevice } from '../net/TiebaParams';
import { BrowseItem, loadBrowseHistory } from '../utils/BrowseHistory';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import {
  backfillForumAvatars, ForumAvatarBackfillPlan, ForumAvatarNeed
} from '../utils/ForumAvatarBackfill';

@ObservedV2
export class RecentForumsVM {
  @Trace forums: RecentForumItem[] = [];
  @Trace loaded: boolean = false;

  private api: TiebaApi = new TiebaApi();
  private disposed: boolean = false;
  private readEpoch: number = 0;
  private retrying: Set<string> = new Set<string>();

  dispose(): void {
    this.disposed = true;
    this.readEpoch++;
    this.forums = [];
    this.loaded = false;
    this.retrying.clear();
  }

  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.disposed) { return; }
    const epoch: number = ++this.readEpoch;
    try {
      const history: BrowseItem[] = await loadBrowseHistory(context);
      if (this.disposed || epoch !== this.readEpoch) { return; }
      const items: RecentForumItem[] = buildRecentForums(
        history,
        RECENT_FORUMS_MAX,
        (name: string): string => getForumAvatar(name)
      );
      this.forums = items;
      this.loaded = true;
      void this.resolveAvatars(context, epoch);
    } catch {
      if (!this.disposed && epoch === this.readEpoch) {
        this.loaded = true;
      }
    }
  }

  syncKnownAvatars(followed: FollowForumItem[]): void {
    if (this.disposed || this.forums.length === 0 || followed.length === 0) { return; }
    const avatarByName: Map<string, string> = new Map<string, string>();
    for (const item of followed) {
      const name: string = item.fname.trim();
      const avatar: string = item.avatar.trim();
      if (name.length > 0 && avatar.length > 0) {
        avatarByName.set(name, avatar);
      }
    }
    if (avatarByName.size === 0) { return; }
    let changed: boolean = false;
    const next: RecentForumItem[] = this.forums.map((item: RecentForumItem): RecentForumItem => {
      if (item.avatar.length > 0) { return item; }
      const known: string | undefined = avatarByName.get(item.forumName);
      if (known === undefined) { return item; }
      const copy: RecentForumItem = RecentForumItem.copy(item);
      copy.avatar = known;
      changed = true;
      return copy;
    });
    if (changed) {
      this.forums = next;
    }
  }

  async retryAvatar(context: common.UIAbilityContext, forumName: string): Promise<void> {
    const name: string = forumName.trim();
    if (name.length === 0 || this.disposed || this.retrying.has(name)) { return; }
    const epoch: number = this.readEpoch;
    this.retrying.add(name);
    try {
      forgetCachedForumAvatar(name);
      this.clearAvatar(name);
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (this.disposed || epoch !== this.readEpoch) { return; }
      const knownId: number = getForumAvatarId(name);
      const avatar: string = await this.api.fetchForumAvatar(
        device, authSession.session(), name, knownId, 'recent-retry'
      );
      if (this.disposed || epoch !== this.readEpoch || avatar.length === 0) { return; }
      putForumAvatar(name, avatar, knownId);
      this.applyAvatar(name, avatar);
    } catch (err) {
      hilog.warn(0x0000, 'RecentForumsVM', 'avatar retry %{public}s threw %{public}s',
        name, (err as Error).message);
    } finally {
      this.retrying.delete(name);
    }
  }

  private async resolveAvatars(context: common.UIAbilityContext, epoch: number): Promise<void> {
    const needs: ForumAvatarNeed[] = [];
    for (const item of this.forums) {
      if (item.avatar.length === 0 && item.forumName.length > 0) {
        needs.push(new ForumAvatarNeed(item.forumName, getForumAvatarId(item.forumName)));
      }
    }
    if (needs.length === 0) { return; }
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (this.disposed || epoch !== this.readEpoch) { return; }
      const session = authSession.session();
      const plan: ForumAvatarBackfillPlan = new ForumAvatarBackfillPlan();
      plan.label = 'RecentForumsVM';
      plan.maxFetch = RECENT_FORUMS_MAX;
      plan.stopped = (): boolean => this.disposed || epoch !== this.readEpoch;
      plan.fetch = async (name: string, forumId: number): Promise<string> =>
        this.api.fetchForumAvatar(device, session, name, forumId, 'recent');
      plan.apply = (name: string, _forumId: number, url: string): void => {
        if (!this.disposed && epoch === this.readEpoch) {
          this.applyAvatar(name, url);
        }
      };
      await backfillForumAvatars(needs, plan);
    } catch {
      // 设备指纹或网络异常不影响文字兜底展示
    }
  }

  private applyAvatar(forumName: string, url: string): void {
    if (url.length === 0) { return; }
    let changed: boolean = false;
    const next: RecentForumItem[] = this.forums.map((item: RecentForumItem): RecentForumItem => {
      if (item.forumName !== forumName || item.avatar === url) { return item; }
      const copy: RecentForumItem = RecentForumItem.copy(item);
      copy.avatar = url;
      changed = true;
      return copy;
    });
    if (changed) {
      this.forums = next;
    }
  }

  private clearAvatar(forumName: string): void {
    let changed: boolean = false;
    const next: RecentForumItem[] = this.forums.map((item: RecentForumItem): RecentForumItem => {
      if (item.forumName !== forumName || item.avatar.length === 0) { return item; }
      const copy: RecentForumItem = RecentForumItem.copy(item);
      copy.avatar = '';
      changed = true;
      return copy;
    });
    if (changed) {
      this.forums = next;
    }
  }
}
