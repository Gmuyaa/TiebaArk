/** 旧设置卡片的几何与配色常量，保留兼容与校验用途；当前设置页面使用 SettingsLayout。 */

/** 设置页卡片与行的几何 / 配色。数值来源：参考图逐像素实测（见类内注释）。 */
export class SettingsCardStyle {
  // ── 几何 ──────────────────────────────────────────────────────────────

  /**
   * 卡片圆角 10vp。参考图实测：左上角圆弧拟合 R≈34px（34 ÷ 3.5 = 9.7）。
   * 比全站信息流卡片的 16vp 小 —— 这是参考图的形态，**不要顺手改成 AppTheme.CARD_RADIUS**。
   */
  static readonly CARD_RADIUS: number = 10;

  /**
   * 卡片之间的竖向间距 18vp。参考图实测：卡片间空白 65px（65 ÷ 3.5 = 18.6），
   * 扣除边缘抗锯齿占掉的 1~2px 后按 18 取。
   *
   * 参考图**没有分组标题**（旧版设置页在每组上方有一行 12vp 灰字），
   * 分组完全靠这个间距表达 —— 所以它比"标题+间距"的总和要小，
   * 两张相邻卡片读起来才像一个列表而不是两段。
   */
  static readonly CARD_GAP: number = 18;

  /** 行高 49vp。参考图实测：两行卡片 341px（341 ÷ 2 ÷ 3.5 = 48.7）。 */
  static readonly ROW_H: number = 49;

  /**
   * 带副标题的行高 62vp（二级页里的选项行）。
   * 参考图没有两行行，沿用改造前的 62vp；**当前调用方是缓存清理的三项**
   * （`SettingsEntry.subtitle` 非空时用这一档）。
   */
  static readonly ROW_H_TALL: number = 62;

  /** 行左内距 18vp。参考图实测：卡片左沿 42px、文字墨迹起点 106px → 64px ÷ 3.5 = 18.3。 */
  static readonly ROW_PAD_L: number = 18;

  /** 行右内距 16vp。参考图实测：箭头字形盒右缘到卡片右沿 16vp（箭头墨迹右缘 1196、卡片右沿 1273）。 */
  static readonly ROW_PAD_R: number = 16;

  /**
   * 右侧值文字与箭头之间的间距 6vp。
   * 参考图实测：值文字右缘 1144px，"2.20GB" 与箭头字形盒（[1161..1217]）之间 17px ≈ 5vp。
   */
  static readonly VALUE_GAP: number = 6;

  // ── 文字 ──────────────────────────────────────────────────────────────

  /**
   * 主标签字号 16vp。
   * 参考图实测（CJK 全角字宽 = 1em，"n 字墨迹宽 ≈ (n−1)·em + 0.86em"）：
   * 「头像与个人信息」7 字 376px → 15.7vp；「账号与绑定」5 字 269px → 15.8vp；
   * 「退出登录」4 字 210px → 15.5vp。三处独立吻合，取 16。
   */
  static readonly LABEL_SIZE: number = 16;

  /**
   * 右侧值文字字号 14vp。参考图实测：「2.20GB」墨迹高 34px，数字 cap-height≈0.7em
   * → 34 ÷ 0.7 ÷ 3.5 = 13.9。
   */
  static readonly VALUE_SIZE: number = 14;

  /** 右侧箭头字号 16vp（`chevron_right`）。参考图实测墨迹高 29px ≈ 0.52em。 */
  static readonly CHEVRON_SIZE: number = 16;

  /**
   * 副标题字号 12vp。
   * 参考图里没有带副标题的行（这是缓存清理页新增的形态），按"比主标签小两档、
   * 与浏览设置页那行 12vp 说明文字同号"取；颜色用 `AppTheme.TEXT_SUB` 而不是本文件常量，
   * 因为副标题要跟随夜间模式。
   */
  static readonly SUB_SIZE: number = 12;

  /**
   * 箭头额外左移 4vp。**这一条是图标字体差异的补偿，不是随手加的间距。**
   *
   * 参考图的箭头字形盒宽 1em（16vp），墨迹在盒内居中 → 墨迹中心落在离卡片右沿
   * 22vp 处（实测墨迹 x[1183..1196]，中心 1189.5 = 卡片右沿 1273 − 83.5px）。
   * 而 `sys.symbol.chevron_right` 的字形盒只有 **0.5em**（真机 dumpLayout：
   * 字号 16vp 时盒宽 28px）且墨迹居中 → 墨迹中心会落到 1203.5px，比参考图**右 14px**。
   *
   * 补 4vp 内缩后墨迹回到 x[1182..1197]，与参考图逐像素对齐。
   */
  static readonly CHEVRON_INSET: number = 4;

  /** 二级页里选中项的勾选字号 20vp（参考图无此形态，按 49vp 行高定的视觉值）。 */
  static readonly CHECK_SIZE: number = 20;

  // ── 配色 ──────────────────────────────────────────────────────────────

  /**
   * 右侧值文字 `#767676`。
   * 参考图实测：暗像素众数 (118,118,118)。比全站次要文字 `AppTheme.TEXT_SUB`
   * （`#999999`）深一档 —— 参考图里 "2.20GB" 明显比灰标题实，别拿 TEXT_SUB 顶替。
   */
  static readonly VALUE_TEXT: string = '#767676';

  /**
   * 箭头 `#BABABA`。
   * 参考图实测：暗像素众数 (186,186,186)。细描边经抗锯齿后墨迹最暗值到 174，
   * 真色在两者之间，取 186 这一档。
   */
  static readonly CHEVRON_TINT: string = '#BABABA';

  /**
   * 危险项（退出登录）`#C7161C`。
   * 参考图实测：最饱和像素众数 (199,22,28)。
   */
  static readonly DANGER_TEXT: string = '#C7161C';

  static readonly NAV_FADE_COLOR: string = '#FFFFFF';

  /** 顶栏渐隐的终点色（全透明 = 露出页面底色 / 玻璃底），见 NAV_FADE_COLOR。 */
  static readonly NAV_FADE_TRANSPARENT: string = '#00FFFFFF';

  // ── 列表尾部 ──────────────────────────────────────────────────────────

  /** 列表底部留白，让最后一张卡片不贴着屏幕底（参考图末卡被屏幕裁掉，按卡片间距取）。 */
  static readonly BOTTOM_PAD: number = 18;

  /**
   * 弹层宽度 156vp（参考图实测面板 x[728..1273] = 546px）。
   *
   * **为什么写死而不是按比例**：弹层是"菜单"，宽度该由**菜单自己的内容**决定，
   * 不该随屏幕变宽 —— 与底栏「宽度 = 屏宽 × 2/3」（TD-28）是两种性质的需求。
   * 本页最长的档位名是「悬浮胶囊式」5 字 ≈ 80vp，18（左内距）+ 80 + 20（右内距）= 118vp
   * < 156vp，留有余量，不会挤。
   *
   * 位置：参考图里面板**右沿与卡片右沿齐平**（都在 364vp）→ 用 `Placement.BottomRight`。
   */
  static readonly POPUP_W: number = 156;

  /** 弹层单行高 48vp（参考图实测行距 168px ÷ 3.5 = 48）。 */
  static readonly POPUP_ROW_H: number = 48;

  /** 弹层圆角 12vp（参考图实测左上圆弧 R ≈ 40px ÷ 3.5 = 11.4）。 */
  static readonly POPUP_RADIUS: number = 12;

  /** 弹层行左内距 18vp（实测选项文字墨迹距面板左沿 63px = 18.0vp，与列表行一致）。 */
  static readonly POPUP_PAD_L: number = 18;

  /** 弹层行右内距 20vp（实测勾墨迹右缘距面板右沿 79px = 22.6vp，含字形盒留白；与列表 16+4 的等效值一致）。 */
  static readonly POPUP_PAD_R: number = 20;

  /** 弹层行主文案字号（与列表标签同号；实测墨迹高 50~51px ≈ 16vp）。 */
  static readonly POPUP_LABEL_SIZE: number = 16;

  /**
   * 弹层内分隔线颜色 `#CBCBCB`。
   * 参考图实测：分隔线所在行平均亮度 **203**，比页面底色（243）暗 40 级 —— 是一根实线，
   * 不是"浅灰到看不见"的那种（浅色页面上 20 级以内的差异会被 JPEG 噪声吃掉）。
   */
  static readonly POPUP_LINE: string = '#CBCBCB';

  /** 分隔线粗细 1vp（参考图实测只有 1 行像素命中）。 */
  static readonly POPUP_LINE_H: number = 1;

  /**
   * 分隔线左右缩进 18vp。
   * 参考图实测：线墨迹 x[784..1203]，距面板左沿 56px（16vp）、距右沿 70px（20vp）——
   * 两边不对称（JPEG 边缘判定误差 ±2px），取**对称的 18vp**，与行内文字左内距一致。
   */
  static readonly POPUP_LINE_INSET: number = 18;

  /**
   * 弹层与锚点行的间距 0vp。
   * 参考图实测：被点的行（「深色模式」）所在卡片底边 y=184，面板顶边 y=184 —— **齐平**。
   */
  static readonly POPUP_TARGET_SPACE: number = 0;

  /**
   * 弹层投影。参考图实测（面板外侧相对页面底色的压暗量）：
   * ```
   *   右侧 x[1274..1302]  237~241  → 最深 −6
   *   下侧 y[710..745]    243~247  → 最深 −8
   *   左侧 x[690..728]    248~253  → 最深 −7
   * ```
   * 衰减距离约 35px = **10vp**，四向都有（不是单向偏移的"假阴影"）。
   *
   * ⚠️ ArkUI 的 `shadow.radius` 是**模糊半径**，形状边缘处的峰值约为颜色 alpha 的 50%
   * → 要复现实测的 −7（≈2.7%），颜色 alpha 取 **14/255 ≈ 5.5%**。
   * 这个量级很轻，但因为面板本身在浅色背景上几乎与卡片同色，投影是**唯一**能把
   * "这是一层浮起来的东西"说清楚的东西 —— 真机复核时先看它，不要先怀疑材质。
   */
  static readonly POPUP_SHADOW_RADIUS: number = 20;
  static readonly POPUP_SHADOW_COLOR: string = '#0E000000';
  static readonly POPUP_SHADOW_OFFSET_Y: number = 6;
}
