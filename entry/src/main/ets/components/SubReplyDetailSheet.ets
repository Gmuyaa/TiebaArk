

import { display } from '@kit.ArkUI';
import { HdsTabs } from '@kit.UIDesignKit';
import { PostItem, SubPostItem, UserBrief } from '../model/ThreadDetail';
import { AgreeState } from '../viewmodel/ThreadDetailVM';
import { materialManager } from '../common/material/MaterialManager';
import { MaterialSlot, SPLIT_PILL_GRADIENT_MASK } from '../common/material/MaterialConfig';
import { DetailTheme } from '../theme/Theme';
import { AnchorReplyCard } from './AnchorReplyCard';
import { SubReplyDetailItem } from './SubReplyDetailItem';

const PILL_HEIGHT: number = 52;

const PILL_RADIUS: number = PILL_HEIGHT / 2;

const PILL_GUTTER: number = 16;

const LIST_BOTTOM_PAD: number = PILL_HEIGHT + 8;

@ComponentV2
export struct SubReplyDetailSheet {
  @Param tid: number = 0;
  @Param threadTitle: string = '';
  @Event onOpenUser: (user: UserBrief) => void = (): void => {};

  @Require @Param anchor: PostItem;

  @Param anchorIsThreadAuthor: boolean = false;

  @Require @Param anchorAgreeState: AgreeState;

  @Param subPosts: SubPostItem[] = [];

  @Param totalReplies: number = -1;
  @Require @Param subAgreeState: (sub: SubPostItem) => AgreeState;

  @Param loading: boolean = false;

  @Param errorText: string = '';

  @Param hasMore: boolean = false;

  @Param safeTopVp: number = 0;

  @Param safeBottomVp: number = 0;

  @BuilderParam anchorBody: () => void = this.emptyBody;

  @BuilderParam subBody: (sub: SubPostItem) => void = this.emptySubBody;

  @Event onClose: () => void = (): void => {};

  @Event onToggleAnchorLike: () => void = (): void => {};
  @Event onToggleSubLike: (sub: SubPostItem) => void = (_sub: SubPostItem): void => {};

  @Event onReply: () => void = (): void => {};

  @Event onRetry: () => void = (): void => {};

  @Event onLoadMore: () => void = (): void => {};

  @Local pillWidthVp: number = 0;

  aboutToAppear(): void {

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
    Column({ space: 8 }) {
      if (this.errorText.length > 0) {
        Text(this.errorText)
          .fontSize(12)
          .fontColor(DetailTheme.ERROR)
          .textAlign(TextAlign.Center)
        Text('点击重试')
          .fontSize(13)
          .fontColor(DetailTheme.ACCENT_DARK)
          .onClick(() => {
            this.onRetry();
          })
      } else if (this.loading) {
        Text('正在加载…')
          .fontSize(12)
          .fontColor(DetailTheme.TEXT_SUB)
      } else if (this.hasMore) {
        Text('加载更多')
          .fontSize(13)
          .fontColor(DetailTheme.ACCENT_DARK)
          .onClick(() => {
            this.onLoadMore();
          })
      } else if (this.subPosts.length > 0) {
        Text('没有更多回复')
          .fontSize(12)
          .fontColor(DetailTheme.TEXT_MUTED)
      }
    }
    .width('100%')
    .padding({ top: 14, bottom: 18 + LIST_BOTTOM_PAD + this.safeBottomVp })
    .justifyContent(FlexAlign.Center)
  }

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

      .barBackgroundColor(Color.Transparent)
      .barBackgroundBlurStyle(BlurStyle.NONE)
      .barFloatingStyle({

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

        .padding({ bottom: 8 })
        .onReachEnd(() => {
          this.onLoadMore();
        })

        this.FloatingReplyPill();
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.safeTopVp })

    .backgroundColor(DetailTheme.BG)
    .clip(true)
  }
}
