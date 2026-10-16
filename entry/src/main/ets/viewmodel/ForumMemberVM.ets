
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
  /** 该吧的 id（`getMemberInfo` 只认 `forum_id`，不认吧名） */
  @Trace forumId: number = 0;
  @Trace forumName: string = '';
  /**
   * 吧务全量请求失败、页面正在用 `getMemberInfo` 的预览顶着。
   * 这个字段不直接画字（文案由模型的 `previewNote()` 出），只用于将来排查；
   * 保留它是为了**不把失败吞掉**（"我看到的是预览还是全量"必须能从状态里问出来）。
   */
  @Trace teamFallback: boolean = false;
  private api: TiebaApi = new TiebaApi();

  /** 有没有任何可展示的分组（空数组 = 服务端没给组，页面走空态） */
  hasGroups(): boolean {
    return this.groups.length > 0;
  }

  /**
   * 加载（或重试）。`forumId` 缺失时不发请求 —— 宁可显示"拿不到吧身份"，
   * 也不发一个必然失败的请求再报服务端错误。
   */
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
      /*
       * 吧务组在 `getMemberInfo` 里**只有预览**（实测 52 人回 5 个），全量在 `getBawuInfo`。
       * 这里再请求一次拿全量：**它失败不影响页面** —— 失败就继续用预览，并保留
       * "共 N 人，这里显示前 M 位"的说明（宁可如实标注，也不假装拿到了全量）。
       */
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
