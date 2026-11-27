/**
 * 账号全局隐私设置状态：读取 GetPrivateInfo（303016），写入 /c/c/friend/setprivate（不带 tid），
 * 写后强制回读校准真实服务端状态，不乐观假改、不自动重发写请求。
 */
import { common } from '@kit.AbilityKit';
import { TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import {
  AccountPrivacy, AccountPrivacyField, accountPrivacyLabel, validAccountPrivacy
} from '../model/AccountPrivacy';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { accountWithPortrait } from './SessionOwner';

@ObservedV2
export class PrivacySettingsVM {
  @Trace data: AccountPrivacy = new AccountPrivacy();
  @Trace loading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace pending: boolean = false;
  @Trace pendingField: string = '';
  @Trace error: string = '';
  @Trace notice: string = '';

  private account: string = '';
  private epoch: number = 0;
  private disposed: boolean = false;
  private api: TiebaApi = new TiebaApi();

  private current(mine: number): boolean {
    return !this.disposed && mine === this.epoch && this.account === accountWithPortrait();
  }

  fieldValue(field: AccountPrivacyField): number {
    return this.data.fieldValue(field);
  }

  valueLabel(field: AccountPrivacyField): string {
    if (!authSession.snapshot.isLoggedIn()) { return '未登录'; }
    if (this.pending && this.pendingField === field) { return '正在保存…'; }
    if (this.loading && !this.loaded) { return '正在读取…'; }
    return accountPrivacyLabel(field, this.data.fieldValue(field));
  }

  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.disposed || this.pending) { return; }
    const nextAccount: string = accountWithPortrait();
    if (this.loading && this.account === nextAccount) { return; }
    const keepOld: boolean = nextAccount.length > 0 && nextAccount === this.account && this.loaded;
    this.account = nextAccount;
    const mine: number = ++this.epoch;
    this.loaded = keepOld;
    this.error = '';
    this.notice = '';
    this.loading = false;
    if (!keepOld) { this.data = new AccountPrivacy(); }
    if (this.account.length === 0) {
      this.data = new AccountPrivacy();
      return;
    }
    this.loading = true;
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!this.current(mine)) { return; }
      const response = await this.api.fetchAccountPrivacy(device, authSession.session(), authSession.snapshot.uid);
      if (!this.current(mine)) { return; }
      if (response.ok) {
        this.data = response.data;
        this.loaded = true;
        this.error = '';
      } else {
        this.error = response.describeFailure();
      }
    } catch (err) {
      if (this.current(mine)) { this.error = '读取隐私设置失败，请重试'; }
    } finally {
      if (mine === this.epoch) {
        this.loading = false;
        if (this.account !== accountWithPortrait()) {
          this.data = new AccountPrivacy();
          this.loaded = false;
          this.error = '账号已变化，请重新读取';
        }
      }
    }
  }

  /** 提交单项全局隐私修改并回读确认；返回空串表示已确认生效。 */
  async set(context: common.UIAbilityContext, field: AccountPrivacyField, value: number): Promise<string> {
    const currentAccount: string = accountWithPortrait();
    if (this.disposed || this.loading || this.pending) { return ''; }
    if (currentAccount.length === 0 || this.account !== currentAccount || !this.loaded) {
      return '请先等待隐私设置读取完成';
    }
    if (!validAccountPrivacy(field, value)) { return '隐私设置值无效'; }
    const before: number = this.data.fieldValue(field);
    if (before < 0) { return '当前状态未确认，请重新读取'; }
    if (before === value) { return ''; }
    const mine: number = ++this.epoch;
    this.pending = true;
    this.pendingField = field;
    this.error = '';
    this.notice = '';
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!this.current(mine)) { return '账号已变化，未继续操作'; }
      const uid: number = authSession.snapshot.uid;
      let accepted: boolean = false;
      let writeError: string = '提交结果未确认，请重新读取';
      try {
        const write = await this.api.setAccountPrivacy(device, authSession.session(), field, value);
        accepted = write.ok;
        if (!write.ok) { writeError = write.describeFailure(); }
      } catch (err) { /* 异常也可能已在服务端生效，下面仅回读校准，不重发写请求。 */ }
      if (!this.current(mine)) { return '账号已变化，请在原账号确认结果'; }
      const read = await this.api.fetchAccountPrivacy(device, authSession.session(), uid);
      if (!this.current(mine)) { return '账号已变化，请在原账号确认结果'; }
      if (!read.ok) {
        this.data = new AccountPrivacy();
        this.loaded = false;
        this.error = '提交后状态未确认，请重新读取';
        return this.error;
      }
      this.data = read.data;
      this.loaded = true;
      const actual: number = this.data.fieldValue(field);
      if (actual === value) {
        this.notice = '设置已生效';
        return '';
      }
      this.error = accepted ? '读回设置与提交值不一致，请重新读取' : writeError;
      return this.error;
    } catch (err) {
      if (this.current(mine)) {
        this.data = new AccountPrivacy();
        this.loaded = false;
        this.error = '提交结果未确认，请重新读取';
        return this.error;
      }
      return '';
    } finally {
      if (mine === this.epoch) {
        this.pending = false;
        this.pendingField = '';
        if (this.account !== accountWithPortrait()) {
          this.data = new AccountPrivacy();
          this.loaded = false;
          this.notice = '';
          this.error = '账号已变化，请重新读取';
        }
      }
    }
  }

  dispose(): void {
    this.disposed = true;
    this.epoch++;
    this.loading = false;
    this.pending = false;
    this.pendingField = '';
    this.loaded = false;
    this.data = new AccountPrivacy();
  }
}
