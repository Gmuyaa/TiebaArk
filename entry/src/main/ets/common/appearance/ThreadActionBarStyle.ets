/** 操作栏样式及旧值迁移的纯逻辑；平台存储位于 ThreadActionBarStore。 */

/** 枚举数值为持久化值，不可重新编号；2 为已退役样式，保留用于旧值迁移。 */
export enum ThreadActionBarStyle {
  /** 经典玻璃：自绘玻璃 + 下沿暗线。完全不依赖系统 HDS 材质，是最稳的备用路径。 */
  CLASSIC_GLASS = 0,
  /** 弹出式：与经典玻璃同布局，右胶囊末尾多一个「更多」，操作菜单用 Popup 承载。 */
  POPUP = 1,
  /**
   * 分离式（默认）：左右各一个 `HdsTabs`，材质由系统沉浸光感提供。
   *
   * 编号是 3 而不是 2 —— 2 号是已淘汰的「悬浮 Dock」，见 `RETIRED_FLOATING_DOCK`。
   * **不许把 2 重新分给别的样式**：老设备上存着 2，重新分配会让那台设备静默换样式。
   */
  SPLIT_IMMERSIVE = 3
}

/** 已退役样式的持久化编号，仅用于旧值迁移，读取后回落到默认样式。 */
export const RETIRED_FLOATING_DOCK: number = 2;

/** 默认样式：分离式（左右双胶囊 + 官方系统材质） */
export const DEFAULT_ACTION_BAR_STYLE: ThreadActionBarStyle = ThreadActionBarStyle.SPLIT_IMMERSIVE;

/** 设置页展示顺序（默认项在最前） */
export const ALL_ACTION_BAR_STYLES: ThreadActionBarStyle[] = [
  ThreadActionBarStyle.SPLIT_IMMERSIVE,
  ThreadActionBarStyle.POPUP,
  ThreadActionBarStyle.CLASSIC_GLASS
];

/** 操作栏样式的展示名称。 */
export function actionBarStyleLabel(style: ThreadActionBarStyle): string {
  switch (style) {
    case ThreadActionBarStyle.CLASSIC_GLASS:
      return '经典玻璃';
    case ThreadActionBarStyle.POPUP:
      return '弹出式';
    case ThreadActionBarStyle.SPLIT_IMMERSIVE:
    default:
      return '分离式';
  }
}

/** 设置页副文案：只说"长什么样、怎么用"，不解释实现 */
export function actionBarStyleDesc(style: ThreadActionBarStyle): string {
  switch (style) {
    case ThreadActionBarStyle.CLASSIC_GLASS:
      return '使用轻量玻璃效果';
    case ThreadActionBarStyle.POPUP:
      return '通过弹出菜单提供更多操作';
    case ThreadActionBarStyle.SPLIT_IMMERSIVE:
    default:
      return '左右分离的沉浸操作栏';
  }
}

/** 旧值与未知值归一到合法样式，退役编号 2 与非法值回落到分离式。 */
export function normalizeActionBarStyle(raw: number): ThreadActionBarStyle {
  switch (raw) {
    case ThreadActionBarStyle.CLASSIC_GLASS:
      return ThreadActionBarStyle.CLASSIC_GLASS;
    case ThreadActionBarStyle.POPUP:
      return ThreadActionBarStyle.POPUP;
    case ThreadActionBarStyle.SPLIT_IMMERSIVE:
    case RETIRED_FLOATING_DOCK:
    default:
      return DEFAULT_ACTION_BAR_STYLE;
  }
}
