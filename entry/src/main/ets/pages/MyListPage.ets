import { motionEdgeEffect } from '../common/appearance/MotionPolicy';
import { PageState, ListFooter } from '../components/PageState';
import { PullRefreshHeader, PULL_REFRESH_OFFSET } from '../components/RefreshSpinner';
/** 浏览历史、收藏、回复与帖子列表页面，共用列表布局与对应 VM。 */

import { common } from '@kit.AbilityKit';
import { accessibility } from '@kit.AccessibilityKit';
import { promptAction } from '@kit.ArkUI';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { AppTheme } from '../theme/Theme';
import { PageHeader } from '../components/PageHeader';
import { GlassCircleButton } from '../components/GlassCircleButton';
import { GlassPillButton } from '../components/GlassPillButton';
import { GlassToast } from '../components/GlassToast';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { ForumAvatarImage, forumAvatarRadius } from '../components/ForumAvatarImage';
import { MyListItem, MyListVM, kindTitle, parseKind } from '../viewmodel/MyListVM';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { MyListParams, NavigationService } from '../navigation/AppNavigation';
import { PostContentInline } from '../components/PostContentInline';
import { POST_BODY_SIZE } from '../common/appearance/PostTypography';
import { ThreadCardLayout } from '../common/appearance/ThreadCardLayout';
import { openContentPiece } from '../navigation/ContentNavigation';
import { ContentPiece } from '../model/ThreadDetail';
import { ThreadPreviewCard } from '../components/ThreadPreviewCard';
import { ImageViewer } from '../components/ImageViewer';
import { closeImageTransition } from '../components/ImageTransition';
import { ThreadCardActionsVM, ThreadCardActionState } from '../viewmodel/ThreadCardActionsVM';
import { contentDeletionRevision } from '../viewmodel/ContentDeletionRevision';

/** 已删除帖子的左下角提示（标题同色灰显，见 `CardItem`） */
const DELETED_LABEL: string = '该帖子已被删除';
/** 发帖时选了「个人主页不可见」的标签，与官方「我的帖子」右上角一致 */
const HIDE_FROM_PROFILE_LABEL: string = '主页不可见';
const FAVORITE_ACTION_INSET: number = 84;

@ComponentV2
export struct MyListPage {
  @Local pullRefreshDragging: boolean = false;
  /** PageMap 注入的路由参数，唯一定义见 navigation/AppNavigation.ets 的 MyListParams */
  @Param routeParams: MyListParams | undefined = undefined;
  @Local vm: MyListVM = new MyListVM();
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;
  @Local refreshing: boolean = false;
  @Local viewerImages: string[] = [];
  @Local viewerIndex: number = 0;
  @Local favoriteResult: string = '';
  private favoriteResultTimer: number = -1;
  private cardActions: ThreadCardActionsVM = new ThreadCardActionsVM();
  private deletionRevision: number = contentDeletionRevision();
  @Local pageVisible: boolean = false;

  @Monitor('vm.loading', 'vm.loadingMore', 'vm.threadPendingTid', 'vm.removing', 'pageVisible')
  refreshAfterDeletion(): void {
    if (!this.pageVisible || this.vm.loading || this.vm.loadingMore || this.vm.threadPendingTid > 0 ||
      this.vm.removing || this.deletionRevision === contentDeletionRevision()) { return; }
    this.deletionRevision = contentDeletionRevision();
    void this.vm.load(this.hostContext());
  }
  private imageScrollers: Map<number, ListScroller> = new Map<number, ListScroller>();

  private imageScroller(tid: number): ListScroller {
    let scroller: ListScroller | undefined = this.imageScrollers.get(tid);
    if (scroller === undefined) {
      scroller = new ListScroller();
      this.imageScrollers.set(tid, scroller);
    }
    return scroller;
  }

  private showActionResult(message: string): void {
    if (message.length > 0) { this.getUIContext().getPromptAction().showToast({ message }); }
  }

  private threadMenu(item: MyListItem): MenuElement[] {
    const owner: string = this.vm.threadActionOwner();
    const action: 'hide' | 'show' = item.hideFromProfile ? 'show' : 'hide';
    return [
      { value: item.hideFromProfile ? '设为主页可见' : '设为主页不可见', action: (): void => {
        void this.vm.manageThread(this.hostContext(), item, owner, action)
          .then((message: string): void => { this.showActionResult(message); });
      } },
      { value: '删除', action: (): void => { this.confirmDeleteThread(item, owner); } }
    ];
  }

  private confirmDeleteThread(item: MyListItem, owner: string): void {
    if (this.vm.threadPendingTid > 0) { return; }
    this.getUIContext().getPromptAction().showDialog({
      title: '删除帖子',
      message: item.title.length > 0 ? `确定删除“${item.title}”？删除后无法恢复。` : '确定删除这条帖子？删除后无法恢复。',
      buttons: [{ text: '取消', color: AppTheme.TEXT_SUB }, { text: '删除', color: AppTheme.DANGER_TEXT }]
    }).then((result) => {
      if (result.index === 1) {
        void this.vm.manageThread(this.hostContext(), item, owner, 'delete')
          .then((message: string): void => { this.showActionResult(message); });
      }
    }).catch(() => {});
  }

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
      // 保持兜底值
    });
    this.vm.load(context);
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToDisappear(): void {
    this.clearFavoriteResult();
    this.vm.dispose();
  }

  private clearFavoriteResult(): void {
    clearTimeout(this.favoriteResultTimer);
    this.favoriteResultTimer = -1;
    this.favoriteResult = '';
  }

  private showFavoriteResult(message: string): void {
    if (message.length === 0) { return; }
    this.clearFavoriteResult();
    this.favoriteResult = message;
    this.favoriteResultTimer = setTimeout((): void => {
      this.favoriteResultTimer = -1;
      this.favoriteResult = '';
    }, message.length <= 12 ? 2000 : 3500);
    if (accessibility.isOpenAccessibilitySync()) {
      const event = new accessibility.EventInfo('announceForAccessibilityNotInterrupt',
        this.hostContext().abilityInfo.bundleName, 'common');
      event.textAnnouncedForAccessibility = message;
      void accessibility.sendAccessibilityEvent(event).catch(() => {});
    }
  }

  private confirmRemoveFavorites(): void {
    if (!this.canRemoveFavorites()) { return; }
    const confirmed: number[] = this.vm.selected.slice();
    const confirmedOwner: string = this.vm.selectionOwner();
    this.getUIContext().getPromptAction().showDialog({
      title: '取消收藏',
      message: `将取消选中的 ${confirmed.length} 条收藏。`,
      buttons: [{ text: '取消', color: AppTheme.TEXT_SUB }, { text: '取消收藏', color: AppTheme.DANGER_TEXT }]
    }).then(async (result): Promise<void> => {
      if (result.index === 1) {
        this.showFavoriteResult(await this.vm.removeSelected(this.hostContext(), confirmed, confirmedOwner));
      }
    }).catch(() => {});
  }

  private canRemoveFavorites(): boolean {
    return this.vm.selected.length > 0 && !this.vm.removing &&
      !this.vm.loading && !this.vm.loadingMore;
  }

  private openThread(item: MyListItem): void {
    if (item.tid <= 0) {
      return;
    }
    // 已删除的帖子点进去只会是空详情页 / 加载失败，直接不跳（不给"点了没反应"的入口）
    if (item.isDeleted) {
      promptAction.showToast({ message: DELETED_LABEL, duration: 1500 });
      return;
    }
    // Shared 单栈：同栈进 ThreadDetail。历史/收藏项没有实时 replyCount，不传（同 SearchResultPage）。

    NavigationService.openThreadDetail({
      tid: item.tid, forumName: item.forumName,
      targetPid: this.vm.kind === 'reply' && item.pid > 0 ? item.pid : undefined
    });
  }

  private goBack(): void {
    if (this.vm.managing) { this.vm.toggleManaging(); return; }
    NavigationService.back();
  }

  private headerTitle(): string {
    if (!this.vm.managing) { return kindTitle(this.vm.kind); }
    if (this.vm.stoppingRemoval) { return '正在停止…'; }
    if (this.vm.removing) { return '正在取消收藏…'; }
    return this.vm.selected.length === 0 ? '未选择' : `已选择 ${this.vm.selected.length} 项`;
  }

  /** 吧名展示文本：服务端给的多半不带"吧"字，缺就补上（与参考图一致） */
  private forumLabel(name: string): string {
    return name.endsWith('吧') ? name : `${name}吧`;
  }

  /** 空态文案：四种各不相同，说清"为什么空"而不是笼统的一句"暂无" */
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
  HeaderActions() {
    if (this.vm.kind === 'fav' && (this.vm.managing || this.vm.items.length > 0)) {
      if (this.vm.managing) {
        GlassPillButton({ label: this.vm.allLoadedSelected() ? '取消全选' : '全选',
          pillWidth: this.vm.allLoadedSelected() ? 88 : 64,
          active: !this.vm.removing && !this.vm.loading && !this.vm.loadingMore,
          onTap: (): void => { this.vm.selectLoaded(); } })
      } else {
        GlassPillButton({ label: '多选', active: !this.vm.loading && !this.vm.loadingMore,
          onTap: (): void => { this.vm.toggleManaging(); } })
      }
    }

    if (this.vm.kind === 'history' && this.vm.items.length > 0) {
      Text('清空')
        .fontSize(14).constraintSize({ minHeight: 40, minWidth: 40 }).textAlign(TextAlign.Center)
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
            // 用户取消
          });
        })
    }

  }

  @Builder
  PullHeader() { PullRefreshHeader({ active: this.refreshing || this.pullRefreshDragging }) }

  build() {

    HdsNavDestination() {
      Stack() {
      Column() {
        // ── 页头：返回 + 标题（+ 历史页的"清空"）──
        PageHeader({ title: this.headerTitle(),
          closeLabel: this.vm.managing ? (this.vm.removing ? '停止取消收藏' : '退出多选') : '',
          onBack: (): void => { this.goBack(); },
          actions: (): void => { this.HeaderActions(); } })

      if (this.vm.kind === 'fav') {
        this.FavoritesBody()
      } else if (this.vm.kind === 'reply') {
        this.ReplyBody()
      } else if (this.vm.kind === 'thread') {
        this.ThreadBody()
      } else if (this.vm.loading && !this.vm.loadedOnce) {
        PageState({ fillRemaining: true, loading: true, message: '正在加载…' }).layoutWeight(1)
      } else if (this.vm.errorText.length > 0) {
        PageState({ fillRemaining: true, title: '加载失败', message: this.vm.errorText, actionLabel: '重试',
          onAction: (): void => { void this.vm.load(this.hostContext()); } }).layoutWeight(1)
      } else if (this.vm.items.length === 0) {
        PageState({ fillRemaining: true, message: this.emptyText() }).layoutWeight(1)
      } else {
        List() {
          ForEach(this.vm.items, (item: MyListItem) => {
            ListItem() {
              this.CardItem(item)
            }
            .margin({ left: 12, right: 12, top: 5, bottom: 5 })
          }, (item: MyListItem) => `${item.tid}-${item.title}-${item.forumAvatar}-${item.isDeleted}-${item.hideFromProfile}`)
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(AppTheme.BG)
        .edgeEffect(motionEdgeEffect())
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarH })
    .backgroundColor(AppTheme.BG)
      if (this.vm.managing) {
        Row() {
          GlassCircleButton({ symbol: $r('sys.symbol.trash'), iconWeight: FontWeight.Regular,
            accessibilityLabel: '取消所选收藏', diameter: 56, iconSize: 24, slot: MaterialSlot.BOTTOM_BAR,
            onTap: (): void => { this.confirmRemoveFavorites(); } })
            .enabled(this.canRemoveFavorites()).opacity(this.canRemoveFavorites() ? 1 : 0.4)
        }.width('100%').justifyContent(FlexAlign.Center).hitTestBehavior(HitTestMode.Transparent)
          .position({ x: 0, y: '100%' }).translate({ y: -FAVORITE_ACTION_INSET })
      }
      if (this.favoriteResult.length > 0) {
        Column() {
          Blank()
          GlassToast({ message: this.favoriteResult })
        }.width('100%').height('100%').clip(false).hitTestBehavior(HitTestMode.None)
          .padding({ left: 16, right: 16, bottom: this.vm.managing ? FAVORITE_ACTION_INSET + 12 : AppTheme.BAR_SAFE_H + 16 })
      }
      if (this.viewerImages.length > 0) {
        ImageViewer({ imageUrls: this.viewerImages, initialIndex: this.viewerIndex,
          onClose: (): void => { this.viewerImages = []; } })
      }
      }.width('100%').height('100%')
    }
    // 本页页头完全由内容自绘（GlassBackButton + 标题在页面流内），绝不显示 HDS 默认标题栏
    .hideTitleBar(true)
    .onShown((): void => { this.pageVisible = true; this.refreshAfterDeletion(); })
    .onHidden((): void => { this.pageVisible = false; this.clearFavoriteResult(); })
    .onBackPressed((): boolean => {
      if (this.viewerImages.length > 0) {
        closeImageTransition(this.getUIContext(), (): void => { this.viewerImages = []; });
        return true;
      }
      if (!this.vm.managing) { return false; }
      this.goBack();
      return true;
    })
  }

  @Builder
  ThreadBody() {
    Refresh({ refreshing: $$this.refreshing, builder: (): void => { this.PullHeader(); } }) {
      Column() {
        if (this.vm.items.length === 0) {
          PageState({ fillRemaining: true, loading: this.vm.loading,
            title: this.vm.errorText.length > 0 ? '加载失败' : '',
            message: this.vm.loading ? '正在加载…' : (this.vm.errorText || this.emptyText()),
            actionLabel: this.vm.errorText.length > 0 ? '重试' : '',
            onAction: (): void => { void this.vm.load(this.hostContext()); } }).layoutWeight(1)
        } else {
          if (this.vm.errorText.length > 0) {
            PageState({ compact: true, message: this.vm.errorText, actionLabel: '重试',
              onAction: (): void => { void this.vm.load(this.hostContext()); } })
          }
          List({ space: ThreadCardLayout.LIST_GAP }) {
            ForEach(this.vm.items, (item: MyListItem) => {
              ListItem() { this.ThreadCard(item) }
            }, (item: MyListItem) => `${item.tid}-${item.forumAvatar}-${item.hideFromProfile}`)
          }.padding({ left: 12, right: 12, top: 8 }).width('100%').layoutWeight(1)
            .edgeEffect(motionEdgeEffect())
        }
      }.width('100%').height('100%')
    }.refreshOffset(PULL_REFRESH_OFFSET)
      .onStateChange((state: RefreshStatus) => {
        this.pullRefreshDragging = state === RefreshStatus.Drag || state === RefreshStatus.OverDrag;
      }).width('100%').layoutWeight(1).onRefreshing(() => {
        this.vm.load(this.hostContext()).finally(() => { this.refreshing = false; });
      })
  }

  @Builder
  ThreadCard(item: MyListItem) {
    ThreadPreviewCard({
      forumIdentity: true, forumName: item.forumName, forumAvatar: item.forumAvatar,
      postedTime: item.postedTime, title: item.title, summary: item.content, contentPieces: item.pieces,
      headerStatus: item.hideFromProfile ? HIDE_FROM_PROFILE_LABEL : '公开',
      menuBusy: this.vm.threadPendingTid === item.tid, menu: this.threadMenu(item),
      images: item.images, originImages: item.originImages, imageScroller: this.imageScroller(item.tid),
      agreeCount: item.agreeCount, replyCount: item.replyCount, shareCount: item.shareCount,
      onActivateContent: (piece: ContentPiece): void => { openContentPiece(piece, this.getUIContext()); },
      canOpenForum: item.forumName.length > 0,
      onOpenForum: (): void => { NavigationService.openForum({ forumName: item.forumName }); },
      onOpenThread: (): void => { this.openThread(item); },
      onOpenComments: (): void => {
        NavigationService.openThreadDetail({ tid: item.tid, forumName: item.forumName,
          replyCount: item.replyCount, openComments: true });
      },
      onToggleLike: (state: ThreadCardActionState): void => {
        void this.cardActions.toggleLike(state, this.hostContext(), item.tid, item.forumName)
          .then((message: string): void => { this.showActionResult(message); });
      },
      onShare: (): void => {
        void this.cardActions.share(this.hostContext(), item.tid, item.title)
          .then((message: string): void => { this.showActionResult(message); });
      },
      onOpenImage: (index: number): void => {
        this.viewerIndex = index;
        this.viewerImages = item.originImages.length > 0 ? item.originImages : item.images;
      }
    })
  }

  @Builder
  FavoritesBody() {
    Column() {
      Refresh({ refreshing: $$this.refreshing, builder: (): void => { this.PullHeader(); } }) {
        Column() {
          if (this.vm.items.length === 0) {
            PageState({ fillRemaining: true, loading: this.vm.loading,
              title: this.vm.errorText.length > 0 ? '加载失败' : '',
              message: this.vm.loading ? '正在加载…' : (this.vm.errorText || this.emptyText()),
              actionLabel: this.vm.errorText.length > 0 ? '重试' : '',
              onAction: (): void => { void this.vm.load(this.hostContext()); } }).layoutWeight(1)
          } else {
            if (this.vm.errorText.length > 0) {
              PageState({ compact: true, message: '刷新失败，正在显示上次数据', actionLabel: '重试',
                onAction: (): void => { void this.vm.load(this.hostContext()); } })
            }
            List({ space: 10 }) {
              Repeat<MyListItem>(this.vm.items)
                .each((row: RepeatItem<MyListItem>) => {
                  ListItem() { this.FavoriteRow(row.item) }
                })
                .key((item: MyListItem): string =>
                  `${item.tid}-${item.forumAvatar}-${item.isDeleted}-${item.title}-${item.coverUrl}`)
                .virtualScroll({ reusable: false })
              ListItem() {
                ListFooter({ loading: this.vm.loadingMore, error: this.vm.pagingError, hasMore: this.vm.hasMore,
                onRetry: (): void => { void this.vm.loadMore(this.hostContext()); } })
              }
              if (this.vm.managing) {
                ListItem() { Row().height(FAVORITE_ACTION_INSET).width('100%') }
              }
            }.padding({ left: 12, right: 12, top: 8 }).width('100%').layoutWeight(1)
              .cachedCount(2).edgeEffect(motionEdgeEffect()).onReachEnd(() => {
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
  FavoriteRow(item: MyListItem) {
    Row() {
      Column() { this.CardItem(item) }.layoutWeight(1)
      if (this.vm.managing) {
        Checkbox().select(this.vm.isSelected(item.tid)).width(20).height(20)
          .selectedColor(AppTheme.ACCENT).unselectedColor(AppTheme.TEXT_MUTED)
          .mark({ strokeColor: AppTheme.ON_ACCENT })
          .margin({ left: 4, right: 16 }).enabled(!this.vm.removing)
          .accessibilityText(`选择${item.title}`)
          .onChange((selected: boolean) => {
            if (selected !== this.vm.isSelected(item.tid)) { this.vm.toggleSelected(item.tid); }
          })
      }
    }.width('100%').backgroundColor(AppTheme.CARD).borderRadius(AppTheme.CARD_RADIUS)
  }

  @Builder
  ReplyBody() {
    Refresh({ refreshing: $$this.refreshing, builder: (): void => { this.PullHeader(); } }) {
      Column() {
        if (this.vm.items.length === 0) {
          PageState({ fillRemaining: true, loading: this.vm.loading,
            title: this.vm.errorText.length > 0 ? '加载失败' : '',
            message: this.vm.loading ? '正在加载…' : (this.vm.errorText || this.emptyText()),
            actionLabel: this.vm.errorText.length > 0 ? '重试' : '',
            onAction: (): void => { void this.vm.load(this.hostContext()); } }).layoutWeight(1)
        } else {
          if (this.vm.errorText.length > 0) {
            PageState({ compact: true, message: '刷新失败，正在显示上次数据', actionLabel: '重试',
              onAction: (): void => { void this.vm.load(this.hostContext()); } })
          }
          List({ space: 10 }) {
            ForEach(this.vm.items, (item: MyListItem) => {
              ListItem() { this.ReplyCard(item) }
            }, (item: MyListItem) => `${item.key}-${item.forumAvatar}-${item.title}-${item.content}-${item.meta}`)
            ListItem() {
              ListFooter({ loading: this.vm.loadingMore, error: this.vm.pagingError, hasMore: this.vm.hasMore,
              onRetry: (): void => { void this.vm.loadMore(this.hostContext()); } })
            }
          }
          .padding({ left: 12, right: 12, top: 8 }).width('100%').layoutWeight(1)
          .edgeEffect(motionEdgeEffect())
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
    .backgroundColor(AppTheme.CARD).borderRadius(AppTheme.CARD_RADIUS)
    .onClick(() => { this.openThread(item); })
  }

  @Builder
  CardItem(item: MyListItem) {
    Row({ space: 12 }) {
      // ── 左列：标题在上、吧信息钉在底 ──
      // ⚠️ 不能用 Blank() 撑开：constraintSize 的 minHeight 不参与子节点测量，
      // Blank 量到 0，吧信息会贴在标题下面。用 SpaceBetween 把两个子节点顶到两端。
      Column() {
        Text(item.title)
          .fontSize(16)
          // 已删除：整行灰显（与正文主色区分开，一眼看出点不开）
          .fontColor(item.isDeleted ? AppTheme.TEXT_SUB : AppTheme.TEXT_MAIN)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(22)

        Row({ space: 6 }) {
          if (item.isDeleted) {
            // 已删除：左下角只留这一句，不再摆吧头像/吧名（那样会让人以为还能点进去）
            Text(DELETED_LABEL)
              .fontSize(12)
              .fontColor(AppTheme.TEXT_SUB)
              .maxLines(1)
          } else {
            if (item.forumAvatar.length > 0 || item.forumName.length > 0) {
              // 没头像（或加载失败）时用吧名首字占位，不给空圈
              ForumAvatarImage({ url: item.forumAvatar, forumName: item.forumName,
                avatarSize: 20, radius: forumAvatarRadius(20), fontSize: 11 })
            }
            if (item.forumName.length > 0) {
              Text(this.forumLabel(item.forumName))
                .fontSize(12)
                .fontColor(AppTheme.TEXT_SUB)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            }
          }
        }
        .margin({ top: 8 })
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .justifyContent(FlexAlign.SpaceBetween)
      // 有图时左列与右侧封面等高（吧信息钉在底部）；无图时不要空出来的高度
      .constraintSize({ minHeight: item.coverUrl.length > 0 ? 84 : 0 })

      // ── 右侧圆角封面图：没有图就不占位置，只留标题 ──
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
    .borderRadius(AppTheme.CARD_RADIUS)
    .onClick(() => {
      if (this.vm.managing) { this.vm.toggleSelected(item.tid); }
      else { this.openThread(item); }
    })
  }
}
