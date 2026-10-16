/** 沉浸光感的共享配置。按 MaterialSlot 区分组件用途；HDS 组件与普通组件分别选择支持的材质通道。 */

import { uiMaterial } from '@kit.ArkUI';
import { hdsMaterial, SystemMaterialParams, HdsTabsBackgroundStyle } from '@kit.UIDesignKit';
import { HdsMaterialLevelPref, hdsStrengthLevel } from './MaterialStrength';

/**
 * 用户可选的沉浸光感强度档位。
 *
 * 数值即持久化值，**不要改已有编号**（改了会让老用户的偏好错位）。
 */
export enum MaterialMode {
  /** 跟随系统 / 各组件按自己的官方推荐默认档（= 不下发统一档位） */
  SYSTEM = 0,
  /** 超薄：透明感很强（官方推荐：浮动工具栏、顶部悬浮区域） */
  ULTRA_THIN = 1,
  /** 薄：透明感较强（官方推荐：搜索框、底部悬浮操作栏） */
  THIN = 2,
  /** 常规：厚度适中（官方推荐：普通卡片、通用悬浮组件） */
  REGULAR = 3,
  /** 厚：模糊较强（官方推荐：菜单、临时浮层） */
  THICK = 4,
  /** 超厚：模糊很强（官方推荐：弹窗、半模态页面） */
  ULTRA_THICK = 5
}

/**
 * 组件槽位。**不同类型组件可以有不同默认档位**，统一档位只在用户显式选择时生效。
 *
 * 这样"跟随系统"才有意义：返回按钮（小面积悬浮控件）与弹层（大面积）本来就不该同档。
 */
export enum MaterialSlot {
  /** 返回按钮等小型圆形悬浮控件（`components/GlassBackButton`） */
  BACK_BUTTON = 0,
  /** 页面顶栏 / 玻璃头（含首页搜索胶囊，`components/ForumListView` 的 Header） */
  NAV_BAR = 1,
  /** 公共搜索胶囊（`components/SearchField`），HDS 官方沉浸光感通道 */
  SEARCH_BAR = 2,
  /**
   * 悬浮胶囊底栏（`pages/Index` 的首页底栏，以及 `pages/ThreadDetail` 的
   * 「分离式」操作栏 —— 二者都是 `HdsTabs.barFloatingStyle`）
   */
  BOTTOM_BAR = 3,

  SHEET = 4,

  BOTTOM_FLOATING_BAR = 5,
  /** 回复输入弹窗材质槽位。弹窗宽度与圆角由对话框配置提供，内容层避免重复绘制背景。 */
  REPLY_SHEET = 6,

  HOME_TOP_ISLAND = 7,
  /** 首页整片沉浸顶栏使用的材质槽位，对应 OFFICIAL_DUAL_ROW 样式。 */
  HOME_TOP_CONTINUOUS = 8,
  /** 吧页关注/签到按钮：普通组件的自绘玻璃，独立默认配方。 */
  FORUM_ACTION_BUTTON = 9,
  /** 搜索历史、全站结果及吧内结果共用的整片官方沉浸顶栏。 */
  SEARCH_TOP_CONTINUOUS = 10
}

export enum MaterialBackend {
  /** 官方沉浸光感 API（HDS 组件唯一可用路径） */
  OFFICIAL = 0,
  /** 自绘玻璃：`backgroundEffect`（普通组件在真机上的唯一可用路径） */
  GLASS = 1
}

/** 玻璃底色（RGBA 分量）。存分量而不是字符串，是为了按档位缩放 alpha 后再拼回去 */
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
  /** 下沿暗线宽度（vp） */
  width: number;
  /** 下沿暗线颜色 */
  color: string;
}

/**
 * HDS 组件的材质下发参数形状。
 *
 * **直接复用官方类型**（`@kit.UIDesignKit` 的 `SystemMaterialParams`），
 * 不自己声明一个"长得一样"的 interface —— ArkTS 的
 * `arkts-no-untyped-obj-literals` 会因为"别的 interface"而在
 * `HdsTabs.barFloatingStyle({ systemMaterialEffect })` 处直接编译失败（已踩）。
 */
export type HdsMaterialEffect = SystemMaterialParams;

/** 双胶囊使用全透明 gradientMask，避免系统默认渐变在矩形节点上形成灰色背景。 */
export const SPLIT_PILL_GRADIENT_MASK: HdsTabsBackgroundStyle = {
  maskColor: '#00000000',
  maskHeight: 0
};

/** 一个槽位的静态定义：SYSTEM 模式下的默认档位 + 自绘玻璃的基准参数 */
interface SlotDefaults {
  mode: MaterialMode;
  radius: number;
  tint: GlassTint;
  saturation: number;
  /** 自绘玻璃的提亮系数（1 = 不提亮，即官方默认） */
  brightness: number;
}

/** 默认档位（用户没改过设置时用的那份） */
export const DEFAULT_MODE: MaterialMode = MaterialMode.SYSTEM;

/** 普通组件的材质后端选择；HDS 组件使用独立通道。 */
export const PLAIN_COMPONENT_BACKEND: MaterialBackend = MaterialBackend.GLASS;

/** 材质槽位到渲染通道的映射。HDS 容器使用系统材质；普通组件按后端配置选择实现。 */
export function materialBackendOf(slot: MaterialSlot): MaterialBackend {

  return slot === MaterialSlot.BOTTOM_BAR || slot === MaterialSlot.SHEET
    || slot === MaterialSlot.REPLY_SHEET || slot === MaterialSlot.HOME_TOP_ISLAND
    || slot === MaterialSlot.HOME_TOP_CONTINUOUS || slot === MaterialSlot.SEARCH_BAR
    || slot === MaterialSlot.SEARCH_TOP_CONTINUOUS
    ? MaterialBackend.OFFICIAL
    : PLAIN_COMPONENT_BACKEND;
}

/** 持久化：库名与键名 */
export const MATERIAL_STORE: string = 'tieba_material_prefs';
export const MATERIAL_KEY_MODE: string = 'mode';
export const MATERIAL_KEY_HDS_LEVEL: string = 'hdsLevel';

/**
 * 槽位默认表。
 *
 * 档位的选取依据是官方 `ImmersiveStyle` 的"适用场景"列（见 `MaterialMode` 注释），
 * 不是拍脑袋：返回按钮=浮动工具栏→ULTRA_THIN、顶栏/搜索→THIN、弹层→THICK。
 *
 * 自绘玻璃的基准参数则是**本项目真机量出来的值**（`GlassBackButton` 与 `ForumListView`
 * 各自文件头有取证过程），改这里等于改全站玻璃观感。
 */
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
  /** 经典玻璃操作栏的自绘配方，与系统材质通道分开。 */
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
  /** 回复弹窗的背景、模糊与亮度配置。 */
  const replySheet: SlotDefaults = {
    mode: MaterialMode.THICK,
    radius: 40,
    tint: { r: 255, g: 255, b: 255, a: 0.22 },
    saturation: 1.4,
    brightness: 1.0
  };
  /** 首页双岛顶栏的材质配方；外层容器负责阴影。 */
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

  const forumActionButton: SlotDefaults = {
    mode: MaterialMode.THIN,
    radius: 20,
    tint: { r: 255, g: 255, b: 255, a: 0.188 },
    saturation: 1.1,
    brightness: 1.05
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
    case MaterialSlot.SEARCH_TOP_CONTINUOUS:
      return homeTopContinuous;
    case MaterialSlot.FORUM_ACTION_BUTTON:
      return forumActionButton;
    default:
      return navBar;
  }
}

/** 该槽位在 SYSTEM 模式下的默认档位 */
export function defaultModeOf(slot: MaterialSlot): MaterialMode {
  return slotDefaults(slot).mode;
}

/**
 * 把"用户偏好"解析成"该槽位实际生效的档位"。
 *
 * `SYSTEM` **不是**"不生效"，而是"不下发统一档位、各槽位用各自的官方推荐默认"
 * —— 这正是需求里"跟随系统时使用各组件官方默认效果"的落点。
 */
export function resolveMode(slot: MaterialSlot, userMode: MaterialMode): MaterialMode {
  return userMode === MaterialMode.SYSTEM ? defaultModeOf(slot) : userMode;
}

/** 档位 → 官方 ArkUI 材质样式枚举（普通组件用） */
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

/**
 * 档位 → HDS 材质**类型**。
 *
 * 官方注释：`ADAPTIVE` = "Follow system material policy"；它跟随系统策略，部分设备会
 * **不渲染沉浸光感**。本项目真机验证通过的是显式 `IMMERSIVE`
 * （Mate 70 Pro 上是真毛玻璃）。所以这里恒返回 `IMMERSIVE`，把"强度"交给 level。
 */
export function hdsTypeOf(_mode: MaterialMode): hdsMaterial.MaterialType {
  return hdsMaterial.MaterialType.IMMERSIVE;
}

/** HDS等级单独选择，不从五档厚度推导。 */
export function hdsLevelOf(level: HdsMaterialLevelPref): hdsMaterial.MaterialLevel {
  return hdsStrengthLevel(level) as hdsMaterial.MaterialLevel;
}

/** 档位的"厚度序号"（越厚越大）。SYSTEM 不该出现在这里，兜底按 REGULAR */
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
/** 底色 alpha 的档位步长（刻意小于半径步长，见上） */
const ALPHA_STEP: number = 0.07;
const RADIUS_MIN: number = 8;
const RADIUS_MAX: number = 80;
/** alpha 的安全区间：太低等于没有玻璃，太高就不是玻璃了 */
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

/**
 * 相对缩放：以**该槽位自己的默认档位**为 1.0。
 *
 * 这么定是为了让"SYSTEM"与"用户手动选到同一档"渲染出**完全相同**的结果 ——
 * 槽位默认表里那组参数（radius / tint / saturation）就是本项目在真机上量过、
 * 当前正在跑的那一套，不能被档位换算改掉。
 */
function relativeScale(slot: MaterialSlot, mode: MaterialMode, step: number): number {
  const baseIndex: number = thicknessIndex(defaultModeOf(slot));
  return 1 + step * (thicknessIndex(mode) - baseIndex);
}

/**
 * 按档位推导某个槽位的自绘玻璃参数。
 *
 * 只在 `MaterialBackend.GLASS` 通道下被用；档位差异体现在**模糊半径**与**底色 alpha**
 * 两个旋钮上（都是本项目量过的有效旋钮，见 `GlassBackButton.ets` 文末配方表），
 * 但两者步长不同 —— 半径是主角，alpha 只跟着微调，理由见上面 `RADIUS_STEP` 的注释。
 */
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
    // 提亮系数**不随档位缩放**：它是槽位配方的一部分（当前只有悬浮胶囊非 1）
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
  /** progress 开始增长的滚动偏移（vp） */
  startOffset: number;
  /** progress 达到 1 的滚动偏移（vp）；滚动超过后强度恒定 */
  endOffset: number;

  minAlphaRatio: number;
  /** progress=0 时的 radius 比例（× 槽位基准 radius） */
  minRadiusRatio: number;
}

const NAV_BAR_SCROLL: SlotScrollSpec = {
  startOffset: 0,
  endOffset: 56,
  minAlphaRatio: 0.55,
  minRadiusRatio: 0.45
};

/** 该槽位是否有滚动渐变；没有 = 固定玻璃（忽略页面传来的 offset） */
export function scrollSpecOf(slot: MaterialSlot): SlotScrollSpec | undefined {
  return slot === MaterialSlot.NAV_BAR ? NAV_BAR_SCROLL : undefined;
}

/**
 * 滚动偏移 → 渐变进度，**线性 + clamp**。
 *
 * clamp 在这里做而不是页面做：Refresh 下拉时 offset 可能是负值/异常值，
 * 调用方不需要也不允许自己写保护。
 */
export function scrollProgressOf(spec: SlotScrollSpec, scrollOffset: number): number {
  if (spec.endOffset <= spec.startOffset) {
    return 1; // 配置退化时恒为满强度，别让页面黑掉
  }
  if (scrollOffset <= spec.startOffset) {
    return 0;
  }
  if (scrollOffset >= spec.endOffset) {
    return 1;
  }
  return (scrollOffset - spec.startOffset) / (spec.endOffset - spec.startOffset);
}

/**
 * 按 progress 在「弱玻璃 ↔ 槽位基准玻璃」之间线性插值。
 *
 * `progress` 须已在 0~1（由 `scrollProgressOf` 保证）；超出范围时按 0/1 处理。
 * 无渐变配置的槽位直接返回基准 spec（等价 progress=1）。
 */
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

/** `GlassTint` → `backgroundEffect` 能吃的颜色串 */
export function tintToColor(tint: GlassTint): string {
  return `rgba(${tint.r}, ${tint.g}, ${tint.b}, ${tint.a.toFixed(3)})`;
}

/** 设置页要用的中文名 */
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

/** 设置页顺序（含 SYSTEM，共 6 项） */
export const ALL_MODES: MaterialMode[] = [
  MaterialMode.SYSTEM,
  MaterialMode.ULTRA_THIN,
  MaterialMode.THIN,
  MaterialMode.REGULAR,
  MaterialMode.THICK,
  MaterialMode.ULTRA_THICK
];

/** 让"持久化里读到的脏值"回到合法档位 */
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
