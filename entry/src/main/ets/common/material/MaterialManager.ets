/** 材质配置与偏好的统一管理入口。参数与槽位映射由 MaterialConfig 提供；mode 与 hdsLevel 使用独立 @Trace，调用组件需使用 V2 或接入对应刷新机制。 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { uiMaterial } from '@kit.ArkUI';
import { MotionEffect } from '../appearance/MotionConfig';
import { motionStore } from '../appearance/MotionStore';
import {
  DEFAULT_MODE, HdsMaterialEffect, MaterialMode, MaterialSlot,
  MATERIAL_KEY_MODE, MATERIAL_KEY_HDS_LEVEL, MATERIAL_STORE,
  immersiveStyleOf, hdsLevelOf, hdsTypeOf, modeLabel, normalizeMode, resolveMode
} from './MaterialConfig';
import { DEFAULT_HDS_LEVEL, HdsMaterialLevelPref, normalizeHdsLevel } from './MaterialStrength';

const DOMAIN: number = 0x0000;
const TAG: string = 'TiebaMaterial';

/** 官方材质对象按「槽位 × 档位 × 阴影开关」缓存：`ImmersiveMaterial` 不必每次 build 都 new */
type MaterialCache = Map<string, uiMaterial.ImmersiveMaterial>;

@ObservedV2
export class MaterialManager {
  /** 用户偏好档位。默认 `SYSTEM`（需求：当前阶段先使用统一默认值） */
  @Trace mode: MaterialMode = DEFAULT_MODE;
  @Trace hdsLevel: HdsMaterialLevelPref = DEFAULT_HDS_LEVEL;
  /** 由已就绪页面的 UI 作用域检测；ArkUI 不可用时悬浮面才回退 HDS。 */
  @Trace useArkUI: boolean = true;

  private cache: MaterialCache = new Map<string, uiMaterial.ImmersiveMaterial>();
  private loaded: boolean = false;
  private feedbackKey: string = '';

  /**
   * 启动时读一次持久化偏好。
   *
   * 失败一律静默回落到 `SYSTEM`：材质偏好读不出来不该影响 App 启动
   * （与 `SearchHistory` / `DeviceIdentity` 同一取舍）。
   * ⚠️ ohosTest 进程里 `preferences.getPreferences(getAppContext())` 会抛
   * "context is invalid"，所以**调用方要传真实 UIAbilityContext**
   * （`EntryAbility.onCreate` 的 `this.context`）。
   */
  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      return;
    }
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, MATERIAL_STORE);
      const raw: number = (await store.get(MATERIAL_KEY_MODE, DEFAULT_MODE as number)) as number;
      this.mode = normalizeMode(raw);
      const rawHds: number = (await store.get(MATERIAL_KEY_HDS_LEVEL, DEFAULT_HDS_LEVEL as number)) as number;
      this.hdsLevel = normalizeHdsLevel(rawHds);
      this.loaded = true;
      hilog.info(DOMAIN, TAG, 'material mode loaded: %{public}s',
        this.describe());
    } catch (e) {
      this.loaded = true;
      hilog.warn(DOMAIN, TAG, 'material mode load failed, fallback to SYSTEM: %{public}s',
        String(e));
    }
  }

  /**
   * 仅由已就绪页面通过 UIContext.runScopedTask 调用。
   * Ability.onCreate 中无 UI 容器，查询可能返回 false，不能据此全局关闭材质。
   * load 只加载偏好，不做依赖 UI 作用域的能力判断。
   */
  refreshCapabilities(): void {
    try {
      this.useArkUI = uiMaterial.isImmersiveMaterialSupported();
      hilog.info(DOMAIN, TAG, 'ArkUI material capability in UI scope: %{public}s', `${this.useArkUI}`);
    } catch (error) {
      this.useArkUI = false;
      hilog.warn(DOMAIN, TAG, 'ArkUI material capability query failed: %{public}s', String(error));
    }
  }

  /**
   * 设置档位：改状态 → 清缓存 → 落盘。
   *
   * 先改状态再落盘：界面立刻响应，落盘失败也不回滚
   * （本次会话内一致，下次启动可能回到旧值——与搜索历史的取舍一致）。
   */
  async setMode(mode: MaterialMode, context: common.UIAbilityContext): Promise<void> {
    const next: MaterialMode = normalizeMode(mode as number);
    if (next === this.mode) {
      return;
    }
    this.mode = next;
    this.cache.clear();
    hilog.info(DOMAIN, TAG, 'material mode -> %{public}s', `${next}(${modeLabel(next)})`);
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, MATERIAL_STORE);
      await store.put(MATERIAL_KEY_MODE, next as number);
      await store.flush();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'material mode save failed: %{public}s', String(e));
    }
  }

  /** 独立设置HDS等级，仅写入hdsLevel键，不改五档厚度及其缓存。 */
  async setHdsLevel(level: HdsMaterialLevelPref, context: common.UIAbilityContext): Promise<void> {
    const next: HdsMaterialLevelPref = normalizeHdsLevel(level as number);
    if (next === this.hdsLevel) { return; }
    this.hdsLevel = next;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, MATERIAL_STORE);
      await store.put(MATERIAL_KEY_HDS_LEVEL, next as number);
      await store.flush();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'HDS level save failed: %{public}s', String(e));
    }
  }

  /** 某槽位当前实际生效的厚度（SYSTEM按槽位默认解析） */
  modeOf(slot: MaterialSlot): MaterialMode {
    return resolveMode(slot, this.mode);
  }

  /** 官方材质按用途、厚度与阴影开关复用；不提供自绘模糊回退。 */
  officialOf(slot: MaterialSlot, applyShadow: boolean = true): uiMaterial.ImmersiveMaterial | undefined {
    if (!this.useArkUI) {
      return undefined;
    }
    const interactive: boolean = motionStore.isOn(MotionEffect.DEFORMATION);
    const light: boolean = motionStore.isOn(MotionEffect.TOUCH_LIGHT);
    const feedbackKey: string = `${interactive}:${light}`;
    if (feedbackKey !== this.feedbackKey) {
      this.cache.clear();
      this.feedbackKey = feedbackKey;
    }
    const mode: MaterialMode = this.modeOf(slot);
    const key: string = `${slot}:${mode}:${applyShadow}`;
    const hit: uiMaterial.ImmersiveMaterial | undefined = this.cache.get(key);
    if (hit !== undefined) {
      return hit;
    }
    const created: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
      style: immersiveStyleOf(mode), applyShadow: applyShadow,
      interactive: interactive, lightEffect: light ? {} : null,
      materialColor: slot === MaterialSlot.FORUM_TAB_SELECTION ? '#30569CFF' : undefined
    });
    this.cache.set(key, created);
    return created;
  }

  /** HDS 组件（底栏 `HdsTabs.barFloatingStyle`）的材质参数 */
  hdsEffectOf(_slot: MaterialSlot): HdsMaterialEffect {
    return {
      materialType: hdsTypeOf(MaterialMode.SYSTEM),
      materialLevel: hdsLevelOf(this.hdsLevel)
    };
  }

  /** 日志用的一行摘要 */
  describe(): string {
    return `backend=${this.useArkUI ? 'ArkUI' : 'HDS'},mode=${this.mode}(${modeLabel(this.mode)})`;
  }
}

/** 全局单例：App 内只有一个材质偏好 */
export const materialManager: MaterialManager = new MaterialManager();
