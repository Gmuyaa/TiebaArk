import { common } from '@kit.AbilityKit';
import { TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { AtCandidate, AtCandidateKind, validAtKind, prepareAtMention } from '../model/AtCandidates';
import { DeviceIdentity } from '../utils/DeviceIdentity';

function owner(): string {
  return authSession.isLoggedIn() ? `${authSession.snapshot.uid}:${authSession.snapshot.portrait}` : '';
}
@ObservedV2
export class AtCandidatesVM {
  @Trace items: AtCandidate[] = [];
  @Trace selected: AtCandidate[] = [];
  @Trace loading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace error: string = '';
  @Trace kind: AtCandidateKind = 'search';
  @Trace word: string = '';
  private account: string = '';
  private bduss: string = '';
  private stoken: string = '';
  private epoch: number = 0;
  private disposed: boolean = false;
  private api: TiebaApi = new TiebaApi();

  async load(context: common.UIAbilityContext, kind: AtCandidateKind, word: string = ''): Promise<void> {
    if (this.disposed || !validAtKind(kind)) { return; }
    const query: string = word.trim();
    if (this.loading && this.sameAccount() && this.kind === kind && this.word === query) { return; }
    if (!this.sameAccount()) { this.selected = []; }
    this.account = owner(); this.kind = kind; this.word = query;
    const session = authSession.session();
    this.bduss = session.bduss ?? ''; this.stoken = session.stoken ?? '';
    const mine: number = ++this.epoch;
    this.items = []; this.loaded = false; this.error = ''; this.loading = false;
    if (this.account.length === 0) { this.error = '登录后才能选择用户'; return; }
    this.loading = true;
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!this.current(mine)) { return; }
      const response = await this.api.fetchAtCandidates(device, authSession.session(), kind, query);
      if (!this.current(mine)) { return; }
      if (response.ok) { this.items = response.data.items; this.loaded = true; }
      else { this.error = response.describeFailure(); }
    } catch (err) { if (this.current(mine)) { this.error = '选人列表读取失败，请重试'; } }
    finally {
      if (mine === this.epoch) {
        this.loading = false;
        if (!this.sameAccount()) { this.items = []; this.selected = []; this.loaded = false; this.bduss = ''; this.stoken = ''; this.error = '账号已变化，请重新读取'; }
      }
    }
  }

  toggle(id: string): void {
    if (this.disposed || this.loading || !this.loaded || !this.sameAccount()) { return; }
    const found: AtCandidate | undefined = this.items.find((item: AtCandidate) => item.id === id);
    if (found === undefined) { return; }
    if (this.selected.some((item: AtCandidate) => item.id === id)) {
      this.selected = this.selected.filter((item: AtCandidate) => item.id !== id); this.error = ''; return;
    }
    if (this.selected.length >= 5) { this.error = '最多选择 5 位用户'; return; }
    const copy: AtCandidate = new AtCandidate();
    copy.id = found.id; copy.name = found.name; copy.displayName = found.displayName; copy.portrait = found.portrait;
    this.selected = this.selected.concat([copy]); this.error = '';
  }
  private sameAccount(): boolean {
    const live = authSession.session();
    return this.account.length > 0 && this.account === owner() &&
      this.bduss === (live.bduss ?? '') && this.stoken === (live.stoken ?? '');
  }
  private current(mine: number): boolean { return !this.disposed && mine === this.epoch && this.sameAccount(); }
  /** 显式确认前取独立快照；失败/在途/会话变化或不可编码候选不交接。 */
  selection(): AtCandidate[] {
    if (this.disposed || this.loading || !this.loaded || !this.sameAccount()) { return []; }
    if (this.selected.some((item: AtCandidate) => prepareAtMention(item) === undefined)) {
      this.error = '所选用户信息未确认，请重新选择'; return [];
    }
    return this.selected.map((item: AtCandidate) => {
      const copy: AtCandidate = new AtCandidate();
      copy.id = item.id; copy.name = item.name; copy.displayName = item.displayName; copy.portrait = item.portrait;
      return copy;
    });
  }
  remove(id: string): void {
    if (this.disposed || !this.sameAccount()) { return; }
    this.selected = this.selected.filter((item: AtCandidate) => item.id !== id); this.error = '';
  }
  dispose(): void { this.disposed = true; this.epoch++; this.loading = false; this.loaded = false; this.items = []; this.selected = []; this.account = ''; this.bduss = ''; this.stoken = ''; }
}
