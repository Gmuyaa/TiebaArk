import { common } from '@kit.AbilityKit';
import { TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { VideoFeedItem, appendVideoFeed } from '../model/VideoFeed';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { readVideoEnvironment } from '../utils/VideoEnvironment';
function owner(): string { return authSession.isLoggedIn() ? `${authSession.snapshot.uid}:${authSession.snapshot.portrait}` : ''; }
@ObservedV2
export class VideoFeedVM {
  @Trace items: VideoFeedItem[] = [];
  @Trace loading: boolean = false;
  @Trace loadingMore: boolean = false;
  @Trace loaded: boolean = false;
  @Trace error: string = '';
  @Trace moreError: string = '';
  @Trace canContinue: boolean = false;
  private epoch: number = 0;
  private account: string = owner();
  private disposed: boolean = false;
  private api: TiebaApi = new TiebaApi();
  private current(mine: number): boolean { return !this.disposed && mine === this.epoch && this.account === owner(); }
  async refresh(context: common.UIAbilityContext): Promise<void> {
    if (this.disposed) { return; }
    const changed: boolean = this.account !== owner(); this.account = owner();
    if (changed) { this.items = []; this.loaded = false; this.canContinue = false; }
    const mine: number = ++this.epoch; this.loading = true; this.loadingMore = false; this.error = ''; this.moreError = '';
    await this.fetch(context, mine, true);
  }
  async loadMore(context: common.UIAbilityContext): Promise<void> {
    if (this.disposed) { return; }
    if (this.account !== owner()) { await this.refresh(context); return; }
    if (this.loading || this.loadingMore || !this.canContinue || this.error.length > 0) { return; }
    const mine: number = ++this.epoch; this.loadingMore = true; this.moreError = '';
    await this.fetch(context, mine, false);
  }
  private async fetch(context: common.UIAbilityContext, mine: number, replace: boolean): Promise<void> {
    try {
      const device = await DeviceIdentity.ensure(context); if (!this.current(mine)) { return; }
      const environment = await readVideoEnvironment(); if (!this.current(mine)) { return; }
      const response = await this.api.fetchVideoFeed(device, authSession.session(), environment, replace ? 1 : 2);
      if (!this.current(mine)) { return; }
      if (!response.ok) { if (replace) { this.error = response.describeFailure(); } else { this.moreError = response.describeFailure(); } return; }
      const before: number = replace ? 0 : this.items.length;
      this.items = appendVideoFeed(replace ? [] : this.items, response.data.items);
      this.loaded = true; this.canContinue = this.items.length > before;
    } catch (err) {
      if (this.current(mine)) { if (replace) { this.error = '视频读取失败，请重试'; } else { this.moreError = '视频续取失败，请重试'; } }
    } finally {
      if (mine === this.epoch) {
        this.loading = false; this.loadingMore = false;
        if (!this.disposed && this.account !== owner()) {
          this.items = []; this.loaded = false; this.canContinue = false; this.error = '账号已变化，请刷新'; this.moreError = '';
        }
      }
    }
  }
  dispose(): void { this.disposed = true; this.epoch++; this.items = []; this.loading = false; this.loadingMore = false; this.loaded = false; this.canContinue = false; }
}
