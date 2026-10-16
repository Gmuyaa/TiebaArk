import { AppTheme } from '../theme/Theme';
import { UiLayout } from '../common/appearance/UiLayout';
import { RefreshSpinner } from './RefreshSpinner';

/** 公共内容状态；调用方根据真实读取状态提供文案与动作。 */
@ComponentV2
export struct PageState {
  @Param title: string = '';
  @Param message: string = '';
  @Param loading: boolean = false;
  @Param actionLabel: string = '';
  @Param compact: boolean = false;
  @Param fillRemaining: boolean = false;
  @Event onAction: () => void = (): void => {};

  @Builder
  CompactContent() {
    Row({ space: 8 }) {
      if (this.loading) { RefreshSpinner({ diameter: 18 }) }
      if (this.title.length > 0 || this.message.length > 0) {
        Text(this.message.length > 0 ? this.message : this.title).fontSize(UiLayout.META)
          .fontColor(AppTheme.TEXT_SUB).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
      }
      if (!this.loading && this.actionLabel.length > 0) {
        Text(this.actionLabel).fontSize(13).fontColor(AppTheme.ACCENT_DARK)
          .constraintSize({ minHeight: 40, minWidth: 48 }).textAlign(TextAlign.Center)
          .padding({ left: 8, right: 8 }).flexShrink(0).onClick(() => { this.onAction(); })
      }
    }.width('100%').justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16, top: 8 })
  }

  @Builder
  FullContent() {
      Column({ space: 12 }) {
        if (this.loading) { RefreshSpinner() }
        if (this.title.length > 0) {
          Text(this.title).fontSize(UiLayout.STATE_TITLE).fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT_MAIN).textAlign(TextAlign.Center).width('100%')
        }
        if (this.message.length > 0) {
          Text(this.message).fontSize(UiLayout.STATE_BODY)
            .fontColor(AppTheme.TEXT_SUB).textAlign(TextAlign.Center).width('100%')
        }
        if (!this.loading && this.actionLabel.length > 0) {
          Button(this.actionLabel).fontSize(14).fontColor(AppTheme.ACCENT_DARK)
            .backgroundColor(AppTheme.ACCENT_LIGHT).constraintSize({ minHeight: 40, minWidth: 88 })
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .onClick(() => { this.onAction(); })
        }
      }
      .width('100%').padding({ left: 24, right: 24, top: 28 })
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }

  build() {
    // layoutWeight 分配给自定义组件包装层，实体根还要填满这段高度。
    Column() {
      if (this.compact) {
        this.CompactContent()
      } else {
        this.FullContent()
      }
    }.width('100%').height(this.fillRemaining ? '100%' : undefined)
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }
}

/** 列表尾部只为分页反馈占位；悬浮控件的实际避让由宿主另行提供。 */
@ComponentV2
export struct ListFooter {
  @Param loading: boolean = false;
  @Param error: string = '';
  @Param hasMore: boolean = false;
  @Param moreText: string = '';
  @Param endText: string = '已经到底了';
  @Event onRetry: () => void = (): void => {};

  build() {
    if (this.loading || this.error.length > 0 || (this.hasMore ? this.moreText.length > 0 : this.endText.length > 0)) {
      PageState({ compact: true, loading: this.loading,
        message: this.loading ? '正在加载更多…' : (this.error.length > 0 ? this.error :
        (this.hasMore ? this.moreText : this.endText)),
        actionLabel: this.error.length > 0 ? '重试' : '',
        onAction: (): void => { this.onRetry(); } })
    }
  }
}
