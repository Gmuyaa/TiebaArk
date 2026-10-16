
import { curves } from '@kit.ArkUI';
import { AppTheme } from '../theme/Theme';
import { fontScaleStore } from '../common/appearance/FontSizeScaleStore';
import { fontSizeScaleOf } from '../common/appearance/FontSizeScale';

const CHANNEL_LABELS: string[] = ['关注', '推荐', '热榜'];
const ROW_H: number = 54;
const HIT_H: number = 44;
const SELECTED_H: number = 35;
const CHANNEL_GAP: number = 6;
const CHANNEL_PADDING: number = 12;

@ComponentV2
export struct HomeChannelPills {
  @Param selectedChannel: string = '推荐';
  @Param hidden: boolean = false;
  @Event onSelectChannel: (label: string) => void = (_label: string): void => {};
  /** 搜索入口：首页接真实搜索页，设置页预览接空动作 */
  @Event onSearch: () => void = (): void => {};
  // 初值对应 16fp 双汉字 + 两侧各 12vp；文字缩放后按实际测量更新。
  @Local firstWidth: number = 56;
  @Local secondWidth: number = 56;
  @Local thirdWidth: number = 56;

  private channelWidth(index: number): number {
    const scale: number = fontSizeScaleOf(fontScaleStore.pref,
      fontScaleStore.systemScale, fontScaleStore.customSize);
    const minimum: number = CHANNEL_PADDING * 2 + 32 * Math.max(1, scale);
    if (index === 0) { return Math.max(this.firstWidth, minimum); }
    if (index === 1) { return Math.max(this.secondWidth, minimum); }
    return Math.max(this.thirdWidth, minimum);
  }

  private updateChannelWidth(index: number, width: number): void {
    if (width <= 0) { return; }
    if (index === 0 && Math.abs(width - this.firstWidth) > 0.5) { this.firstWidth = width; }
    if (index === 1 && Math.abs(width - this.secondWidth) > 0.5) { this.secondWidth = width; }
    if (index === 2 && Math.abs(width - this.thirdWidth) > 0.5) { this.thirdWidth = width; }
  }

  private selectedIndex(): number {
    const index: number = CHANNEL_LABELS.indexOf(this.selectedChannel);
    return index < 0 ? 1 : index;
  }

  private selectedX(): number {
    const index: number = this.selectedIndex();
    if (index === 0) { return 0; }
    if (index === 1) { return this.channelWidth(0) + CHANNEL_GAP; }
    return this.channelWidth(0) + this.channelWidth(1) + CHANNEL_GAP * 2;
  }

  build() {
    Row() {
      Stack({ alignContent: Alignment.TopStart }) {
        Row()
          .width(this.channelWidth(this.selectedIndex()))
          .height(SELECTED_H)
          .borderRadius(SELECTED_H / 2)
          .backgroundColor(AppTheme.ACCENT_LIGHT)
          .opacity(0.7)
          .margin({ top: (HIT_H - SELECTED_H) / 2 })
          .translate({ x: this.selectedX() })
          .animation({ duration: 220, curve: Curve.EaseInOut })

        Row({ space: CHANNEL_GAP }) {
          ForEach(CHANNEL_LABELS, (label: string, index: number) => {
            Row() {
              Text(label)
                .fontSize(16)
                .maxFontScale(2)
                .fontWeight(this.selectedChannel === label ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.selectedChannel === label ? AppTheme.ACCENT : AppTheme.TAB_UNDERLINE_TEXT)
                .padding({ left: CHANNEL_PADDING, right: CHANNEL_PADDING })
                .onAreaChange((_old: Area, area: Area) => {
                  this.updateChannelWidth(index, Number(area.width));
                })
                .animation({ duration: 220, curve: Curve.EaseInOut })
            }
            .width(this.channelWidth(index))
            .height(HIT_H)
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.onSelectChannel(label); })
          }, (label: string) => label)
        }
        .height(HIT_H)
      }
      .width(this.channelWidth(0) + this.channelWidth(1) + this.channelWidth(2) + CHANNEL_GAP * 2)
      .height(HIT_H)

      Blank().layoutWeight(1)

      Row() {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(23)
          .fontColor([AppTheme.TAB_UNDERLINE_TEXT])
      }
      .width(HIT_H)
      .height(HIT_H)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .accessibilityText('搜索')
      .onClick(() => { this.onSearch(); })
    }
    .width('100%')
    .height(ROW_H)
    .alignItems(VerticalAlign.Center)
    .scale({ x: this.hidden ? 0.04 : 1, y: this.hidden ? 0.04 : 1,
      centerX: '50%', centerY: 0 })
    .translate({ y: this.hidden ? -64 : 0 })
    .animation({ duration: this.hidden ? 300 : 440,
      curve: this.hidden ? Curve.EaseIn : curves.springMotion(0.38, 0.64) })
  }
}
