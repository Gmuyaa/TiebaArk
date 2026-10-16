import { common } from '@kit.AbilityKit';
import { authSession } from '../auth/AuthSession';
import { TiebaApi } from '../api/TiebaApi';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { createReplyImagePreview, pickUploadImage } from '../utils/ImagePrepare';
import { CryptoUtil } from '../utils/CryptoUtil';
import { ImageUploadChunk, ImageUploadInput, UploadedPostImage, imageUploadInputError, imageUploadChunkError, uploadedImageToken } from '../model/ImageUpload';
function owner(): string {
  return authSession.isLoggedIn() ? `${authSession.snapshot.uid}:${authSession.snapshot.portrait}` : '';
}
/** 整图上传调度；已发出的请求不宣称能撤销。 */
@ObservedV2
export class ImageUploadVM {
  @Trace busy: boolean = false;
  @Trace selecting: boolean = false;
  @Trace totalBytes: number = 0;
  @Trace uploadedBytes: number = 0;
  @Trace error: string = '';
  @Trace image: UploadedPostImage | undefined = undefined;
  private api: TiebaApi = new TiebaApi();
  private account: string = '';
  private epoch: number = 0;
  private disposed: boolean = false;
  private current(mine: number): boolean { return !this.disposed && this.epoch === mine && this.account === owner(); }
  contentToken(): string { return this.account === owner() && !this.disposed && this.image !== undefined ? uploadedImageToken(this.image) : ''; }
  async pickAndUpload(context: common.UIAbilityContext, forumName: string): Promise<void> {
    if (this.disposed || ((this.busy || this.selecting) && this.account === owner())) { return; }
    const mine: number = ++this.epoch; this.account = owner();
    this.image = undefined; this.error = ''; this.busy = false; this.selecting = false;
    this.totalBytes = 0; this.uploadedBytes = 0;
    if (this.account.length === 0) { this.error = '登录后才能上传图片'; return; }
    this.selecting = true;
    try {
      const result = await pickUploadImage(forumName, () => this.current(mine));
      if (!this.current(mine)) { return; }
      this.selecting = false;
      if (result.cancelled) { return; }
      if (result.input === undefined) { this.error = result.message; return; }
      await this.upload(context, result.input);
    } catch (err) { if (this.current(mine)) { this.error = '图片准备失败，请重试'; } }
    finally {
      if (mine === this.epoch) {
        this.selecting = false;
        if (!this.disposed && this.account !== owner()) { this.error = '账号已变化，请重新选择图片'; }
      }
    }
  }
  async upload(context: common.UIAbilityContext, input: ImageUploadInput): Promise<void> {
    if (this.disposed || ((this.busy || this.selecting) && this.account === owner())) { return; }
    const mine: number = ++this.epoch; this.account = owner();
    this.image = undefined; this.error = ''; this.uploadedBytes = 0; this.totalBytes = 0; this.busy = false; this.selecting = false;
    if (this.account.length === 0) { this.error = '登录后才能上传图片'; return; }
    const invalid: string = imageUploadInputError(input);
    if (invalid.length > 0) { this.error = invalid; return; }
    const bytes: Uint8Array = input.bytes.slice();
    const width: number = input.width; const height: number = input.height; const forumName: string = input.forumName.trim();
    const userName: string = authSession.snapshot.userName;
    this.busy = true; this.totalBytes = bytes.length;
    try {
      const device = await DeviceIdentity.ensure(context);
      if (!this.current(mine)) { return; }
      const session = authSession.session();
      const watermark = await this.api.fetchImageWatermark(device, session);
      if (!this.current(mine)) { return; }
      if (!watermark.ok) { this.error = watermark.describeFailure(); return; }
      if (watermark.data.type === 1 && (typeof userName !== 'string' || userName.length === 0)) {
        this.error = '水印账号名未确认，请先刷新账号资料'; return;
      }
      const digest: string = await CryptoUtil.md5OfBytes(bytes);
      if (!this.current(mine)) { return; }
      const previewInput: ImageUploadInput = new ImageUploadInput();
      previewInput.bytes = bytes; previewInput.width = width; previewInput.height = height;
      const localPreview: string = await createReplyImagePreview(previewInput, () => this.current(mine));
      if (!this.current(mine)) { return; }
      const chunkSize: number = 512000; const count: number = Math.ceil(bytes.length / chunkSize);
      let chunkNo: number = 1; let redirects: number = 0;
      const accepted: Set<number> = new Set<number>();
      while (chunkNo <= count) {
        if (!this.current(mine)) { return; }
        const chunk: ImageUploadChunk = new ImageUploadChunk();
        chunk.digest = digest; chunk.totalSize = bytes.length; chunk.chunkSize = chunkSize; chunk.chunkNo = chunkNo;
        chunk.bytes = bytes.slice((chunkNo - 1) * chunkSize, Math.min(chunkNo * chunkSize, bytes.length));
        chunk.width = width; chunk.height = height; chunk.forumName = forumName; chunk.userName = userName;
        chunk.watermarkType = watermark.data.type;
        const chunkError: string = imageUploadChunkError(chunk);
        if (chunkError.length > 0) { this.error = chunkError; return; }
        const response = await this.api.uploadImageChunk(device, session, chunk);
        if (!this.current(mine)) { return; }
        if (!response.ok) {
          // 当前 c27 只对明确 CHUNK_ERROR 指定的不同正片号续传；未知写结果不重发。
          const next: number = response.data.resumeChunk;
          if (response.data.code === 2230203 && Number.isInteger(next) && next > 0 && next <= count && next !== chunkNo && redirects < 3) {
            redirects++;
            for (const previous of accepted) { if (previous >= next) { accepted.delete(previous); } }
            this.uploadedBytes = 0;
            for (const previous of accepted) { this.uploadedBytes += Math.min(chunkSize, bytes.length - (previous - 1) * chunkSize); }
            chunkNo = next; continue;
          }
          this.error = response.describeFailure(); return;
        }
        if (chunkNo === count) {
          if (!response.data.complete() || response.data.image === undefined || uploadedImageToken(response.data.image).length === 0) {
            this.error = '图片上传响应尚未确认完整图片'; return;
          }
          const image: UploadedPostImage = new UploadedPostImage(); image.id = response.data.image.id;
          image.width = response.data.image.width; image.height = response.data.image.height;
          image.previewUrl = response.data.image.previewUrl;
          image.localPreview = localPreview;
          this.image = image; this.uploadedBytes = bytes.length; return;
        }
        accepted.add(chunkNo);
        this.uploadedBytes = 0;
        for (const previous of accepted) { this.uploadedBytes += Math.min(chunkSize, bytes.length - (previous - 1) * chunkSize); }
        chunkNo++;
      }
    } catch (err) { if (this.current(mine)) { this.error = '图片上传未确认完成，请重试'; } }
    finally {
      if (mine === this.epoch) {
        this.busy = false;
        if (!this.disposed && this.account !== owner()) {
          this.image = undefined; this.uploadedBytes = 0; this.totalBytes = 0; this.error = '账号已变化，上传结果未确认';
        }
      }
    }
  }
  cancel(): void {
    this.epoch++; this.busy = false; this.selecting = false; this.image = undefined; this.totalBytes = 0; this.uploadedBytes = 0;
    this.error = '已停止后续上传，已发出的请求结果未确认';
  }
  dispose(): void { this.cancel(); this.disposed = true; this.error = ''; }
}
