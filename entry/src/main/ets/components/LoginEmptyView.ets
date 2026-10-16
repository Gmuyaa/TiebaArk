

import { promptAction } from '@kit.ArkUI';
import { AppTheme } from '../theme/Theme';

@ComponentV2
export struct LoginEmptyView {

  @Param icon: Resource = $r('app.media.icon_person');

  @Param title: string = '';

  @Param subtitle: string = '';

  @Param onLogin: () => void = () => {
    promptAction.showToast({ message: '登录功能暂未开放', duration: 2000 });
  };

  build() {
    Column() {
      Column({ space: 12 }) {
        Stack({ alignContent: Alignment.Center }) {
          Image(this.icon)
            .width(42)
            .height(42)
            .fillColor(AppTheme.ACCENT)
        }
        .width(72)
        .height(72)
        .backgroundColor(AppTheme.ACCENT_LIGHT)
        .borderRadius(36)

        Text(this.title)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_MAIN)

        Text(this.subtitle)
          .fontSize(13)
          .fontColor(AppTheme.TEXT_SUB)
          .textAlign(TextAlign.Center)
          .padding({ left: 36, right: 36 })

        Button('去登录')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .width(132)
          .height(40)
          .margin({ top: 8 })
          .borderRadius(AppTheme.PILL_RADIUS)
          .backgroundColor(AppTheme.ACCENT)
          .fontColor(Color.White)
          .onClick(() => {
            this.onLogin();
          })
      }
      .padding({ top: 28, bottom: 28, left: 12, right: 12 })
      .backgroundColor(AppTheme.CARD)
      .borderRadius(AppTheme.CARD_RADIUS)
      .shadow({ radius: 14, color: '#12000000', offsetY: 3 })
      .margin({ left: AppTheme.PAGE_GUTTER, right: AppTheme.PAGE_GUTTER })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(AppTheme.BG)
  }
}
