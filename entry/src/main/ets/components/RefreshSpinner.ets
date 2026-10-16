/** 全站下拉刷新圆圈：沿用首页尺寸和应用深浅色；新下拉刷新必须复用此公共件。 */
import { themeModeStore } from '../common/appearance/ThemeModeStore';
import { AppTheme } from '../theme/Theme';

/** 全站以吧资料页为基准：刷新区域／触发门槛统一为 96vp。 */
export const PULL_REFRESH_OFFSET: number = 96;
export const HOME_REFRESH_OFFSET: number = PULL_REFRESH_OFFSET;
export const FORUM_REFRESH_OFFSET: number = PULL_REFRESH_OFFSET;

/** 原生 Refresh 的统一自定义指示器；悬浮顶栏页面用 inset 对齐可见内容起点。 */
@ComponentV2
export struct PullRefreshHeader {
  @Param inset: number = 0;
  /** 平移的头不能依赖 Refresh 裁剪来隐藏圆圈，结束时必须明确撤下。 */
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
