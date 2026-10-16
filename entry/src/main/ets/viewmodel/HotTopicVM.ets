/** 首页热榜独立状态。网页热议榜是公开接口，切频道时首次加载，下拉时刷新。 */

import { HotTopicsResponse, TiebaApi } from '../api/TiebaApi';
import { HotTopicItem } from '../model/HotTopic';

@ObservedV2
export class HotTopicVM {
  @Trace items: HotTopicItem[] = [];
  @Trace loading: boolean = false;
  @Trace loadedOnce: boolean = false;
  @Trace errorText: string = '';

  private api: TiebaApi = new TiebaApi();

  async load(force: boolean = false): Promise<void> {
    if (this.loading || (this.loadedOnce && !force)) {
      return;
    }
    this.loading = true;
    this.errorText = '';
    try {
      const response: HotTopicsResponse = await this.api.fetchHotTopics();
      if (!response.ok) {
        this.errorText = response.describeFailure();
        return;
      }
      this.items = response.data;
      this.loadedOnce = true;
    } catch (err) {
      this.errorText = `加载热榜失败：${(err as Error).message}`;
    } finally {
      this.loading = false;
    }
  }
}
