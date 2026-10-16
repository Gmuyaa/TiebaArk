import { AppTheme } from '../theme/Theme';
import { UiLayout } from '../common/appearance/UiLayout';
import { GlassBackButton } from './GlassBackButton';
import { common } from '@kit.AbilityKit';
import { readStatusBarVp, STATUS_BAR_FALLBACK_VP } from '../utils/SafeArea';

/** 主标签页标题；兼容 HDS 为不同宿主预留或忽略状态栏的两种布局。 */
@ComponentV2
export struct RootPageHeader {
  @Param title: string = '';
  @Param gutter: number = UiLayout.PAGE_GUTTER;
  @BuilderParam actions: () => void = this.emptyActions;
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;
  @Local originY: number = 0;
  private measuredOrigin: boolean = false;

  aboutToAppear(): void {
    readStatusBarVp(this.getUIContext().getHostContext() as common.UIAbilityContext)
      .then((height: number): void => { this.statusBarH = height; }).catch(() => {});
  }

  @Builder emptyActions() {}

  build() {
    Column() {
      Row({ space: 12 }) {
        Text(this.title).fontSize(UiLayout.ROOT_TITLE).fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT_MAIN).layoutWeight(1)
        this.actions()
      }.width('100%').constraintSize({ minHeight: 44 }).alignItems(VerticalAlign.Center)
    }
    .width('100%').padding({ left: this.gutter, right: this.gutter,
      top: Math.max(0, this.statusBarH - this.originY) + 8, bottom: 8 })
    .onAreaChange((_old: Area, area: Area): void => {
      // 只捕获初始宿主起点；我的页滚动不能反过来增加安全区内距。
      if (!this.measuredOrigin) {
        this.measuredOrigin = true;
        this.originY = Number(area.globalPosition.y);
      }
    })
  }
}

/** 页面流内的普通二级页顶栏；状态栏避让由宿主统一承担。 */
@ComponentV2
export struct PageHeader {
  @Param title: string = '';
  @Event onBack: () => void = (): void => {};
  @BuilderParam actions: () => void = this.emptyActions;

  @Builder emptyActions() {}

  build() {
    Row({ space: 8 }) {
      GlassBackButton({ onTap: (): void => { this.onBack(); } })
      Text(this.title).fontSize(UiLayout.HEADER_TITLE).fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_MAIN).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      this.actions()
    }
    .width('100%').constraintSize({ minHeight: UiLayout.HEADER_HEIGHT })
    .padding({ left: UiLayout.PAGE_GUTTER, right: UiLayout.PAGE_GUTTER, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }
}
