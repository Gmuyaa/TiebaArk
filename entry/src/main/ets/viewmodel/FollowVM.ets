import { cachedForumMembership, cachedFollowForums, confirmForumSign, forumReadFresh, readFollowForumsShared, readForumShared, restoreForumCache } from './ForumReadCache';

import { common } from '@kit.AbilityKit';
import { TiebaApi } from '../api/TiebaApi';
import { FollowForumItem } from '../model/FollowForum';
import { TiebaDevice } from '../net/TiebaParams';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { authSession } from '../auth/AuthSession';
import { signStatsLabel } from '../model/SignStats';
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

  @Trace loadedOnce: boolean = false;

  @Trace errorText: string = '';

  @Trace forums: FollowForumItem[] = [];

  @Trace signingFname: string = '';

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

      confirmForumSign(item.fname);
      const updated: FollowForumItem[] = [];
      for (const f of this.forums) {
        if (f.fname === item.fname) {
          const signed: FollowForumItem = FollowForumItem.copy(f);
          signed.isSigned = true;
          signed.signKnown = true;

          signed.currentScore = -1; signed.nextScore = -1; signed.experienceError = '';
          signed.continuousCount = response.stats.continuousCount;
          signed.totalCount = response.stats.totalCount;
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

  async signInAll(context: common.UIAbilityContext): Promise<string> {
    if (this.disposed || this.signingAll || this.signingFname.length > 0) {
      return '';
    }
    await signStrategyStore.load(context);
    if (this.disposed || this.signingAll || this.signingFname.length > 0) { return ''; }
    if (signStrategyStore.strategy === 1) {
      return '官方签到暂不可用：批量接口尚未验证，未发送签到请求';
    }
    if (this.loading) { return '正在读取关注吧，请稍后重试'; }
    this.signingAll = true;
    const account: string = signOwner();
    let successCount: number = 0;
    let failCount: number = 0;
    try {

      await this.load(context, true);
      if (this.disposed || account.length === 0 || account !== signOwner()) { return '账号或页面已变化，未开始签到'; }
      if (this.errorText.length > 0) { return '关注吧未完整读取，未开始签到：' + this.errorText; }
      if (this.forums.some((item: FollowForumItem): boolean => !item.signKnown)) {
        return '部分吧的签到状态未确认，未开始签到';
      }
      const targets: FollowForumItem[] = this.forums.filter((f: FollowForumItem): boolean => !f.isSigned);
      if (targets.length === 0) { return '关注的吧今天都已签到'; }
      for (const target of targets) {
        if (this.disposed) { return `页面已关闭，一键签到已停止；已确认成功 ${successCount} 个`; }
        if (account.length === 0 || account !== signOwner()) { return `账号已变化，一键签到已停止；已确认成功 ${successCount} 个`; }

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
}
