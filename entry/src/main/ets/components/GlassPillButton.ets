import { MaterialTabs } from './MaterialTabs';
import { MaterialMotionLayer } from './MaterialMotionLayer';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { materialManager } from '../common/material/MaterialManager';
import { AppTheme } from '../theme/Theme';
import { pressLight } from '../common/appearance/MotionPolicy';

/** 文字或图标文字胶囊，沿用圆按钮的 ArkUI 优先官方材质通道。 */
@ComponentV2
export struct GlassPillButton {
  @Local pressed: boolean = false;
  @Param label: string = '';
  @Param accessibilityLabel: string = '';
  @Param symbol: Resource | undefined = undefined;
  @Param pillWidth: number = 64;
  @Param pillHeight: number = 40;
  @Param stacked: boolean = false;
  @Param active: boolean = true;
  @Param slot: MaterialSlot = MaterialSlot.BACK_BUTTON;
  @Event onTap: () => void = (): void => {};

  @Builder
  LabelContent() {
    Column({ space: this.stacked ? 2 : 0 }) {
      if (this.symbol !== undefined) {
        SymbolGlyph(this.symbol).fontSize(24).maxFontScale(1).fontWeight(FontWeight.Regular)
          .fontColor([AppTheme.TEXT_MAIN])
      }
      Text(this.label).fontSize(this.stacked ? 11 : 16).maxFontScale(1)
        .fontWeight(FontWeight.Regular).fontColor(AppTheme.TEXT_MAIN).maxLines(1)
        .width('100%').textAlign(TextAlign.Center)
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .opacity(this.active ? 1 : 0.4)
      .accessibilityGroup(true).accessibilityText(this.accessibilityLabel || this.label)
      .hitTestBehavior(HitTestMode.None).zIndex(1)
  }

  @Builder
  Content() {
    if (materialManager.useArkUI) {
      Button({ type: ButtonType.Capsule }) {
        Row().width('100%').height('100%')
      }
      .width(this.pillWidth).height(this.pillHeight).margin(0).padding(0)
      .backgroundColor(Color.Transparent)
      .systemMaterial(materialManager.officialOf(this.slot))
      .accessibilityLevel('no')
      .onClick((): void => {})
    } else {
      this.CompatibilityContent()
    }
  }

  @Builder
  CompatibilityContent() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row().width('100%').height('100%')
    }
      .width('100%').height('100%').padding(0).borderRadius(this.pillHeight / 2)
      .backgroundColor(Color.Transparent).visualEffect(pressLight(this.pressed))
      .hitTestBehavior(HitTestMode.None).accessibilityText(this.accessibilityLabel || this.label)
      .onClick(() => { if (this.active) { this.onTap(); } })
  }

  build() {
    Stack() {
      MaterialTabs({ slot: this.slot, barHeight: this.pillHeight, barWidth: this.pillWidth, componentMaterial: true,
        barContent: (): void => { this.Content(); } })
        .borderRadius(this.pillHeight / 2).clip(false).width(this.pillWidth).height(this.pillHeight)
      if (!materialManager.useArkUI) {
        MaterialMotionLayer({ radius: this.pillHeight / 2, pressed: this.pressed })
          .width(this.pillWidth).height(this.pillHeight)
      }
      this.LabelContent()
    }.width(this.pillWidth).height(this.pillHeight)
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Down && this.active) { this.pressed = true; }
        if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.pressed = false; }
      })
      .parallelGesture(TapGesture().onAction((): void => { if (this.active) { this.onTap(); } }))
  }
}
