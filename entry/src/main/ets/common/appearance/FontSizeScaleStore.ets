

import { preferences } from '@kit.ArkData';
import { common, systemConfiguration } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  DEFAULT_FONT_SIZE_PREF, FONT_SIZE_BASE, FontSizePref, fontSizeLabel, fontSizeScaleOf,
  legacyFontSize, normalizeCustomFontSize, normalizeFontSizePref
} from './FontSizeScale';

const DOMAIN: number = 0x0000;
const TAG: string = 'TiebaFontSize';

const STORE: string = 'tieba_font_size_prefs';
const KEY_PREF: string = 'pref';
const KEY_CUSTOM_SIZE: string = 'customSize';

@ObservedV2
export class FontSizeScaleStore {

  @Trace pref: FontSizePref = DEFAULT_FONT_SIZE_PREF;
  @Trace customSize: number = FONT_SIZE_BASE;

  @Trace systemScale: number = 1.0;

  private loaded: boolean = false;

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

  private apply(context: common.UIAbilityContext): void {
    const scale: number = fontSizeScaleOf(this.pref, this.systemScale, this.customSize);
    try {
      context.getApplicationContext().setFontSizeScale(scale);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'setFontSizeScale failed: %{public}s', String(e));
    }
  }

  describe(): string {
    return `${this.pref}(${fontSizeLabel(this.pref)}), customSize=${this.customSize}, systemScale=${String(this.systemScale)}`;
  }
}

export const fontScaleStore: FontSizeScaleStore = new FontSizeScaleStore();
