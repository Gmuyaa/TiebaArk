import { ImageTransitionGallery } from './ImageTransition';

/** 每次富文本渲染独占图库；同一评论出现在列表和面板时不会互相抢返回位置。 */
@ComponentV2
export struct ImageTransitionGalleryScope {
  @Param blockGap: number = 9;
  @BuilderParam content: (gallery: ImageTransitionGallery) => void = this.Empty;
  private gallery: ImageTransitionGallery = new ImageTransitionGallery();

  @Builder Empty(_gallery: ImageTransitionGallery) {}

  aboutToDisappear(): void { this.gallery.dispose(); }

  build() {
    Column({ space: this.blockGap }) {
      this.content(this.gallery)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
