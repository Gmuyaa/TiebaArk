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
  /** 官方材质的投影；不需要在深色/玻璃背景上再压一层浅影时传 false（分类胶囊贴住工具栏时用）。 */
  @Param applyShadow: boolean = true;
  @Param slot: MaterialSlot = MaterialSlot.BACK_BUTTON;
  /** 文字色与字重：吧页分类行贴顶后，选中项用强调色 + Medium（2026-11-11 持有者定），默认沿用主文字色/Regular。 */
  @Param textColor: ResourceColor = AppTheme.TEXT_MAIN;
  @Param textWeight: FontWeight = FontWeight.Regular;
  /**
   * 把材质裁到胶囊轮廓内（默认不裁，保留官方材质的边缘效果越界）。
   * 吧页分类行一排胶囊只隔 8vp，材质自带的边缘层会溢进缝里、几颗胶囊连成一条浅灰带
   * （2026-11-11 实测：不裁时缝里恒定 220、面板色 233、胶囊内 237，且与 `applyShadow` 无关）。
   */
  @Param clipToPill: boolean = false;
  /**
   * 裁边外扩量（vp，默认 0 = 正好裁在胶囊轮廓上）。设成 4 时裁切区比胶囊各方向大 4vp，
   * 材质自带的边缘层能在轮廓外保留 4vp 再被切掉（2026-11-11 持有者定，缝里 220 → 244~249）。
   */
  @Param clipOutset: number = 0;
  /**
   * 强制材质静态（`interactive:false`、`lightEffect:null`，2026-11-11 持有者定）：
   * 分类行整排紧挨着的胶囊不参与按压形变与光随指动——任意一颗形变都会让 8vp 缝里的
   * 边缘层跟着动，整排观感发飘。默认 false，其它调用方仍跟随全局动效开关。
   */
  @Param staticMaterial: boolean = false;
  @Event onTap: () => void = (): void => {};

  /** 文字/图标。必须是材质 Button 的内容，不能在外层当覆盖层——覆盖层会挡掉材质中心的指针位置。 */
  @Builder
  LabelContent() {
    Column({ space: this.stacked ? 2 : 0 }) {
      if (this.symbol !== undefined) {
        SymbolGlyph(this.symbol).fontSize(24).maxFontScale(1).fontWeight(FontWeight.Regular)
          .fontColor([AppTheme.TEXT_MAIN])
      }
      Text(this.label).fontSize(this.stacked ? 11 : 16).maxFontScale(1)
        .fontWeight(this.textWeight).fontColor(this.textColor).maxLines(1)
        .width('100%').textAlign(TextAlign.Center)
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .opacity(this.active ? 1 : 0.4)
      .accessibilityGroup(true).accessibilityText(this.accessibilityLabel || this.label)
  }

  @Builder
  Content() {
    if (materialManager.useArkUI) {
      Button({ type: ButtonType.Capsule }) {
        this.LabelContent()
      }
      .width(this.pillWidth).height(this.pillHeight).margin(0).padding(0)
      .backgroundColor(Color.Transparent)
      .systemMaterial(materialManager.officialOf(this.slot, true, this.staticMaterial))
      .accessibilityLevel('no')
      .onClick((): void => {})
    } else {
      this.CompatibilityContent()
    }
  }

  @Builder
  CompatibilityContent() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      this.LabelContent()
    }
      .width('100%').height('100%').padding(0).borderRadius(this.pillHeight / 2)
      .backgroundColor(Color.Transparent).visualEffect(pressLight(this.pressed))
      .hitTestBehavior(HitTestMode.None).accessibilityText(this.accessibilityLabel || this.label)
      .onClick(() => { if (this.active) { this.onTap(); } })
  }

  build() {
    Stack() {
      Stack() {
        MaterialTabs({ slot: this.slot, barHeight: this.pillHeight, barWidth: this.pillWidth, componentMaterial: true,
          applyShadow: this.applyShadow,
          barContent: (): void => { this.Content(); } })
          .borderRadius(this.pillHeight / 2).width(this.pillWidth).height(this.pillHeight)
        if (!materialManager.useArkUI) {
          MaterialMotionLayer({ radius: this.pillHeight / 2, pressed: this.pressed })
            .width(this.pillWidth).height(this.pillHeight)
        }
      }
      // 裁切区比胶囊各方向大 clipOutset（默认 0 = 正好裁在轮廓上），并居中盖住胶囊。
      .width(this.pillWidth + this.clipOutset * 2).height(this.pillHeight + this.clipOutset * 2)
      .borderRadius(this.pillHeight / 2 + this.clipOutset)
      .clip(this.clipToPill)
      .position({ x: -this.clipOutset, y: -this.clipOutset })
    }.width(this.pillWidth).height(this.pillHeight)
      .borderRadius(this.pillHeight / 2)
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Down && this.active) { this.pressed = true; }
        if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.pressed = false; }
      })
      .parallelGesture(TapGesture().onAction((): void => { if (this.active) { this.onTap(); } }))
  }
}
