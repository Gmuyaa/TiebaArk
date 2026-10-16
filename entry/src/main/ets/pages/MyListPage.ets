import { PullRefreshHeader, PULL_REFRESH_OFFSET } from '../components/RefreshSpinner';

import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { AppTheme } from '../theme/Theme';
import { GlassBackButton } from '../components/GlassBackButton';
import { ForumAvatarImage, forumAvatarRadius } from '../components/ForumAvatarImage';
import { MyListItem, MyListVM, kindTitle, parseKind } from '../viewmodel/MyListVM';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { MyListParams, NavigationService } from '../navigation/AppNavigation';
import { PostContentInline } from '../components/PostContentInline';
import { POST_BODY_SIZE } from '../common/appearance/PostTypography';
import { openContentPiece } from '../navigation/ContentNavigation';
import { ContentPiece } from '../model/ThreadDetail';

const DELETED_LABEL: string = '该帖子已被删除';

@ComponentV2
export struct MyListPage {
  @Local pullRefreshDragging: boolean = false;

  @Param routeParams: MyListParams | undefined = undefined;
  @Local vm: MyListVM = new MyListVM();
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;
  @Local refreshing: boolean = false;

  aboutToAppear(): void {

    const kind: string | undefined = this.routeParams?.kind;
    if (kind !== undefined) {
      this.vm.kind = parseKind(kind);
    }
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    readStatusBarVp(context).then((vp: number) => {
      this.statusBarH = vp;
    }).catch(() => {

    });
    this.vm.load(context);
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToDisappear(): void { this.vm.dispose(); }

  private confirmRemoveFavorites(): void {
    if (this.vm.removing || this.vm.selected.length === 0) { return; }
    const confirmed: number[] = this.vm.selected.slice();
    const confirmedOwner: string = this.vm.selectionOwner();
    promptAction.showDialog({
      title: '取消收藏',
      message: `将取消选中的 ${this.vm.selected.length} 条收藏。`,
      buttons: [{ text: '取消', color: AppTheme.TEXT_SUB }, { text: '取消收藏', color: AppTheme.ACCENT_DARK }]
    }).then((result) => {
      if (result.index === 1) { this.vm.removeSelected(this.hostContext(), confirmed, confirmedOwner); }
    }).catch(() => {});
  }

  private openThread(item: MyListItem): void {
    if (this.vm.kind === 'fav' && this.vm.managing) { this.vm.toggleSelected(item.tid); return; }
    if (item.tid <= 0) {
      return;
    }

    if (item.isDeleted) {
      promptAction.showToast({ message: DELETED_LABEL, duration: 1500 });
      return;
    }

    NavigationService.openThreadDetail({
      tid: item.tid, forumName: item.forumName,
      targetPid: this.vm.kind === 'reply' && item.pid > 0 ? item.pid : undefined
    });
  }

  private goBack(): void {
    NavigationService.back();
  }

  private forumLabel(name: string): string {
    return name.endsWith('吧') ? name : `${name}吧`;
  }

  private emptyText(): string {
    if (this.vm.kind === 'history') {
      return '还没有浏览记录，去看几个帖子就会出现在这里';
    }
    if (this.vm.kind === 'fav') {
      return '还没有收藏的帖子';
    }
    if (this.vm.kind === 'reply') {
      return '还没有发布过回复';
    }
    return '还没有发布过主题帖';
  }

  @Builder
  PullHeader() { PullRefreshHeader({ active: this.refreshing || this.pullRefreshDragging }) }

  build() {

    HdsNavDestination() {
      Column() {

        Row() {

          GlassBackButton({
            onTap: (): void => {
              this.goBack();
            }
          })

        Text(kindTitle(this.vm.kind))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_MAIN)
          .margin({ left: 10 })

        Blank()

        if (this.vm.kind === 'fav' && this.vm.items.length > 0) {
          Text(this.vm.managing ? '完成' : '管理').fontSize(13).fontColor(AppTheme.ACCENT_DARK)
            .enabled(!this.vm.removing).onClick(() => { this.vm.toggleManaging(); })
        }

        if (this.vm.kind === 'history' && this.vm.items.length > 0) {
          Text('清空')
            .fontSize(13)
            .fontColor(AppTheme.ACCENT_DARK)
            .onClick(() => {
              promptAction.showDialog({
                title: '清空浏览历史',
                message: '将删除本机的全部浏览记录，且无法恢复。',
                buttons: [
                  { text: '取消', color: AppTheme.TEXT_SUB },
                  { text: '清空', color: AppTheme.ACCENT_DARK }
                ]
              }).then((result) => {
                if (result.index === 1) {
                  this.vm.clearHistory(this.hostContext());
                }
              }).catch(() => {

              });
            })
        }
      }
      .width('100%')
      .height(52)
      .padding({ left: 12, right: 16 })

      .backgroundColor(Color.Transparent)

      if (this.vm.kind === 'fav') {
        this.FavoritesBody()
      } else if (this.vm.kind === 'reply') {
        this.ReplyBody()
      } else if (this.vm.loading && !this.vm.loadedOnce) {
        Column() {
          Text('正在加载…')
            .fontSize(14)
            .fontColor(AppTheme.TEXT_SUB)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.vm.errorText.length > 0) {
        Column({ space: 10 }) {
          Text(this.vm.errorText)
            .fontSize(14)
            .fontColor(AppTheme.TEXT_SUB)
            .textAlign(TextAlign.Center)
            .padding({ left: 36, right: 36 })
          Text('点击重试')
            .fontSize(13)
            .fontColor(AppTheme.ACCENT_DARK)
            .onClick(() => {
              this.vm.load(this.hostContext());
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.vm.items.length === 0) {
        Column() {
          Text(this.emptyText())
            .fontSize(14)
            .fontColor(AppTheme.TEXT_SUB)
            .textAlign(TextAlign.Center)
            .padding({ left: 36, right: 36 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.vm.items, (item: MyListItem) => {
            ListItem() {
              this.CardItem(item)
            }
            .margin({ left: 12, right: 12, top: 5, bottom: 5 })
          }, (item: MyListItem) => `${item.tid}-${item.title}-${item.forumAvatar}-${item.isDeleted}`)
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(AppTheme.BG)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarH })
    .backgroundColor(AppTheme.BG)
    }

    .hideTitleBar(true)
  }

  @Builder
  FavoritesBody() {
    Column() {
      if (this.vm.managing) {
        Row() {
          Text(this.vm.selected.length === this.vm.items.length ? '取消全选' : '全选已加载')
            .fontSize(13).fontColor(AppTheme.ACCENT_DARK)
            .enabled(!this.vm.removing).onClick(() => { this.vm.selectLoaded(); })
          Blank()
          Text(this.vm.removing ? '正在取消收藏…' : `取消收藏 (${this.vm.selected.length})`)
            .fontSize(13).fontColor(AppTheme.ACCENT_DARK)
            .enabled(!this.vm.removing && !this.vm.loading && !this.vm.loadingMore && this.vm.selected.length > 0)
            .onClick(() => { this.confirmRemoveFavorites(); })
        }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 })
      }
      if (this.vm.manageNotice.length > 0) {
        Text(this.vm.manageNotice).fontSize(12).fontColor(AppTheme.TEXT_SUB)
          .width('100%').padding(12)
      }
      Refresh({ refreshing: $$this.refreshing, builder: (): void => { this.PullHeader(); } }) {
        Column() {
          if (this.vm.items.length === 0) {
            Column({ space: 12 }) {
              if (this.vm.loading) {
                LoadingProgress().width(28).height(28).color(AppTheme.ACCENT_DARK)
              } else {
                Text(this.vm.errorText.length > 0 ? this.vm.errorText : this.emptyText())
                  .fontSize(14).fontColor(AppTheme.TEXT_SUB).textAlign(TextAlign.Center)
                Text('点击重新加载').fontSize(13).fontColor(AppTheme.ACCENT_DARK)
                  .onClick(() => { this.vm.load(this.hostContext()); })
              }
            }.padding({ left: 32, right: 32 }).width('100%').layoutWeight(1)
              .justifyContent(FlexAlign.Center)
          } else {
            if (this.vm.errorText.length > 0) {
              Text(`刷新失败：${this.vm.errorText}`).fontSize(12).fontColor(AppTheme.TEXT_SUB).padding(12)
            }
            List({ space: 10 }) {
              ForEach(this.vm.items, (item: MyListItem) => {
                ListItem() {
                  Row({ space: 8 }) {
                    if (this.vm.managing) {
                      Checkbox().select(this.vm.selected.includes(item.tid)).enabled(!this.vm.removing)
                        .onChange(() => { this.vm.toggleSelected(item.tid); })
                    }
                    Column() { this.CardItem(item) }.layoutWeight(1)
                  }.width('100%')
                }
              }, (item: MyListItem) => `${item.tid}-${item.forumAvatar}-${item.isDeleted}`)
              ListItem() {
                Text(this.vm.loadingMore ? '正在加载更多…' : (this.vm.pagingError.length > 0
                  ? '加载失败，点击重试' : (this.vm.hasMore ? '上拉加载更多收藏' : '下拉刷新收藏')))
                  .fontSize(12).fontColor(AppTheme.TEXT_SUB).width('100%').textAlign(TextAlign.Center)
                  .padding({ top: 12, bottom: 12 }).onClick(() => { this.vm.loadMore(this.hostContext()); })
              }
            }.padding({ left: 12, right: 12, top: 8 }).width('100%').layoutWeight(1)
              .edgeEffect(EdgeEffect.Spring).onReachEnd(() => {
                if (this.vm.pagingError.length === 0) { this.vm.loadMore(this.hostContext()); }
              })
          }
        }.width('100%').height('100%')
      }.refreshOffset(PULL_REFRESH_OFFSET)
        .onStateChange((state: RefreshStatus) => {
          this.pullRefreshDragging = state === RefreshStatus.Drag || state === RefreshStatus.OverDrag;
        }).width('100%').layoutWeight(1).onRefreshing(() => {
        this.vm.load(this.hostContext()).finally(() => { this.refreshing = false; });
      })
    }.width('100%').layoutWeight(1)
  }

  @Builder
  ReplyBody() {
    Refresh({ refreshing: $$this.refreshing, builder: (): void => { this.PullHeader(); } }) {
      Column() {
        if (this.vm.items.length === 0) {
          Column({ space: 12 }) {
            if (this.vm.loading) {
              LoadingProgress().width(28).height(28).color(AppTheme.ACCENT_DARK)
              Text('正在加载回复…').fontSize(14).fontColor(AppTheme.TEXT_SUB)
            } else {
              SymbolGlyph(this.vm.errorText.length > 0
                ? $r('sys.symbol.exclamationmark_circle') : $r('sys.symbol.message'))
                .fontSize(36).fontColor([AppTheme.TEXT_MUTED])
              Text(this.vm.errorText.length > 0 ? this.vm.errorText : this.emptyText())
                .fontSize(14).fontColor(AppTheme.TEXT_SUB).textAlign(TextAlign.Center)
              Text(this.vm.errorText.length > 0 ? '点击重试' : '下拉刷新，查看最新回复')
                .fontSize(13).fontColor(AppTheme.ACCENT_DARK)
                .onClick(() => { this.vm.load(this.hostContext()); })
            }
          }
          .padding({ left: 32, right: 32 }).width('100%').layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          if (this.vm.errorText.length > 0) {
            Text(`刷新失败：${this.vm.errorText} · 点击重试`)
              .fontSize(12).fontColor(AppTheme.TEXT_SUB).padding(12).width('100%')
              .onClick(() => { this.vm.load(this.hostContext()); })
          }
          List({ space: 10 }) {
            ForEach(this.vm.items, (item: MyListItem) => {
              ListItem() { this.ReplyCard(item) }
            }, (item: MyListItem) => `${item.key}-${item.forumAvatar}-${item.title}-${item.content}-${item.meta}`)
            ListItem() {
              Text(this.vm.loadingMore ? '正在加载更多…' : (this.vm.pagingError.length > 0
                ? '加载失败，点击重试' : (this.vm.hasMore ? '上拉加载更多回复' : '暂无更多回复')))
                .fontSize(12).fontColor(AppTheme.TEXT_SUB).width('100%')
                .textAlign(TextAlign.Center).padding({ top: 14, bottom: 24 })
                .onClick(() => { this.vm.loadMore(this.hostContext()); })
            }
          }
          .padding({ left: 12, right: 12, top: 8 }).width('100%').layoutWeight(1)
          .edgeEffect(EdgeEffect.Spring)
          .onReachEnd(() => {
            if (this.vm.pagingError.length === 0) {
              this.vm.loadMore(this.hostContext());
            }
          })
        }
      }
      .width('100%').height('100%')
    }.refreshOffset(PULL_REFRESH_OFFSET)
        .onStateChange((state: RefreshStatus) => {
          this.pullRefreshDragging = state === RefreshStatus.Drag || state === RefreshStatus.OverDrag;
        })
    .width('100%').layoutWeight(1)
    .onRefreshing(() => {
      this.vm.load(this.hostContext()).finally(() => { this.refreshing = false; });
    })
  }

  @Builder
  ReplyCard(item: MyListItem) {
    Column({ space: 12 }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.message')).fontSize(14).fontColor([AppTheme.ACCENT_DARK])
        Text(item.isComment ? '楼中楼回复' : '我的回复')
          .fontSize(12).fontColor(AppTheme.ACCENT_DARK)
        Blank()
        if (item.meta.length > 0) {
          Text(item.meta).fontSize(12).fontColor(AppTheme.TEXT_MUTED)
        }
      }
      .width('100%')
      Text() {
        if (item.pieces.length > 0) {
          PostContentInline({ pieces: item.pieces, emojiSize: 21,
            textColor: AppTheme.TEXT_MAIN, accentColor: AppTheme.ACCENT_DARK,
            onActivate: (piece: ContentPiece): void => { openContentPiece(piece, this.getUIContext()); } })
        } else {
          Span(item.content.length > 0 ? item.content : '回复内容未返回，点击查看原帖')
        }
      }
      .fontSize(POST_BODY_SIZE).fontColor(AppTheme.TEXT_MAIN).lineHeight(24)
      .maxLines(6).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      Column({ space: 8 }) {
        Text(item.title.length > 0 ? item.title : '查看原帖')
          .fontSize(13).fontColor(AppTheme.TEXT_SUB).maxLines(2).lineHeight(19)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Row({ space: 6 }) {

          if (item.forumAvatar.length > 0 || item.forumName.length > 0) {
            ForumAvatarImage({ url: item.forumAvatar, forumName: item.forumName,
              avatarSize: 18, radius: forumAvatarRadius(18), fontSize: 10 })
          }
          if (item.forumName.length > 0) {
            Text(this.forumLabel(item.forumName)).fontSize(11).fontColor(AppTheme.TEXT_MUTED)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          } else {
            Blank()
          }
          Text('查看回复').fontSize(11).fontColor(AppTheme.ACCENT_DARK)
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(10).fontColor([AppTheme.ACCENT_DARK])
        }
        .width('100%')
      }
      .width('100%').padding(10).backgroundColor(AppTheme.BG).borderRadius(8)
    }
    .alignItems(HorizontalAlign.Start).width('100%').padding(14)
    .backgroundColor(AppTheme.CARD).borderRadius(12)
    .onClick(() => { this.openThread(item); })
  }

  @Builder
  CardItem(item: MyListItem) {
    Row({ space: 12 }) {

      Column() {
        Text(item.title)
          .fontSize(16)

          .fontColor(item.isDeleted ? AppTheme.TEXT_SUB : AppTheme.TEXT_MAIN)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(22)

        Row({ space: 6 }) {
          if (item.isDeleted) {

            Text(DELETED_LABEL)
              .fontSize(12)
              .fontColor(AppTheme.TEXT_SUB)
              .maxLines(1)
          } else {
            if (item.forumAvatar.length > 0 || item.forumName.length > 0) {

              ForumAvatarImage({ url: item.forumAvatar, forumName: item.forumName,
                avatarSize: 20, radius: forumAvatarRadius(20), fontSize: 11 })
            }
            if (item.forumName.length > 0) {
              Text(this.forumLabel(item.forumName))
                .fontSize(12)
                .fontColor(AppTheme.TEXT_SUB)
                .maxLines(1)
            }
          }
        }
        .margin({ top: 8 })
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .justifyContent(FlexAlign.SpaceBetween)

      .constraintSize({ minHeight: item.coverUrl.length > 0 ? 84 : 0 })

      if (item.coverUrl.length > 0) {
        Image(item.coverUrl)
          .width(112)
          .height(84)
          .borderRadius(10)
          .objectFit(ImageFit.Cover)
      }
    }
    .width('100%')
    .padding(12)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(AppTheme.CARD)
    .borderRadius(12)
    .onClick(() => {
      this.openThread(item);
    })
  }
}
