

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  DEFAULT_ACTION_BAR_STYLE, ThreadActionBarStyle, actionBarStyleLabel, normalizeActionBarStyle
} from './ThreadActionBarStyle';

const DOMAIN: number = 0x0000;
const TAG: string = 'TiebaActionBar';

const STORE: string = 'tieba_actionbar_prefs';

const LEGACY_STORE: string = 'tieba_exp_actionbar';
const KEY_STYLE: string = 'style';

@ObservedV2
export class ThreadActionBarStore {

  @Trace style: ThreadActionBarStyle = DEFAULT_ACTION_BAR_STYLE;

  private loaded: boolean = false;

  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      if (await store.has(KEY_STYLE)) {
        const raw: number = (await store.get(KEY_STYLE, DEFAULT_ACTION_BAR_STYLE as number)) as number;
        this.style = normalizeActionBarStyle(raw);
        hilog.info(DOMAIN, TAG, 'action bar style loaded: %{public}s', this.describe());
        return;
      }
      this.style = await this.migrateFromLegacy(context, store);
      hilog.info(DOMAIN, TAG, 'action bar style migrated: %{public}s', this.describe());
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'action bar style load failed, keep default: %{public}s', String(e));
    }
  }

  private async migrateFromLegacy(context: common.UIAbilityContext,
    store: preferences.Preferences): Promise<ThreadActionBarStyle> {
    let style: ThreadActionBarStyle = DEFAULT_ACTION_BAR_STYLE;
    try {
      const legacy: preferences.Preferences =
        await preferences.getPreferences(context, LEGACY_STORE);
      if (await legacy.has(KEY_STYLE)) {
        const raw: number = (await legacy.get(KEY_STYLE, DEFAULT_ACTION_BAR_STYLE as number)) as number;
        style = normalizeActionBarStyle(raw);
        hilog.info(DOMAIN, TAG, 'migrating action bar style from legacy store: %{public}s',
          `${raw} -> ${style}(${actionBarStyleLabel(style)})`);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'legacy action bar store unreadable: %{public}s', String(e));
    }
    await store.put(KEY_STYLE, style as number);
    await store.flush();
    return style;
  }

  async setStyle(style: ThreadActionBarStyle, context: common.UIAbilityContext): Promise<void> {
    const next: ThreadActionBarStyle = normalizeActionBarStyle(style as number);
    if (next === this.style) {
      return;
    }
    this.style = next;
    hilog.info(DOMAIN, TAG, 'action bar style -> %{public}s', this.describe());
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      await store.put(KEY_STYLE, next as number);
      await store.flush();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'action bar style save failed: %{public}s', String(e));
    }
  }

  describe(): string {
    return `${this.style}(${actionBarStyleLabel(this.style)})`;
  }
}

export const threadActionBarStore: ThreadActionBarStore = new ThreadActionBarStore();
