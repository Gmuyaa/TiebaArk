import { cachedForumId, restoreForumCache } from './ForumReadCache';
import { common } from '@kit.AbilityKit';
import { TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { ForumIdentity, ensureForumIdentity, forumIdentity, forumSignDay, registerForumAlias, signForum,
  toggleForumFollow } from './ForumStateStore';

function ownerKey(): string {
  return authSession.forumCacheSessionKey();
}

/**
 * 吧头：简介与公开计数属于本页，关注关系/今日签到/等级经验只读 `ForumStateStore`。
 *
 * 2026-11-13（1.0.268）：不再自己维护"已关注的关注态"和"今天的签到态"，也不再单独发
 * rn=1 的首页请求——那些状态由吧页首包与关注吧列表回填到身份实例上，本 VM 只做转发与
 * 按钮文案。页面实例重建（返回再进）不会再触发重复读取。
 */
@ObservedV2
export class ForumHeaderVM {
  @Trace identity: ForumIdentity = new ForumIdentity();
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
  private disposed: boolean = false;

  async initialize(context: common.UIAbilityContext, id: number, name: string): Promise<void> {
    restoreForumCache(context);
    id = id > 0 ? id : cachedForumId(name);
    const owner: string = ownerKey();
    if (!this.disposed && id === this.forumId && name === this.forumName && owner === this.owner) {
      await this.ensureMembership(context);
      return;
    }
    ++this.introductionSequence;
    this.disposed = false;
    this.forumId = id;
    this.forumName = name;
    this.owner = owner;
    this.introduction = '';
    this.introductionError = '';
    this.introductionLoading = false;
    this.publicMemberCount = -1;
    this.publicThreadCount = -1;
    this.introductionLoaded = false;
    // 身份实例跨页面存活：同一账号同一个吧再进时直接复用已确认的关注/签到态。
    this.identity = forumIdentity(id, name);
    if (id <= 0 || name.length === 0) { return; }
    registerForumAlias(id, name);
    await this.ensureMembership(context);
  }

  dispose(): void {
    this.disposed = true;
    ++this.introductionSequence;
    this.introductionLoading = false;
  }

  /** 简介是公共资料，未登录也可读取；切吧、切账号和销毁后的响应不得回填。 */
  async ensureIntroduction(context: common.UIAbilityContext, retry: boolean = false): Promise<void> {
    if (this.disposed || this.forumId <= 0 || this.owner !== ownerKey() ||
      !this.followKnown() ||
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

  /** 首次只在已确认关注后读取；关注写请求中的乐观状态不会触发签到。 */
  async ensureMembership(context: common.UIAbilityContext, retry: boolean = false): Promise<void> {
    if (this.disposed || this.owner !== ownerKey() || this.forumId <= 0) { return; }
    await ensureForumIdentity(context, this.forumId, this.forumName, retry);
  }

  followKnown(): boolean { return this.identity.known(); }
  follows(): boolean { return this.identity.follows(); }
  followPending(): boolean { return this.identity.pending; }

  /** 只有已确认关注才切换为签到；关注提交中的乐观值仍属于关注操作。 */
  buttonIsSign(): boolean {
    return this.identity.known() && this.identity.follows() && !this.identity.pending;
  }

  buttonBusy(): boolean {
    return this.identity.reading || this.identity.signing || this.identity.pending ||
      (this.identity.verifying && !this.identity.known());
  }

  /** 完成外观只使用今日已确认的签到状态，跨日旧缓存不能显示为已签到。 */
  buttonCompleted(): boolean {
    return this.identity.completed(forumSignDay());
  }

  /** 进行中只由按钮内的转圈表示，文案保持状态本身（2026-11-13 持有者要求去掉「…中…」字样）。 */
  buttonLabel(): string {
    const value: ForumIdentity = this.identity;
    if (!value.known()) { return '重试'; }
    if (value.pending) { return value.follows() ? '已关注' : '关注'; }
    if (!value.follows()) { return '关注'; }
    if (!value.signKnown(forumSignDay())) { return '重试'; }
    return value.signed === true ? '已签到' : '签到';
  }

  async activate(context: common.UIAbilityContext): Promise<string> {
    if (this.disposed || this.owner !== ownerKey()) { return ''; }
    const value: ForumIdentity = this.identity;
    if (value.pending || value.reading || value.signing ||
      (value.verifying && !value.known())) { return ''; }
    if (!value.known() || !value.follows()) {
      const message: string = await toggleForumFollow(context, this.forumId, this.forumName);
      if (!value.known()) { await this.ensureMembership(context); }
      return message;
    }
    const day: string = forumSignDay();
    if (!value.signKnown(day)) {
      await ensureForumIdentity(context, this.forumId, this.forumName, true);
      return value.error;
    }
    if (value.signed === true) { return '今天已经签过啦'; }
    return await signForum(context, this.forumId, this.forumName);
  }
}
