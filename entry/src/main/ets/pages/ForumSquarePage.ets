import { common } from '@kit.AbilityKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { ForumSquareView } from '../components/ForumSquareView';
import { PageHeader } from '../components/PageHeader';
import { NavigationService } from '../navigation/AppNavigation';
import { AppTheme } from '../theme/Theme';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';

/** 吧广场：从进吧页进入共享导航栈的分类发现页。 */
@ComponentV2
export struct ForumSquarePage {
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;
  @Local pageVisible: boolean = false;

  aboutToAppear(): void {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    readStatusBarVp(context).then((height: number): void => {
      this.statusBarH = height;
    }).catch(() => {});
  }

  build() {
    HdsNavDestination() {
      Column() {
        PageHeader({ title: '吧广场', onBack: (): void => { NavigationService.back(); } })
        ForumSquareView({ active: this.pageVisible }).layoutWeight(1)
      }
      .width('100%').height('100%')
      .padding({ top: this.statusBarH }).backgroundColor(AppTheme.BG)
    }
    .hideTitleBar(true)
    .onShown((): void => { this.pageVisible = true; })
    .onHidden((): void => { this.pageVisible = false; })
  }
}
