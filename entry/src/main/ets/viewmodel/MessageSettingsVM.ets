import { common } from '@kit.AbilityKit';
import { TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { MessageSettingField, MessageSettings, validMessageSetting } from '../model/MessageSettings';
import { DeviceIdentity } from '../utils/DeviceIdentity';

function owner(): string {
  return authSession.isLoggedIn() ? `${authSession.snapshot.uid}:${authSession.snapshot.portrait}` : '';
}

@ObservedV2
export class MessageSettingsVM {
  @Trace data: MessageSettings = new MessageSettings();
  @Trace loading: boolean = false;
  @Trace pending: boolean = false;
  @Trace error: string = '';
  @Trace notice: string = '';
  private epoch: number = 0;
  private disposed: boolean = false;
  private account: string = owner();
  private api: TiebaApi = new TiebaApi();

  private current(mine: number): boolean {
    return !this.disposed && mine === this.epoch && this.account === owner();
  }

  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.loading || this.pending || this.disposed) { return; }
    const nextAccount: string = owner();

    const keepOld: boolean = nextAccount.length > 0 && nextAccount === this.account && this.data.maskType >= 0;
    this.account = nextAccount;
    this.error = '';
    this.notice = '';
    if (!keepOld) { this.data = new MessageSettings(); }
    if (this.account.length === 0) { this.data = new MessageSettings(); this.error = '登录后才能读取消息设置'; return; }
    const mine: number = ++this.epoch;
    this.loading = true;
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!this.current(mine)) { return; }
      const response = await this.api.fetchMessageSettings(device, authSession.session());
      if (!this.current(mine)) { return; }
      if (response.ok) { this.data = response.data; this.error = ''; }
      else { this.error = response.describeFailure(); }
    } catch (err) {
      if (this.current(mine)) { this.error = '读取消息设置失败，请重试'; }
    } finally {
      if (mine === this.epoch) { this.loading = false; }
      if (this.account !== owner()) { this.data = new MessageSettings(); this.error = '账号已变化，请重新读取'; }
    }
  }

  async set(context: common.UIAbilityContext, field: MessageSettingField, value: number): Promise<void> {
    if (this.pending || this.loading || this.disposed || this.account !== owner() || owner().length === 0) { return; }
    const before: number = field === 'maskType' ? this.data.maskType : this.data.pushType;
    if (!validMessageSetting(field, value) || before < 0 || before === value) { return; }
    this.pending = true;
    this.error = '';
    this.notice = '';
    const mine: number = ++this.epoch;
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!this.current(mine)) { return; }
      let accepted: boolean = false;
      let writeError: string = '提交结果未确认，请重新读取';
      try {
        const write = await this.api.setMessageSetting(device, authSession.session(), field, value);
        accepted = write.ok;
        if (!write.ok) { writeError = write.describeFailure(); }
      } catch (err) {  }
      if (!this.current(mine)) { return; }

      const read = await this.api.fetchMessageSettings(device, authSession.session());
      if (!this.current(mine)) { return; }
      if (!read.ok) {
        this.data = new MessageSettings();
        this.error = '提交后状态未确认，请重新读取';
        return;
      }
      this.data = read.data;
      const actual: number = field === 'maskType' ? this.data.maskType : this.data.pushType;
      if (actual === value) { this.notice = '设置已读回确认'; }
      else { this.error = accepted ? '读回设置与提交值不一致，请重新读取' : writeError; }
    } catch (err) {
      if (this.current(mine)) {
        this.data = new MessageSettings();
        this.error = '提交结果未确认，请重新读取';
      }
    } finally {
      if (mine === this.epoch) { this.pending = false; }
      if (this.account !== owner()) { this.data = new MessageSettings(); }
    }
  }

  dispose(): void {
    this.disposed = true;
    this.epoch++;
    this.loading = false;
    this.pending = false;
    this.data = new MessageSettings();
  }
}
