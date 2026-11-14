import { FloatingCircleButton } from './FloatingCircleButton';
import { FloatingButtonKind } from '../model/SmartReach';
import { AppTheme } from '../theme/Theme';

/**
 * 首页发帖按钮。
 *
 * 2026-11-10 重构：握姿订阅、防抖、绕屏换边、拖拽吸附、边缘入场、触控区、按压缩放
 * 全部收进 `FloatingCircleButton`，本组件只声明"首页发帖"这一种用法和它自己的差异
 * （加号图标、底栏以上 68vp 的默认落点、独立的位置记忆字段）。
 */
@ComponentV2
export struct HomeComposeButton {
  @Param viewportWidth: number = 0;
  @Param viewportHeight: number = 0;
  @Param topInset: number = 0;
  @Param active: boolean = true;
  @Event onCompose: () => void = (): void => {};

  build() {
    FloatingCircleButton({
      kind: FloatingButtonKind.HOME_COMPOSE,
      viewportWidth: this.viewportWidth,
      viewportHeight: this.viewportHeight,
      topInset: this.topInset,
      active: this.active,
      symbol: $r('sys.symbol.plus'),
      diameter: 48,
      iconSize: 24,
      label: '发帖，可自由拖拽移动',
      // 无记忆位置时的落点：底栏高度 + 68vp 之上。
      fallbackYFromBottom: AppTheme.BAR_TOTAL_H + 68,
      onTap: (): void => { this.onCompose(); }
    })
  }
}

