import { common } from '@kit.AbilityKit';
import { SavedEmojiManager } from './SavedEmojiManager';
import { SavedEmojiManagerVM } from '../viewmodel/SavedEmojiManagerVM';
import { ImageTransitionSource } from './ImageTransition';
import { SavedEmojiPreview } from './SavedEmojiPreview';
import { EmojiPickerVM } from '../viewmodel/EmojiPickerVM';
import { MemePicItem } from '../model/MemeEmoji';
import { REPLY_EMOTICON_CODES, emojiImageUrl, emojiTokenFromUrl } from '../model/ThreadDetail';
import { emojiSrc } from '../common/emoji/EmojiSrc';
import { DetailTheme as AppTheme } from '../theme/Theme';
const REPLY_EMOJI_COLUMNS: string = '1fr 1fr 1fr 1fr 1fr 1fr 1fr';
const REPLY_EMOJI_SIZE: number = 30;
const REPLY_EMOJI_VISIBLE_ROWS: number = 5;
const SAVED_EMOJI_COLUMNS: string = '1fr 1fr 1fr 1fr 1fr';
const SAVED_EMOJI_VISIBLE_ROWS: number = 4;
const SAVED_EMOJI_SIZE: number = 52.5;
const REPLY_EMOJI_ROW_GAP: number = 14;
// 两个分类共用面板高度，切换时输入卡位置稳定，放大的收藏图也能完整排下四行。
export const EMOJI_GRID_MIN_HEIGHT: number = Math.max(
  REPLY_EMOJI_SIZE * REPLY_EMOJI_VISIBLE_ROWS + REPLY_EMOJI_ROW_GAP * (REPLY_EMOJI_VISIBLE_ROWS - 1),
  SAVED_EMOJI_SIZE * SAVED_EMOJI_VISIBLE_ROWS + REPLY_EMOJI_ROW_GAP * (SAVED_EMOJI_VISIBLE_ROWS - 1));
const REPLY_EMOJI_TAB_SIZE: number = 36;
const EMOJI_PANEL_TOP_PADDING: number = 8;
const EMOJI_PANEL_BOTTOM_PADDING: number = 12;
const EMOJI_PANEL_TAB_H: number = 40;

/** 评论与发帖共用的内置/收藏表情面板。 */
@ComponentV2
export struct EmojiPickerPanel {
  @Param picker: EmojiPickerVM = new EmojiPickerVM();
  @Param tab: number = 0;
  @Param gridHeight: number = 248;
  @Param safeBottom: number = 0;
  @Event onTabChange: (tab: number) => void = (): void => {};
  @Event onLoad: () => void = (): void => {};
  @Event onRetry: () => void = (): void => {};
  @Event onBuiltin: (code: number) => void = (): void => {};
  @Event onMeme: (item: MemePicItem) => void = (): void => {};
  @Event onManagerChange: (open: boolean) => void = (_open: boolean): void => {};
  @Event onDelete: () => void = (): void => {};
  @Local managerOpen: boolean = false;
  @Local manager: SavedEmojiManagerVM = new SavedEmojiManagerVM();
  private preview: SavedEmojiPreview = new SavedEmojiPreview();
  private imageTransition: ImageTransitionSource = new ImageTransitionSource();

  aboutToDisappear(): void { this.preview.dispose(); this.manager.dispose(); }

  private openManager(): void {
    this.preview.dispose(); this.manager = new SavedEmojiManagerVM(); this.onManagerChange(true); this.managerOpen = true;
  }
  @Builder
  Manager() {
    SavedEmojiManager({ vm: this.manager, onClose: (): void => { this.managerOpen = false; } })
  }

  build() {
    Column() {
      Row({ space: 14 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.face_smiling'))
            .fontSize(20)
            .fontColor([this.tab === 0 ? AppTheme.ACCENT : AppTheme.EMOJI_PANEL_TEXT])
        }
        .width(REPLY_EMOJI_TAB_SIZE)
        .height(REPLY_EMOJI_TAB_SIZE)
        .borderRadius(REPLY_EMOJI_TAB_SIZE / 2)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.tab === 0 ? '#FFFFFF' : Color.Transparent)
        .id('emoji-tab-builtin').accessibilityText('贴吧表情').accessibilitySelected(this.tab === 0)
        .onClick(() => {
          this.onTabChange(0);
        })

        Row() {
          SymbolGlyph($r('sys.symbol.heart'))
            .fontSize(20)
            .fontColor([this.tab === 1 ? AppTheme.ACCENT : AppTheme.EMOJI_PANEL_TEXT])
        }
        .width(REPLY_EMOJI_TAB_SIZE)
        .height(REPLY_EMOJI_TAB_SIZE)
        .borderRadius(REPLY_EMOJI_TAB_SIZE / 2)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.tab === 1 ? '#FFFFFF' : Color.Transparent)
        .id('emoji-tab-saved').accessibilityText('收藏表情').accessibilitySelected(this.tab === 1)
        .onClick(() => {
          this.onTabChange(1);
          this.onLoad();
        })

        Blank()

        Row() {
          SymbolGlyph($r('sys.symbol.delete_left'))
            .fontSize(20)
            .fontColor([AppTheme.EMOJI_PANEL_TEXT])
        }
        .width(REPLY_EMOJI_TAB_SIZE)
        .height(REPLY_EMOJI_TAB_SIZE)
        .borderRadius(REPLY_EMOJI_TAB_SIZE / 2)
        .justifyContent(FlexAlign.Center)
        .id('emoji-delete').accessibilityText('删除表情或文字')
        .onClick(() => {
          this.onDelete();
        })
      }
      .width('100%')
      .height(EMOJI_PANEL_TAB_H)

      if (this.tab === 0) {
        Grid() {
          ForEach(REPLY_EMOTICON_CODES, (code: number) => {
            // Grid 的子组件必须是 GridItem（ArkTS 编译器强约束），点击区给整格
            GridItem() {
              Image(emojiSrc(emojiImageUrl(`image_emoticon${code}`)))
                .width(REPLY_EMOJI_SIZE)
                .height(REPLY_EMOJI_SIZE)
                .objectFit(ImageFit.Contain)
                .interpolation(ImageInterpolation.High)
            }
            .height((this.gridHeight - REPLY_EMOJI_ROW_GAP * (REPLY_EMOJI_VISIBLE_ROWS - 1)) / REPLY_EMOJI_VISIBLE_ROWS)
            .id(`emoji-builtin-${code}`).accessibilityText(emojiTokenFromUrl(emojiImageUrl(`image_emoticon${code}`)))
            .onClick(() => {
              this.onBuiltin(code);
            })
          }, (code: number) => `emoticon_${code}`)
        }
        .columnsTemplate(REPLY_EMOJI_COLUMNS)
        .rowsGap(REPLY_EMOJI_ROW_GAP)
        .height(this.gridHeight)
        .width('100%')
      } else {
        this.MemeEmojiGrid()
      }
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: EMOJI_PANEL_TOP_PADDING,
      bottom: EMOJI_PANEL_BOTTOM_PADDING + this.safeBottom
    })
    .bindContentCover($$this.managerOpen, this.Manager(), {
      backgroundColor: AppTheme.CARD, enableSafeArea: false,
      onWillDismiss: (action: DismissContentCoverAction): void => { if (!this.manager.busy) { action.dismiss(); } },
      onDisappear: (): void => {
        this.managerOpen = false; this.manager.dispose(); this.onManagerChange(false);
        void this.picker.retryMemePics(this.getUIContext().getHostContext() as common.UIAbilityContext);
      }
    })
  }

  /** 表情面板在 Builder 内直接读取 vm.memePics，以响应 @Trace 数组替换；不经 Builder 参数保存快照。ForEach key 包含 picId 与 URL，避免复用其他表情节点。 */
  @Builder
  MemeEmojiGrid() {
    if (this.picker.memeStateText === 'loading') {
      Column() {
        Text('收藏表情加载中…')
          .fontSize(13)
          .fontColor(AppTheme.EMOJI_PANEL_TEXT)
      }
      .width('100%')
      .height(this.gridHeight)
      .justifyContent(FlexAlign.Center)
    } else if (this.picker.memeStateText.length > 0) {
      Column() {
        Text(this.picker.memeStateText)
          .fontSize(13)
          .fontColor(AppTheme.EMOJI_PANEL_TEXT)
          .textAlign(TextAlign.Center)
        Text('点此重试')
          .fontSize(13)
          .fontColor(AppTheme.ACCENT)
          .margin({ top: 10 })
          .onClick(() => {
            this.onRetry();
          })
      }
      .width('100%')
      .height(this.gridHeight)
      .justifyContent(FlexAlign.Center)
    } else {
      Grid() {
        GridItem() {
          Stack() {
            SymbolGlyph($r('sys.symbol.plus')).fontSize(28).fontColor([AppTheme.EMOJI_PANEL_TEXT])
          }.width(SAVED_EMOJI_SIZE).height(SAVED_EMOJI_SIZE).borderRadius(10)
            .border({ width: 1, color: AppTheme.EMOJI_PANEL_SUB_TEXT, style: BorderStyle.Dashed })
        }
        .height((this.gridHeight - REPLY_EMOJI_ROW_GAP * (SAVED_EMOJI_VISIBLE_ROWS - 1)) / SAVED_EMOJI_VISIBLE_ROWS)
        .id('emoji-saved-manage').accessibilityText('添加或整理收藏表情')
        .onClick((): void => { this.openManager(); })
        ForEach(this.picker.memePics, (item: MemePicItem, index: number) => {
          GridItem() {
            Stack() {
              Image(this.picker.memeDisplayUrl(item))
                .width('100%').height('100%').objectFit(ImageFit.Contain)
            }
            .width(SAVED_EMOJI_SIZE).height(SAVED_EMOJI_SIZE)
            .geometryTransition(this.imageTransition.id(this.picker.memeDisplayUrl(item), index), { follow: true })
            .renderFit(RenderFit.RESIZE_FILL).clip(true)
          }
          .height((this.gridHeight - REPLY_EMOJI_ROW_GAP * (SAVED_EMOJI_VISIBLE_ROWS - 1)) / SAVED_EMOJI_VISIBLE_ROWS)
          .id(`emoji-saved-${index}`).accessibilityText('收藏表情，长按放大查看')
          .onClick(() => {
            if (this.preview.canInsert()) { this.onMeme(item); }
          })
          .onTouch((event: TouchEvent): void => {
            if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.preview.hide(); }
          })
          .gesture(LongPressGesture({ duration: 350, repeat: false })
            .onAction((): void => {
              const url: string = this.picker.memeDisplayUrl(item);
              this.preview.show(this.getUIContext(), url, item.picUrl,
                this.imageTransition.id(url, index), item.width, item.height);
            })
            .onActionEnd((): void => { this.preview.hide(); })
            .onActionCancel((): void => { this.preview.hide(); }))
        }, (item: MemePicItem) => `meme_${item.picId}_${item.picUrl}`)
      }
      .columnsTemplate(SAVED_EMOJI_COLUMNS)
      .rowsGap(REPLY_EMOJI_ROW_GAP)
      .height(this.gridHeight)
      .width('100%')
    }
  }

}
