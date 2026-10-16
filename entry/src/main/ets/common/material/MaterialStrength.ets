/** HDS材质等级独立于ArkUI五档厚度，编号为本机偏好值。 */
export enum HdsMaterialLevelPref {
  EXQUISITE = 1,
  GENTLE = 2,
  SMOOTH = 3
}
export const DEFAULT_HDS_LEVEL: HdsMaterialLevelPref = HdsMaterialLevelPref.EXQUISITE;
export const ALL_HDS_LEVELS: HdsMaterialLevelPref[] = [
  HdsMaterialLevelPref.EXQUISITE, HdsMaterialLevelPref.GENTLE, HdsMaterialLevelPref.SMOOTH
];
export function normalizeHdsLevel(raw: number): HdsMaterialLevelPref {
  return raw === HdsMaterialLevelPref.GENTLE ? HdsMaterialLevelPref.GENTLE
    : raw === HdsMaterialLevelPref.SMOOTH ? HdsMaterialLevelPref.SMOOTH : DEFAULT_HDS_LEVEL;
}
/** 对应SDK等级EXQUISITE=0、GENTLE=1、SMOOTH=2，厚度设置不参与转换。 */
export function hdsStrengthLevel(level: HdsMaterialLevelPref): number {
  return (normalizeHdsLevel(level as number) as number) - 1;
}
export function hdsLevelLabel(level: HdsMaterialLevelPref): string {
  const normalized: HdsMaterialLevelPref = normalizeHdsLevel(level as number);
  return normalized === HdsMaterialLevelPref.GENTLE ? '轻柔'
    : normalized === HdsMaterialLevelPref.SMOOTH ? '流畅' : '精美';
}