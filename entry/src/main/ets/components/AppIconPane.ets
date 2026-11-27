/** 设置 → 外观与布局 → 应用图标：网格展示默认与备用图标，点选后直调系统接口切换。 */
import { ALL_APP_ICON_OPTIONS, AppIconOption, appIconLabel } from '../model/AppIcon';
import { appIconPreviewResource, appIconStore } from '../common/appearance/AppIconStore';
import { SettingsLayout } from '../common/appearance/SettingsLayout';
import { AppTheme } from '../theme/Theme';
import { SettingsCard, SettingsStatusKind, SettingsStatusLine } from './SettingsComponents';

const GRID_COLUMNS: number = 3;
const ICON_SIZE_VP: number = 64;
const ICON_RADIUS_VP: number = 16;

function buildIconRows(): AppIconOption[][] {
  const rows: AppIconOption[][] = [];
  for (let i = 0; i < ALL_APP_ICON_OPTIONS.length; i += GRID_COLUMNS) {
    rows.push(ALL_APP_ICON_OPTIONS.slice(i, i + GRID_COLUMNS));
  }
  return rows;
}

@ComponentV2
export struct AppIconPane {
  private readonly iconRows: AppIconOption[][] = buildIconRows();

  aboutToAppear(): void {
    void appIconStore.refresh();
  }

  private async pickIcon(option: AppIconOption): Promise<void> {
    if (appIconStore.busy) { return; }
    const ok: boolean = await appIconStore.select(option.name);
    if (ok) {
      try {
        this.getUIContext().getPromptAction().showToast({
          message: `已切换为「${appIconLabel(option.name)}」图标`,
          duration: 1800
        });
      } catch (_) {}
    }
  }

  build() {
    Column() {
      SettingsCard({
        content: (): void => { this.IconGrid(); }
      })
      if (appIconStore.loadError.length > 0) {
        SettingsStatusLine({
          kind: SettingsStatusKind.ERROR,
          message: appIconStore.loadError,
          retryLabel: '重试',
          onRetry: (): void => { void appIconStore.refresh(); }
        })
      }
      if (appIconStore.switchError.length > 0) {
        SettingsStatusLine({
          kind: SettingsStatusKind.ERROR,
          message: appIconStore.switchError
        })
      }
    }
    .width('100%')
  }

  @Builder
  private IconGrid() {
    Column({ space: 20 }) {
      ForEach(this.iconRows, (row: AppIconOption[], rowIndex: number) => {
        Row() {
          ForEach(row, (option: AppIconOption) => {
            this.IconTile(option);
          }, (option: AppIconOption) => option.name.length > 0 ? option.name : 'default')
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceAround)
      }, (_row: AppIconOption[], rowIndex: number) => `app_icon_row_${rowIndex}`)
    }
    .width('100%')
    .padding({ top: 20, bottom: 20, left: 12, right: 12 })
    .opacity(appIconStore.busy ? 0.6 : 1)
  }

  @Builder
  private IconTile(option: AppIconOption) {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Image(appIconPreviewResource(option.name))
          .width(ICON_SIZE_VP)
          .height(ICON_SIZE_VP)
          .borderRadius(ICON_RADIUS_VP)
          .objectFit(ImageFit.Cover)
          .border({
            width: 0.5,
            color: AppTheme.DIVIDER
          })
      }
      .padding(3)
      .borderRadius(ICON_RADIUS_VP + 3)
      .border({
        width: 2,
        color: appIconStore.currentName === option.name ? AppTheme.ACCENT : Color.Transparent
      })

      Text(option.label)
        .fontSize(SettingsLayout.SUB_SIZE)
        .fontWeight(appIconStore.currentName === option.name ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(appIconStore.currentName === option.name ? AppTheme.ACCENT : AppTheme.TEXT_MAIN)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .enabled(!appIconStore.busy)
    .onClick((): void => {
      void this.pickIcon(option);
    })
    .id(`settings-app-icon-${option.name.length > 0 ? option.name : 'default'}`)
  }
}
