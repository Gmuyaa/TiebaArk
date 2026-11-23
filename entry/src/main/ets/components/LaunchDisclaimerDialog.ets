/** 首次启动提示与免责声明居中弹窗；优先承载 ArkUI 官方沉浸材质，不支持时回退主题卡片底色。 */

import { promptAction } from '@kit.ArkUI';
import { motionEdgeEffect, popupMotion } from '../common/appearance/MotionPolicy';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { materialManager } from '../common/material/MaterialManager';
import {
  DISCLAIMER_FOOTER_HINT, DISCLAIMER_SUBTITLE, DISCLAIMER_TITLE, DisclaimerSection,
  disclaimerSections
} from '../model/LaunchDisclaimer';
import { AppTheme } from '../theme/Theme';

const DIALOG_RADIUS: number = 24;
const DIALOG_MIN_WIDTH: number = 280;
const DIALOG_MAX_WIDTH: number = 360;
const DIALOG_FALLBACK_WIDTH: number = 328;
const DIALOG_SIDE_INSET: number = 24;

export function launchDisclaimerDialogWidth(viewportWidthVp: number): number {
  if (!Number.isFinite(viewportWidthVp) || viewportWidthVp <= 0) {
    return DIALOG_FALLBACK_WIDTH;
  }
  return Math.min(Math.max(viewportWidthVp - DIALOG_SIDE_INSET * 2, DIALOG_MIN_WIDTH), DIALOG_MAX_WIDTH);
}

export function launchDisclaimerBodyMaxHeight(viewportHeightVp: number): number {
  if (!Number.isFinite(viewportHeightVp) || viewportHeightVp <= 0) {
    return 320;
  }
  return Math.max(220, Math.min(Math.round(viewportHeightVp * 0.52), 420));
}

/** 强制确认弹窗：禁止点击遮罩或返回键关闭，确保未同意前无法落入空白壳页。 */
export function launchDisclaimerDialogOptions(builder: CustomBuilder, viewportWidthVp: number,
  onDisappear: () => void): promptAction.CustomDialogOptions {
  return {
    builder: builder,
    alignment: DialogAlignment.Center,
    width: launchDisclaimerDialogWidth(viewportWidthVp),
    cornerRadius: DIALOG_RADIUS,
    isModal: true,
    autoCancel: false,
    dialogTransition: popupMotion(),
    maskTransition: popupMotion(),
    systemMaterial: materialManager.officialOf(MaterialSlot.SHEET, true, true),
    backgroundColor: materialManager.useArkUI ? undefined : AppTheme.CARD,
    onWillDismiss: (_action: DismissDialogAction): void => {},
    onDidDisappear: onDisappear
  };
}

@ComponentV2
export struct LaunchDisclaimerContent {
  @Param maxBodyHeight: number = 320;
  @Param busy: boolean = false;
  @Event onAgree: () => void = (): void => {};
  @Event onDecline: () => void = (): void => {};

  build() {
    Column() {
      Column({ space: 6 }) {
        Image($r('app.media.app_icon'))
          .width(48)
          .height(48)
          .borderRadius(12)
          .objectFit(ImageFit.Cover)
          .accessibilityLevel('no')
        Text(DISCLAIMER_TITLE)
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT_MAIN)
          .textAlign(TextAlign.Center)
          .margin({ top: 4 })
        Text(DISCLAIMER_SUBTITLE)
          .fontSize(13)
          .fontColor(AppTheme.TEXT_SUB)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .margin({ bottom: 16 })

      Scroll() {
        Column({ space: 12 }) {
          ForEach(disclaimerSections(), (section: DisclaimerSection, secIndex: number) => {
            Column({ space: 6 }) {
              Text(section.title)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppTheme.TEXT_MAIN)
                .width('100%')
              ForEach(section.paragraphs, (paragraph: string, pIndex: number) => {
                Text(paragraph)
                  .fontSize(13.5)
                  .fontColor(AppTheme.NOTE_TEXT)
                  .lineHeight(21)
                  .width('100%')
              }, (_p: string, pIndex: number) => `sec_${secIndex}_p_${pIndex}`)
            }
            .width('100%')
          }, (section: DisclaimerSection, secIndex: number) => `sec_${secIndex}_${section.title}`)

          Text(DISCLAIMER_FOOTER_HINT)
            .fontSize(12)
            .fontColor(AppTheme.TEXT_MUTED)
            .lineHeight(18)
            .width('100%')
            .margin({ top: 2 })
        }
        .width('100%')
      }
      .width('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(motionEdgeEffect())
      .constraintSize({ maxHeight: this.maxBodyHeight })

      Row({ space: 12 }) {
        Button('不同意并退出', { type: ButtonType.Capsule })
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .maxFontScale(1.3)
          .fontColor(AppTheme.TEXT_MAIN)
          .backgroundColor(AppTheme.SURFACE_MUTED)
          .enabled(!this.busy)
          .id('launch-disclaimer-decline')
          .onClick((): void => {
            this.onDecline();
          })

        Button('同意并继续', { type: ButtonType.Capsule })
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .maxFontScale(1.3)
          .fontColor(AppTheme.ON_EMPHASIS)
          .backgroundColor(AppTheme.EMPHASIS)
          .enabled(!this.busy)
          .id('launch-disclaimer-agree')
          .onClick((): void => {
            this.onAgree();
          })
      }
      .width('100%')
      .margin({ top: 18 })
    }
    .width('100%')
    .padding({ top: 24, bottom: 20, left: 22, right: 22 })
  }
}
