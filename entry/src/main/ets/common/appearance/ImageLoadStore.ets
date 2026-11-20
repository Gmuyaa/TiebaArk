/** 图片加载偏好（Wi-Fi / 移动数据清晰度与动图自动播放），含旧版低流量模式一次性迁移。 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferenceGate } from './PreferenceGate';
import {
  DEFAULT_GIF_AUTO_PLAY, DEFAULT_MOBILE_QUALITY, DEFAULT_WIFI_QUALITY,
  GifAutoPlay, ImageLoadPolicy, ImageQuality,
  imageLoadPolicy, parseGifAutoPlay, parseImageQuality
} from '../../model/ImageLoadPolicy';
import { networkKindWatch } from '../../utils/NetworkKindWatch';

const STORE: string = 'tieba_image_load_prefs';
const WIFI_KEY: string = 'wifi_quality';
const MOBILE_KEY: string = 'mobile_quality';
const GIF_KEY: string = 'gif_autoplay';
const LEGACY_STORE: string = 'tieba_low_flow_prefs';
const LEGACY_ENABLED_KEY: string = 'low_flow_enabled';

@ObservedV2
export class ImageLoadStore {
  @Trace wifi: ImageQuality = DEFAULT_WIFI_QUALITY;
  @Trace mobile: ImageQuality = DEFAULT_MOBILE_QUALITY;
  @Trace gif: GifAutoPlay = DEFAULT_GIF_AUTO_PLAY;
  /** 仅偏好变更或落盘恢复时递增；网络切换不递增，避免已显示的图整屏重下。 */
  @Trace revision: number = 0;
  @Trace saveError: string = '';
  private gate: PreferenceGate = new PreferenceGate();

  currentPolicy(): ImageLoadPolicy {
    return imageLoadPolicy(this.wifi, this.mobile, this.gif, networkKindWatch.kind);
  }

  isAutoLoadOff(): boolean {
    return this.currentPolicy().quality === ImageQuality.OFF;
  }

  async load(context: common.UIAbilityContext): Promise<void> {
    await this.gate.loadOnce(async (revision: number): Promise<void> => {
      try {
        const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
        const hasNew: boolean = (await store.has(WIFI_KEY)) || (await store.has(MOBILE_KEY)) || (await store.has(GIF_KEY));
        if (!hasNew) {
          const migrated: boolean = await this.migrateLegacyLowFlow(context, store, revision);
          if (migrated) { return; }
        }
        const wifi: ImageQuality = parseImageQuality(
          Number(await store.get(WIFI_KEY, DEFAULT_WIFI_QUALITY)), DEFAULT_WIFI_QUALITY);
        const mobile: ImageQuality = parseImageQuality(
          Number(await store.get(MOBILE_KEY, DEFAULT_MOBILE_QUALITY)), DEFAULT_MOBILE_QUALITY);
        const gif: GifAutoPlay = parseGifAutoPlay(
          Number(await store.get(GIF_KEY, DEFAULT_GIF_AUTO_PLAY)), DEFAULT_GIF_AUTO_PLAY);
        if (revision === this.gate.revision()) {
          const changed: boolean = this.wifi !== wifi || this.mobile !== mobile || this.gif !== gif;
          this.wifi = wifi;
          this.mobile = mobile;
          this.gif = gif;
          if (changed) { this.revision += 1; }
        }
      } catch (e) {
        hilog.warn(0x0, 'TiebaImageLoad', 'image load preference load failed: %{public}s', String(e));
      } finally {
        this.gate.markLoaded();
      }
    });
  }

  private async migrateLegacyLowFlow(
    context: common.UIAbilityContext,
    store: preferences.Preferences,
    revision: number
  ): Promise<boolean> {
    try {
      const legacy: preferences.Preferences = await preferences.getPreferences(context, LEGACY_STORE);
      const legacyOn: boolean = (await legacy.get(LEGACY_ENABLED_KEY, false)) === true;
      if (!legacyOn) { return false; }
      if (revision === this.gate.revision()) {
        this.wifi = ImageQuality.OFF;
        this.mobile = ImageQuality.OFF;
        this.gif = DEFAULT_GIF_AUTO_PLAY;
        this.revision += 1;
      }
      await store.put(WIFI_KEY, ImageQuality.OFF);
      await store.put(MOBILE_KEY, ImageQuality.OFF);
      await store.put(GIF_KEY, DEFAULT_GIF_AUTO_PLAY);
      await store.flush();
      await legacy.delete(LEGACY_ENABLED_KEY);
      await legacy.flush();
      return true;
    } catch (e) {
      hilog.warn(0x0, 'TiebaImageLoad', 'legacy low flow migration failed: %{public}s', String(e));
      return false;
    }
  }

  async setWifi(quality: ImageQuality, context: common.UIAbilityContext): Promise<void> {
    this.wifi = quality;
    this.revision += 1;
    await this.retrySave(context);
  }

  async setMobile(quality: ImageQuality, context: common.UIAbilityContext): Promise<void> {
    this.mobile = quality;
    this.revision += 1;
    await this.retrySave(context);
  }

  async setGif(gif: GifAutoPlay, context: common.UIAbilityContext): Promise<void> {
    this.gif = gif;
    this.revision += 1;
    await this.retrySave(context);
  }

  /** 写入当前快照并串行落盘；旧操作不得清除新操作的错误。 */
  async retrySave(context: common.UIAbilityContext): Promise<void> {
    const wifi: ImageQuality = this.wifi;
    const mobile: ImageQuality = this.mobile;
    const gif: GifAutoPlay = this.gif;
    const revision: number = this.gate.bump();
    try {
      await this.gate.enqueue(async (): Promise<void> => {
        const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
        await store.put(WIFI_KEY, wifi);
        await store.put(MOBILE_KEY, mobile);
        await store.put(GIF_KEY, gif);
        await store.flush();
      });
      if (revision === this.gate.revision()) { this.saveError = ''; }
    } catch (e) {
      if (revision === this.gate.revision()) {
        this.saveError = '图片加载设置本次已生效，保存失败，重启后可能恢复旧值';
      }
      hilog.warn(0x0, 'TiebaImageLoad', 'image load preference save failed: %{public}s', String(e));
    }
  }
}

export const imageLoadStore: ImageLoadStore = new ImageLoadStore();
