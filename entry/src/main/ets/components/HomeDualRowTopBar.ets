
import { HdsTabs } from '@kit.UIDesignKit';
import { AppTheme } from '../theme/Theme';
import { themeModeStore } from '../common/appearance/ThemeModeStore';
import { materialManager } from '../common/material/MaterialManager';
import { MaterialSlot, SPLIT_PILL_GRADIENT_MASK } from '../common/material/MaterialConfig';
import { fontSizeScaleOf } from '../common/appearance/FontSizeScale';
import { fontScaleStore } from '../common/appearance/FontSizeScaleStore';

export const DUAL_SEARCH_ROW_H: number = 40;

export const DUAL_CHANNEL_ROW_H: number = 30;

export const DUAL_ROW_GAP: number = 2;

export const DUAL_CONTENT_H: number = DUAL_SEARCH_ROW_H + DUAL_ROW_GAP + DUAL_CHANNEL_ROW_H;

export const DUAL_BOX_INSET: number = 4;

const DUAL_BOX_INSET_X: number = 12;

const FALLBACK_VIS_W: number = 300;

const AVATAR_D: number = 28;
const SEARCH_FIELD_H: number = 32;

const CHANNEL_FONT_SELECTED: number = 17;
const CHANNEL_FONT_UNSELECTED: number = 16;

@ComponentV2
export struct HomeDualRowTopBar {

  @Param statusBarHeight: number = 39;
  @Param selectedChannel: string = '推荐';

  @Param collapsed: boolean = false;

  @Param avatarUrl: string = '';
  @Event onSelectChannel: (label: string) => void = (_label: string): void => {};
  @Event onSearch: () => void = (): void => {};
  @Event onAvatar: () => void = (): void => {};

  @Local visW: number = 0;

  private channelColor(selected: boolean): ResourceColor {
    if (selected) {
      return themeModeStore.isDark ? Color.White : Color.Black;
    }
    return themeModeStore.isDark ? AppTheme.TEXT_MUTED : AppTheme.BAR_TAB_TEXT;
  }

  private fieldStroke(): ResourceColor {
    return themeModeStore.isDark ? 'rgba(255, 255, 255, 0.28)' : 'rgba(0, 0, 0, 0.16)';
  }

  private fieldShadowColor(): ResourceColor {
    return themeModeStore.isDark ? 'rgba(0, 0, 0, 0.40)' : 'rgba(0, 0, 0, 0.10)';
  }

  private channelLabels(): string[] {
    return ['关注', '推荐', '热榜'];
  }

  private panelH(): number {

    const content: number = this.collapsed ? DUAL_CHANNEL_ROW_H : DUAL_CONTENT_H;
    return this.statusBarHeight + content + DUAL_BOX_INSET * 2;
  }

  private visibleW(): number {
    return this.visW > 0 ? this.visW : FALLBACK_VIS_W;
  }

  private nodeW(): number {
    return this.visibleW() + this.panelH();
  }

  private fontSizeOf(selected: boolean): number {
    const scale: number = Math.max(1, Math.min(1.3,
      fontSizeScaleOf(fontScaleStore.pref, fontScaleStore.systemScale, fontScaleStore.customSize)));
    return Math.round((selected ? CHANNEL_FONT_SELECTED : CHANNEL_FONT_UNSELECTED) * scale);
  }

  build() {

    Stack({ alignContent: Alignment.Top }) {

      Row()
        .width('100%')
        .height(1)
        .onAreaChange((_old: Area, area: Area) => {
          const w: number = Number(area.width);
          if (w <= 0 || Math.abs(w - this.visW) < 0.5) { return; }
          this.visW = w;
        })
      HdsTabs({ barPosition: BarPosition.End }) {
        TabContent() {
        }
        .tabBar(this.PanelContent())
      }
      .barHeight(this.panelH())
      .barMode(BarMode.Fixed)
      .scrollable(false)
      .animationDuration(0)
      .barOverlap(true)
      .barBackgroundColor(Color.Transparent)
      .barBackgroundBlurStyle(BlurStyle.NONE)
      .barFloatingStyle({
        barWidth: { smallWidth: this.nodeW(), mediumWidth: this.nodeW(), largeWidth: this.nodeW() },
        barSideMargin: 0,
        barBottomMargin: 0,
        gradientMask: SPLIT_PILL_GRADIENT_MASK,
        thermoCtrl: true,
        systemMaterialEffect: materialManager.hdsEffectOf(MaterialSlot.HOME_TOP_CONTINUOUS)
      })

      .borderRadius(this.panelH() / 2)
      .clip(true)
      .width(this.nodeW())
      .height(this.panelH())

    }
    .width('100%')
    .height(this.panelH())
  }

  @Builder
  PanelContent() {
    Column() {

      Blank().height(Math.max(0, this.statusBarHeight - DUAL_BOX_INSET))
      this.SearchRow()
      Blank().height(this.collapsed ? 0 : DUAL_ROW_GAP)
      this.ChannelRow()
    }
    .width(this.visibleW())
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SearchRow() {
    Row() {

      if (this.avatarUrl.length > 0) {
        Image(this.avatarUrl)
          .width(AVATAR_D)
          .height(AVATAR_D)
          .borderRadius(AVATAR_D / 2)
          .objectFit(ImageFit.Cover)
          .accessibilityText('个人主页')
          .onClick((): void => { this.onAvatar(); })
      } else {
        Row() {
          SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
            .fontSize(AVATAR_D - 6)
            .fontColor([AppTheme.TAB_UNDERLINE_TEXT])
        }
        .width(AVATAR_D)
        .height(AVATAR_D)
        .justifyContent(FlexAlign.Center)
        .accessibilityText('个人主页')
        .onClick((): void => { this.onAvatar(); })
      }

      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(20)
          .fontColor([AppTheme.TAB_UNDERLINE_TEXT])
        Text('搜索')
          .fontSize(16)
          .maxLines(1)
          .fontColor(AppTheme.TAB_UNDERLINE_TEXT)
      }
      .height(SEARCH_FIELD_H)
      .layoutWeight(1)
      .padding({ left: 14, right: 14 })
      .margin({ left: 12 })
      .borderRadius(SEARCH_FIELD_H / 2)

      .backgroundColor(AppTheme.SURFACE_MUTED)
      .border({ width: 1.5, color: this.fieldStroke() })
      .shadow({ radius: 6, offsetY: 1, color: this.fieldShadowColor() })
      .alignItems(VerticalAlign.Center)
      .accessibilityText('搜索')
      .onClick((): void => { this.onSearch(); })
    }
    .width('100%')

    .height(this.collapsed ? 0 : DUAL_SEARCH_ROW_H)
    .clip(true)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  ChannelRow() {
    Row() {
      ForEach(this.channelLabels(), (label: string) => {
        Row({ space: 4 }) {
          Text(label)
            .fontSize(this.fontSizeOf(this.selectedChannel === label))
            .maxLines(1)
            .fontWeight(this.selectedChannel === label ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.channelColor(this.selectedChannel === label))
          if (this.selectedChannel === label) {
            Circle({ width: 5, height: 5 })
              .fill(this.channelColor(true))
          }
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick((): void => { this.onSelectChannel(label); })
      }, (label: string) => label)
    }
    .width('100%')
    .height(DUAL_CHANNEL_ROW_H)
    .padding({ left: DUAL_BOX_INSET_X, right: DUAL_BOX_INSET_X })
  }
}
