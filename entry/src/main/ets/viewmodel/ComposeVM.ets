import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import hilog from '@ohos.hilog';
import { AddThreadResponse } from '../api/ApiResponses';
import { TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { UploadedPostImage, uploadedImageToken } from '../model/ImageUpload';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { ImagePrepareResult, prepareUploadImage } from '../utils/ImagePrepare';
import { ImageUploadVM } from './ImageUploadVM';
import { deleteForumSnapshot } from '../utils/ForumSnapshotStore';
import { accountWithPortrait } from './SessionOwner';

export const COMPOSE_TYPES: string[] = ['文章', '帖子', '视频', '求助'];

/** 标题长度区间：与发帖页输入框提示"5–31个字"、`maxLength(31)` 保持一致。 */
export const TITLE_MIN_LENGTH: number = 5;
export const TITLE_MAX_LENGTH: number = 31;


/** 未接入发布的选项：发布前必须让用户明确知道会被忽略，不能静默丢弃。 */
export function unsupportedComposeOptions(draft: ComposeDraft): string[] {
  const list: string[] = [];
  // 话题、展示范围、内容声明都已接入发布参数，不再列在这里
  if (draft.mood.length > 0) { list.push(`心情（${draft.mood}）`); }
  return list;
}
/**
 * 组装正文：文字在前，已上传图片的 `#(pic,<id>,<w>,<h>)` 逐行追加在后。
 * 这是官方客户端的正文形态（见 `model/ImageUpload.ets` 的 `uploadedImageToken`）。
 */
export function composeBodyContent(body: string, images: UploadedPostImage[]): string {
  const text: string = body.trim();
  const tokens: string[] = [];
  for (const image of images) {
    const token: string = uploadedImageToken(image);
    if (token.length > 0) { tokens.push(token); }
  }
  if (tokens.length === 0) { return text; }
  return text.length > 0 ? `${text}\n${tokens.join('\n')}` : tokens.join('\n');
}

/**
 * 话题不能只发 `topic_id`，还要以 `#话题名#` 文本出现在帖子里。
 *
 * 取证：官方 PC 发帖页的话题是编辑器里的内联 chip（`innerText = "#" + name + "#"`），
 * 提交体只带正文、不带任何话题 id；话题联想接口 `/c/f/recommend/getSugTopic_pc` 里
 * 「常用话题」项的 `topic_id` 直接就是 `"0"`（只有名字）。说明服务端按 `#名字#` 认话题，
 * id 只是辅助关联，缺文本时整条话题被忽略。
 * 用户已经在标题或正文里手打过同一个话题就不重复插。
 */
export function composeBodyWithTopic(body: string, title: string, topic: string): string {
  // 选项写入的是纯名字，但用户手打过 `#名字#` 形态的也一并容错
  const name: string = topic.trim().replace(/^#+/, '').replace(/#+$/, '');
  if (name.length === 0) { return body; }
  const tag: string = `#${name}#`;
  if (title.includes(tag) || body.includes(tag)) { return body; }
  return body.length > 0 ? `${tag}\n${body}` : tag;
}

/** 发布结果：`message` 失败时是原因，成功时是提示文案。 */
export class ComposePublishResult {
  ok: boolean = false;
  message: string = '';
  /** 新帖 id；0 = 响应里没带，界面只能提示成功、无法跳转 */
  tid: number = 0;
  tidText: string = '';
}

/** 编辑内容只保留在本次页面内，退出即丢弃。 */
@ObservedV2
export class ComposeDraft {
  @Trace title: string = '';
  @Trace body: string = '';
  @Trace forum: string = '';
  @Trace forumId: number = 0;
  @Trace topic: string = '';
  @Trace topicId: number = 0;
  @Trace visibility: string = '全场景可见';
  @Trace declaration: string = '';
  @Trace mood: string = '';
  @Trace media: string[] = [];
  @Trace video: string = '';
}

@ObservedV2
export class ComposeVM {
  @Trace type: number = 1;
  @Trace drafts: ComposeDraft[] = [new ComposeDraft(), new ComposeDraft(), new ComposeDraft(), new ComposeDraft()];
  @Trace picking: boolean = false;
  @Trace error: string = '';
  /** 发布进行中：发布按钮与关闭动作都应让位，避免重复提交 */
  @Trace publishing: boolean = false;
  /** 发布阶段提示（如"正在上传图片 2/3"）；空闲时为空串 */
  @Trace publishStep: string = '';
  private alive: boolean = true;
  private publishEpoch: number = 0;
  private api: TiebaApi = new TiebaApi();
  private uploader: ImageUploadVM = new ImageUploadVM();

  get draft(): ComposeDraft { return this.drafts[this.type]; }

  hasContent(): boolean {
    return this.drafts.some((draft: ComposeDraft): boolean => draft.title.length > 0 || draft.body.length > 0 ||
      draft.media.length > 0 || draft.video.length > 0 || draft.forum.length > 0 || draft.topic.length > 0 ||
      draft.declaration.length > 0 || draft.mood.length > 0 || draft.visibility !== '全场景可见');
  }

  dispose(): void {
    this.alive = false;
    this.publishEpoch++;
    this.publishing = false;
    this.publishStep = '';
    this.uploader.dispose();
  }

  async pickMedia(asVideo: boolean = false): Promise<void> {
    if (this.picking || !this.alive) { return; }
    const type: number = this.type;
    const draft: ComposeDraft = this.drafts[type];
    const video: boolean = type === 2 || asVideo;
    const remaining: number = video ? 1 : 9 - draft.media.length;
    if (remaining <= 0) { this.error = '最多添加9张图片'; return; }
    this.picking = true;
    this.error = '';
    try {
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const selected = await picker.select({
        MIMEType: video ? photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE : photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: remaining
      });
      if (!this.alive || selected.photoUris.length === 0) { return; }
      // 结果归属打开选取器时的草稿，切页签不会将附件放进另一篇。
      if (asVideo && type !== 2) { draft.video = selected.photoUris[0]; }
      else {
        draft.media = video ? selected.photoUris.slice(0, 1) :
          Array.from(new Set<string>(draft.media.concat(selected.photoUris))).slice(0, 9);
      }
    } catch (err) {
      if (this.alive) { this.error = video ? '选择视频失败，请重试' : '选择图片失败，请重试'; }
    } finally {
      if (this.alive) { this.picking = false; }
    }
  }

  /**
   * 发布前的本地校验；返回空串表示可以发。
   *
   * 这里只挡**确定发不出去或会违背用户意图**的情况，不预先猜测服务端风控。
   */
  publishBlocked(): string {
    const draft: ComposeDraft = this.draft;
    if (!authSession.isLoggedIn()) { return '登录后才能发布'; }
    if (draft.forum.trim().length === 0 || draft.forumId <= 0) { return '请先选择要发布到哪个吧'; }
    if (this.type === 2) { return '视频帖暂未接入发布，请先切换为帖子或文章'; }
    if (draft.video.length > 0) { return '视频附件暂未接入发布，请先移除'; }
    const title: string = draft.title.trim();
    if (title.length === 0) { return '请输入标题'; }
    if (title.length < TITLE_MIN_LENGTH || title.length > TITLE_MAX_LENGTH) {
      return `标题需要 ${TITLE_MIN_LENGTH}–${TITLE_MAX_LENGTH} 个字`;
    }
    if (draft.body.trim().length === 0 && draft.media.length === 0) { return '请输入正文或添加图片'; }
    return '';
  }

  /**
   * 发布：校验 → 逐张上传图片 → 拼正文 → 提交 `/c/c/thread/add` → 成功后清空草稿与吧缓存。
   *
   * 图片是**串行**上传的：任一张失败就整体中止且已选图片保留，用户可重试；
   * 不并发上传是为了和回复框同一套顺序语义，也避免多张同时失败后分不清哪张缺。
   */
  async publish(context: common.UIAbilityContext): Promise<ComposePublishResult> {
    const result: ComposePublishResult = new ComposePublishResult();
    // 失败一律从这里出：界面提示、VM.error 常驻、hilog 留一条带步骤的痕迹。
    // hilog 缓冲会被系统其它应用的日志冲掉，所以界面必须常驻显示原因，不能只弹一次 toast。
    const fail = (message: string): ComposePublishResult => {
      result.message = message;
      this.error = message;
      hilog.warn(0x0000, 'ComposeVM', 'publish failed step=%{public}s reason=%{public}s',
        this.publishStep.length > 0 ? this.publishStep : 'precheck', message);
      return result;
    };
    if (this.publishing) { return fail('正在发布中，请稍候'); }
    const blocked: string = this.publishBlocked();
    if (blocked.length > 0) { return fail(blocked); }

    const account: string = accountWithPortrait();
    if (account.length === 0) { return fail('账号信息未就绪，请稍后重试'); }
    const type: number = this.type;
    const draft: ComposeDraft = this.drafts[type];
    const title: string = draft.title.trim();
    const body: string = draft.body;
    const media: string[] = draft.media.slice();
    const forumName: string = draft.forum.trim();
    const fid: number = draft.forumId;
    const topicId: number = draft.topicId;
    const topicName: string = draft.topic.trim();
    // 展示范围与内容声明：官方 PC 发帖页把范围映射成 is_hide（'0' 全场景可见 / '1' 个人主页不可见），
    // 内容声明直接传下发文案本身（见 `AddThreadParams.build` 注释里的取证）
    const isHide: string = draft.visibility === '个人主页不可见' ? '1' : '0';
    const contentStatement: string = draft.declaration;
    const mine: number = ++this.publishEpoch;
    const current = (): boolean => this.alive && mine === this.publishEpoch && account === accountWithPortrait();

    this.publishing = true;
    this.publishStep = '';
    this.error = '';
    try {
      const images: UploadedPostImage[] = [];
      for (let i = 0; i < media.length; i++) {
        if (!current()) { return fail('发布已取消'); }
        this.publishStep = `正在上传图片 ${i + 1}/${media.length}`;
        const prepared = await prepareUploadImage(media[i], forumName, current);
        if (!current()) { return fail('发布已取消'); }
        if (prepared.cancelled) { return fail('图片上传已中断，请重试'); }
        if (prepared.input === undefined) {
          return fail(prepared.message.length > 0 ? prepared.message : '图片准备失败，请重试');
        }
        await this.uploader.upload(context, prepared.input);
        if (!current()) { return fail('发布已取消'); }
        if (this.uploader.error.length > 0) { return fail(this.uploader.error); }
        const uploaded: UploadedPostImage | undefined = this.uploader.image;
        if (uploaded === undefined || uploadedImageToken(uploaded).length === 0) {
          return fail('图片上传未确认完成，请重试');
        }
        const snapshot: UploadedPostImage = new UploadedPostImage();
        snapshot.id = uploaded.id;
        snapshot.width = uploaded.width;
        snapshot.height = uploaded.height;
        snapshot.previewUrl = uploaded.previewUrl;
        snapshot.localPreview = uploaded.localPreview;
        images.push(snapshot);
      }

      this.publishStep = '正在提交';
      const content: string = composeBodyContent(composeBodyWithTopic(body, title, topicName), images);
      const device = await DeviceIdentity.ensure(context);
      if (!current()) { result.message = '发布已取消'; return result; }
      const session = authSession.session();
      const nickname: string = authSession.snapshot.nickname;
      const response: AddThreadResponse = await this.api.addThread(device, session, title, content,
        fid, forumName, nickname, topicId, isHide, contentStatement);
      if (!current()) { return result; }
      if (!response.ok) {
        return fail(response.describeFailure());
      }
      result.ok = true;
      result.tid = response.result.tid;
      result.tidText = response.result.tidText;
      result.message = '发布成功';
      // 该吧的列表快照已经过时：留着会让用户回到吧页看不见新帖
      try { await deleteForumSnapshot(context, authSession.forumCacheUid()); } catch (err) { /* 清缓存失败不影响发布结果 */ }
      this.clearDrafts();
      return result;
    } finally {
      if (mine === this.publishEpoch) {
        this.publishing = false;
        this.publishStep = '';
        this.uploader.cancel();
      }
    }
  }

  /** 发布成功后清掉四个页签的全部草稿：内容已经发出，不应再以"待发"状态留着。 */
  private clearDrafts(): void {
    this.drafts = [new ComposeDraft(), new ComposeDraft(), new ComposeDraft(), new ComposeDraft()];
  }
}
