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
    Text(name).fontSize(13)
      .fontWeight(this.vm.selected === id ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.vm.selected === id ? AppTheme.ACCENT_DARK : AppTheme.TEXT_SUB)
      .width('100%').constraintSize({ minHeight: 48 }).padding({ left: 8, right: 8, top: 9, bottom: 9 })
      .backgroundColor(this.vm.selected === id ? AppTheme.ACCENT_LIGHT : Color.Transparent)
      .borderRadius(10).textAlign(TextAlign.Center)
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
        FollowButton({ kind: 'forum', targetId: item.followId(), targetName: item.name, forumStyle: true })
          .flexShrink(0)
      }
    }.width('100%').padding({ left: 10, right: 10, top: 10, bottom: 10 })
      .onClick((): void => { NavigationService.openForum({ forumName: item.name }); })
  }
  @Builder
  Subcategories() {
    Scroll(this.subcategoryScroller) {
      Row({ space: 6 }) {
        ForEach(this.vm.subcategories, (name: string) => {
          Text(name).fontSize(12).padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .constraintSize({ minHeight: 48 })
            .fontColor(this.vm.selectedSub === name ? AppTheme.ACCENT_DARK : AppTheme.TEXT_SUB)
            .backgroundColor(this.vm.selectedSub === name ? AppTheme.ACCENT_LIGHT : Color.Transparent)
            .borderRadius(10).accessibilitySelected(this.vm.selectedSub === name)
            .onClick((): void => {
              this.forumsScroller.scrollTo({ xOffset: 0, yOffset: 0 });
              void this.vm.selectSub(this.context(), name);
            })
        }, (name: string): string => `${this.vm.selected}-${name}`)
      }.padding({ left: 10, right: 10 })
    }.width('100%').align(Alignment.TopStart)
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
  }
  build() {
    Row() {
      List({ space: 4 }) {
        if (this.vm.categories.length === 0) { ListItem() { this.Category('推荐', '推荐') } }
        ForEach(this.vm.categories, (item: SquareCategory) => {
          ListItem() { this.Category(item.name, item.id) }
        }, (item: SquareCategory): string => item.id)
        ListItem() {
          Column().width('100%').height(this.bottomBarOcclusion)
            .accessibilityLevel('no').hitTestBehavior(HitTestMode.None)
        }.id('square-category-bottom-occlusion')
      }.width(88).height('100%').padding({ left: 6, right: 6 }).scrollBar(BarState.Off)
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
