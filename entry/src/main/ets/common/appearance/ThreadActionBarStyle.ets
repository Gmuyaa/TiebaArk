

export enum ThreadActionBarStyle {

  CLASSIC_GLASS = 0,

  POPUP = 1,

  SPLIT_IMMERSIVE = 3
}

export const RETIRED_FLOATING_DOCK: number = 2;

export const DEFAULT_ACTION_BAR_STYLE: ThreadActionBarStyle = ThreadActionBarStyle.SPLIT_IMMERSIVE;

export const ALL_ACTION_BAR_STYLES: ThreadActionBarStyle[] = [
  ThreadActionBarStyle.SPLIT_IMMERSIVE,
  ThreadActionBarStyle.POPUP,
  ThreadActionBarStyle.CLASSIC_GLASS
];

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
