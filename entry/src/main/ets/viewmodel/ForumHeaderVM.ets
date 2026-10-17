import { cachedForumId, cachedForumFollow, cachedForumMembership, confirmForumSign, forumReadFresh, readForumShared, readFollowForumsShared, restoreForumCache } from './ForumReadCache';
import { common } from '@kit.AbilityKit';
import { TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { ForumMembership } from '../model/ThreadList';
import { FollowForumItem, FollowForumList } from '../model/FollowForum';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { followAction, FollowActionVM } from './FollowActionVM';
import { hilog } from '@kit.PerformanceAnalysisKit';

function ownerKey(): string {
  return authSession.forumCacheSessionKey();
}
/** 贴吧签到按北京时间换日，不能复用昨天的已签到状态。 */
export function forumSignDay(): string {
  return new Date(Date.now() + 8 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

@ObservedV2
export class ForumHeaderVM {
  @Trace follow: FollowActionVM = new FollowActionVM('forum', 0, '', '');
  @Trace membership: ForumMembership = new ForumMembership();
  @Trace reading: boolean = false;
  @Trace signing: boolean = false;
  @Trace errorText: string = '';
  @Trace introduction: string = '';
  @Trace introductionError: string = '';
  @Trace introductionLoading: boolean = false;
  @Trace publicMemberCount: number = -1;
  @Trace publicThreadCount: number = -1;
  private introductionSequence: number = 0;
  private introductionLoaded: boolean = false;
  private api: TiebaApi = new TiebaApi();
  private forumId: number = 0;
  private forumName: string = '';
  private owner: string = '';
  private sequence: number = 0;
  private readDay: string = '';
  private confirmedDay: string = '';
  private disposed: boolean = false;

  async initialize(context: common.UIAbilityContext, id: number, name: string): Promise<void> {
    restoreForumCache(context);
    id = id > 0 ? id : cachedForumId(name);
    const owner: string = ownerKey();
    if (!this.disposed && id === this.forumId && name === this.forumName && owner === this.owner) {
      await this.ensureMembership(context);
      return;
    }
    ++this.sequence;
    ++this.introductionSequence;
    this.disposed = false;
    this.forumId = id;
    this.forumName = name;
    this.owner = owner;
    this.readDay = '';
    this.confirmedDay = '';
    this.membership = new ForumMembership();
    this.reading = false;
    this.signing = false;
    this.errorText = '';
    this.introduction = '';
    this.introductionError = '';
    this.introductionLoading = false;
    this.publicMemberCount = -1;
    this.publicThreadCount = -1;
    this.introductionLoaded = false;
    this.follow = followAction('forum', id, '', name);
    if (id <= 0 || name.length === 0) { return; }
    const cached = cachedForumMembership(name, id);
    if (cached !== undefined) {
      this.membership = cached;
      if (cached.signed !== undefined) { this.readDay = forumSignDay(); }
    }
    const following = cachedForumFollow(name, id);
    if (following !== undefined && !this.follow.known) { this.follow.acceptRead(following); }
    await this.follow.load(context);
    if (owner !== this.owner || owner !== ownerKey() || this.disposed) { return; }
    await this.ensureMembership(context);
  }

  dispose(): void {
    this.disposed = true;
    ++this.sequence;
    ++this.introductionSequence;
    this.reading = false;
    this.signing = false;
    this.introductionLoading = false;
  }

  /** 简介是公共资料，未登录也可读取；切吧、切账号和销毁后的响应不得回填。 */
  async ensureIntroduction(context: common.UIAbilityContext, retry: boolean = false): Promise<void> {
    if (this.disposed || this.forumId <= 0 || this.owner !== ownerKey() ||
      !this.follow.known || (this.follow.following && !this.follow.pending) ||
      this.introductionLoading || (this.introductionLoaded && !retry)) { return; }
    const sequence: number = ++this.introductionSequence;
    const id: number = this.forumId;
    this.introductionLoading = true;
    this.introductionError = '';
    try {
      const device = await DeviceIdentity.ensure(context);
      if (this.disposed || sequence !== this.introductionSequence || this.owner !== ownerKey()) { return; }
      const response = await this.api.fetchDirectory(device, authSession.session(), 'forum', id, 1);
      if (this.disposed || sequence !== this.introductionSequence || this.owner !== ownerKey()) { return; }
      if (!response.ok || response.data.forum.id !== id) {
        this.introductionError = response.ok ? '吧简介信息不匹配，点击重试' : '吧简介读取失败，点击重试';
        return;
      }
      this.introduction = response.data.forum.description;
      this.publicMemberCount = response.data.forum.members;
      this.publicThreadCount = response.data.forum.threads;
      this.introductionLoaded = true;
    } catch (err) {
      if (!this.disposed && sequence === this.introductionSequence && this.owner === ownerKey()) {
        this.introductionError = '吧简介读取失败，点击重试';
      }
    } finally {
      if (sequence === this.introductionSequence) { this.introductionLoading = false; }
    }
  }

  private current(sequence: number, day: string): boolean {
    return !this.disposed && sequence === this.sequence && this.owner.length > 0 &&
      this.owner === ownerKey() && day === forumSignDay() && this.follow.known && this.follow.following;
  }

  /** 首次只在已确认关注后读取；关注写请求中的乐观状态不会触发签到。 */
  async ensureMembership(context: common.UIAbilityContext, retry: boolean = false): Promise<void> {
    if (this.disposed || this.owner.length === 0 || this.owner !== ownerKey() || this.forumId <= 0 ||
      !this.follow.known || !this.follow.following || this.follow.pending || this.reading || this.signing) { return; }
    const day: string = forumSignDay();
    const cached = cachedForumMembership(this.forumName, this.forumId);
    if (cached !== undefined) { this.membership = cached; }
    if (!retry && forumReadFresh(this.forumName) && cached?.signed !== undefined) {
      this.readDay = day; return;
    }
    if (!retry && this.readDay === day && this.errorText.length > 0) { return; }
    if (this.readDay.length > 0 && this.readDay !== day) { this.membership.signed = undefined; }
    const sequence: number = ++this.sequence;
    this.reading = true;
    this.errorText = '';
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!this.current(sequence, day)) { return; }
      const response = await readForumShared(context, this.forumName, this.forumId, retry);
      if (!this.current(sequence, day)) { return; }
      if (!response.ok || response.data.forum.id !== this.forumId) {
        this.errorText = response.ok ? '吧信息不匹配，请重试' : response.describeFailure();
        this.readDay = day;
        return;
      }
      if (response.data.forum.followed !== undefined) { this.follow.acceptRead(response.data.forum.followed); }
      if (!this.follow.following) { return; }
      const membership: ForumMembership = cachedForumMembership(this.forumName, this.forumId) ?? response.data.membership;
      // FRS JSON 有时省略签到段，复用已验证的 forumGuide 只读链路。
      if (membership.signed === undefined || (retry && response.data.membership.signed === undefined)) {
        if (authSession.session().tbs.length === 0) {
          const result = await authSession.refreshTbs(context);
          if (!this.current(sequence, day)) { return; }
          if (!result.ok) {
            this.membership = membership;
            this.errorText = result.message;
            this.readDay = day;
            return;
          }
        }
        const seen: Set<number> = new Set<number>();
        for (let page: number = 1; page <= 10; page++) {
          let guide: FollowForumList;
          if (page === 1) { guide = await readFollowForumsShared(context, retry); }
          else {
            const response = await this.api.fetchFollowForums(authSession.session(), page, 50);
            if (!this.current(sequence, day)) { return; }
            if (!response.ok) { this.errorText = response.describeFailure(); break; }
            guide = response.data;
          }
          if (!this.current(sequence, day)) { return; }
          const item: FollowForumItem | undefined = guide.items.find((value: FollowForumItem): boolean =>
            value.fid === this.forumId);
          if (item !== undefined) {
            if (membership.level < 0 && item.level > 0) { membership.level = item.level; }
            if (item.signKnown) { membership.signed = item.isSigned; }
            if (item.continuousCount >= 0) { membership.continuousCount = item.continuousCount; }
            if (item.totalCount >= 0) { membership.totalCount = item.totalCount; }
            break;
          }
          const before: number = seen.size;
          for (const value of guide.items) { seen.add(value.fid); }
          if (!guide.hasMore || seen.size === before) { break; }
        }
      }
      // 本次签到的业务成功优先于 forumGuide 可能过期的 is_sign。
      if (this.confirmedDay === day) { membership.signed = true; }
      this.membership = membership;
      this.readDay = day;
      hilog.info(0x0000, 'ForegroundRefresh', 'forum state applied sign=%{public}d',
        membership.signed === undefined ? -1 : (membership.signed ? 1 : 0));
      if (membership.signed === undefined && this.errorText.length === 0) {
        this.errorText = '签到状态暂未获取，请重试';
      }
    } catch (err) {
      if (this.current(sequence, day)) {
        this.errorText = '吧等级和签到状态读取失败，请重试';
        this.readDay = day;
      }
    } finally {
      if (sequence === this.sequence) { this.reading = false; }
    }
  }

  buttonLabel(): string {
    if (this.follow.pending) { return '关注'; }
    if ((this.follow.loading && !this.follow.known) || (this.reading && this.membership.signed === undefined)) { return '读取中…'; }
    if (this.follow.verifying && !this.follow.known) { return '核对中…'; }
    if (!this.follow.known) { return '重试关注状态'; }
    if (!this.follow.following) { return '关注'; }
    if (this.signing) { return '签到中…'; }
    if (this.readDay !== forumSignDay() || this.membership.signed === undefined) { return '重试签到状态'; }
    return this.membership.signed ? '已签到' :
      (this.membership.missedDays > 0 ? `漏签${this.membership.missedDays}天` : '签到');
  }

  async activate(context: common.UIAbilityContext): Promise<string> {
    if (this.disposed || this.owner !== ownerKey() || this.follow.pending || this.follow.loading ||
      this.reading || this.signing) { return ''; }
    if (this.follow.verifying && !this.follow.known) { return ''; }
    if (!this.follow.known || !this.follow.following) {
      const message: string = await this.follow.toggle(context);
      await this.ensureMembership(context);
      return message;
    }
    if (this.readDay !== forumSignDay() || this.membership.signed === undefined) {
      await this.ensureMembership(context, true);
      return this.errorText;
    }
    if (this.membership.signed) { return '今天已经签过啦'; }
    const sequence: number = ++this.sequence;
    const day: string = forumSignDay();
    this.signing = true;
    try {
      if (authSession.session().tbs.length === 0) {
        const result = await authSession.refreshTbs(context);
        if (!this.current(sequence, day)) { return ''; }
        if (!result.ok) { return result.message; }
      }
      const device = await DeviceIdentity.ensure(context);
      if (!this.current(sequence, day)) { return ''; }
      const response = await this.api.signForum(device, authSession.session(), this.forumName);
      if (!this.current(sequence, day)) { return ''; }
      if (!response.ok) { return response.describeFailure(); }
      confirmForumSign(this.forumName, response.stats, this.forumId);
      this.confirmedDay = day;
      const membership: ForumMembership = new ForumMembership();
      membership.level = this.membership.level;
      membership.levelName = this.membership.levelName;
      membership.currentScore = this.membership.currentScore;
      membership.nextScore = this.membership.nextScore;
      membership.missedDays = this.membership.missedDays;
      membership.continuousCount = response.stats.continuousCount >= 0 ?
        response.stats.continuousCount : this.membership.continuousCount;
      membership.totalCount = response.stats.totalCount >= 0 ?
        response.stats.totalCount : this.membership.totalCount;
      membership.signed = true;
      this.membership = membership;
      this.readDay = day;
      this.errorText = '';
      return response.alreadySigned ? '今天已经签过啦' :
        (response.bonusPoint.length > 0 ? `签到成功 +${response.bonusPoint} 经验` : '签到成功');
    } catch (err) {
      return this.current(sequence, day) ? '签到失败，请重试' : '';
    } finally {
      if (sequence === this.sequence) { this.signing = false; }
    }
  }
}
