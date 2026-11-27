/** 应用桌面图标的纯逻辑清单、名称归一与系统错误映射（供设置页与测试共用）。 */

export const DEFAULT_APP_ICON_NAME: string = '';

export interface AppIconOption {
  /** 与 AppScope/app.json5 的 alternateIcons[].name 一致；空串代表恢复默认图标。 */
  readonly name: string;
  readonly label: string;
}

export interface AlternateIconState {
  readonly iconName: string;
  readonly enabled: boolean;
}

export const ALL_APP_ICON_OPTIONS: AppIconOption[] = [
  { name: DEFAULT_APP_ICON_NAME, label: '默认' },
  { name: 'icon_script_green', label: '墨绿花体' },
  { name: 'icon_italic_green', label: '墨绿斜体' },
  { name: 'icon_clean_green', label: '墨绿简约' },
  { name: 'icon_pine_white', label: '松青' },
  { name: 'icon_azure_white', label: '蔚蓝' }
];

export function isKnownAppIconName(name: string): boolean {
  for (let i = 0; i < ALL_APP_ICON_OPTIONS.length; i++) {
    if (ALL_APP_ICON_OPTIONS[i].name === name) {
      return true;
    }
  }
  return false;
}

export function normalizeAppIconName(name: string): string {
  return isKnownAppIconName(name) ? name : DEFAULT_APP_ICON_NAME;
}

export function appIconLabel(name: string): string {
  for (let i = 0; i < ALL_APP_ICON_OPTIONS.length; i++) {
    if (ALL_APP_ICON_OPTIONS[i].name === name) {
      return ALL_APP_ICON_OPTIONS[i].label;
    }
  }
  return '默认';
}

/** 从系统返回的备用图标列表解析当前启用的图标名；均未启用或无法识别时返回默认空串。 */
export function resolveEnabledAlternateIcon(entries: ReadonlyArray<AlternateIconState>): string {
  for (let i = 0; i < entries.length; i++) {
    const entry: AlternateIconState = entries[i];
    if (entry.enabled && isKnownAppIconName(entry.iconName)) {
      return entry.iconName;
    }
  }
  return DEFAULT_APP_ICON_NAME;
}

/** `bundleManager.setAlternateIcon` / `getAlternateIcons` 错误码转中文提示。 */
export function formatAppIconError(code: number): string {
  if (code === 17700308) {
    return '未找到对应的备用图标配置';
  }
  if (code === 17700309) {
    return '';
  }
  if (code === 17700310) {
    return '应用图标切换失败，若系统启用了自定义主题图标请先恢复默认主题后重试';
  }
  if (code === 17700311) {
    return '无法读取当前应用图标状态';
  }
  return '应用图标切换失败，当前系统可能暂不支持';
}
