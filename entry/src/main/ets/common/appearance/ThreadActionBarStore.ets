/** 操作栏样式的持久化与变更广播。优先读取当前存储；缺失时只读旧存储并迁移，旧值由 normalizeActionBarStyle 归一。 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  DEFAULT_ACTION_BAR_STYLE, ThreadActionBarStyle, actionBarStyleLabel, normalizeActionBarStyle
} from './ThreadActionBarStyle';

const DOMAIN: number = 0x0000;
const TAG: string = 'TiebaActionBar';

/** 正式存储 */
const STORE: string = 'tieba_actionbar_prefs';

const LEGACY_STORE: string = 'tieba_exp_actionbar';
const KEY_STYLE: string = 'style';

/**
 * 全局单例：App 内只有一个"详情页操作栏样式"偏好。
 *
 * `loaded` 保证只读一次盘；保存失败保持本次效果，并向设置页提供错误与重试。
 */
@ObservedV2
export class ThreadActionBarStore {
  /** 当前生效的操作栏样式。`@Trace` → 所有读到它的 V2 组件跟着重绘 */
  @Trace style: ThreadActionBarStyle = DEFAULT_ACTION_BAR_STYLE;
  @Trace saveError: string = '';

  private loaded: boolean = false;
  private writes: Promise<void> = Promise.resolve();
  private saveRevision: number = 0;

  /**
   * 启动时读一次持久化偏好（正式存储 → 缺失则尝试从实验存储迁移）。
   *
   * ⚠️ 与 `MaterialManager.load` 同一个坑：ohosTest 进程里
   * `preferences.getPreferences(getAppContext())` 会抛 "context is invalid"，
   * 所以**调用方要传真实 UIAbilityContext**（`EntryAbility.onCreate` 的 `this.context`）。
   */
  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    const revision: number = this.saveRevision;
    const operation: Promise<void> = this.writes.then(async (): Promise<void> => {
      try {
        const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
        if (await store.has(KEY_STYLE)) {
          const raw: number = (await store.get(KEY_STYLE, DEFAULT_ACTION_BAR_STYLE as number)) as number;
          if (revision !== this.saveRevision) { return; }
          this.style = normalizeActionBarStyle(raw);
          if (raw !== (this.style as number)) {
            await store.put(KEY_STYLE, this.style as number);
            await store.flush();
          }
          hilog.info(DOMAIN, TAG, 'action bar style loaded: %{public}s', this.describe());
          return;
        }
        const style: ThreadActionBarStyle = await this.migrateFromLegacy(context, store);
        if (revision !== this.saveRevision) { return; }
        this.style = style;
        hilog.info(DOMAIN, TAG, 'action bar style migrated: %{public}s', this.describe());
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'action bar style load failed, keep default: %{public}s', String(e));
      }
    });
    this.writes = operation;
    await operation;
  }

  /**
   * 旧实验存储 → 正式存储的一次性迁移。
   *
   * 读不到（从未装过带实验入口的版本）就用默认值；读到任何值都过一遍
   * `normalizeActionBarStyle`，由它负责"已淘汰的悬浮 Dock → 分离式"与其他脏值回落。
   * 迁移结果当场落盘，所以只会执行一次。
   */
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

  /**
   * 设置样式：改状态 → 落盘。
   *
   * 先改状态再落盘（同 `MaterialManager.setMode`）：界面立刻响应，落盘失败也不回滚。
   */
  async setStyle(style: ThreadActionBarStyle, context: common.UIAbilityContext): Promise<void> {
    const next: ThreadActionBarStyle = normalizeActionBarStyle(style as number);
    if (next === this.style) {
      if (this.saveError.length > 0) { await this.retrySave(context); }
      return;
    }
    this.style = next;
    hilog.info(DOMAIN, TAG, 'action bar style -> %{public}s', this.describe());
    await this.retrySave(context);
  }

  async retrySave(context: common.UIAbilityContext): Promise<void> {
    const style: ThreadActionBarStyle = this.style;
    const revision: number = ++this.saveRevision;
    const operation: Promise<void> = this.writes.then(async (): Promise<void> => {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      await store.put(KEY_STYLE, style as number);
      await store.flush();
    });
    this.writes = operation.catch(() => {});
    try {
      await operation;
      if (revision === this.saveRevision) { this.saveError = ''; }
    } catch (e) {
      if (revision === this.saveRevision) {
        this.saveError = '帖子底栏样式本次已生效，保存失败，重启后可能恢复旧值';
      }
      hilog.warn(DOMAIN, TAG, 'action bar style save failed: %{public}s', String(e));
    }
  }

  /** 日志用的一行摘要 */
  describe(): string {
    return `${this.style}(${actionBarStyleLabel(this.style)})`;
  }
}

/** 全局单例 */
export const threadActionBarStore: ThreadActionBarStore = new ThreadActionBarStore();
