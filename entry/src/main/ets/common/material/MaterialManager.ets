/** 材质配置与偏好的统一管理入口。参数与槽位映射由 MaterialConfig 提供；mode 与 hdsLevel 使用独立 @Trace，调用组件需使用 V2 或接入对应刷新机制。 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { uiMaterial } from '@kit.ArkUI';
// `BackgroundEffectOptions` 是 ArkUI 的**环境类型**（组件声明里全局可见），不需要 import
import {
  CapsuleEdge,
  DEFAULT_MODE,
  GlassSpec,
  HdsMaterialEffect,
  MaterialBackend,
  MaterialMode,
  MaterialSlot,
  MATERIAL_KEY_MODE,
  MATERIAL_KEY_HDS_LEVEL,
  MATERIAL_STORE,
  SlotScrollSpec,
  immersiveStyleOf,
  edgeShadeOf,
  glassSpecAtProgress,
  glassSpecOf,
  hdsLevelOf,
  hdsTypeOf,
  materialBackendOf,
  modeLabel,
  normalizeMode,
  resolveMode,
  scrollProgressOf,
  scrollSpecOf,
  tintToColor
} from './MaterialConfig';
import { DEFAULT_HDS_LEVEL, HdsMaterialLevelPref, normalizeHdsLevel } from './MaterialStrength';

const DOMAIN: number = 0x0000;
const TAG: string = 'TiebaMaterial';

/** 官方材质对象**按「槽位 × 档位」缓存**：`ImmersiveMaterial` 不必每次 build 都 new */
type MaterialCache = Map<string, uiMaterial.Material>;

@ObservedV2
export class MaterialManager {
  /** 用户偏好档位。默认 `SYSTEM`（需求：当前阶段先使用统一默认值） */
  @Trace mode: MaterialMode = DEFAULT_MODE;
  @Trace hdsLevel: HdsMaterialLevelPref = DEFAULT_HDS_LEVEL;

  private cache: MaterialCache = new Map<string, uiMaterial.Material>();
  private loaded: boolean = false;

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
        `${this.mode}(${modeLabel(this.mode)})`);
    } catch (e) {
      this.loaded = true;
      hilog.warn(DOMAIN, TAG, 'material mode load failed, fallback to SYSTEM: %{public}s',
        String(e));
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

  /** 某槽位当前走哪条通道（官方 / 自绘） */
  backendOf(slot: MaterialSlot): MaterialBackend {
    return materialBackendOf(slot);
  }

  /**
   * 自绘玻璃参数；当前通道是 `OFFICIAL` 时返回 `undefined`（= 不施加任何背景效果）。
   *
   * 直接喂给 `.backgroundEffect(...)`，该 API 的签名是
   * `backgroundEffect(options: Optional<BackgroundEffectOptions>)`，吃 undefined。
   */
  glassOf(slot: MaterialSlot): BackgroundEffectOptions | undefined {
    if (this.backendOf(slot) !== MaterialBackend.GLASS) {
      return undefined;
    }
    const spec: GlassSpec = glassSpecOf(slot, this.modeOf(slot));
    return {
      radius: spec.radius,
      saturation: spec.saturation,
      brightness: spec.brightness,
      color: tintToColor(spec.tint)
    };
  }

  capsuleEdgeOf(slot: MaterialSlot): CapsuleEdge | undefined {
    return edgeShadeOf(slot);
  }

  glassAtOffset(slot: MaterialSlot, scrollOffset: number): BackgroundEffectOptions | undefined {
    if (this.backendOf(slot) !== MaterialBackend.GLASS) {
      return undefined;
    }
    const spec: SlotScrollSpec | undefined = scrollSpecOf(slot);
    const progress: number = spec === undefined ? 1 : scrollProgressOf(spec, scrollOffset);
    const glass: GlassSpec = glassSpecAtProgress(slot, this.modeOf(slot), progress);
    return {
      radius: glass.radius,
      saturation: glass.saturation,
      brightness: glass.brightness,
      color: tintToColor(glass.tint)
    };
  }

  /**
   * 官方沉浸材质对象；当前通道是 `GLASS` 时返回 `undefined`
   * （官方语义：`undefined` = 恢复组件默认的沉浸光感效果，**不等于**关闭）。
   *
   * 直接喂给 `.systemMaterial(...)`，签名 `systemMaterial(material: SystemUiMaterial | undefined)`。
   */
  officialOf(slot: MaterialSlot): uiMaterial.Material | undefined {
    if (this.backendOf(slot) !== MaterialBackend.OFFICIAL) {
      return undefined;
    }
    const mode: MaterialMode = this.modeOf(slot);
    const key: string = `${slot}:${mode}`;
    const hit: uiMaterial.Material | undefined = this.cache.get(key);
    if (hit !== undefined) {
      return hit;
    }
    const created: uiMaterial.Material = new uiMaterial.ImmersiveMaterial({
      style: immersiveStyleOf(mode)
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
    return `mode=${this.mode}(${modeLabel(this.mode)})`;
  }
}

/** 全局单例：App 内只有一个材质偏好 */
export const materialManager: MaterialManager = new MaterialManager();
