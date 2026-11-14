import { FloatingCircleButton } from './FloatingCircleButton';
import { FloatingButtonKind } from '../model/SmartReach';

/**
 * 吧页刷新按钮。
 *
 * 2026-11-10 重构：与发帖按钮的共有能力全部下沉到 `FloatingCircleButton`，
 * 本组件只声明"吧页刷新"这一种用法和它自己的差异：刷新图标、busy 锁、
 * 避让悬浮分类胶囊、向吧页上报位置（胶囊据此让位）。
 */
@ComponentV2
export struct ForumRefreshButton {
  @Param viewportWidth: number = 0;
  @Param viewportHeight: number = 0;
  @Param topInset: number = 0;
  @Param active: boolean = true;
  @Param busy: boolean = false;
  @Param obstacleX: number = 0;
  @Param obstacleY: number = 0;
  @Param obstacleWidth: number = 0;
  @Param obstacleHeight: number = 0;
  @Event onMoveStart: () => void = (): void => {};
  @Event onPositionChanged: (x: number, y: number) => void = (): void => {};
  @Event onRefresh: () => void = (): void => {};

  build() {
    FloatingCircleButton({
      kind: FloatingButtonKind.FORUM_REFRESH,
      viewportWidth: this.viewportWidth,
      viewportHeight: this.viewportHeight,
      topInset: this.topInset,
      active: this.active,
      busy: this.busy,
      symbol: $r('sys.symbol.arrow_clockwise'),
      diameter: 48,
      iconSize: 24,
      label: '刷新当前分类，可拖拽移动',
      // 无记忆位置时的落点：距底部 128vp。
      fallbackYFromBottom: 128,
      obstacleX: this.obstacleX,
      obstacleY: this.obstacleY,
      obstacleWidth: this.obstacleWidth,
      obstacleHeight: this.obstacleHeight,
      onTap: (): void => { this.onRefresh(); },
      onMoveStart: (): void => { this.onMoveStart(); },
      onPositionChanged: (x: number, y: number): void => { this.onPositionChanged(x, y); }
    })
  }
}

