import { common } from '@kit.AbilityKit';
import { TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { TailChange, TailItem, TailList, tailChangeError } from '../model/Tails';
import { DeviceIdentity } from '../utils/DeviceIdentity';

function owner(): string {
  return authSession.isLoggedIn() ? `${authSession.snapshot.uid}:${authSession.snapshot.portrait}` : '';
}

@ObservedV2
export class TailsVM {
  @Trace data: TailList = new TailList();
  @Trace loading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace error: string = '';
  @Trace pending: boolean = false;
  @Trace notice: string = '';
  private account: string = '';

  private bduss: string = '';
  private stoken: string = '';
  private epoch: number = 0;
  private disposed: boolean = false;
  private readValid: boolean = false;
  private api: TiebaApi = new TiebaApi();

  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.disposed || ((this.pending || this.loading) && this.sameAccount())) { return; }
    const nextAccount: string = owner();
    const sameAccount: boolean = nextAccount.length > 0 && nextAccount === this.account &&
      this.sameAccount();
    this.readValid = false;
    const keepOld: boolean = sameAccount && this.loaded;
    this.account = nextAccount;
    const session = authSession.session();
    this.bduss = session.bduss ?? ''; this.stoken = session.stoken ?? '';
    this.pending = false;
    const mine: number = ++this.epoch;
    this.error = '';
    this.notice = '';
    this.loaded = keepOld;
    this.loading = false;
    if (!keepOld) { this.data = new TailList(); }
    if (this.account.length === 0) { this.data = new TailList(); this.error = '登录后才能读取小尾巴'; return; }
    this.loading = true;
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!this.current(mine)) { return; }
      const response = await this.api.fetchTails(device, authSession.session());
      if (!this.current(mine)) { return; }
      if (response.ok) { this.readValid = true; this.data = response.data; this.loaded = true; this.error = ''; }
      else { this.error = response.describeFailure(); }
    } catch (err) {
      if (this.current(mine)) { this.error = '小尾巴读取失败，请重试'; }
    } finally {
      if (mine === this.epoch) {
        this.loading = false;
        if (!this.sameAccount()) {

          this.data = new TailList(); this.loaded = false; this.bduss = ''; this.stoken = '';
          this.error = '账号已变化，请重新读取';
        }
      }
    }
  }

  private sameAccount(): boolean {
    const live = authSession.session();
    return this.account.length > 0 && this.account === owner() &&
      this.bduss === (live.bduss ?? '') && this.stoken === (live.stoken ?? '');
  }

  private current(mine: number): boolean {
    return !this.disposed && this.epoch === mine && this.sameAccount();
  }

  async change(context: common.UIAbilityContext, input: TailChange): Promise<void> {
    if (this.disposed || this.loading || this.pending || !this.loaded || !this.readValid || !this.sameAccount() || owner().length === 0) {
      return;
    }
    const error: string = tailChangeError(input);
    if (error.length > 0) { this.error = error; return; }
    if (input.action !== 'add' && !this.data.items.some((item: TailItem) => item.id === input.id)) {
      this.error = '列表中不存在该小尾巴，请重新读取'; return;
    }

    const change: TailChange = new TailChange();
    change.action = input.action; change.id = input.id; change.content = input.content;
    change.fontColor = input.fontColor; change.fontKeyName = input.fontKeyName; change.type = input.type;
    this.pending = true; this.error = ''; this.notice = '';
    const mine: number = ++this.epoch;
    let returnedId: string = '';
    let submitted: boolean = false;
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!this.current(mine)) { return; }
      const session = authSession.session();
      try {
        const write = change.action === 'add'
          ? await this.api.addTail(device, session, change.content, change.fontColor, change.fontKeyName)
          : change.action === 'update'
            ? await this.api.updateTail(device, session, change.id, change.content, change.fontColor, change.fontKeyName)
            : change.action === 'set' ? await this.api.setTail(device, session, change.id, change.type)
              : await this.api.deleteTail(device, session, change.id);
        submitted = write.ok; returnedId = write.id;
      } catch (err) {  }
      if (!this.current(mine)) { return; }
      const read = await this.api.fetchTails(device, authSession.session());
      if (!this.current(mine)) { return; }
      if (!read.ok) {
        this.data = new TailList(); this.loaded = false; this.error = '提交后状态未确认，请重新读取'; return;
      }
      this.data = read.data; this.loaded = true;
      const id: string = change.action === 'add' ? returnedId : String(change.id);
      const item: TailItem | undefined = read.data.items.find((row: TailItem) => String(row.id) === id);
      const matches: boolean = change.action === 'delete' ? item === undefined
        : change.action === 'set' ? item !== undefined && item.selected === change.type
          : item !== undefined && item.content === change.content && item.fontColor === change.fontColor &&
            item.fontKeyName === change.fontKeyName;
      if (matches && (change.action !== 'add' || (submitted && returnedId.length > 0 && returnedId !== '0'))) {
        this.notice = '当前状态已回读确认';
      } else { this.error = '提交结果未确认，请核对当前列表后再操作'; }
    } catch (err) {
      if (this.current(mine)) {
        this.data = new TailList(); this.loaded = false; this.error = '提交结果未确认，请重新读取';
      }
    } finally {
      if (mine === this.epoch) {
        this.pending = false;
        if (!this.sameAccount()) {
          this.data = new TailList(); this.loaded = false; this.notice = ''; this.bduss = ''; this.stoken = '';
          this.error = '账号已变化，请重新读取';
        }
      }
    }
  }

  dispose(): void {
    this.disposed = true; this.epoch++; this.loading = false; this.pending = false;
    this.loaded = false; this.data = new TailList(); this.notice = '';
    this.account = ''; this.bduss = ''; this.stoken = '';
  }
}
