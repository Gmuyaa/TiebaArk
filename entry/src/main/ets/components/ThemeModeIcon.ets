

import { AppTheme } from '../theme/Theme';
import { ThemeModePref, normalizeThemeModePref } from '../common/appearance/ThemeMode';

const GRID: number = 24;

const CENTER: number = 12;

const R_OUT: number = 9.6;

const R_SUN: number = 5.5;

const RAY_IN: number = 7;
const RAY_OUT: number = 9;

const BITE_R: number = 9.2;
const BITE_T: number = 3;

const STROKE: number = 1.7;

const S: number = Math.SQRT1_2;

const MOON_SHIFT: number = 2.29;

const MOON_CX: number = CENTER - MOON_SHIFT;
const MOON_CY: number = CENTER - MOON_SHIFT;

const CHORD_A: number = (BITE_T * BITE_T + R_OUT * R_OUT - BITE_R * BITE_R) / (2 * BITE_T);
const CHORD_H: number = Math.sqrt(R_OUT * R_OUT - CHORD_A * CHORD_A);
const TIP_AX: number = MOON_CX - CHORD_A * S + CHORD_H * S;
const TIP_AY: number = MOON_CY - CHORD_A * S - CHORD_H * S;
const TIP_BX: number = MOON_CX - CHORD_A * S - CHORD_H * S;
const TIP_BY: number = MOON_CY - CHORD_A * S + CHORD_H * S;

const SPLIT_SUN_X: number = 6.9;
const SPLIT_SUN_Y: number = 6.9;

const SPLIT_SUN_R: number = 3.4;

const SPLIT_RAY_IN: number = 4.6;
const SPLIT_RAY_OUT: number = 5.7;

const SPLIT_MOON_X: number = 17.15;
const SPLIT_MOON_Y: number = 17.15;
const SPLIT_MOON_R: number = 5.65;
const SPLIT_MOON_BITE_R: number = 5.17;
const SPLIT_MOON_BITE_T: number = 2.83;

const SPLIT_LINE_X1: number = 21.5;
const SPLIT_LINE_Y1: number = 2.5;
const SPLIT_LINE_X2: number = 2.5;
const SPLIT_LINE_Y2: number = 21.5;

const SPLIT_CHORD_A: number =
  (SPLIT_MOON_BITE_T * SPLIT_MOON_BITE_T + SPLIT_MOON_R * SPLIT_MOON_R -
    SPLIT_MOON_BITE_R * SPLIT_MOON_BITE_R) / (2 * SPLIT_MOON_BITE_T);
const SPLIT_CHORD_H: number = Math.sqrt(SPLIT_MOON_R * SPLIT_MOON_R - SPLIT_CHORD_A * SPLIT_CHORD_A);
const SPLIT_TIP_AX: number = SPLIT_MOON_X - SPLIT_CHORD_A * S + SPLIT_CHORD_H * S;
const SPLIT_TIP_AY: number = SPLIT_MOON_Y - SPLIT_CHORD_A * S - SPLIT_CHORD_H * S;
const SPLIT_TIP_BX: number = SPLIT_MOON_X - SPLIT_CHORD_A * S - SPLIT_CHORD_H * S;
const SPLIT_TIP_BY: number = SPLIT_MOON_Y - SPLIT_CHORD_A * S + SPLIT_CHORD_H * S;

function px(size: number, design: number): number {
  return Number.parseFloat(vp2px(design * size / GRID).toFixed(2));
}

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

function moonCommands(size: number): string {
  const rOut: number = px(size, R_OUT);
  const rBite: number = px(size, BITE_R);
  return `M ${px(size, TIP_AX)} ${px(size, TIP_AY)}` +
    ` A ${rOut} ${rOut} 0 1 1 ${px(size, TIP_BX)} ${px(size, TIP_BY)}` +
    ` A ${rBite} ${rBite} 0 0 0 ${px(size, TIP_AX)} ${px(size, TIP_AY)} Z`;
}

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

function splitMoonCommands(size: number): string {
  const rOut: number = px(size, SPLIT_MOON_R);
  const rBite: number = px(size, SPLIT_MOON_BITE_R);
  return `M ${px(size, SPLIT_TIP_AX)} ${px(size, SPLIT_TIP_AY)}` +
    ` A ${rOut} ${rOut} 0 1 1 ${px(size, SPLIT_TIP_BX)} ${px(size, SPLIT_TIP_BY)}` +
    ` A ${rBite} ${rBite} 0 0 0 ${px(size, SPLIT_TIP_AX)} ${px(size, SPLIT_TIP_AY)} Z`;
}

function splitCommands(size: number): string {
  return splitSunCommands(size) + splitMoonCommands(size) +
    ` M ${px(size, SPLIT_LINE_X1)} ${px(size, SPLIT_LINE_Y1)}` +
    ` L ${px(size, SPLIT_LINE_X2)} ${px(size, SPLIT_LINE_Y2)}`;
}

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

  @Param mode: ThemeModePref = ThemeModePref.FOLLOW_SYSTEM;

  @Param iconSize: number = 22;

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
