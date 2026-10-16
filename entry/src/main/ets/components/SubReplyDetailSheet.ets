/** 回复详情内容层，展示锚点回复与楼中楼列表。正文构建器由页面传入，分页状态由 VM 管理；底部回复胶囊浮于列表上方。 */

import { PageState, ListFooter as PagingFooter } from './PageState';
import { display } from '@kit.ArkUI';
import { HdsTabs } from '@kit.UIDesignKit';
import { PostItem, SubPostItem, UserBrief } from '../model/ThreadDetail';
import { AgreeState } from '../viewmodel/ThreadDetailVM';
import { materialManager } from '../common/material/MaterialManager';
import { MaterialSlot, SPLIT_PILL_GRADIENT_MASK } from '../common/material/MaterialConfig';
import { DetailTheme } from '../theme/Theme';
import { AnchorReplyCard } from './AnchorReplyCard';
import { SubReplyDetailItem } from './SubReplyDetailItem';

/** 悬浮胶囊高度：要求在 48~54 之间，取 52（与详情页底部胶囊同高） */
const PILL_HEIGHT: number = 52;
/** 圆角取高度的一半 → 两端正好是半圆 */
const PILL_RADIUS: number = PILL_HEIGHT / 2;
/** 胶囊距左右边缘，约 16vp */
const PILL_GUTTER: number = 16;
/**
 * 列表底部预留（vp）。
 *
 * 末尾留出胶囊、手势区与 8vp 间距；最后一条的操作可完整滚到胶囊上方。
 */
const LIST_BOTTOM_PAD: number = PILL_HEIGHT + 8;

@ComponentV2
export struct SubReplyDetailSheet {
  @Param tid: number = 0;
  @Param threadTitle: string = '';
  @Event onOpenUser: (user: UserBrief) => void = (): void => {};
  /** 被展开的一级回复（页面按 pid 从已加载楼层里找） */
  @Require @Param anchor: PostItem;
  /** 锚点回复的作者是不是楼主 */
  @Param anchorIsThreadAuthor: boolean = false;
  /** 锚点回复的可观察点赞态（透传给 AnchorReplyCard，弹层内点赞也能局部刷新） */
  @Require @Param anchorAgreeState: AgreeState;
  /** 楼中楼完整列表（已加载部分） */
  @Param subPosts: SubPostItem[] = [];
  /** 服务端回复总数；未知时传 -1 */
  @Param totalReplies: number = -1;
  @Require @Param subAgreeState: (sub: SubPostItem) => AgreeState;
  /** 是否正在加载（首屏或翻页） */
  @Param loading: boolean = false;
  /** 加载失败提示；为空表示没有失败 */
  @Param errorText: string = '';
  /** 还有更多可加载 */
  @Param hasMore: boolean = false;
  /** 顶部状态栏高度（vp），全屏内容层自行避让标题 */
  @Param safeTopVp: number = 0;
  /** 系统底部手势区高度（vp），由页面从窗口避让区读取 */
  @Param safeBottomVp: number = 0;
  /** 锚点回复正文（富文本） */
  @BuilderParam anchorBody: () => void = this.emptyBody;
  /** 一条楼中楼回复的正文（富文本） */
  @BuilderParam subBody: (sub: SubPostItem) => void = this.emptySubBody;
  /** 关闭面板 */
  @Event onClose: () => void = (): void => {};
  /** 锚点回复点赞 */
  @Event onToggleAnchorLike: () => void = (): void => {};
  @Event onToggleSubLike: (sub: SubPostItem) => void = (_sub: SubPostItem): void => {};
  /** 回复入口：调用方打开父楼层的回复框 */
  @Event onReply: () => void = (): void => {};
  /** 首屏/翻页失败重试 */
  @Event onRetry: () => void = (): void => {};
  /** 加载更多 */
  @Event onLoadMore: () => void = (): void => {};

  /**
   * 悬浮胶囊宽度（vp）= 屏宽 − 左右各 `PILL_GUTTER`。
   * `barFloatingStyle` 不显式钉宽时官方悬浮面会被系统压到 84vp（详情页同款问题），
   * 而本胶囊要通栏（左右各留 `PILL_GUTTER`），只能运行时读屏宽算出来。
   */
  @Local pillWidthVp: number = 0;

  aboutToAppear(): void {
    // 与首页底栏同一口径：display 给的是 px，先 px2vp 转 vp 才能参与布局计算（Index.ets 同款）。
    const screenVp: number = px2vp(display.getDefaultDisplaySync().width);
    if (screenVp > PILL_GUTTER * 2) {
      this.pillWidthVp = screenVp - PILL_GUTTER * 2;
    }
  }

  @Builder
  emptyBody() {
  }

  @Builder
  emptySubBody(sub: SubPostItem) {
  }

  /** 标题用真实楼层号；楼层缺失时退化成"本层"而不是硬写一个假数字 */
  private sheetTitle(): string {
    return this.anchor.floor > 0 ? `${this.anchor.floor}楼的回复` : '本层的回复';
  }

  @Builder
  Header() {
    Row({ space: 8 }) {
      Text(this.sheetTitle())
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(DetailTheme.TEXT_MAIN)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      // 关闭：官方 Symbol `xmark`；外层 Row 只负责维持原先 40×40 的点击区
      Row() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(17)
          .fontColor([DetailTheme.ICON])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.onClose();
      })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 10 })
    .backgroundColor(DetailTheme.BG)
  }

  /** 锚点卡与列表之间的分隔：细线 + 上下留白，靠留白分层而不是加卡片 */
  @Builder
  SectionDivider() {
    Column({ space: 12 }) {
      Divider()
        .color(DetailTheme.DIVIDER)
        .strokeWidth(1)
      Text(this.totalReplies >= 0 ? `全部回复 · ${this.totalReplies}` : '全部回复')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(DetailTheme.TEXT_MAIN)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, bottom: 16 })
  }

  @Builder
  ListFooter() {
    Column() {
      if (this.hasMore && !this.loading && this.errorText.length === 0) {
        PageState({ compact: true, actionLabel: '加载更多',
          onAction: (): void => { this.onLoadMore(); } })
      } else {
        PagingFooter({ loading: this.loading, error: this.errorText, hasMore: this.hasMore,
          endText: this.subPosts.length > 0 ? '没有更多回复' : '',
          onRetry: (): void => { this.onRetry(); } })
      }
    }.width('100%').padding({ bottom: 18 + LIST_BOTTOM_PAD + this.safeBottomVp })
  }

  /** 楼中楼弹层的回复入口，使用系统材质胶囊；内容层避免叠加自绘玻璃。 */
  @Builder
  FloatingReplyPill() {

    Stack() {
      HdsTabs({ barPosition: BarPosition.End }) {
        TabContent() {
        }
        .tabBar(this.ReplyPillTab())
      }
      .barHeight(PILL_HEIGHT)
      .barMode(BarMode.Fixed)
      .scrollable(false)
      .animationDuration(0)
      .barOverlap(true)
      // 系统自带的整块底衬让出来（与首页底栏 / 详情页胶囊同一处理）
      .barBackgroundColor(Color.Transparent)
      .barBackgroundBlurStyle(BlurStyle.NONE)
      .barFloatingStyle({
        // 钉宽理由见 pillWidthVp；side/bottomMargin = 0 → 节点矩形 = 胶囊外接矩形
        barWidth: {
          smallWidth: this.pillWidthVp,
          mediumWidth: this.pillWidthVp,
          largeWidth: this.pillWidthVp
        },
        barSideMargin: 0,
        barBottomMargin: 0,

        gradientMask: SPLIT_PILL_GRADIENT_MASK,
        thermoCtrl: true,
        systemMaterialEffect: materialManager.hdsEffectOf(MaterialSlot.BOTTOM_BAR)
      })

      .borderRadius(PILL_RADIUS)
      .clip(true)
      .width(this.pillWidthVp)
      .height(PILL_HEIGHT)
    }
    .width(this.pillWidthVp)
    .height(PILL_HEIGHT)

    .borderRadius(PILL_RADIUS)

    .shadow({ radius: 14, color: DetailTheme.FLOAT_SHADOW, offsetX: 0, offsetY: 0 })
    // 全屏内容层铺到物理底边，胶囊避让手势区后仍停在原来的屏幕位置。
    .margin({ left: PILL_GUTTER, right: PILL_GUTTER, bottom: this.safeBottomVp })
  }

  @Builder
  ReplyPillTab() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.pencil_line'))
        .fontSize(23)
        .fontColor([DetailTheme.TEXT_MAIN])

      Text('写评论')
        .fontSize(15)
        .fontColor(DetailTheme.TEXT_MAIN)
    }

    .height('100%')

    .width('100%')

    .padding({ left: 14, right: 14 })
    .onClick(() => {
      this.onReply();
    })
  }

  build() {
    Column() {
      this.Header();

      Stack({ alignContent: Alignment.Bottom }) {
        List({ space: 0 }) {
          ListItem() {
            AnchorReplyCard({
              tid: this.tid,
              threadTitle: this.threadTitle,
              onOpenAuthor: (): void => { this.onOpenUser(this.anchor.author); },
              item: this.anchor,
              isThreadAuthor: this.anchorIsThreadAuthor,
              agreeState: this.anchorAgreeState,
              bodyBuilder: this.anchorBody,
              onToggleLike: this.onToggleAnchorLike,
              onReply: this.onReply
            })
          }

          ListItem() {
            this.SectionDivider();
          }

          ForEach(this.subPosts, (sub: SubPostItem, index: number) => {
            ListItem() {
              Column() {
                SubReplyDetailItem({
                  tid: this.tid,
                  parentPid: this.anchor.pid,
                  threadTitle: this.threadTitle,
                  onOpenAuthor: (): void => { this.onOpenUser(sub.author); },
                  sub: sub,
                  agreeState: this.subAgreeState(sub),
                  isFloorAuthor: this.anchor.author.id > 0 && sub.author.id === this.anchor.author.id,
                  bodyBuilder: (): void => {
                    this.subBody(sub);
                  },
                  onReply: this.onReply,
                  onToggleLike: (): void => {
                    this.onToggleSubLike(sub);
                  }
                })
                .margin({ top: index === 0 ? 0 : 12 })
                if (index < this.subPosts.length - 1) {
                  Divider()
                    .color(DetailTheme.DIVIDER)
                    .opacity(0.45)
                    .strokeWidth(1)
                    .margin({ left: 42, top: 8 })
                }
              }
            }
            .padding({ left: 16, right: 16 })
          }, (sub: SubPostItem) => `${sub.pid}`)

          ListItem() {
            this.ListFooter();
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        // 避让空间放在可滚动的 ListFooter，保持内容可经过玻璃后方。
        .padding({ bottom: 8 })
        .onReachEnd(() => {
          this.onLoadMore();
        })

        // 后写的在 Stack 上层，胶囊浮在列表之上
        this.FloatingReplyPill();
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.safeTopVp })
    // 全屏根节点只在屏幕边界裁剪；胶囊与列表共用同一内容层。
    .backgroundColor(DetailTheme.BG)
    .clip(true)
  }
}
