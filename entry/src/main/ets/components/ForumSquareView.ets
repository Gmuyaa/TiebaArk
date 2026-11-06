import { common } from '@kit.AbilityKit';
import { ForumSquareVM } from '../viewmodel/ForumSquareVM';
import { SquareCategory, SquareForum } from '../model/ForumSquare';
import { NavigationService } from '../navigation/AppNavigation';
import { AppTheme } from '../theme/Theme';
import { formatCount } from '../model/UserProfile';
import { ForumAvatarImage } from './ForumAvatarImage';
import { PageState } from './PageState';
import { authSession, AuthSession } from '../auth/AuthSession';
import { FollowButton } from './FollowButton';

@ComponentV2
export struct ForumSquareView {
  @Param active: boolean = true;
  @Local vm: ForumSquareVM = new ForumSquareVM();
  @Local auth: AuthSession = authSession;
  private account: string = authSession.sessionKey();
  @Monitor('auth.snapshot')
  onAccountChanged(): void {
    const account: string = authSession.sessionKey();
    if (this.account === account) { return; }
    this.account = account;
    void this.vm.reset(this.context());
  }
  @Param bottomBarOcclusion: number = 0;
  private forumsScroller: Scroller = new Scroller();
  private subcategoryScroller: Scroller = new Scroller();
  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }
  aboutToAppear(): void { void this.vm.load(this.context()); }
  aboutToDisappear(): void { this.vm.dispose(); }
  private select(id: string): void {
    if (this.vm.selected === id) { return; }
    this.forumsScroller.scrollTo({ xOffset: 0, yOffset: 0 });
    this.subcategoryScroller.scrollTo({ xOffset: 0, yOffset: 0 });
    void this.vm.select(this.context(), id);
  }
  @Builder
  Category(name: string, id: string) {
    Row({ space: 9 }) {
      Column().width(3).height(18).borderRadius(2)
        .backgroundColor(this.vm.selected === id ? AppTheme.ACCENT_DARK : Color.Transparent)
        .accessibilityLevel('no')
      Text(name).fontSize(14)
        .fontWeight(this.vm.selected === id ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.vm.selected === id ? AppTheme.ACCENT_DARK : AppTheme.TEXT_SUB)
        .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
    }.width('100%').constraintSize({ minHeight: 44 }).padding({ top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .id(`square-category-${id}`)
      .accessibilityGroup(true).accessibilityText(name)
      .accessibilitySelected(this.vm.selected === id)
      .onClick((): void => { this.select(id); })
  }
  @Builder
  Forum(item: SquareForum) {
    Row({ space: 8 }) {
      ForumAvatarImage({ url: item.avatar, forumName: item.name, avatarSize: 36, radius: 8 })
      Column({ space: 3 }) {
        Text(item.name.endsWith('吧') ? item.name : `${item.name}吧`).fontSize(14)
          .fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT_MAIN)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.members.length > 0) {
          Text(`关注 ${formatCount(Number(item.members))}`)
            .fontSize(12).fontColor(AppTheme.TEXT_SUB).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (item.threads.length > 0) {
          Text(`帖子 ${formatCount(Number(item.threads))}`)
            .fontSize(12).fontColor(AppTheme.TEXT_SUB).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (item.followId() > 0) {
        FollowButton({ kind: 'forum', targetId: item.followId(), targetName: item.name })
          .flexShrink(0)
      }
    }.width('100%').padding({ left: 10, right: 10, top: 10, bottom: 10 })
      .onClick((): void => { NavigationService.openForum({ forumName: item.name }); })
  }
  @Builder
  Subcategory(name: string) {
    Column({ space: 6 }) {
      Text(name).fontSize(14).maxLines(1)
        .fontWeight(this.vm.selectedSub === name ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.vm.selectedSub === name ? AppTheme.ACCENT_DARK : AppTheme.TEXT_SUB)
      Row().width(20).height(2).borderRadius(1)
        .backgroundColor(this.vm.selectedSub === name ? AppTheme.ACCENT_DARK : Color.Transparent)
        .accessibilityLevel('no')
    }.constraintSize({ minHeight: 44, minWidth: 52 })
      .padding({ left: 12, right: 12, top: 8, bottom: 6 })
      .justifyContent(FlexAlign.Center).flexShrink(0)
      .id(`square-subcategory-${name}`)
      .accessibilityGroup(true).accessibilityText(name)
      .accessibilitySelected(this.vm.selectedSub === name)
      .onClick((): void => {
        this.forumsScroller.scrollTo({ xOffset: 0, yOffset: 0 });
        void this.vm.selectSub(this.context(), name);
      })
  }
  @Builder
  Subcategories() {
    Scroll(this.subcategoryScroller) {
      Row({ space: 4 }) {
        ForEach(this.vm.subcategories, (name: string) => {
          this.Subcategory(name)
        }, (name: string): string => `${this.vm.selected}-${name}`)
      }.padding({ left: 10, right: 10 })
    }.width('100%').align(Alignment.TopStart)
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      .id('square-subcategories')
  }
  build() {
    Row() {
      List({ space: 2 }) {
        if (this.vm.categories.length === 0) { ListItem() { this.Category('推荐', '推荐') } }
        ForEach(this.vm.categories, (item: SquareCategory) => {
          ListItem() { this.Category(item.name, item.id) }
        }, (item: SquareCategory): string => item.id)
        ListItem() {
          Column().width('100%').height(this.bottomBarOcclusion)
            .accessibilityLevel('no').hitTestBehavior(HitTestMode.None)
        }.id('square-category-bottom-occlusion')
      }.width(88).height('100%').padding({ left: 8, right: 8 }).scrollBar(BarState.Off)
        .id('square-categories')
      Column() {
        if (this.vm.subcategories.length > 0) { this.Subcategories() }
        List({ scroller: this.forumsScroller }) {
        if (this.vm.error.length > 0) {
          ListItem() {
            PageState({ title: '加载失败', message: this.vm.error, actionLabel: '重试',
              onAction: (): void => { void this.vm.load(this.context(), this.vm.loaded && this.vm.hasMore); } })
          }
        }
        ForEach(this.vm.forums, (item: SquareForum) => {
          ListItem() { this.Forum(item) }
        }, (item: SquareForum): string => `${this.vm.selected}-${this.vm.selectedSub}-${item.id}`)
        if (this.vm.loading) {
          ListItem() { PageState({ loading: true, message: '正在加载…' }) }
        } else if (this.vm.loaded && this.vm.forums.length === 0 && this.vm.error.length === 0) {
          ListItem() { PageState({ message: '暂无贴吧' }) }
        } else if (this.vm.hasMore && this.vm.error.length === 0) {
          ListItem() {
            PageState({ compact: true, actionLabel: '加载更多',
              onAction: (): void => { void this.vm.load(this.context(), true); } })
          }
        }
        ListItem() {
          Column().width('100%').height(this.bottomBarOcclusion)
            .accessibilityLevel('no').hitTestBehavior(HitTestMode.None)
        }.id('square-forums-bottom-occlusion')
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
        .onReachEnd((): void => {
          if (this.active && this.vm.error.length === 0) { void this.vm.load(this.context(), true); }
        })
      }.layoutWeight(1).height('100%')
    }.width('100%').height('100%').alignItems(VerticalAlign.Top)
  }
}
