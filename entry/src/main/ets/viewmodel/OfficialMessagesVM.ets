import { common } from '@kit.AbilityKit';
import { authSession } from '../auth/AuthSession';
import { TiebaApi } from '../api/TiebaApi';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { OfficialMessageSetting } from '../model/OfficialMessages';
function owner(): string {
  return authSession.isLoggedIn() ? `${authSession.snapshot.uid}:${authSession.snapshot.portrait}` : '';
}
@ObservedV2
export class OfficialMessagesVM {
  @Trace items: OfficialMessageSetting[] = [];
  @Trace loading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace error: string = '';
  private account: string = '';
  private epoch: number = 0;
  private disposed: boolean = false;
  private api: TiebaApi = new TiebaApi();
  private current(mine: number): boolean { return !this.disposed && mine === this.epoch && this.account === owner(); }

  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.disposed || (this.loading && this.account === owner())) { return; }
    const nextAccount: string = owner();
    const sameAccount: boolean = nextAccount.length > 0 && nextAccount === this.account;
    const keepOld: boolean = sameAccount && this.loaded;   // 只有同账号刷新才保留旧内容
    this.account = nextAccount; const mine: number = ++this.epoch;
    this.loaded = keepOld; this.error = ''; this.loading = false;
    if (!keepOld) { this.items = []; }
    if (this.account.length === 0) { this.items = []; this.error = '登录后才能读取官方消息设置'; return; }
    this.loading = true;
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!this.current(mine)) { return; }
      const response = await this.api.fetchOfficialMessages(device, authSession.session());
      if (!this.current(mine)) { return; }
      if (response.ok) { this.items = response.data.items; this.loaded = true; this.error = ''; }
      else { this.error = response.describeFailure(); }   // 失败：保留旧列表
    } catch (err) { if (this.current(mine)) { this.error = '官方消息设置读取失败，请重试'; } }
    finally {
      if (mine === this.epoch) {
        this.loading = false;
        if (!this.disposed && this.account !== owner()) {
          // 账号已变化：立即清空旧账号的数据与状态
          this.items = []; this.loaded = false; this.error = '账号已变化，请重新读取';
        }
      }
    }
  }
  dispose(): void { this.disposed = true; this.epoch++; this.items = []; this.loaded = false; this.loading = false; }
}
