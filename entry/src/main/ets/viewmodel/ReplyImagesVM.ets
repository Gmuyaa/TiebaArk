import { common } from '@kit.AbilityKit';
import { authSession } from '../auth/AuthSession';
import { UploadedPostImage, uploadedImageToken } from '../model/ImageUpload';
import { ImageUploadVM } from './ImageUploadVM';

function owner(): string {
  return authSession.isLoggedIn() ? `${authSession.snapshot.uid}:${authSession.snapshot.portrait}` : '';
}

@ObservedV2
export class ReplyImagesVM {
  @Trace images: UploadedPostImage[] = [];
  @Trace inlineImages: UploadedPostImage[] = [];
  @Trace upload: ImageUploadVM = new ImageUploadVM();
  private account: string = '';
  private epoch: number = 0;
  private disposed: boolean = false;

  reset(): void {
    this.cancel(); this.images = []; this.inlineImages = []; this.account = owner(); this.upload.error = '';
  }
  cancel(): void { this.epoch++; this.upload.cancel(); }
  remove(index: number): void {
    if (!this.disposed && !this.upload.busy && !this.upload.selecting) {
      this.images = this.images.filter((_image: UploadedPostImage, i: number) => i !== index);
    }
  }
  async pick(context: common.UIAbilityContext, forumName: string): Promise<UploadedPostImage | undefined> {
    if (this.disposed || this.upload.busy || this.upload.selecting) { return; }
    if (this.account !== owner()) { this.reset(); }
    const mine: number = ++this.epoch;
    await this.upload.pickAndUpload(context, forumName);
    if (this.disposed || mine !== this.epoch || this.account !== owner()) { return; }
    const image: UploadedPostImage | undefined = this.upload.image;
    if (image === undefined || this.upload.contentToken().length === 0) { return; }
    const snapshot: UploadedPostImage = new UploadedPostImage();
    snapshot.id = image.id; snapshot.width = image.width; snapshot.height = image.height;
    snapshot.previewUrl = image.previewUrl;
    snapshot.localPreview = image.localPreview;
    this.images = [...this.images, snapshot];
    return snapshot;
  }
  canInline(image: UploadedPostImage): boolean {
    const token: string = uploadedImageToken(image);
    return !this.disposed && this.account === owner() && this.images.indexOf(image) >= 0 &&
      token.length > 0 && image.localPreview.length <= 175000 &&
      /^data:image\/png;base64,[A-Za-z0-9+/]+={0,2}$/.test(image.localPreview) &&
      !this.inlineImages.some((item: UploadedPostImage) =>
        item.localPreview === image.localPreview && uploadedImageToken(item) !== token);
  }
  moveInline(image: UploadedPostImage): boolean {
    if (!this.canInline(image)) { return false; }
    this.images = this.images.filter((item: UploadedPostImage) => item !== image);
    this.inlineImages = [...this.inlineImages, image]; return true;
  }
  restoreAttachment(image: UploadedPostImage): void {
    if (this.inlineImages.indexOf(image) < 0) { return; }
    this.inlineImages = this.inlineImages.filter((item: UploadedPostImage) => item !== image);
    this.images = [...this.images, image];
  }
  inlineTokenTable(): Map<string, string> {
    const table: Map<string, string> = new Map<string, string>();
    for (const image of this.inlineImages) { table.set(image.localPreview, uploadedImageToken(image)); }
    return table;
  }
  inlineImageFor(token: string): UploadedPostImage | undefined {
    return this.inlineImages.find((image: UploadedPostImage) => uploadedImageToken(image) === token);
  }

  reconcileInline(counts: Map<string, number>): void {
    if (this.disposed || this.account !== owner()) { return; }
    const remaining: Map<string, number> = new Map<string, number>(counts);
    const kept: UploadedPostImage[] = [];
    for (const image of this.inlineImages) {
      const token: string = uploadedImageToken(image); const count: number = remaining.get(token) ?? 0;
      if (count > 0) { kept.push(image); remaining.set(token, count - 1); }
    }
    if (kept.length !== this.inlineImages.length) { this.inlineImages = kept; }
  }
  content(text: string): string {
    if (this.disposed) { return ''; }
    if (this.images.length === 0 && this.inlineImages.length === 0) { return text.trim(); }
    if (this.account !== owner()) { return ''; }
    return text.trim() + this.images.map((image: UploadedPostImage) => uploadedImageToken(image)).join('');
  }
  submissionError(text: string, maxLength: number): string {
    if (this.disposed) { return '回复编辑器已关闭'; }
    if (this.upload.busy || this.upload.selecting) { return '请等待图片准备完成，或停止上传'; }
    if ((this.images.length > 0 || this.inlineImages.length > 0) && this.account !== owner()) { return '账号已变化，请重新选择回复图片'; }
    if ([...this.images, ...this.inlineImages].some((image: UploadedPostImage) => uploadedImageToken(image).length === 0)) {
      return '回复图片信息未确认，请移除后重新选择';
    }
    const content: string = this.content(text);
    if (content.length === 0) { return '请输入回复内容或选择图片'; }
    return content.length > maxLength ? '回复内容含图片已超过长度上限，请减少文字或图片' : '';
  }
  dispose(): void { this.cancel(); this.images = []; this.inlineImages = []; this.disposed = true; this.upload.dispose(); }
}
