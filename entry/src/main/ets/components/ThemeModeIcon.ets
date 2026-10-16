/** 外观切换按钮的三态图标：跟随系统、浅色与深色。图形采用统一坐标系绘制。 */

import { AppTheme } from '../theme/Theme';
import { ThemeModePref, normalizeThemeModePref } from '../common/appearance/ThemeMode';

/** 设计栅格边长：所有几何常量都按 24 设计，实际绘制按 `size / 24` 等比缩放 */
const GRID: number = 24;
/** 栅格中心 */
const CENTER: number = 12;
/** 独立态月牙的外圆半径 */
const R_OUT: number = 9.6;
/** 独立态日盘半径 */
const R_SUN: number = 5.5;
/** 独立态射线起止半径 */
const RAY_IN: number = 7;
const RAY_OUT: number = 9;
/** 独立态月牙的缺口圆半径，及其圆心沿左上方（−1,−1 方向）的偏移量 */
const BITE_R: number = 9.2;
const BITE_T: number = 3;
/** 描边宽度（vp）。与 `CommentActionHost` 的选区图标同值，不随 size 缩放 */
const STROKE: number = 1.7;

/** √2/2：斜线方向与缺口偏移方向上的单位分量 */
const S: number = Math.SQRT1_2;

const MOON_SHIFT: number = 2.29;
/** 独立态月牙外圆圆心（= 缺口圆心 + 沿右下 `BITE_T`） */
const MOON_CX: number = CENTER - MOON_SHIFT;
const MOON_CY: number = CENTER - MOON_SHIFT;

/**
 * 独立态月牙两尖 = 外圆 ∩ 缺口圆（两圆交点公式），圆心用光学居中后的 `MOON_CX/MOON_CY`。
 * 缺口圆心 = 月牙外圆圆心沿左上方向偏移 `BITE_T`（屏幕坐标左上 = (−1,−1)/√2），
 * 于是两圆圆心距正好是 `BITE_T`。
 * `CHORD_A` 是交点弦到外圆圆心的距离，`CHORD_H` 是半弦长；
 * 圆心连线方向 = 左上，垂直方向 = 右上，所以两尖对称落在斜线两侧。
 */
const CHORD_A: number = (BITE_T * BITE_T + R_OUT * R_OUT - BITE_R * BITE_R) / (2 * BITE_T);
const CHORD_H: number = Math.sqrt(R_OUT * R_OUT - CHORD_A * CHORD_A);
const TIP_AX: number = MOON_CX - CHORD_A * S + CHORD_H * S;
const TIP_AY: number = MOON_CY - CHORD_A * S - CHORD_H * S;
const TIP_BX: number = MOON_CX - CHORD_A * S - CHORD_H * S;
const TIP_BY: number = MOON_CY - CHORD_A * S + CHORD_H * S;

/* ---------------------------------------------------------------------- *
 * 合成态（跟随系统）：左上小太阳 + 右下小月牙 + 中间斜线
 * ---------------------------------------------------------------------- */

const SPLIT_SUN_X: number = 6.9;
const SPLIT_SUN_Y: number = 6.9;
/** 合成态日盘半径（比独立态小一圈，但要压得住右下的月牙） */
const SPLIT_SUN_R: number = 3.4;
/**
 * 合成态射线起止半径。起点压在日盘描边外一点点（与独立态同样的轻微分离），
 * 终点 5.7 + 半个描边 0.93 仍在栅格内（左/上方向到边还剩 0.27）。
 */
const SPLIT_RAY_IN: number = 4.6;
const SPLIT_RAY_OUT: number = 5.7;
/** 合成态月牙：外圆圆心、外圆半径、缺口圆半径、缺口圆心偏移（偏移方向同独立态） */
const SPLIT_MOON_X: number = 17.15;
const SPLIT_MOON_Y: number = 17.15;
const SPLIT_MOON_R: number = 5.65;
const SPLIT_MOON_BITE_R: number = 5.17;
const SPLIT_MOON_BITE_T: number = 2.83;

const SPLIT_LINE_X1: number = 21.5;
const SPLIT_LINE_Y1: number = 2.5;
const SPLIT_LINE_X2: number = 2.5;
const SPLIT_LINE_Y2: number = 21.5;

/** 合成态月牙两尖：与独立态同一套交点公式，换成合成态的圆心与半径 */
const SPLIT_CHORD_A: number =
  (SPLIT_MOON_BITE_T * SPLIT_MOON_BITE_T + SPLIT_MOON_R * SPLIT_MOON_R -
    SPLIT_MOON_BITE_R * SPLIT_MOON_BITE_R) / (2 * SPLIT_MOON_BITE_T);
const SPLIT_CHORD_H: number = Math.sqrt(SPLIT_MOON_R * SPLIT_MOON_R - SPLIT_CHORD_A * SPLIT_CHORD_A);
const SPLIT_TIP_AX: number = SPLIT_MOON_X - SPLIT_CHORD_A * S + SPLIT_CHORD_H * S;
const SPLIT_TIP_AY: number = SPLIT_MOON_Y - SPLIT_CHORD_A * S - SPLIT_CHORD_H * S;
const SPLIT_TIP_BX: number = SPLIT_MOON_X - SPLIT_CHORD_A * S - SPLIT_CHORD_H * S;
const SPLIT_TIP_BY: number = SPLIT_MOON_Y - SPLIT_CHORD_A * S + SPLIT_CHORD_H * S;

/** 坐标换算为物理像素后保留两位小数，消除浮点噪声。 */
function px(size: number, design: number): number {
  return Number.parseFloat(vp2px(design * size / GRID).toFixed(2));
}

/**
 * 一条射线（`degrees` 用屏幕角：0=右、90=下、270=上）。
 * 圆心与起止半径都由调用方给：独立态与合成态用的是两组不同尺寸。
 */
function ray(size: number, cx: number, cy: number, degrees: number, rIn: number, rOut: number): string {
  const rad: number = degrees * Math.PI / 180;
  const cos: number = Math.cos(rad);
  const sin: number = Math.sin(rad);
  const x1: number = px(size, cx + rIn * cos);
  const y1: number = px(size, cy + rIn * sin);
  const x2: number = px(size, cx + rOut * cos);
  const y2: number = px(size, cy + rOut * sin);
  return ` M ${x1} ${y1} L ${x2} ${y2}`;
}

/** 浅色：完整太阳 —— 日盘整圆 + 8 条射线 */
function sunCommands(size: number): string {
  const r: number = px(size, R_SUN);
  const left: number = px(size, CENTER - R_SUN);
  const right: number = px(size, CENTER + R_SUN);
  const mid: number = px(size, CENTER);
  let commands: string = `M ${left} ${mid} A ${r} ${r} 0 1 0 ${right} ${mid}` +
    ` A ${r} ${r} 0 1 0 ${left} ${mid} Z`;
  for (let i = 0; i < 8; i++) {
    commands += ray(size, CENTER, CENTER, i * 45, RAY_IN, RAY_OUT);
  }
  return commands;
}

/** 深色：完整月牙 —— 外圆大弧 + 缺口圆小弧，两尖落在左上、右下 */
function moonCommands(size: number): string {
  const rOut: number = px(size, R_OUT);
  const rBite: number = px(size, BITE_R);
  return `M ${px(size, TIP_AX)} ${px(size, TIP_AY)}` +
    ` A ${rOut} ${rOut} 0 1 1 ${px(size, TIP_BX)} ${px(size, TIP_BY)}` +
    ` A ${rBite} ${rBite} 0 0 0 ${px(size, TIP_AX)} ${px(size, TIP_AY)} Z`;
}

/**
 * 合成态的太阳：整圆日盘 + 只朝左上的 5 条射线（135°…315°，每 45° 一条）。
 * 右下半边不画射线：那里是月牙的位置，射线还会撞上斜线。
 */
function splitSunCommands(size: number): string {
  const r: number = px(size, SPLIT_SUN_R);
  const left: number = px(size, SPLIT_SUN_X - SPLIT_SUN_R);
  const right: number = px(size, SPLIT_SUN_X + SPLIT_SUN_R);
  const midY: number = px(size, SPLIT_SUN_Y);
  let commands: string = `M ${left} ${midY} A ${r} ${r} 0 1 0 ${right} ${midY}` +
    ` A ${r} ${r} 0 1 0 ${left} ${midY} Z`;
  for (let i = 0; i < 5; i++) {
    commands += ray(size, SPLIT_SUN_X, SPLIT_SUN_Y, 135 + i * 45, SPLIT_RAY_IN, SPLIT_RAY_OUT);
  }
  return commands;
}

/** 合成态的月牙：完整月牙（两个尖都在右下这半边，不被斜线切） */
function splitMoonCommands(size: number): string {
  const rOut: number = px(size, SPLIT_MOON_R);
  const rBite: number = px(size, SPLIT_MOON_BITE_R);
  return `M ${px(size, SPLIT_TIP_AX)} ${px(size, SPLIT_TIP_AY)}` +
    ` A ${rOut} ${rOut} 0 1 1 ${px(size, SPLIT_TIP_BX)} ${px(size, SPLIT_TIP_BY)}` +
    ` A ${rBite} ${rBite} 0 0 0 ${px(size, SPLIT_TIP_AX)} ${px(size, SPLIT_TIP_AY)} Z`;
}

/** 跟随系统：左上小太阳 + 右下小月牙 + 中间一条斜线 */
function splitCommands(size: number): string {
  return splitSunCommands(size) + splitMoonCommands(size) +
    ` M ${px(size, SPLIT_LINE_X1)} ${px(size, SPLIT_LINE_Y1)}` +
    ` L ${px(size, SPLIT_LINE_X2)} ${px(size, SPLIT_LINE_Y2)}`;
}

/** 三态图标路径。未识别的档位按「跟随系统」画（同 `normalizeThemeModePref` 的兜底） */
function themeModeIconCommands(mode: ThemeModePref, size: number): string {
  switch (normalizeThemeModePref(mode as number)) {
    case ThemeModePref.LIGHT:
      return sunCommands(size);
    case ThemeModePref.DARK:
      return moonCommands(size);
    case ThemeModePref.FOLLOW_SYSTEM:
    default:
      return splitCommands(size);
  }
}

@ComponentV2
export struct ThemeModeIcon {
  /** 当前档位：浅色画太阳、深色画月牙、跟随系统画各半 */
  @Param mode: ThemeModePref = ThemeModePref.FOLLOW_SYSTEM;
  /** 图标边长（vp）；设计栅格 24 等比缩放，调用侧与相邻 Symbol 图标取同值 */
  @Param iconSize: number = 22;
  /** 线条颜色；默认跟 `AppTheme.ICON`，与相邻 Symbol 图标同色 */
  @Param iconColor: ResourceColor = AppTheme.ICON;

  build() {
    Path()
      .commands(themeModeIconCommands(this.mode, this.iconSize))
      .fill(Color.Transparent)
      .stroke(this.iconColor)
      .strokeWidth(STROKE)
      .strokeLineCap(LineCapStyle.Round)
      .strokeLineJoin(LineJoinStyle.Round)
      .width(this.iconSize)
      .height(this.iconSize)
  }
}
