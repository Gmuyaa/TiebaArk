import { promptAction } from '@kit.ArkUI';
import { MotionEffect } from '../common/appearance/MotionConfig';
import { motionDuration } from '../common/appearance/MotionPolicy';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { materialManager } from '../common/material/MaterialManager';

const EMOJI_PANEL_FALLBACK_HEIGHT: number = 314;
// 8vp 顶部内边距 + 40vp 分类栏 + 12vp 底部内边距 + 原生容器可见残差 6vp。
const EMOJI_PANEL_CHROME_HEIGHT: number = 66;
// 沿用评论区已校准的原生弹窗底部补偿，避免系统容器空腔露在屏内。
const EMOJI_PANEL_BOTTOM_INSET_COMP: number = 50;
const EMOJI_PANEL_RADIUS: number = 16;
const EMOJI_PANEL_TRANSITION_MS: number = 220;

/** 两处编辑器共用实际键盘占位；短键盘由表情网格收紧间距或滚动适配。 */
export function emojiPanelHeight(lastKeyboardVp: number): number {
  return lastKeyboardVp > 0 ? lastKeyboardVp : EMOJI_PANEL_FALLBACK_HEIGHT;
}

export function emojiPanelGridHeight(panelHeight: number): number {
  return Math.max(0, panelHeight - EMOJI_PANEL_CHROME_HEIGHT);
}

/** 原生弹窗统一负责材质、圆角和升降；内容组件不再套材质承载或裁剪。 */
export function emojiPanelDialogOptions(builder: CustomBuilder, width: number, height: number,
  onDismiss: () => void, onDisappear: () => void): promptAction.CustomDialogOptions {
  return {
    builder: builder,
    alignment: DialogAlignment.Bottom,
    offset: { dx: 0, dy: EMOJI_PANEL_BOTTOM_INSET_COMP },
    keyboardAvoidMode: KeyboardAvoidMode.NONE,
    dialogTransition: TransitionEffect.translate({ y: height })
      .animation({ duration: motionDuration(EMOJI_PANEL_TRANSITION_MS, MotionEffect.MOVE) }),
    width: width > 0 ? width : 360,
    cornerRadius: {
      topLeft: EMOJI_PANEL_RADIUS,
      topRight: EMOJI_PANEL_RADIUS,
      bottomLeft: 0,
      bottomRight: 0
    },
    isModal: false,
    autoCancel: false,
    systemMaterial: materialManager.officialOf(MaterialSlot.REPLY_SHEET),
    onWillDismiss: (action: DismissDialogAction): void => {
      action.dismiss();
      onDismiss();
    },
    onDidDisappear: onDisappear
  };
}
