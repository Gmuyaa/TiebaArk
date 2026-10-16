
import { themeModeStore } from '../common/appearance/ThemeModeStore';
import { AppTheme } from '../theme/Theme';

export const PULL_REFRESH_OFFSET: number = 96;
export const HOME_REFRESH_OFFSET: number = PULL_REFRESH_OFFSET;
export const FORUM_REFRESH_OFFSET: number = PULL_REFRESH_OFFSET;

@ComponentV2
export struct PullRefreshHeader {
  @Param inset: number = 0;

  @Param active: boolean = false;
  build() {
    Row() { if (this.active) { RefreshSpinner() } }
      .width('100%').height(PULL_REFRESH_OFFSET).justifyContent(FlexAlign.Center)
      .translate({ y: this.inset }).hitTestBehavior(HitTestMode.None)
  }
}

@ComponentV2
export struct RefreshSpinner {

  @Param diameter: number = 32;

  build() {
    LoadingProgress()
      .width(this.diameter)
      .height(this.diameter)
      .color(themeModeStore.isDark ? Color.White : AppTheme.TEXT_MAIN)
  }
}
