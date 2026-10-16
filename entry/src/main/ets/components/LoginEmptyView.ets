/**
 * 未登录功能的统一空态视图。
 *
 * 关注 / 消息这类依赖登录态的功能，在登录做出来之前都挂这个空态：
 * 图标 + 主文案 + 副文案 + 一个"去登录"按钮。
 *
 * 登录入口由**调用方**通过 `onLogin` 注入：组件不认识路由，也不判断登录态，
 * 这样它既能被 Tab 页复用，也不会把 `pages/Login` 这个具体页面焊死在里面。
 * 没有传 `onLogin` 时按老行为 toast 说明未开放——不给出点了没反应的假入口。
 */

import { promptAction } from '@kit.ArkUI';
import { AppTheme } from '../theme/Theme';

@ComponentV2
export struct LoginEmptyView {
  /** Tab 图标位的示意图标。单色 SVG，靠 fillColor 染浅色 */
  @Param icon: Resource = $r('app.media.icon_person');
  /** 主文案：这个功能是什么 */
  @Param title: string = '';
  /** 副文案：登录后能干什么 */
  @Param subtitle: string = '';
  /** 点"去登录"时的行为；不传则退化为 toast 提示 */
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
