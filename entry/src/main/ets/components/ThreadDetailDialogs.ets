/** 帖子详情独立弹层：单帖评论权限选择面板与跳转楼层弹窗。 */

import { AppTheme as BrandTheme, DetailTheme as AppTheme } from '../theme/Theme';
import {
  ThreadReplyPermission, ThreadReplyPermissionOption, THREAD_REPLY_PERMISSION_OPTIONS
} from '../model/ThreadDetail';
import { MotionEffect } from '../common/appearance/MotionConfig';
import { motionDuration, motionTransition } from '../common/appearance/MotionPolicy';

@ComponentV2
export struct ThreadCommentPermissionSheet {
  @Param currentPermission: ThreadReplyPermission = ThreadReplyPermission.ALL;
  @Param pending: boolean = false;
  @Param pendingPermission: ThreadReplyPermission | undefined = undefined;
  @Event onSelect: (permission: ThreadReplyPermission) => void = (_p: ThreadReplyPermission): void => {};
  @Event onCancel: () => void = (): void => {};

  build() {
    Column() {
      Column({ space: 4 }) {
        Text('评论权限')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT_MAIN)
          .textAlign(TextAlign.Center)
        Text('仅对该贴生效，不影响设置页权限')
          .fontSize(12.5)
          .fontColor(AppTheme.TEXT_SUB)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 24, right: 24, top: 22, bottom: 14 })

      Divider()
        .color(AppTheme.DIVIDER)
        .strokeWidth(0.5)
        .margin({ left: 20, right: 20 })

      ForEach(THREAD_REPLY_PERMISSION_OPTIONS, (option: ThreadReplyPermissionOption, index: number) => {
        Column() {
          Row({ space: 12 }) {
            Text(option.label)
              .fontSize(15)
              .fontWeight(this.currentPermission === option.permission ? FontWeight.Medium : FontWeight.Regular)
              .fontColor(this.currentPermission === option.permission ? AppTheme.ACCENT : AppTheme.TEXT_MAIN)
              .layoutWeight(1)
            if (this.pending && this.pendingPermission === option.permission) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color(AppTheme.ACCENT)
            } else if (this.currentPermission === option.permission) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(18)
                .maxFontScale(1)
                .fontColor([AppTheme.ACCENT])
            }
          }
          .width('100%')
          .constraintSize({ minHeight: 50 })
          .padding({ left: 24, right: 24, top: 12, bottom: 12 })
          .alignItems(VerticalAlign.Center)
          .enabled(!this.pending)
          .accessibilityGroup(true)
          .accessibilityText(option.label)
          .accessibilitySelected(this.currentPermission === option.permission)
          .id(`thread-comment-permission-option-${option.permission}`)
          .onClick((): void => { this.onSelect(option.permission); })

          if (index < THREAD_REPLY_PERMISSION_OPTIONS.length - 1) {
            Divider()
              .color(AppTheme.DIVIDER)
              .strokeWidth(0.5)
              .margin({ left: 24, right: 24 })
          }
        }
        .width('100%')
      }, (option: ThreadReplyPermissionOption): string => String(option.permission))

      Divider()
        .color(AppTheme.DIVIDER)
        .strokeWidth(0.5)
        .margin({ left: 20, right: 20 })

      Text('取消')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_SUB)
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ top: 14, bottom: 16 })
        .enabled(!this.pending)
        .id('thread-comment-permission-cancel')
        .onClick((): void => {
          if (!this.pending) { this.onCancel(); }
        })
    }
    .width('100%')
    .id('thread-comment-permission-sheet')
  }
}

@ComponentV2
export struct ThreadJumpFloorDialog {
  @Param text: string = '';
  @Param jumping: boolean = false;
  @Event onChange: (value: string) => void = (_v: string): void => {};
  @Event onSubmit: () => void = (): void => {};
  @Event onClose: () => void = (): void => {};

  build() {
    Stack() {
      Column({ space: 14 }) {
        Text('跳转楼层')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_MAIN)

        TextInput({ text: this.text, placeholder: '输入楼层号，如 25' })
          .caretColor(AppTheme.ACCENT)
          .selectedBackgroundColor(BrandTheme.SELECTION_BACKGROUND)
          .type(InputType.Number)
          .enabled(!this.jumping)
          .fontSize(15)
          .fontColor(AppTheme.TEXT_MAIN)
          .placeholderColor(AppTheme.TEXT_MUTED)
          .width(210)
          .height(44)
          .backgroundColor(AppTheme.SURFACE_MUTED)
          .borderRadius(12)
          .onChange((value: string): void => { this.onChange(value); })
          .onSubmit((): void => { this.onSubmit(); })

        Row({ space: 12 }) {
          Text('取消')
            .fontSize(14)
            .fontColor(AppTheme.TEXT_SUB)
            .textAlign(TextAlign.Center)
            .width(92)
            .height(38)
            .borderRadius(19)
            .backgroundColor(AppTheme.SURFACE_MUTED)
            .onClick((): void => { this.onClose(); })

          Text(this.jumping ? '跳转中…' : '跳转')
            .fontSize(14)
            .fontColor(BrandTheme.ON_ACCENT)
            .textAlign(TextAlign.Center)
            .width(92)
            .height(38)
            .borderRadius(19)
            .backgroundColor(AppTheme.ACCENT)
            .opacity(this.jumping ? 0.65 : 1)
            .enabled(!this.jumping)
            .onClick((): void => { this.onSubmit(); })
        }
      }
      .padding({ left: 22, right: 22, top: 22, bottom: 20 })
      .borderRadius(18)
      .backgroundColor(AppTheme.CARD)
      .shadow({ radius: 24, color: '#40000000', offsetY: 8 })
      .onClick((): void => {})
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.OVERLAY)
    .transition(motionTransition(TransitionEffect.OPACITY, MotionEffect.FADE)
      .animation({ duration: motionDuration(180, MotionEffect.FADE), curve: Curve.EaseOut }))
    .onClick((): void => { this.onClose(); })
  }
}
