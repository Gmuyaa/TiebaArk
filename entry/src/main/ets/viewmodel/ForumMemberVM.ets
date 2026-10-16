
import { common } from '@kit.AbilityKit';
import { BawuTeamResponse, ForumMemberResponse, TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { BawuTeamResult, composeMemberGroups, ForumMemberGroup } from '../model/ForumMember';
import { DeviceIdentity } from '../utils/DeviceIdentity';

@ObservedV2
export class ForumMemberVM {
  @Trace groups: ForumMemberGroup[] = [];
  @Trace loading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace error: string = '';

  @Trace forumId: number = 0;
  @Trace forumName: string = '';

  @Trace teamFallback: boolean = false;
  private api: TiebaApi = new TiebaApi();

  hasGroups(): boolean {
    return this.groups.length > 0;
  }

  async load(context: common.UIAbilityContext, forumId: number, forumName: string): Promise<void> {
    if (this.loading) { return; }
    this.forumName = forumName;
    if (!Number.isSafeInteger(forumId) || forumId <= 0) {
      this.forumId = 0;
      this.error = '拿不到这个吧的 id，暂时无法查看吧成员';
      this.loaded = true;
      return;
    }
    this.forumId = forumId;
    this.loading = true;
    this.error = '';
    try {
      const device = await DeviceIdentity.ensure(context);
      const response: ForumMemberResponse = await this.api.fetchForumMembers(
        device, authSession.session(), forumId);
      if (!response.ok) {
        this.error = response.describeFailure();
        return;
      }

      this.teamFallback = false;
      const team: BawuTeamResponse = await this.api.fetchBawuTeam(device, authSession.session(), forumId);
      if (team.ok) {
        const result: BawuTeamResult = new BawuTeamResult();
        result.code = 0;
        result.total = team.total;
        result.roles = team.roles;
        this.groups = composeMemberGroups(response.groups, result);
      } else {
        this.teamFallback = true;
        this.groups = response.groups;
      }
    } catch (err) {
      this.error = '加载失败，请重试';
    } finally {
      this.loading = false;
      this.loaded = true;
    }
  }
}
