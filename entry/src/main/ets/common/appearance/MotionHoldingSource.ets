import { motion } from '@kit.MultimodalAwarenessKit';
import { HoldingSource } from '../../model/SmartReach';

/** 刷新按钮与分类胶囊共用的平台适配，订阅生命周期由各自HoldingSession管理。 */
export class MotionHoldingSource implements HoldingSource {
  on(callback: (status: number) => void): void { motion.on('holdingHandChanged', callback); }
  off(callback: (status: number) => void): void { motion.off('holdingHandChanged', callback); }
}
