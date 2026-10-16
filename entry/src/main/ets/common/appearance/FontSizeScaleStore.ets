/** 字体大小偏好的持久化与应用。逻辑换算由 FontSizeScale 提供；应用后广播设置变化。 */

import { preferences } from '@kit.ArkData';
import { common, systemConfiguration } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  DEFAULT_FONT_SIZE_PREF, FONT_SIZE_BASE, FontSizePref, fontSizeLabel, fontSizeScaleOf,
  legacyFontSize, normalizeCustomFontSize, normalizeFontSizePref
} from './FontSizeScale';

const DOMAIN: number = 0x0000;
const TAG: string = 'TiebaFontSize';

/** 持久化存储与键名 */
const STORE: string = 'tieba_font_size_prefs';
const KEY_PREF: string = 'pref';
const KEY_CUSTOM_SIZE: string = 'customSize';

/**
 * 全局单例：App 内只有一个"字体大小"偏好。
 *
 * 与 `ThemeModeStore` 同一取舍：读/写失败一律静默（本次会话内仍生效，
 * 只是下次启动可能回到旧值）——偏好存储异常不该影响 App 启动。
 */
@ObservedV2
export class FontSizeScaleStore {
  /** 用户偏好：跟随系统或自定义。 */
  @Trace pref: FontSizePref = DEFAULT_FONT_SIZE_PREF;
  @Trace customSize: number = FONT_SIZE_BASE;

  /**
   * 系统当前字体缩放比（`onFontSizeScaleUpdated` 持续刷新；跟随系统档用它）。
   *
   * `@Trace`：暂无 UI 读它，但保留可观测性（后续若做"当前系统字号"展示直接可用）。
   */
  @Trace systemScale: number = 1.0;

  private loaded: boolean = false;

  /**
   * 启动时**同步**读偏好并立即应用（首帧前）。
   *
   * ⚠️ ohosTest 进程里 `preferences.getPreferences(getAppContext())` 会抛
   * "context is invalid"，所以**调用方要传真实 UIAbilityContext**（`EntryAbility.onCreate`）。
   * ⚠️ 任何一步失败都保持默认（跟随系统）：读不出偏好 = 老用户行为不变。
   */
  load(context: common.UIAbilityContext): void {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    try {
      const options: preferences.Options = { name: STORE };
      const store: preferences.Preferences = preferences.getPreferencesSync(context, options);
      const raw: number = store.getSync(KEY_PREF, DEFAULT_FONT_SIZE_PREF as number) as number;
      this.pref = normalizeFontSizePref(raw);
      this.customSize = raw === FontSizePref.SYSTEM || raw === FontSizePref.CUSTOM
        ? normalizeCustomFontSize(store.getSync(KEY_CUSTOM_SIZE, FONT_SIZE_BASE) as number)
        : normalizeCustomFontSize(legacyFontSize(raw));
    } catch (e) {
      this.pref = DEFAULT_FONT_SIZE_PREF;
      hilog.warn(DOMAIN, TAG, 'font size pref load failed, fallback to follow-system: %{public}s',
        String(e));
    }
    this.readSystemScale(context);
    this.watchSystem(context);
    this.apply(context);
    hilog.info(DOMAIN, TAG, 'font size loaded: %{public}s', this.describe());
  }

  /**
   * 设置偏好（设置页唯一入口）：改状态 → 应用 → 落盘。
   *
   * 先改状态再落盘（同 `ThemeModeStore.setMode`）：界面立刻响应，落盘失败也不回滚。
   * `setFontSizeScale` 是同步调用；全站字号重算与页面重绘由框架负责。
   */
  setPref(pref: FontSizePref, context: common.UIAbilityContext): void {
    const next: FontSizePref = normalizeFontSizePref(pref as number);
    if (next === this.pref) {
      return;
    }
    this.pref = next;
    this.apply(context);
    hilog.info(DOMAIN, TAG, 'font size -> %{public}s', this.describe());
    this.save(context);
  }

  /** 拖动时实时预览，松手后才写存储；旧档位迁移也统一落在新键上。 */
  setCustomSize(size: number, context: common.UIAbilityContext, persist: boolean = true): void {
    const next: number = normalizeCustomFontSize(size);
    if (next !== this.customSize || this.pref !== FontSizePref.CUSTOM) {
      this.customSize = next;
      this.pref = FontSizePref.CUSTOM;
      this.apply(context);
    }
    if (persist) {
      this.save(context);
    }
  }

  private save(context: common.UIAbilityContext): void {
    try {
      const options: preferences.Options = { name: STORE };
      const store: preferences.Preferences = preferences.getPreferencesSync(context, options);
      store.putSync(KEY_PREF, this.pref as number);
      store.putSync(KEY_CUSTOM_SIZE, this.customSize);
      store.flushSync();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'font size save failed: %{public}s', String(e));
    }
  }

  /**
   * 读系统此刻的字体缩放比，作为"跟随系统"的初始锚点。
   *
   * 应用声明 `fontSizeScale: followSystem` 后，首帧前、尚未调用
   * `setFontSizeScale` 时，`context.config.fontSizeScale` 才能作为系统值的
   * 初始锚点。进程内应用过固定档后，它可能是应用覆盖值，因此只在
   * `load` 里读取一次，之后靠系统监听刷新。
   */
  private readSystemScale(context: common.UIAbilityContext): void {
    try {
      const scale: number | undefined = context.config.fontSizeScale;
      if (scale !== undefined && Number.isFinite(scale) && scale > 0) {
        this.systemScale = scale;
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'read system font scale failed, keep 1.0: %{public}s', String(e));
    }
  }

  /**
   * 订阅系统字体变化（API 24+）：回调给的是**系统**的缩放比。
   *
   * - 自定义模式：只刷新 `systemScale` 缓存（应用观感不变）；
   * - 跟随系统档位：缓存刷新后立即重新应用，实现"实时跟随"。
   *
   * SDK 将回调参数定义为系统字号，去重应比较上一次系统值。若与应用上次
   * 设置值比较，系统刚好切到该值时会漏更新缓存，之后切回跟随系统会用旧值。
   */
  private watchSystem(context: common.UIAbilityContext): void {
    try {
      const callback: systemConfiguration.UpdatedCallback = {
        onFontSizeScaleUpdated: (scale: number): void => {
          if (!Number.isFinite(scale) || scale <= 0 || scale === this.systemScale) {
            return;
          }
          this.systemScale = scale;
          hilog.info(DOMAIN, TAG, 'system font scale -> %{public}s', String(scale));
          if (this.pref === FontSizePref.SYSTEM) {
            this.apply(context);
          }
        }
      };
      context.getApplicationContext().onSystemConfigurationUpdated(callback);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'watch system font scale failed: %{public}s', String(e));
    }
  }

  /**
   * 把偏好应用到应用级字体缩放比。
   *
   * 跟随系统档 = 钉在 `systemScale`（实时值）；自定义 = 基准字号 / 16。
   * 全站 fp 字号 = 设计值 × 缩放比，重算与重绘由框架负责。
   */
  private apply(context: common.UIAbilityContext): void {
    const scale: number = fontSizeScaleOf(this.pref, this.systemScale, this.customSize);
    try {
      context.getApplicationContext().setFontSizeScale(scale);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'setFontSizeScale failed: %{public}s', String(e));
    }
  }

  /** 日志用的一行摘要 */
  describe(): string {
    return `${this.pref}(${fontSizeLabel(this.pref)}), customSize=${this.customSize}, systemScale=${String(this.systemScale)}`;
  }
}

/** 全局单例：App 内只有一个字体大小偏好 */
export const fontScaleStore: FontSizeScaleStore = new FontSizeScaleStore();
