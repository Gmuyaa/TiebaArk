/** 搜索页：输入、历史记录与结果导航。 */

import { UiLayout } from '../common/appearance/UiLayout';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { AppTheme } from '../theme/Theme';
import { SearchPageHeader } from '../components/SearchPageHeader';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { addSearchHistory, clearSearchHistory, loadSearchHistory } from '../utils/SearchHistory';
import { NavigationService, SearchResultParams } from '../navigation/AppNavigation';

@ComponentV2
export struct SearchPage {
  /** 搜索框内容 */
  @Local input: string = '';
  /** 搜索历史，最近在前；进入页面与从结果页返回时都重新读一次 */
  @Local history: string[] = [];
  /** 跳转结果页期间防重复提交（连按搜索键会压两个同样的页面进栈） */
  private submitting: boolean = false;
  /** 状态栏高度（vp），见 SafeArea.ets */
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;
  @Local headerHeight: number = STATUS_BAR_FALLBACK_VP + 90;

  aboutToAppear(): void {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    readStatusBarVp(context).then((vp: number) => {
      this.statusBarH = vp;
    }).catch(() => {
      // 拿不到就保持兜底值
    });
    this.reloadHistory();
  }

  private reloadHistory(): void {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    loadSearchHistory(context).then((words: string[]) => {
      this.history = words;
    }).catch(() => {
      // 读失败按无历史处理
    });
  }

  /**
   * 执行搜索：trim → 空词不动作 → 记历史 → 进结果页。
   * 历史写入失败不阻断跳转（SearchHistory 内部已兜底）。
   */
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
      // 历史落库失败照常搜索
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
      Stack({ alignContent: Alignment.Top }) {
        if (this.history.length > 0) {
          Scroll() {
            Column() {
              Row().height(this.headerHeight + UiLayout.SEARCH_CONTENT_GAP).width('100%')
              this.HistorySection()
            }.width('100%')
          }
            .width('100%').height('100%').scrollBar(BarState.Off).align(Alignment.TopStart)
            .padding({ left: UiLayout.PAGE_GUTTER, right: UiLayout.PAGE_GUTTER })
        }
        // 无历史时整个历史区不渲染（不需要复杂空状态）
        this.TopBar()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppTheme.CARD)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    }
    // 搜索栏与历史标题固定在同一片沉浸材质上，历史内容从后方经过。
    .hideTitleBar(true)
    // 搜索前后保持顶栏原位，避免整页滑动让搜索框跟着移动。
    .systemTransition(NavigationSystemTransitionType.NONE)
    .onBackPressed((): boolean => { this.goBack(); return true; })
    .onShown(() => {
      this.reloadHistory();
    })
  }

  /** 顶部：返回按钮 + 与首页一致的圆角搜索框 */
  @Builder
  TopBar() {
    SearchPageHeader({ text: this.input, statusBarHeight: this.statusBarH,
      secondaryHeight: this.history.length > 0 ? 32 : 0,
      secondary: (): void => { this.HistoryHeading(); },
      onHeightChange: (height: number): void => { this.headerHeight = height; },
      onChange: (value: string): void => { this.input = value; },
      onSubmit: (): void => { this.submit(this.input); },
      onBack: (): void => { this.goBack(); } })
  }

  /** 历史标题与清空入口固定在整片材质内；无历史时一同收起。 */
  @Builder
  HistoryHeading() {
    if (this.history.length > 0) {
      Column() {
        Row() {
          Text('搜索历史')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT_MAIN)
          Blank()
          // 无历史时整个区不渲染，清空按钮不会空转。
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(16).maxFontScale(1).width(16).height(24)
            .responseRegion({ x: -12, y: -8, width: 40, height: 40 })
            .accessibilityText('清空搜索历史')
            .fontColor([AppTheme.TEXT_MUTED])
            .onClick(() => { this.clearHistory(); })
        }
        .width('100%')
        .constraintSize({ minHeight: 24 }).alignItems(VerticalAlign.Center)
        .id('search-history-heading')
      }
      .width('100%')
      .padding({ left: UiLayout.PAGE_GUTTER, right: UiLayout.PAGE_GUTTER, bottom: 8 })
    }
  }

  /** 自动换行标签；首屏从顶栏材质下沿之外再留共同间距。 */
  @Builder
  HistorySection() {
    // Flex 随文字换行；超长词单行省略，不会把页面撑破。
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.history, (word: string) => {
        Row() {
          Text(word)
            .fontSize(14)
            .fontColor(AppTheme.TEXT_MAIN)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
        }
        .constraintSize({ maxWidth: '100%', minHeight: 28 })
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(16)
        .backgroundColor(AppTheme.BG)
        .margin({ right: 10, bottom: 12 })
        .id('search-history-tag')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.input = word;
          this.submit(word);
        })
      }, (word: string) => word)
    }
    .width('100%')
  }
}
