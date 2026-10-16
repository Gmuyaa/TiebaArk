import { common } from '@kit.AbilityKit';
import { TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { PrivacyMarkField, PrivacyMarks, validPrivacyMark } from '../model/PrivacyMarks';
import { DeviceIdentity } from '../utils/DeviceIdentity';

function owner(): string {
  return authSession.isLoggedIn() ? `${authSession.snapshot.uid}:${authSession.snapshot.portrait}` : '';
}

@ObservedV2
export class PrivacyMarksVM {
  @Trace data: PrivacyMarks = new PrivacyMarks();
  @Trace loading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace error: string = '';
  @Trace pending: boolean = false;
  @Trace notice: string = '';
  private account: string = '';
  private epoch: number = 0;
  private disposed: boolean = false;
  private readValid: boolean = false;
  private api: TiebaApi = new TiebaApi();

  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.disposed || this.pending || (this.loading && this.account === owner())) { return; }
    const nextAccount: string = owner();
    this.readValid = false;
    const keepOld: boolean = nextAccount.length > 0 && nextAccount === this.account && this.loaded;
    this.account = nextAccount;
    const mine: number = ++this.epoch;
    this.loaded = keepOld; this.error = ''; this.notice = ''; this.loading = false;
    if (!keepOld) { this.data = new PrivacyMarks(); }
    if (this.account.length === 0) { this.data = new PrivacyMarks(); this.error = '登录后才能读取隐私标记'; return; }
    this.loading = true;
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!this.current(mine)) { return; }
      const response = await this.api.fetchPrivacyMarks(device, authSession.session(), authSession.snapshot.uid);
      if (!this.current(mine)) { return; }
      if (response.ok) { this.readValid = true; this.data = response.data; this.loaded = true; this.error = ''; }
      else { this.error = response.describeFailure(); }
    } catch (err) {
      if (this.current(mine)) { this.error = '隐私标记读取失败，请重试'; }
    } finally {
      if (mine === this.epoch) {
        this.loading = false;
        if (this.account !== owner()) {

          this.data = new PrivacyMarks(); this.loaded = false; this.error = '账号已变化，请重新读取';
        }
      }
    }
  }

  private current(mine: number): boolean { return !this.disposed && mine === this.epoch && this.account === owner(); }

  async set(context: common.UIAbilityContext, field: PrivacyMarkField, value: number): Promise<void> {
    if (this.disposed || this.loading || this.pending || !this.loaded || !this.readValid || this.account !== owner() || owner().length === 0 ||
      !validPrivacyMark(field, value)) { return; }
    const before: number = field === 'bazhu_show_inside' ? this.data.inside : this.data.outside;
    if ((before !== 1 && before !== 3) || before === value) { return; }
    const mine: number = ++this.epoch;
    this.pending = true; this.error = ''; this.notice = '';
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!this.current(mine)) { return; }
      const uid: number = authSession.snapshot.uid;
      try { await this.api.setPrivacyMark(device, authSession.session(), field, value); }
      catch (err) {  }
      if (!this.current(mine)) { return; }
      const read = await this.api.fetchPrivacyMarks(device, authSession.session(), uid);
      if (!this.current(mine)) { return; }
      if (!read.ok) {
        this.data = new PrivacyMarks(); this.loaded = false; this.error = '提交后状态未确认，请重新读取'; return;
      }
      this.data = read.data; this.loaded = true;
      const actual: number = field === 'bazhu_show_inside' ? this.data.inside : this.data.outside;
      if (actual === value) { this.notice = '当前状态已回读确认'; }
      else { this.error = '当前状态与请求不一致，请重新读取'; }
    } catch (err) {
      if (this.current(mine)) {
        this.data = new PrivacyMarks(); this.loaded = false; this.error = '提交后状态未确认，请重新读取';
      }
    } finally {
      if (mine === this.epoch) {
        this.pending = false;
        if (this.account !== owner()) {
          this.data = new PrivacyMarks(); this.loaded = false; this.notice = ''; this.error = '账号已变化，请重新读取';
        }
      }
    }
  }
  dispose(): void { this.disposed = true; this.epoch++; this.loading = false; this.pending = false; this.loaded = false; this.data = new PrivacyMarks(); }
}
