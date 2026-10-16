

import { uiMaterial } from '@kit.ArkUI';
import { hdsMaterial, SystemMaterialParams, HdsTabsBackgroundStyle } from '@kit.UIDesignKit';

export enum MaterialMode {

  SYSTEM = 0,

  ULTRA_THIN = 1,

  THIN = 2,

  REGULAR = 3,

  THICK = 4,

  ULTRA_THICK = 5
}

export enum MaterialSlot {

  BACK_BUTTON = 0,

  NAV_BAR = 1,

  SEARCH_BAR = 2,

  BOTTOM_BAR = 3,

  SHEET = 4,

  BOTTOM_FLOATING_BAR = 5,

  REPLY_SHEET = 6,

  HOME_TOP_ISLAND = 7,

  HOME_TOP_CONTINUOUS = 8
}

export enum MaterialBackend {

  OFFICIAL = 0,

  GLASS = 1
}

export interface GlassTint {
  r: number;
  g: number;
  b: number;
  a: number;
}

export interface GlassSpec {
  radius: number;
  tint: GlassTint;
  saturation: number;
  brightness: number;
}

export interface CapsuleEdge {

  width: number;

  color: string;
}

export type HdsMaterialEffect = SystemMaterialParams;

export const SPLIT_PILL_GRADIENT_MASK: HdsTabsBackgroundStyle = {
  maskColor: '#00000000',
  maskHeight: 0
};

interface SlotDefaults {
  mode: MaterialMode;
  radius: number;
  tint: GlassTint;
  saturation: number;

  brightness: number;
}

export const DEFAULT_MODE: MaterialMode = MaterialMode.SYSTEM;

export const PLAIN_COMPONENT_BACKEND: MaterialBackend = MaterialBackend.GLASS;

export function materialBackendOf(slot: MaterialSlot): MaterialBackend {

  return slot === MaterialSlot.BOTTOM_BAR || slot === MaterialSlot.SHEET
    || slot === MaterialSlot.REPLY_SHEET || slot === MaterialSlot.HOME_TOP_ISLAND
    || slot === MaterialSlot.HOME_TOP_CONTINUOUS
    ? MaterialBackend.OFFICIAL
    : PLAIN_COMPONENT_BACKEND;
}

export const MATERIAL_STORE: string = 'tieba_material_prefs';
export const MATERIAL_KEY_MODE: string = 'mode';

function slotDefaults(slot: MaterialSlot): SlotDefaults {
  const backButton: SlotDefaults = {
    mode: MaterialMode.ULTRA_THIN,
    radius: 30,

    tint: { r: 255, g: 255, b: 255, a: 0.62 },
    saturation: 1.0,
    brightness: 1.0
  };

  const navBar: SlotDefaults = {
    mode: MaterialMode.THIN,
    radius: 40,
    tint: { r: 255, g: 255, b: 255, a: 0.30 },
    saturation: 1.2,
    brightness: 1.0
  };
  const bottomBar: SlotDefaults = {
    mode: MaterialMode.THIN,
    radius: 40,
    tint: { r: 255, g: 255, b: 255, a: 0.50 },
    saturation: 1.2,
    brightness: 1.0
  };

  const bottomFloatingBar: SlotDefaults = {
    mode: MaterialMode.REGULAR,
    radius: 20,
    tint: { r: 250, g: 250, b: 251, a: 0.76 },
    saturation: 1.15,
    brightness: 1.04
  };

  const sheet: SlotDefaults = {
    mode: MaterialMode.THICK,
    radius: 40,
    tint: { r: 255, g: 255, b: 255, a: 0.60 },
    saturation: 1.2,
    brightness: 1.0
  };

  const replySheet: SlotDefaults = {
    mode: MaterialMode.THICK,
    radius: 40,
    tint: { r: 255, g: 255, b: 255, a: 0.22 },
    saturation: 1.4,
    brightness: 1.0
  };

  const homeTopIsland: SlotDefaults = {
    mode: MaterialMode.THIN,
    radius: 22,
    tint: { r: 255, g: 255, b: 255, a: 0.16 },
    saturation: 1.35,
    brightness: 1.0
  };

  const homeTopContinuous: SlotDefaults = {
    mode: MaterialMode.THIN,
    radius: 40,
    tint: { r: 255, g: 255, b: 255, a: 0.30 },
    saturation: 1.2,
    brightness: 1.0
  };

  switch (slot) {
    case MaterialSlot.BACK_BUTTON:
      return backButton;
    case MaterialSlot.NAV_BAR:
    case MaterialSlot.SEARCH_BAR:
      return navBar;
    case MaterialSlot.BOTTOM_BAR:
      return bottomBar;
    case MaterialSlot.BOTTOM_FLOATING_BAR:
      return bottomFloatingBar;
    case MaterialSlot.SHEET:
      return sheet;
    case MaterialSlot.REPLY_SHEET:
      return replySheet;
    case MaterialSlot.HOME_TOP_ISLAND:
      return homeTopIsland;
    case MaterialSlot.HOME_TOP_CONTINUOUS:
      return homeTopContinuous;
    default:
      return navBar;
  }
}

export function defaultModeOf(slot: MaterialSlot): MaterialMode {
  return slotDefaults(slot).mode;
}

export function resolveMode(slot: MaterialSlot, userMode: MaterialMode): MaterialMode {
  return userMode === MaterialMode.SYSTEM ? defaultModeOf(slot) : userMode;
}

export function immersiveStyleOf(mode: MaterialMode): uiMaterial.ImmersiveStyle {
  switch (mode) {
    case MaterialMode.ULTRA_THIN:
      return uiMaterial.ImmersiveStyle.ULTRA_THIN;
    case MaterialMode.THIN:
      return uiMaterial.ImmersiveStyle.THIN;
    case MaterialMode.THICK:
      return uiMaterial.ImmersiveStyle.THICK;
    case MaterialMode.ULTRA_THICK:
      return uiMaterial.ImmersiveStyle.ULTRA_THICK;
    case MaterialMode.REGULAR:
    case MaterialMode.SYSTEM:
    default:
      return uiMaterial.ImmersiveStyle.REGULAR;
  }
}

export function hdsTypeOf(_mode: MaterialMode): hdsMaterial.MaterialType {
  return hdsMaterial.MaterialType.IMMERSIVE;
}

export const HDS_LEVEL_FOLLOWS_MODE: boolean = false;

export function hdsLevelOf(mode: MaterialMode): hdsMaterial.MaterialLevel {
  if (!HDS_LEVEL_FOLLOWS_MODE) {
    return hdsMaterial.MaterialLevel.EXQUISITE;
  }
  return thicknessIndex(mode) <= 0
    ? hdsMaterial.MaterialLevel.SMOOTH
    : hdsMaterial.MaterialLevel.EXQUISITE;
}

function thicknessIndex(mode: MaterialMode): number {
  switch (mode) {
    case MaterialMode.ULTRA_THIN:
      return 0;
    case MaterialMode.THIN:
      return 1;
    case MaterialMode.THICK:
      return 3;
    case MaterialMode.ULTRA_THICK:
      return 4;
    case MaterialMode.REGULAR:
    case MaterialMode.SYSTEM:
    default:
      return 2;
  }
}

const RADIUS_STEP: number = 0.16;

const ALPHA_STEP: number = 0.07;
const RADIUS_MIN: number = 8;
const RADIUS_MAX: number = 80;

const ALPHA_MIN: number = 0.15;
const ALPHA_MAX: number = 0.78;

function clampAlpha(value: number): number {
  if (value < ALPHA_MIN) {
    return ALPHA_MIN;
  }
  return value > ALPHA_MAX ? ALPHA_MAX : value;
}

function clampRadius(value: number): number {
  if (value < RADIUS_MIN) {
    return RADIUS_MIN;
  }
  return value > RADIUS_MAX ? RADIUS_MAX : value;
}

function relativeScale(slot: MaterialSlot, mode: MaterialMode, step: number): number {
  const baseIndex: number = thicknessIndex(defaultModeOf(slot));
  return 1 + step * (thicknessIndex(mode) - baseIndex);
}

export function glassSpecOf(slot: MaterialSlot, mode: MaterialMode): GlassSpec {
  const base: SlotDefaults = slotDefaults(slot);
  const radiusScale: number = relativeScale(slot, mode, RADIUS_STEP);
  const alphaScale: number = relativeScale(slot, mode, ALPHA_STEP);
  const tint: GlassTint = {
    r: base.tint.r,
    g: base.tint.g,
    b: base.tint.b,
    a: clampAlpha(base.tint.a * alphaScale)
  };
  return {
    radius: clampRadius(base.radius * radiusScale),
    tint: tint,
    saturation: base.saturation,

    brightness: base.brightness
  };
}

export function edgeShadeOf(slot: MaterialSlot): CapsuleEdge | undefined {
  if (slot !== MaterialSlot.BOTTOM_FLOATING_BAR) {
    return undefined;
  }
  return { width: 0.5, color: 'rgba(0,0,0,0.10)' };
}

export interface SlotScrollSpec {

  startOffset: number;

  endOffset: number;

  minAlphaRatio: number;

  minRadiusRatio: number;
}

const NAV_BAR_SCROLL: SlotScrollSpec = {
  startOffset: 0,
  endOffset: 56,
  minAlphaRatio: 0.55,
  minRadiusRatio: 0.45
};

export function scrollSpecOf(slot: MaterialSlot): SlotScrollSpec | undefined {
  return slot === MaterialSlot.NAV_BAR ? NAV_BAR_SCROLL : undefined;
}

export function scrollProgressOf(spec: SlotScrollSpec, scrollOffset: number): number {
  if (spec.endOffset <= spec.startOffset) {
    return 1;
  }
  if (scrollOffset <= spec.startOffset) {
    return 0;
  }
  if (scrollOffset >= spec.endOffset) {
    return 1;
  }
  return (scrollOffset - spec.startOffset) / (spec.endOffset - spec.startOffset);
}

export function glassSpecAtProgress(slot: MaterialSlot, mode: MaterialMode,
  progress: number): GlassSpec {
  const base: GlassSpec = glassSpecOf(slot, mode);
  const scroll: SlotScrollSpec | undefined = scrollSpecOf(slot);
  if (scroll === undefined || progress >= 1) {
    return base;
  }
  const p: number = progress <= 0 ? 0 : progress;
  const minAlpha: number = base.tint.a * scroll.minAlphaRatio;
  const minRadius: number = base.radius * scroll.minRadiusRatio;
  return {
    radius: minRadius + (base.radius - minRadius) * p,
    tint: {
      r: base.tint.r,
      g: base.tint.g,
      b: base.tint.b,
      a: minAlpha + (base.tint.a - minAlpha) * p
    },
    saturation: base.saturation,
    brightness: base.brightness
  };
}

export function tintToColor(tint: GlassTint): string {
  return `rgba(${tint.r}, ${tint.g}, ${tint.b}, ${tint.a.toFixed(3)})`;
}

export function modeLabel(mode: MaterialMode): string {
  switch (mode) {
    case MaterialMode.SYSTEM:
      return '跟随系统';
    case MaterialMode.ULTRA_THIN:
      return '超薄';
    case MaterialMode.THIN:
      return '薄';
    case MaterialMode.REGULAR:
      return '常规';
    case MaterialMode.THICK:
      return '厚';
    case MaterialMode.ULTRA_THICK:
      return '超厚';
    default:
      return '未知';
  }
}

export const ALL_MODES: MaterialMode[] = [
  MaterialMode.SYSTEM,
  MaterialMode.ULTRA_THIN,
  MaterialMode.THIN,
  MaterialMode.REGULAR,
  MaterialMode.THICK,
  MaterialMode.ULTRA_THICK
];

export function normalizeMode(raw: number): MaterialMode {
  switch (raw) {
    case MaterialMode.SYSTEM:
    case MaterialMode.ULTRA_THIN:
    case MaterialMode.THIN:
    case MaterialMode.REGULAR:
    case MaterialMode.THICK:
    case MaterialMode.ULTRA_THICK:
      return raw as MaterialMode;
    default:
      return DEFAULT_MODE;
  }
}
