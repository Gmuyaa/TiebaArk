import { common } from '@kit.AbilityKit';
import { authSession } from '../auth/AuthSession';
import { TiebaApi } from '../api/TiebaApi';
import { MemeEmojiData, MemePicItem, memeCollectionPayload, sameMemeCollection } from '../model/MemeEmoji';
import { ImageUploadInput, UploadedPostImage } from '../model/ImageUpload';
import { TiebaDevice, TiebaSession } from '../net/TiebaParams';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { ImageUploadVM } from './ImageUploadVM';

@ObservedV2
export class SavedEmojiManagerVM {
  @Trace pics: MemePicItem[] = [];
  @Trace selected: string[] = [];
  @Trace loading: boolean = false;
  @Trace busy: boolean = false;
  @Trace ready: boolean = false;
  @Trace editing: boolean = false;
  @Trace error: string = '';
  @Trace upload: ImageUploadVM = new ImageUploadVM();
  private api: TiebaApi = new TiebaApi();
  private account: string = '';
  private epoch: number = 0;
  private disposed: boolean = false;
  private invariantVerified: boolean = false;
  private current(mine: number, session: TiebaSession): boolean {
    return !this.disposed && mine === this.epoch && authSession.matchesSession(session, this.account);
  }
  private apply(data: MemeEmojiData): void {
    this.pics = data.pics; this.selected = []; this.ready = data.collectionComplete;
    if (!this.ready) { this.error = '收藏列表不完整，请重新加载后再整理'; }
  }
  toggle(id: string): void {
    if (!this.ready || this.busy || this.loading || !this.editing) { return; }
    this.selected = this.selected.indexOf(id) >= 0 ? this.selected.filter((value: string) => value !== id) : [...this.selected, id];
  }
  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.disposed || this.busy || this.loading) { return; }
    const mine: number = ++this.epoch; const session: TiebaSession = authSession.session();
    const key: string = authSession.sessionKey();
    if (key !== this.account) { this.pics = []; this.invariantVerified = false; }
    this.account = key; this.loading = true; this.error = ''; this.ready = false; this.selected = [];
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!this.current(mine, session)) { return; }
      const response = await this.api.fetchAllMeme(device, session);
      if (!this.current(mine, session)) { return; }
      if (!response.ok) { this.error = response.describeFailure(); return; }
      this.apply(response.data);
    } catch (err) { if (this.current(mine, session)) { this.error = '收藏加载失败，请重试'; } }
    finally {
      if (mine === this.epoch) {
        this.loading = false;
        if (!this.disposed && !authSession.matchesSession(session, this.account)) {
          this.pics = []; this.ready = false; this.error = '账号已变化，请重新加载收藏';
        }
      }
    }
  }
  /** 必须由用户确认后调用；失败或未知写结果不自动重试。 */
  async deleteSelected(context: common.UIAbilityContext): Promise<boolean> {
    if (!this.editing || this.selected.length === 0) { return false; }
    const ids: string[] = [...this.selected];
    return this.change(context, this.pics.filter((item: MemePicItem) => ids.indexOf(item.picId) < 0));
  }
  async add(context: common.UIAbilityContext): Promise<boolean> {
    if (this.disposed || this.busy || this.loading || !this.ready) { return false; }
    const mine: number = this.epoch; const session: TiebaSession = authSession.session();
    if (!this.current(mine, session)) { this.ready = false; this.error = '账号已变化，请重新加载收藏'; return false; }
    this.busy = true; this.error = '';
    try {
      await this.upload.pickAndUpload(context, '', true);
      if (!this.current(mine, session)) { return false; }
      const image: UploadedPostImage | undefined = this.upload.image;
      if (image === undefined) { this.error = this.upload.error; return false; }
      if (this.pics.some((item: MemePicItem) => item.picId === image.id)) { this.error = '这张图片已在收藏中'; return false; }
      const item: MemePicItem = new MemePicItem();
      item.picId = image.id; item.width = image.width; item.height = image.height;
      item.picUrl = image.previewUrl; item.thumbnail = image.localPreview;
      // 先解除本地选图锁，再由唯一同步入口持有写锁。
      this.busy = false;
      return await this.change(context, [...this.pics, item]);
    } catch (err) { this.error = '添加未完成，请重新加载后确认'; return false; }
    finally { if (mine === this.epoch) { this.busy = false; } }
  }
  /** 查看器明确点击收藏后，上传当前原图并沿用完整列表核对与写后读回。 */
  async addImage(context: common.UIAbilityContext, input: ImageUploadInput): Promise<boolean> {
    if (this.disposed || this.busy || this.loading) { return false; }
    await this.load(context);
    if (!this.ready || this.disposed) { return false; }
    const mine: number = this.epoch; const session: TiebaSession = authSession.session();
    this.busy = true; this.error = '';
    try {
      input.forCollection = true;
      await this.upload.upload(context, input);
      if (!this.current(mine, session)) { this.error = '账号已变化，请重新收藏'; return false; }
      const uploaded: UploadedPostImage | undefined = this.upload.image;
      if (uploaded === undefined) { this.error = this.upload.error || '图片上传未完成'; return false; }
      if (this.pics.some((item: MemePicItem) => item.picId === uploaded.id)) { this.error = '这张图片已在收藏中'; return false; }
      const item: MemePicItem = new MemePicItem();
      item.picId = uploaded.id; item.width = uploaded.width; item.height = uploaded.height;
      item.picUrl = uploaded.previewUrl; item.thumbnail = uploaded.localPreview;
      this.busy = false;
      return await this.change(context, [...this.pics, item]);
    } catch (err) { this.error = '添加未完成，请重新加载后确认'; return false; }
    finally { if (mine === this.epoch) { this.busy = false; } }
  }
  private async pause(): Promise<void> { await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 2000); }); }
  private async change(context: common.UIAbilityContext, target: MemePicItem[]): Promise<boolean> {
    if (this.disposed || this.busy || this.loading || !this.ready) { return false; }
    const mine: number = this.epoch; const session: TiebaSession = authSession.session();
    if (!this.current(mine, session)) { this.ready = false; this.error = '账号已变化，请重新加载收藏'; return false; }
    const baseline: MemePicItem[] = [...this.pics];
    const payload: string = memeCollectionPayload(target);
    if (payload.length === 0) { this.error = '图片信息不完整，无法同步收藏'; return false; }
    this.busy = true; this.error = '';
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (!this.current(mine, session)) { return false; }
      const fresh = await this.api.fetchAllMeme(device, session);
      if (!this.current(mine, session)) { return false; }
      if (!fresh.ok) { this.error = fresh.describeFailure(); return false; }
      if (!fresh.data.collectionComplete) { this.ready = false; this.error = '云端收藏列表不完整，请重新加载'; return false; }
      if (!sameMemeCollection(fresh.data.pics, baseline)) {
        this.apply(fresh.data); this.error = '收藏已在其他地方变化，请重新选择'; return false;
      }
      // 首次真实编辑前，先验证原样推回不改变已有收藏；不在打开页面时写入。
      if (!this.invariantVerified) {
        this.ready = false;
        const unchanged = await this.api.pushMemeCollect(device, session, memeCollectionPayload(baseline), Date.now());
        if (!this.current(mine, session)) { return false; }
        if (!unchanged.ok) { this.error = unchanged.describeFailure(); return false; }
        await this.pause(); if (!this.current(mine, session)) { return false; }
        const checked = await this.api.fetchAllMeme(device, session);
        if (!this.current(mine, session)) { return false; }
        if (!checked.ok || !checked.data.collectionComplete || !sameMemeCollection(checked.data.pics, baseline)) {
          this.error = '收藏同步未确认，请重新加载；本次增删尚未执行'; return false;
        }
        this.invariantVerified = true;
      }
      this.ready = false;
      const response = await this.api.pushMemeCollect(device, session, payload, Date.now());
      if (!this.current(mine, session)) { return false; }
      if (!response.ok) { this.error = response.describeFailure() + '；请重新加载确认收藏'; return false; }
      await this.pause(); if (!this.current(mine, session)) { return false; }
      const result = await this.api.fetchAllMeme(device, session);
      if (!this.current(mine, session)) { return false; }
      if (!result.ok || !result.data.collectionComplete) { this.error = '请求已发出，收藏结果未确认，请重新加载'; return false; }
      this.apply(result.data);
      if (!sameMemeCollection(result.data.pics, target)) { this.error = '云端收藏与预期不同，请检查后再整理'; return false; }
      return true;
    } catch (err) { if (this.current(mine, session)) { this.ready = false; this.error = '同步结果未确认，请重新加载收藏'; } return false; }
    finally {
      if (mine === this.epoch) {
        this.busy = false;
        if (!this.disposed && !authSession.matchesSession(session, this.account)) {
          this.pics = []; this.selected = []; this.ready = false; this.error = '账号已变化，请重新加载收藏';
        }
      }
    }
  }
  dispose(): void { this.disposed = true; ++this.epoch; this.upload.dispose(); this.pics = []; this.selected = []; }
}
