import { cachedForumMembership, cachedFollowForums, confirmForumSign, forumReadFresh, readFollowForumsShared, readForumShared, restoreForumCache } from './ForumReadCache';

import { common } from '@kit.AbilityKit';
import { TiebaApi } from '../api/TiebaApi';
import { FollowForumItem } from '../model/FollowForum';
import { TiebaDevice } from '../net/TiebaParams';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { authSession } from '../auth/AuthSession';
import { signStatsLabel } from '../model/SignStats';
import { OfficialSignItem } from '../model/OfficialSign';
import { signStrategyStore } from '../common/appearance/SignStrategyStore';

function signOwner(): string { return authSession.forumCacheSessionKey(); }
class SignAttempt {
  message: string;
  success: boolean;
  constructor(message: string, success: boolean = false) { this.message = message; this.success = success; }
}

interface ExperienceRead {
  item: FollowForumItem;
  epoch: number;
  account: string;
  version: number;
  force: boolean;
}

@ObservedV2
export class FollowVM {
  @Trace loading: boolean = false;
  /** 首次加载完成标记：true 之后切回关注频道不再显示整页加载态 */
  @Trace loadedOnce: boolean = false;
  /** 首屏失败原因；为空串表示无错误 */
  @Trace errorText: string = '';
  /** 关注吧列表（isSigned 变化靠整体替换触发 @Trace） */
  @Trace forums: FollowForumItem[] = [];
  /** 正在签到的吧名（按钮转圈/防连点） */
  @Trace signingFname: string = '';
  /** 一键签到进行中（头部按钮状态/防连点） */
  @Trace signingAll: boolean = false;

  private experienceQueue: ExperienceRead[] = [];
  private experienceRequested: Set<string> = new Set();
  private experienceActive: number = 0;
  private experienceVersions: Map<string, number> = new Map();

  ensureExperience(context: common.UIAbilityContext, item: FollowForumItem, retry: boolean = false): void {
    if (this.disposed || this.loading || this.readAccount !== signOwner()) { return; }
    const version: number = this.experienceVersions.get(item.fname) ?? 0;
    const key: string = `${this.readEpoch}:${item.fname}:${version}`;
    if (this.experienceRequested.has(key)) { return; }
    if (!retry && (forumReadFresh(item.fname) || item.experienceError.length > 0)) { return; }
    this.experienceRequested.add(key);
    this.experienceQueue.push({ item, epoch: this.readEpoch, account: this.readAccount, version, force: retry });
    this.drainExperience(context);
  }

  private drainExperience(context: common.UIAbilityContext): void {
    while (!this.disposed && this.experienceActive < 3 && this.experienceQueue.length > 0) {
      const request: ExperienceRead = this.experienceQueue.shift()!;
      if (!this.currentExperience(request)) { continue; }
      this.experienceActive++;
      void this.readExperience(context, request).finally(() => {
        this.experienceActive--;
        this.experienceRequested.delete(`${request.epoch}:${request.item.fname}:${request.version}`);
        this.drainExperience(context);
      });
    }
  }

  private currentExperience(request: ExperienceRead): boolean {
    return this.currentRead(request.epoch, request.account) &&
      request.version === (this.experienceVersions.get(request.item.fname) ?? 0);
  }

  private async readExperience(context: common.UIAbilityContext, request: ExperienceRead): Promise<void> {
    try {
      if (!this.currentExperience(request)) { return; }
      const response = await readForumShared(context, request.item.fname, request.item.fid, request.force);
      if (!this.currentExperience(request)) { return; }
      const matches: boolean = response.ok && response.data.forum.id === request.item.fid;
      this.forums = this.forums.map((value: FollowForumItem): FollowForumItem => {
        if (value.fname !== request.item.fname || value.fid !== request.item.fid) { return value; }
        const updated: FollowForumItem = FollowForumItem.copy(value);
        updated.experienceError = matches ? '' : (response.ok ? '吧信息不匹配' : response.describeFailure());
        if (matches) {
          const membership = cachedForumMembership(request.item.fname, request.item.fid) ?? response.data.membership;
          if (membership.signed !== undefined) { updated.isSigned = membership.signed; updated.signKnown = true; }
          if (membership.level >= 0) { updated.level = membership.level; }
          updated.levelName = membership.levelName;
          updated.currentScore = membership.currentScore;
          updated.nextScore = membership.nextScore;
          updated.continuousCount = membership.continuousCount;
          updated.totalCount = membership.totalCount;
          if (membership.currentScore < 0) { updated.experienceError = '服务端未返回经验'; }
        }
        return updated;
      });
    } catch (_) {
      if (!this.currentExperience(request)) { return; }
      this.forums = this.forums.map((value: FollowForumItem): FollowForumItem => {
        if (value.fname !== request.item.fname) { return value; }
        const updated: FollowForumItem = FollowForumItem.copy(value); updated.experienceError = '经验读取失败'; return updated;
      });
    }
  }

  private api: TiebaApi = new TiebaApi();
  private disposed: boolean = false;
  private readEpoch: number = 0;
  private readAccount: string = '';
  private currentRead(mine: number, account: string): boolean {
    return !this.disposed && mine === this.readEpoch && account === signOwner();
  }
  dispose(): void {
    this.disposed = true; this.readEpoch++; this.loading = false; this.experienceQueue = [];
    this.forums = []; this.loadedOnce = false; this.errorText = '';
  }

  /**
   * 加载关注吧列表。未登录直接跳过（界面走"去登录"分支）；
   * 已登录但 tbs 缺失时先刷新一次 tbs（启动恢复路径可能没带 tbs）。
   * context 由调用方（组件）传入——VM 不是组件，拿不到 UIContext。
   */
  async load(context: common.UIAbilityContext, force: boolean = false): Promise<void> {
    if (this.disposed) { return; }
    restoreForumCache(context);
    const account: string = signOwner();
    if (account.length === 0) { this.readEpoch++; this.loading = false; this.forums = []; this.loadedOnce = false; return; }
    if (this.loading && this.readAccount === account) { return; }
    if (this.readAccount !== account) { this.forums = []; this.loadedOnce = false; }
    const cached: FollowForumItem[] | undefined = cachedFollowForums();
    if (cached !== undefined) { this.forums = cached; this.loadedOnce = true; }
    this.readAccount = account; const mine: number = ++this.readEpoch;
    this.experienceQueue = [];
    this.loading = true;
    this.errorText = '';
    try {
      if (authSession.session().tbs.length === 0) {
        await authSession.refreshTbs(context);
        if (!this.currentRead(mine, account)) { return; }
      }
      const response = await readFollowForumsShared(context, force);
      if (!this.currentRead(mine, account)) { return; }
      this.forums = cachedFollowForums() ?? response.items;
      this.loadedOnce = true;
    } catch (err) {
      const e: Error = err as Error;
      if (this.currentRead(mine, account)) { this.errorText = `加载失败：${e.message}`; }
    } finally {
      if (mine === this.readEpoch) {
        this.loading = false;
        if (!this.disposed && account !== signOwner()) { this.forums = []; this.loadedOnce = false; this.errorText = '账号已变化，请重新读取'; }
      }
    }
  }

  /**
   * 签到单个吧。**真实写操作**：成功后把该项标记为已签到（整体替换数组触发 @Trace），
   * 并返回给界面的提示语（含奖励经验）。
   */
  async signIn(context: common.UIAbilityContext, item: FollowForumItem): Promise<string> {
    if (this.disposed || this.signingAll) { return ''; }
    return (await this.signOne(context, item)).message;
  }
  private async signOne(context: common.UIAbilityContext, item: FollowForumItem): Promise<SignAttempt> {
    if (this.disposed || this.signingFname.length > 0 || item.isSigned) {
      return new SignAttempt('');
    }
    this.signingFname = item.fname;
    const account: string = signOwner();
    if (account.length === 0) { this.signingFname = ''; return new SignAttempt('请先登录'); }
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (this.disposed) { return new SignAttempt('页面已关闭，签到未继续'); }
      if (account !== signOwner()) { return new SignAttempt('账号已变化，签到已停止'); }
      const response = await this.api.signForum(device, authSession.session(), item.fname);
      if (this.disposed) { return new SignAttempt('页面已关闭，请重新读取签到结果'); }
      if (account !== signOwner()) { return new SignAttempt('账号已变化，签到结果未用于当前账号'); }
      if (!response.ok) {
        return new SignAttempt(response.describeFailure());
      }
      // 成功（含"其实已签过"的 160002）：把该项标记为已签到——
      // forumGuide 的 is_sign 实测可能是过期值，以签到端点的裁决为准
      confirmForumSign(item.fname, response.stats, item.fid);
      const updated: FollowForumItem[] = [];
      for (const f of this.forums) {
        if (f.fname === item.fname) {
          const signed: FollowForumItem = FollowForumItem.copy(f);
          signed.isSigned = true;
          signed.signKnown = true;
          // 写入后重新读取经验，不能用奖励数推算服务端的新等级。
          signed.currentScore = -1; signed.nextScore = -1; signed.experienceError = '';
          if (response.stats.continuousCount >= 0) { signed.continuousCount = response.stats.continuousCount; }
          if (response.stats.totalCount >= 0) { signed.totalCount = response.stats.totalCount; }
          updated.push(signed);
        } else {
          updated.push(f);
        }
      }
      this.experienceVersions.set(item.fname, (this.experienceVersions.get(item.fname) ?? 0) + 1);
      this.forums = updated;
      const signedItem: FollowForumItem | undefined = updated.find((value: FollowForumItem): boolean => value.fname === item.fname);
      if (signedItem) { this.ensureExperience(context, signedItem, true); }
      if (response.alreadySigned) {
        return new SignAttempt('今天已经签过啦', true);
      }
      const summary: string = signStatsLabel(response.stats);
      const message: string = response.bonusPoint.length > 0 ? `签到成功 +${response.bonusPoint} 经验` : '签到成功';
      return new SignAttempt(summary.length > 0 ? `${message} · ${summary}` : message, true);
    } catch (err) {
      const e: Error = err as Error;
      return new SignAttempt(`签到失败：${e.message}`);
    } finally {
      this.signingFname = '';
    }
  }

  /**
   * 一键签到：顺序签掉所有未签的吧（**串行**发请求——写操作并发打服务端容易触发风控，
   * 且每签一个就整体替换数组，界面逐个翻"已签到"，进度可见）。
   * 返回汇总提示语给界面 toast。
   */
  async signInAll(context: common.UIAbilityContext): Promise<string> {
    if (this.disposed || this.signingAll || this.signingFname.length > 0) {
      return '';
    }
    await signStrategyStore.load(context);
    if (this.disposed || this.signingAll || this.signingFname.length > 0) { return ''; }
    const official: boolean = signStrategyStore.strategy === 1;
    if (this.loading) { return '正在读取关注吧，请稍后重试'; }
    this.signingAll = true;
    const account: string = signOwner();
    let successCount: number = 0;
    let failCount: number = 0;
    try {
      // 每次批量写前强制取得完整列表；旧磁盘快照可能只有首屏 50 个吧。
      await this.load(context, true);
      if (this.disposed || account.length === 0 || account !== signOwner()) { return '账号或页面已变化，未开始签到'; }
      if (this.errorText.length > 0) { return '关注吧未完整读取，未开始签到：' + this.errorText; }
      if (this.forums.some((item: FollowForumItem): boolean => !item.signKnown)) {
        return '部分吧的签到状态未确认，未开始签到';
      }
      const targets: FollowForumItem[] = this.forums.filter((f: FollowForumItem): boolean => !f.isSigned);
      if (targets.length === 0) { return '关注的吧今天都已签到'; }
      if (official) { return await this.signOfficial(context, targets, account); }
      for (const target of targets) {
        if (this.disposed) { return `页面已关闭，一键签到已停止；已确认成功 ${successCount} 个`; }
        if (account.length === 0 || account !== signOwner()) { return `账号已变化，一键签到已停止；已确认成功 ${successCount} 个`; }
        // signIn 内部会把该项标成已签到（含 160002"已签过"），下次循环 targets 不受影响
        const attempt: SignAttempt = await this.signOne(context, target);
        if (this.disposed) { return `页面已关闭，一键签到已停止；已确认成功 ${successCount} 个`; }
        if (account !== signOwner()) { return `账号已变化，一键签到已停止；已确认成功 ${successCount} 个`; }
        if (attempt.success) {
          successCount++;
        } else if (attempt.message.length > 0) {
          failCount++;
        }
      }
    } finally {
      this.signingAll = false;
    }
    if (failCount > 0) {
      return `一键签到完成：成功 ${successCount} 个，失败 ${failCount} 个`;
    }
    return `一键签到完成：成功 ${successCount} 个`;
  }

  private async signOfficial(context: common.UIAbilityContext, targets: FollowForumItem[], account: string): Promise<string> {
    let success: number = 0;
    let failed: number = 0;
    const day: number = Math.floor((Date.now() + 28800000) / 86400000);
    const uid: number = authSession.snapshot.uid;
    const summary = (): string => `官方签到：已确认成功 ${success} 个，失败 ${failed} 个，未确认 ${targets.length - success - failed} 个`;
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (this.disposed || account !== signOwner()) { return `${summary()}；账号或页面已变化，已停止`; }
      const capability = await this.api.fetchOfficialSignCapability(device, authSession.session(), uid);
      if (this.disposed || account !== signOwner() || day !== Math.floor((Date.now() + 28800000) / 86400000)) {
        return `${summary()}；账号、页面或日期已变化，已停止，请刷新确认`;
      }
      if (!capability.ok) { return `${capability.describeFailure()}；未发送签到请求`; }
      // 只对官方明确返回且达到门槛的吧提交；不猜测缺失条目，不自动降级为逐个签到。
      const eligible: FollowForumItem[] = targets.filter((target: FollowForumItem): boolean =>
        capability.data.forums.some((forum): boolean => forum.fid === String(target.fid) &&
          (capability.data.canUseAll || forum.level >= capability.data.minimumLevel)));
      const skipped: number = targets.length - eligible.length;
      if (eligible.length === 0) {
        return `官方签到要求吧等级至少 ${capability.data.minimumLevel} 级，当前 ${targets.length} 个未签到吧均未确认满足条件；可改用逐个签到`;
      }
      const suffix: string = skipped > 0 ? `；另 ${skipped} 个未满足或未确认官方条件，可改用逐个签到` : '';
      for (let start: number = 0; start < eligible.length; start += 50) {
        if (this.disposed || account !== signOwner() || day !== Math.floor((Date.now() + 28800000) / 86400000)) {
          return `${summary()}；账号、页面或日期已变化，已停止，请刷新确认`;
        }
        const batch: FollowForumItem[] = eligible.slice(start, start + 50);
        const response = await this.api.signForumsOfficial(device, authSession.session(), uid,
          batch.map((item: FollowForumItem): number => item.fid));
        if (this.disposed || account !== signOwner() || day !== Math.floor((Date.now() + 28800000) / 86400000)) {
          return `${summary()}；账号、页面或日期已变化，已停止，请刷新确认`;
        }
        if (!response.ok) { return `${summary()}；${response.describeFailure()}，已停止，请刷新确认`; }
        for (const target of batch) {
          const item: OfficialSignItem | undefined = response.data.items.find((value: OfficialSignItem): boolean => value.fid === String(target.fid));
          if (!item || !item.confirmed) { continue; }
          if (!item.signed) { failed++; continue; }
          success++;
          confirmForumSign(target.fname, item.stats, target.fid);
          this.experienceVersions.set(target.fname, (this.experienceVersions.get(target.fname) ?? 0) + 1);
          this.forums = this.forums.map((value: FollowForumItem): FollowForumItem => {
            if (value.fid !== target.fid) { return value; }
            const updated: FollowForumItem = FollowForumItem.copy(value);
            updated.isSigned = true; updated.signKnown = true;
            updated.currentScore = -1; updated.nextScore = -1; updated.experienceError = '';
            if (item.stats.continuousCount >= 0) { updated.continuousCount = item.stats.continuousCount; }
            return updated;
          });
          const updated: FollowForumItem | undefined = this.forums.find((value: FollowForumItem): boolean => value.fid === target.fid);
          if (updated) { this.ensureExperience(context, updated, true); }
        }
        // 缺项、重复项或不明确的结果不能重试写入或被当作失败/成功；留给用户刷新核对。
        if (success + failed < start + batch.length) { return `${summary()}；部分结果不完整，已停止，请刷新确认`; }
      }
      return summary() + suffix;
    } catch (_) { return `${summary()}；请求异常，已停止，请刷新确认`; }
  }
}
