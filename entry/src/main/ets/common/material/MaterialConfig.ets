/** 全站使用官方沉浸材质：ArkUI 优先，HDS 仅用于兼容回退。偏好编号保持兼容。 */
import { uiMaterial } from '@kit.ArkUI';
import { hdsMaterial, SystemMaterialParams } from '@kit.UIDesignKit';
import { HdsMaterialLevelPref, hdsStrengthLevel } from './MaterialStrength';

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

export enum MaterialSlot {
  /** 返回按钮等小型圆形悬浮控件（`components/GlassBackButton`） */
  BACK_BUTTON = 0,
  /** 页面顶栏 / 玻璃头（含首页搜索胶囊，`components/ForumListView` 的 Header） */
  NAV_BAR = 1,
  /** 公共搜索胶囊（`components/SearchField`），ArkUI 优先官方材质通道 */
  SEARCH_BAR = 2,
  /**
   * 悬浮胶囊底栏（`pages/Index` 的首页底栏，以及 `pages/ThreadDetail` 的
   * 「分离式」操作栏 —— 二者均复用 `MaterialTabs`）
   */
  BOTTOM_BAR = 3,

  SHEET = 4,

  BOTTOM_FLOATING_BAR = 5,
  /** 回复输入弹窗材质槽位。弹窗宽度与圆角由对话框配置提供，内容层避免重复绘制背景。 */
  REPLY_SHEET = 6,

  HOME_TOP_ISLAND = 7,
  /** 首页整片沉浸顶栏使用的材质槽位，对应 OFFICIAL_DUAL_ROW 样式。 */
  HOME_TOP_CONTINUOUS = 8,
  /** 吧页关注/签到按钮：官方材质圆角按钮。 */
  FORUM_ACTION_BUTTON = 9,
  /** 搜索历史、全站结果及吧内结果共用的整片官方沉浸顶栏。 */
  SEARCH_TOP_CONTINUOUS = 10,
  /** 吧页分类选中面，使用官方材质赋色。 */
  FORUM_TAB_SELECTION = 11
}


export type HdsMaterialEffect = SystemMaterialParams;
export const DEFAULT_MODE: MaterialMode = MaterialMode.SYSTEM;
export const MATERIAL_STORE: string = 'tieba_material_prefs';
export const MATERIAL_KEY_MODE: string = 'mode';
export const MATERIAL_KEY_HDS_LEVEL: string = 'hdsLevel';

/** 跟随系统时保留各用途的默认厚度；仅统一用户明确选择的档位。 */
export function defaultModeOf(slot: MaterialSlot): MaterialMode {
  switch (slot) {
    case MaterialSlot.BACK_BUTTON: return MaterialMode.ULTRA_THIN;
    case MaterialSlot.SHEET:
    case MaterialSlot.REPLY_SHEET: return MaterialMode.THICK;
    case MaterialSlot.BOTTOM_FLOATING_BAR: return MaterialMode.REGULAR;
    default: return MaterialMode.THIN;
  }
}

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
