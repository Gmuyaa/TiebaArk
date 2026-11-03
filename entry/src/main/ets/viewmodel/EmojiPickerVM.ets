import { common } from '@kit.AbilityKit';
import { MemeEmojiResponse, TiebaApi } from '../api/TiebaApi';
import { memeImageToken, MemePicItem } from '../model/MemeEmoji';
import { DeviceIdentity } from '../utils/DeviceIdentity';
import { TiebaDevice } from '../net/TiebaParams';
import { authSession } from '../auth/AuthSession';

/** 评论与发帖共用的表情加载与协议 token；仅在当前页面内保留。 */
@ObservedV2
export class EmojiPickerVM {
  private api: TiebaApi = new TiebaApi();
  /** 收藏表情列表（云端为空 = 空数组，不是错误） */
  @Trace memePics: MemePicItem[] = [];
  /** '' = 已就绪/未开始；'loading' = 在途；其它 = 面板展示的失败文案 */
  @Trace memeStateText: string = '';
  private memeLoadedOnce: boolean = false;
  private memeAccount: string = '';
  private loadEpoch: number = 0;
  /** 发帖 token 映射：显示 URL（thumbnail 优先）→ `#(pic,...)` 完整 token。
   * Map 不是 @Trace：界面渲染读 memePics，token 只在镜像提取时查表。 */
  private memeTokens: Map<string, string> = new Map<string, string>();

  /** 面板格子的显示 URL：缩略图优先，缺则原图 */
  memeDisplayUrl(item: MemePicItem): string {
    return item.thumbnail.length > 0 ? item.thumbnail : item.picUrl;
  }

  /** 镜像提取（richEditorReplyText）用的 token 查表 */
  memeTokenFor(url: string): string {
    const hit: string | undefined = this.memeTokens.get(url);
    return hit === undefined ? '' : hit;
  }

  /** token 查表入口（页面镜像函数只传 Map，不感知 VM） */
  memeTokenTable(): Map<string, string> {
    return this.memeTokens;
  }

  memeUrlFor(token: string): string {
    let found: string = '';
    this.memeTokens.forEach((value: string, key: string) => {
      if (found.length === 0 && value === token) {
        found = key;
      }
    });
    return found;
  }

  /** 失败重试：清掉"只拉一次"的闸再走同一条加载路径 */
  async retryMemePics(context: common.UIAbilityContext): Promise<void> {
    if (this.memeStateText === 'loading' && this.memeAccount === authSession.sessionKey()) { return; }
    this.memeLoadedOnce = false;
    this.memeStateText = '';
    await this.loadMemePics(context);
  }

  /** 首次拉取收藏表情 + 预计算每个条目的发帖 token 映射 */
  async loadMemePics(context: common.UIAbilityContext): Promise<void> {
    const key: string = authSession.sessionKey();
    if (this.memeAccount !== key) {
      this.memeAccount = key; this.memeLoadedOnce = false; this.memeStateText = '';
      this.memePics = []; this.memeTokens = new Map<string, string>();
    }
    if (this.memeLoadedOnce || this.memeStateText === 'loading') {
      return;
    }
    const mine: number = ++this.loadEpoch;
    this.memeStateText = 'loading';
    try {
      const device: TiebaDevice = await DeviceIdentity.ensure(context);
      if (key !== authSession.sessionKey() || mine !== this.loadEpoch) { return; }
      const response: MemeEmojiResponse =
        await this.api.fetchAllMeme(device, authSession.session());
      if (key !== authSession.sessionKey() || mine !== this.loadEpoch) { return; }
      if (!response.ok) {
        this.memeStateText = response.describeFailure();
        return;
      }
      // token 全部算完才放列表：先放列表后补映射会有"点到了但 token 没算完"的窗口
      const tokens: Map<string, string> = new Map<string, string>(this.memeTokens);
      const pics: MemePicItem[] = [];
      for (const item of response.data.pics) {
        const token: string = memeImageToken(item);
        const url: string = this.memeDisplayUrl(item);
        if (token.length === 0 || url.length === 0) { continue; }
        // 相同显示地址不能映射到不同图片；避免点到的预览与发送图片不一致。
        const previous: string | undefined = tokens.get(url);
        if (previous !== undefined && previous !== token) { continue; }
        tokens.set(url, token);
        pics.push(item);
      }
      this.memeTokens = tokens;
      this.memePics = pics;
      this.memeLoadedOnce = true;
      this.memeStateText = '';
    } catch (err) {
      if (key === authSession.sessionKey() && mine === this.loadEpoch) {
        this.memeStateText = `收藏表情加载失败：${(err as Error).message}`;
      }
    } finally {
      if (mine === this.loadEpoch && key !== authSession.sessionKey()) {
        this.memeStateText = ''; this.memeLoadedOnce = false; this.memePics = []; this.memeTokens.clear();
      }
    }
  }

}
