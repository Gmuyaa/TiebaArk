/** 热榜话题详情：在应用内打开网页首页榜单项的官方目标页。 */

import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { PageHeader } from '../components/PageHeader';
import { HotTopicItem, hotTopicUrl } from '../model/HotTopic';
import { NavigationService, HotTopicParams } from '../navigation/AppNavigation';
import { AppTheme } from '../theme/Theme';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';

@ComponentV2
export struct HotTopicPage {
  @Param routeParams: HotTopicParams | undefined = undefined;
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;
  @Local title: string = '热议话题';
  @Local url: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    const params: HotTopicParams | undefined = this.routeParams;
    if (params !== undefined && Number.isInteger(params.topicId) && params.topicId > 0) {
      const topic: HotTopicItem = new HotTopicItem();
      topic.id = params.topicId;
      topic.name = params.topicName;
      this.title = params.topicName;
      this.url = hotTopicUrl(topic);
    }
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    readStatusBarVp(context).then((vp: number) => {
      this.statusBarH = vp;
    }).catch(() => {});
  }

  build() {
    HdsNavDestination() {
      Column() {
        PageHeader({ title: this.title, onBack: (): void => { NavigationService.back(); } })
        if (this.url.length > 0) {
          Web({ src: this.url, controller: this.controller })
            .cacheMode(CacheMode.Online)
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .layoutWeight(1)
            .width('100%')
        } else {
          Text('话题地址无效')
            .fontSize(15)
            .fontColor(AppTheme.TEXT_SUB)
            .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarH })
      .backgroundColor(AppTheme.BG)
    }
    .hideTitleBar(true)
  }
}
