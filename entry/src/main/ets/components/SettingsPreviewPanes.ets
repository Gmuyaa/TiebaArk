import { common } from '@kit.AbilityKit';
import { FONT_SIZE_MAX, FONT_SIZE_MIN, fontSizeScaleOf } from '../common/appearance/FontSizeScale';
import { fontScaleStore } from '../common/appearance/FontSizeScaleStore';
import { HomeTopNavStyle, OFFICIAL_DUAL_ROW_HEIGHT, homeDualRowHeight } from '../common/appearance/HomeTopNavStyle';
import { homeTopNavStore } from '../common/appearance/HomeTopNavStore';
import { sliderMaterial } from '../common/appearance/MotionPolicy';
import { SettingsLayout } from '../common/appearance/SettingsLayout';
import { PaperLayout } from '../common/appearance/VisualTheme';
import { visualThemeStore } from '../common/appearance/VisualThemeStore';
import { AppTheme } from '../theme/Theme';
import { HomeDualRowTopBar } from './HomeDualRowTopBar';
import { HomeTopNav } from './HomeTopNav';

const TOP_NAV_PREVIEW_H: number = 108;
const TOP_NAV_PREVIEW_DUAL_H: number = 119 + 28;

@ComponentV2
export struct SettingsFontSizeSheet {
  build() {
    Column() {
      Row() {
        Text('字体大小')
          .fontSize(18)
          .fontColor(AppTheme.TEXT_MAIN)
          .layoutWeight(1)
        Text(`${fontScaleStore.customSize} fp`)
          .fontSize(18)
          .fontColor(AppTheme.TEXT_MAIN)
      }
      .width('100%')
      .margin({ bottom: 28 })

      Row() {
        Text('A').fontSize(18).fontColor(AppTheme.TEXT_MAIN)
        Slider({
          value: fontScaleStore.customSize,
          min: FONT_SIZE_MIN,
          max: FONT_SIZE_MAX,
          step: 1,
          style: SliderStyle.InSet
        })
          .systemMaterial(sliderMaterial())
          .layoutWeight(1)
          .selectedColor(AppTheme.ACCENT)
          .onChange((value: number, mode: SliderChangeMode): void => {
            const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
            fontScaleStore.setCustomSize(value, context,
              mode !== SliderChangeMode.Begin && mode !== SliderChangeMode.Moving);
            if (mode !== SliderChangeMode.Begin && mode !== SliderChangeMode.Moving &&
              fontScaleStore.saveError.length > 0) {
              try {
                this.getUIContext().getPromptAction().showToast({ message: fontScaleStore.saveError });
              } catch (_) {}
            }
          })
          .margin({ left: 12, right: 12 })
        Text('A').fontSize(30).fontColor(AppTheme.TEXT_MAIN)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 26 })
  }
}

@ComponentV2
export struct SettingsTopNavPreview {
  @Local previewChannel: string = '推荐';
  @Local previewNavRowH: number = 56;

  build() {
    Column() {
      Text('顶栏预览')
        .fontSize(SettingsLayout.SUB_SIZE)
        .fontColor(AppTheme.NOTE_TEXT)
        .width('100%')
        .margin({ bottom: 8 })
      Stack({ alignContent: Alignment.TopStart }) {
        Row({ space: 8 }) {
          Column()
            .width(72).height(72).borderRadius(10)
            .backgroundColor(AppTheme.TEXT_MUTED)
          Column()
            .width(96).height(56).borderRadius(10)
            .backgroundColor(AppTheme.CARD)
          Column()
            .width(56).height(88).borderRadius(10)
            .backgroundColor(AppTheme.SURFACE_MUTED)
          Blank()
        }
        .width('100%')
        .opacity(0.55)
        .padding({ left: 12, right: 12, top: 6 })
        if (visualThemeStore.isPaper || homeTopNavStore.style === HomeTopNavStyle.OFFICIAL_DUAL_ROW) {
          HomeDualRowTopBar({
            statusBarHeight: 0,
            selectedChannel: this.previewChannel,
            onSelectChannel: (label: string): void => { this.previewChannel = label; },
            onSearch: (): void => {}
          })
            .width('100%')
            .padding({ top: 6 })
        } else {
          HomeTopNav({
            style: homeTopNavStore.style,
            selectedChannel: this.previewChannel,
            onRowHeightChanged: (height: number): void => { this.previewNavRowH = height; },
            hidden: false,
            onSelectChannel: (label: string): void => { this.previewChannel = label; },
            onSearch: (): void => {}
          })
            .width('100%')
            .padding({ left: 0, right: 0 })
        }
      }
      .width('100%')
      .height(visualThemeStore.isPaper
        ? TOP_NAV_PREVIEW_DUAL_H + PaperLayout.BRAND_HEIGHT
        : homeTopNavStore.style === HomeTopNavStyle.OFFICIAL_DUAL_ROW
        ? TOP_NAV_PREVIEW_DUAL_H + homeDualRowHeight(fontSizeScaleOf(fontScaleStore.pref,
          fontScaleStore.systemScale, fontScaleStore.customSize)) - OFFICIAL_DUAL_ROW_HEIGHT
        : Math.max(TOP_NAV_PREVIEW_H, this.previewNavRowH + 28))
      .clip(true)
      .borderRadius(SettingsLayout.CARD_RADIUS - 6)
      .backgroundColor(AppTheme.BG)
    }
    .width('100%')
    .padding(12)
    .margin({ top: SettingsLayout.GROUP_TITLE_GAP })
    .backgroundColor(AppTheme.SURFACE_MUTED)
    .borderRadius(SettingsLayout.CARD_RADIUS)
  }
}
