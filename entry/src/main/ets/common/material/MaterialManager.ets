

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { uiMaterial } from '@kit.ArkUI';

import {
  CapsuleEdge,
  DEFAULT_MODE,
  GlassSpec,
  HdsMaterialEffect,
  MaterialBackend,
  MaterialMode,
  MaterialSlot,
  MATERIAL_KEY_MODE,
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

const DOMAIN: number = 0x0000;
const TAG: string = 'TiebaMaterial';

type MaterialCache = Map<string, uiMaterial.Material>;

@ObservedV2
export class MaterialManager {

  @Trace mode: MaterialMode = DEFAULT_MODE;

  private cache: MaterialCache = new Map<string, uiMaterial.Material>();
  private loaded: boolean = false;

  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      return;
    }
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, MATERIAL_STORE);
      const raw: number = (await store.get(MATERIAL_KEY_MODE, DEFAULT_MODE as number)) as number;
      this.mode = normalizeMode(raw);
      this.loaded = true;
      hilog.info(DOMAIN, TAG, 'material mode loaded: %{public}s',
        `${this.mode}(${modeLabel(this.mode)})`);
    } catch (e) {
      this.loaded = true;
      hilog.warn(DOMAIN, TAG, 'material mode load failed, fallback to SYSTEM: %{public}s',
        String(e));
    }
  }

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

  modeOf(slot: MaterialSlot): MaterialMode {
    return resolveMode(slot, this.mode);
  }

  backendOf(slot: MaterialSlot): MaterialBackend {
    return materialBackendOf(slot);
  }

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

  hdsEffectOf(slot: MaterialSlot): HdsMaterialEffect {
    const mode: MaterialMode = this.modeOf(slot);
    return {
      materialType: hdsTypeOf(mode),
      materialLevel: hdsLevelOf(mode)
    };
  }

  describe(): string {
    return `mode=${this.mode}(${modeLabel(this.mode)})`;
  }
}

export const materialManager: MaterialManager = new MaterialManager();
