import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppTheme } from '../theme/Theme';
import { MemePicItem } from '../model/MemeEmoji';
import { SavedEmojiManagerVM } from '../viewmodel/SavedEmojiManagerVM';
import { GlassCircleButton } from './GlassCircleButton';
import { SavedEmojiPreview } from './SavedEmojiPreview';
import { ImageTransitionSource } from './ImageTransition';

@ComponentV2
export struct SavedEmojiManager {
  @Require @Param vm: SavedEmojiManagerVM;
  @Event onClose: () => void = (): void => {};
  @Local topInset: number = 32;
  @Local bottomInset: number = 24;
  private preview: SavedEmojiPreview = new SavedEmojiPreview();
  private imageTransition: ImageTransitionSource = new ImageTransitionSource();
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  aboutToAppear(): void {
    try {
      const win: window.Window = window.findWindow(this.getUIContext().getWindowName() ?? '');
      this.topInset = this.getUIContext().px2vp(win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height);
      this.bottomInset = this.getUIContext().px2vp(win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height);
    } catch (err) { /* 保留安全区兜底。 */ }
    void this.vm.load(this.context());
  }
  aboutToDisappear(): void { this.preview.dispose(); this.vm.dispose(); }
  private url(item: MemePicItem): string { return item.thumbnail.length > 0 ? item.thumbnail : item.picUrl; }
  private close(): void { if (!this.vm.busy) { this.onClose(); } }
  private async add(): Promise<void> {
    if (!this.vm.ready || this.vm.busy || this.vm.loading) { return; }
    const result = await this.getUIContext().getPromptAction().showDialog({
      title: '添加收藏表情', message: '选择一张本地图片，上传并添加到贴吧云端收藏。',
      buttons: [{ text: '取消', color: AppTheme.TEXT_SUB }, { text: '选图并添加', color: AppTheme.ACCENT }]
    });
    if (result.index === 1) { await this.vm.add(this.context()); }
  }
  private async remove(): Promise<void> {
    if (this.vm.busy || !this.vm.ready || this.vm.selected.length === 0) { return; }
    const count: number = this.vm.selected.length;
    const result = await this.getUIContext().getPromptAction().showDialog({
      title: '删除收藏表情', message: `将从贴吧云端收藏中删除选中的 ${count} 张图片，其他设备同步后也会移除。`,
      buttons: [{ text: '取消', color: AppTheme.TEXT_SUB }, { text: '删除', color: AppTheme.ACCENT }]
    });
    if (result.index === 1 && count === this.vm.selected.length) { await this.vm.deleteSelected(this.context()); }
  }
  @Builder
  Header() {
    Row({ space: 8 }) {
      GlassCircleButton({ symbol: $r('sys.symbol.chevron_left'), diameter: 36, iconSize: 22,
        accessibilityLabel: '返回表情面板', onTap: (): void => { this.close(); } })
      Text(this.vm.editing ? `已选择（${this.vm.selected.length}）` : `我收藏的表情（${this.vm.pics.length}）`)
        .fontSize(18).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT_MAIN)
        .layoutWeight(1).textAlign(TextAlign.Center).maxLines(1)
      Text(this.vm.editing ? '完成' : '整理').fontSize(16).fontColor(AppTheme.ACCENT)
        .width(48).height(44).textAlign(TextAlign.Center)
        .enabled(this.vm.ready && !this.vm.busy && !this.vm.loading)
        .id('saved-emoji-manage-toggle')
        .onClick((): void => { this.preview.dispose(); this.vm.editing = !this.vm.editing; this.vm.selected = []; })
    }.height(56).width('100%').padding({ left: 16, right: 16 })
  }
  @Builder
  Picture(item: MemePicItem, index: number) {
    GridItem() {
      Stack({ alignContent: Alignment.TopEnd }) {
        Stack() {
          Image(this.url(item)).width('100%').height('100%').objectFit(ImageFit.Contain)
        }.width('76%').height('76%')
          .geometryTransition(this.imageTransition.id(this.url(item), index), { follow: true })
          .renderFit(RenderFit.RESIZE_FILL).clip(true).align(Alignment.Center)
        if (this.vm.editing) {
          if (this.vm.selected.indexOf(item.picId) >= 0) {
            Stack() {
              SymbolGlyph($r('sys.symbol.checkmark')).fontSize(14).fontColor([Color.White])
            }.width(22).height(22).borderRadius(11).backgroundColor(AppTheme.ACCENT).margin(5)
          } else {
            Circle().width(22).height(22).fill(Color.Transparent).stroke(AppTheme.TEXT_SUB).strokeWidth(1).margin(5)
          }
        }
      }.width('100%').height('100%')
        .backgroundColor(this.vm.selected.indexOf(item.picId) >= 0 ? AppTheme.SURFACE_MUTED : Color.Transparent)
    }.aspectRatio(1).id(`saved-emoji-manager-${index}`).accessibilityText('收藏表情')
      .accessibilitySelected(this.vm.selected.indexOf(item.picId) >= 0)
      .onClick((): void => { this.vm.toggle(item.picId); })
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.preview.hide(); }
      })
      .gesture(LongPressGesture({ duration: 350, repeat: false }).onAction((): void => {
        if (!this.vm.editing && !this.vm.busy) {
          this.preview.show(this.getUIContext(), this.url(item), item.picUrl,
            this.imageTransition.id(this.url(item), index), item.width, item.height);
        }
      }).onActionEnd((): void => { this.preview.hide(); }).onActionCancel((): void => { this.preview.hide(); }))
  }
  build() {
    Stack({ alignContent: Alignment.Bottom }) {
    Column() {
      this.Header()
      if (this.vm.busy || this.vm.loading) {
        Text(this.vm.loading ? '正在加载收藏…' : this.vm.upload.selecting ? '正在选择图片…' : this.vm.upload.busy ? '正在上传图片…' : '正在同步收藏…')
          .fontSize(13).fontColor(AppTheme.TEXT_SUB).padding(12)
      }
      if (this.vm.error.length > 0) {
        Column({ space: 8 }) {
          Text(this.vm.error).fontSize(13).fontColor(AppTheme.TEXT_SUB).textAlign(TextAlign.Center)
          Text('重新加载').fontSize(14).fontColor(AppTheme.ACCENT).enabled(!this.vm.busy && !this.vm.loading)
            .onClick((): void => { void this.vm.load(this.context()); })
        }.width('100%').padding(12)
      }
      Grid() {
        if (!this.vm.editing) {
          GridItem() {
            SymbolGlyph($r('sys.symbol.plus')).fontSize(32).fontColor([AppTheme.TEXT_SUB])
          }.aspectRatio(1).id('saved-emoji-manager-add').accessibilityText('从相册添加收藏表情')
            .enabled(this.vm.ready && !this.vm.busy && !this.vm.loading)
            .onClick((): void => { void this.add(); })
        }
        ForEach(this.vm.pics, (item: MemePicItem, index: number) => { this.Picture(item, index) },
          (item: MemePicItem, index: number) => `${index}:${item.picId}`)
      }.columnsTemplate('1fr 1fr 1fr 1fr').columnsGap(4).rowsGap(4)
        .width('100%').layoutWeight(1).padding({ left: 12, right: 12 })
        .enabled(!this.vm.busy && !this.vm.loading)
    }.width('100%').height('100%').padding({ top: this.topInset })
      if (this.vm.editing) {
        GlassCircleButton({ symbol: $r('sys.symbol.trash'), diameter: 52, iconSize: 26,
          accessibilityLabel: '删除选中的收藏表情', onTap: (): void => { void this.remove(); } })
          .enabled(this.vm.ready && !this.vm.busy && this.vm.selected.length > 0)
          .id('saved-emoji-manager-delete')
          .margin({ bottom: Math.max(this.bottomInset, 12) + 16 })
      }
    }.width('100%').height('100%').backgroundColor(AppTheme.CARD)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
