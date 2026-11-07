import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ImageLayoutMode, normalizeImageLayoutMode } from '../../model/ImageLayout';

const STORE: string = 'tieba_image_layout_prefs';
const MODE_KEY: string = 'mode';

/** 独立的本机存储边界；测试可控制读写完成顺序，不接触用户偏好。 */
export interface ImageLayoutPersistence {
  read(context?: common.UIAbilityContext): Promise<number | undefined>;
  write(mode: ImageLayoutMode, context?: common.UIAbilityContext): Promise<void>;
}

class PreferencesImageLayoutPersistence implements ImageLayoutPersistence {
  async read(context?: common.UIAbilityContext): Promise<number | undefined> {
    if (context === undefined) { throw new Error('Image layout preferences need an ability context'); }
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
    const raw = await store.get(MODE_KEY, ImageLayoutMode.MODERN);
    return typeof raw === 'number' ? raw : undefined;
  }

  async write(mode: ImageLayoutMode, context?: common.UIAbilityContext): Promise<void> {
    if (context === undefined) { throw new Error('Image layout preferences need an ability context'); }
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
    await store.put(MODE_KEY, mode as number);
    await store.flush();
  }
}

/** 本机阅读偏好；默认新版，退出登录与切换账号均不清除。 */
@ObservedV2
export class ImageLayoutStore {
  @Trace mode: ImageLayoutMode = ImageLayoutMode.MODERN;
  @Trace loadError: string = '';
  @Trace saveError: string = '';
  private loaded: boolean = false;
  private loading: Promise<void> | undefined = undefined;
  private writes: Promise<void> = Promise.resolve();
  private revision: number = 0;
  private persistence: ImageLayoutPersistence;

  constructor(persistence: ImageLayoutPersistence = new PreferencesImageLayoutPersistence()) {
    this.persistence = persistence;
  }

  async load(context?: common.UIAbilityContext): Promise<void> {
    if (this.loaded) { return; }
    if (this.loading !== undefined) { return this.loading; }
    const revision: number = this.revision;
    const operation: Promise<void> = this.readPreference(context, revision);
    this.loading = operation;
    // 在赋值之后清理：存储同步抛错也不能留下一个已完成的 loading，挡住后续重试。
    try { await operation; }
    finally { if (this.loading === operation) { this.loading = undefined; } }
  }

  private async readPreference(context: common.UIAbilityContext | undefined, revision: number): Promise<void> {
    try {
      const raw: number | undefined = await this.persistence.read(context);
      if (revision !== this.revision) { return; }
      const valid: boolean = raw === ImageLayoutMode.MODERN || raw === ImageLayoutMode.CLASSIC;
      this.mode = normalizeImageLayoutMode(raw === undefined ? -1 : raw);
      this.loadError = valid ? '' : '图片排布设置未识别，暂用新版，请重新选择';
      this.loaded = valid;
    } catch (_) {
      if (revision === this.revision) {
        this.loadError = '图片排布读取失败，暂时保留当前排布';
      }
      hilog.warn(0x0, 'TiebaImageLayout', 'image layout preference load failed');
    }
  }

  async setMode(mode: ImageLayoutMode, context?: common.UIAbilityContext): Promise<void> {
    this.mode = normalizeImageLayoutMode(mode as number);
    await this.retrySave(context);
  }

  /** 即时生效、串行落盘；旧读取与旧写入的结果不得覆盖最新选择或错误。 */
  async retrySave(context?: common.UIAbilityContext): Promise<void> {
    const mode: ImageLayoutMode = this.mode;
    const revision: number = ++this.revision;
    this.loaded = true;
    this.loadError = '';
    const operation: Promise<void> = this.writes.then(async (): Promise<void> => {
      await this.persistence.write(mode, context);
    });
    this.writes = operation.catch(() => {});
    try {
      await operation;
      if (revision === this.revision) { this.saveError = ''; }
    } catch (_) {
      if (revision === this.revision) {
        this.saveError = '图片排布本次已生效，保存失败，重启后可能恢复旧值';
      }
      hilog.warn(0x0, 'TiebaImageLayout', 'image layout preference save failed');
    }
  }
}

export const imageLayoutStore: ImageLayoutStore = new ImageLayoutStore();
