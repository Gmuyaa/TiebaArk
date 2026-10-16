

import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { AppTheme } from '../theme/Theme';
import { GlassBackButton } from '../components/GlassBackButton';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { addSearchHistory, clearSearchHistory, loadSearchHistory } from '../utils/SearchHistory';
import { NavigationService, SearchResultParams } from '../navigation/AppNavigation';

@ComponentV2
export struct SearchPage {

  @Local input: string = '';

  @Local history: string[] = [];

  private submitting: boolean = false;

  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;

  aboutToAppear(): void {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    readStatusBarVp(context).then((vp: number) => {
      this.statusBarH = vp;
    }).catch(() => {

    });
    this.reloadHistory();
  }

  private reloadHistory(): void {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    loadSearchHistory(context).then((words: string[]) => {
      this.history = words;
    }).catch(() => {

    });
  }

  private submit(rawWord: string): void {
    if (this.submitting) {
      return;
    }
    const word: string = rawWord.trim();
    if (word.length === 0) {
      return;
    }
    this.submitting = true;
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    addSearchHistory(context, word).then((words: string[]) => {
      this.history = words;
    }).catch(() => {

    });
    this.input = word;

    NavigationService.openSearchResult({ word: word } as SearchResultParams);
    this.submitting = false;
  }

  private goBack(): void {
    NavigationService.back();
  }

  private clearHistory(): void {
    if (this.history.length === 0) {
      return;
    }
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    clearSearchHistory(context).then(() => {
      this.history = [];
    }).catch(() => {
      promptAction.showToast({ message: '清空失败，请重试', duration: 1600 });
    });
  }

  build() {

    HdsNavDestination() {
      Column() {
        this.TopBar()

        if (this.history.length > 0) {
          this.HistorySection()
        }

      }
      .width('100%')
      .height('100%')
      .padding({ left: 24, right: 24, top: this.statusBarH + 12 })
      .backgroundColor(AppTheme.CARD)
      .alignItems(HorizontalAlign.Start)
    }

    .hideTitleBar(true)
    .onShown(() => {
      this.reloadHistory();
    })
  }

  @Builder
  TopBar() {
    Row({ space: 14 }) {

      GlassBackButton({
        onTap: (): void => {
          this.goBack();
        }
      })

      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(19)
          .fontColor([AppTheme.ICON])
        TextInput({ text: this.input, placeholder: '搜索' })
          .fontSize(16)
          .placeholderColor(AppTheme.TEXT_SUB)
          .placeholderFont({ size: 16 })
          .height(54)
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .padding(0)
          .onSubmit(() => {
            this.submit(this.input);
          })
          .onChange((value: string) => {
            this.input = value;
          })
      }
      .layoutWeight(1)
      .height(54)
      .borderRadius(27)
      .backgroundColor(AppTheme.BG)
      .padding({ left: 18, right: 18 })
      .shadow({ radius: 10, color: '#0A000000', offsetY: 2 })

      Button() {
        SymbolGlyph($r('sys.symbol.qrcode'))
          .fontSize(22).fontColor([AppTheme.ICON])
      }.width(44).height(44).backgroundColor(Color.Transparent)
        .accessibilityText('扫一扫')
        .onClick(() => { NavigationService.openScanPage(); })
    }
    .width('100%')
    .margin({ top: 10, bottom: 26 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  HistorySection() {
    Column({ space: 14 }) {
      Row() {
        Text('搜索历史')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_MAIN)
        Blank()

        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(19)
          .fontColor([AppTheme.ICON])
          .onClick(() => {
            this.clearHistory();
          })
      }
      .width('100%')

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.history, (word: string) => {
          Row() {
            Text(word)
              .fontSize(14)
              .fontColor(AppTheme.TEXT_MAIN)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .constraintSize({ maxWidth: '100%' })
          .height(40)
          .padding({ left: 17, right: 17 })
          .borderRadius(20)
          .backgroundColor(AppTheme.BG)
          .margin({ right: 10, bottom: 12 })
          .justifyContent(FlexAlign.Center)
          .onClick(() => {

            this.input = word;
            this.submit(word);
          })
        }, (word: string) => word)
      }
      .width('100%')
    }
    .width('100%')
  }
}
