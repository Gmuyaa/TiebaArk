import { MaterialTabs } from './MaterialTabs';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { materialManager } from '../common/material/MaterialManager';
import { AppTheme } from '../theme/Theme';

/** 短暂结果提示，复用浮动胶囊的官方沉浸材质与阴影。 */
@ComponentV2
export struct GlassToast {
  @Require @Param message: string;

  private pillWidth(): number {
    return Math.min(268, Math.max(116, this.message.length * 15 + 20));
  }

  private pillHeight(): number {
    return this.message.length <= 12 ? 34 : 60;
  }

  @Builder
  Surface() {
    if (materialManager.useArkUI) {
      Button({ type: ButtonType.Capsule, stateEffect: false }) {
        Row().width('100%').height('100%')
      }
      .width('100%').height('100%').padding(0)
      .backgroundColor(Color.Transparent).systemMaterial(materialManager.officialOf(MaterialSlot.SHEET))
      .focusable(false).hitTestBehavior(HitTestMode.None)
    } else {
      Row().width('100%').height('100%')
    }
  }

  build() {
    Stack() {
      MaterialTabs({ slot: MaterialSlot.SHEET, barWidth: this.pillWidth(), barHeight: this.pillHeight(),
        componentMaterial: true, barContent: (): void => { this.Surface(); } })
        .width('100%').height('100%').clip(false).accessibilityLevel('no-hide-descendants')
      Text(this.message).fontSize(13).maxFontScale(1.15).fontColor(AppTheme.TEXT_MAIN)
        .textAlign(TextAlign.Center).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%').padding({ left: 10, right: 10 })
    }.width(this.pillWidth()).height(this.pillHeight()).constraintSize({ maxWidth: '100%' })
      .clip(false).hitTestBehavior(HitTestMode.None)
  }
}
