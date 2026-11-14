/**
 * 首页顶部频道页签样式 —— **持久化 + 广播**（依赖平台的那一半）。
 *
 * 与 `ThreadActionBarStore` 同构（刷新链路 / 保存错误与重试 / 读写取舍全部沿用，
 * 那边的详细注释不再重复）：纯逻辑在 `HomeTopNavStyle.ets`，本文件负责
 * `preferences` 读写与跨页广播，只能在设备上验证。
 *
 * `@ObservedV2` + `@Trace`：设置页改一次，`ForumListView`（`@ComponentV2`）
 * **下一帧**就是新样式 —— 首页在后台挂着也会跟着变，切回 Tab 即所见。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  DEFAULT_HOME_TOP_NAV_STYLE, HomeTopNavStyle, homeTopNavStyleLabel, normalizeHomeTopNavStyle
} from './HomeTopNavStyle';
import { PreferenceGate } from './PreferenceGate';

const DOMAIN: number = 0x0000;
const TAG: string = 'TiebaTopNav';

/** 正式存储 */
const STORE: string = 'tieba_topnav_prefs';
const KEY_STYLE: string = 'style';

/**
 * 全局单例：App 内只有一个"首页顶栏样式"偏好。
 *
 * 读取与落盘共用 `PreferenceGate` 的同一条队列：读盘不会与写入交错，且只读一次。
 */
@ObservedV2
export class HomeTopNavStore {
  /** 当前生效的首页顶栏样式。`@Trace` → 所有读到它的 V2 组件跟着重绘 */
  @Trace style: HomeTopNavStyle = DEFAULT_HOME_TOP_NAV_STYLE;
  @Trace saveError: string = '';

  private gate: PreferenceGate = new PreferenceGate();

  /**
   * 启动时读一次持久化偏好。
   *
   * ⚠️ 与 `MaterialManager.load` 同一个坑：ohosTest 进程里
   * `preferences.getPreferences(getAppContext())` 会抛 "context is invalid"，
   * 所以**调用方要传真实 UIAbilityContext**（`EntryAbility.onCreate` 的 `this.context`）。
   */
  async load(context: common.UIAbilityContext): Promise<void> {
    await this.gate.loadOnce(async (revision: number): Promise<void> => {
      try {
        await this.gate.enqueue(async (): Promise<void> => {
          const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
          if (await store.has(KEY_STYLE)) {
            const raw: number =
              (await store.get(KEY_STYLE, DEFAULT_HOME_TOP_NAV_STYLE as number)) as number;
            if (revision !== this.gate.revision()) { return; }
            this.style = normalizeHomeTopNavStyle(raw);
            if (raw !== (this.style as number)) {
              await store.put(KEY_STYLE, this.style as number);
              await store.flush();
            }
            hilog.info(DOMAIN, TAG, 'home top nav style loaded: %{public}s', this.describe());
            return;
          }
          if (revision !== this.gate.revision()) { return; }
          this.style = DEFAULT_HOME_TOP_NAV_STYLE;
          hilog.info(DOMAIN, TAG, 'home top nav style absent, keep default: %{public}s',
            this.describe());
        });
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'home top nav style load failed, keep default: %{public}s',
          String(e));
      } finally {
        // 读失败也不重试：与原实现一致。
        this.gate.markLoaded();
      }
    });
  }

  /**
   * 设置样式：改状态 → 落盘。
   *
   * 先改状态再落盘（同 `ThreadActionBarStore.setStyle`）：界面立刻响应，落盘失败也不回滚。
   */
  async setStyle(style: HomeTopNavStyle, context: common.UIAbilityContext): Promise<void> {
    const next: HomeTopNavStyle = normalizeHomeTopNavStyle(style as number);
    if (next === this.style) {
      if (this.saveError.length > 0) { await this.retrySave(context); }
      return;
    }
    this.style = next;
    hilog.info(DOMAIN, TAG, 'home top nav style -> %{public}s', this.describe());
    await this.retrySave(context);
  }

  async retrySave(context: common.UIAbilityContext): Promise<void> {
    const style: HomeTopNavStyle = this.style;
    const revision: number = this.gate.bump();
    try {
      await this.gate.enqueue(async (): Promise<void> => {
        const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
        await store.put(KEY_STYLE, style as number);
        await store.flush();
      });
      if (revision === this.gate.revision()) { this.saveError = ''; }
    } catch (e) {
      if (revision === this.gate.revision()) {
        this.saveError = '首页顶栏样式本次已生效，保存失败，重启后可能恢复旧值';
      }
      hilog.warn(DOMAIN, TAG, 'home top nav style save failed: %{public}s', String(e));
    }
  }

  /** 日志用的一行摘要 */
  describe(): string {
    return `${this.style}(${homeTopNavStyleLabel(this.style)})`;
  }
}

/** 全局单例 */
export const homeTopNavStore: HomeTopNavStore = new HomeTopNavStore();
