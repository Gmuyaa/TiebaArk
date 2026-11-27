/** 应用动态图标状态存储：直连系统 bundleManager 备用图标能力，不自造假状态。 */
import { bundleManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AlternateIconState, DEFAULT_APP_ICON_NAME, formatAppIconError,
  normalizeAppIconName, resolveEnabledAlternateIcon
} from '../../model/AppIcon';

const DOMAIN: number = 0x0000;
const TAG: string = 'TiebaAppIcon';

export interface AppIconService {
  getAlternateIcons(): Promise<AlternateIconState[]>;
  setAlternateIcon(name: string): Promise<void>;
}

class SystemAppIconService implements AppIconService {
  async getAlternateIcons(): Promise<AlternateIconState[]> {
    const list: Array<bundleManager.AlternateIconInfo> = await bundleManager.getAlternateIcons();
    const out: AlternateIconState[] = [];
    for (let i = 0; i < list.length; i++) {
      out.push({ iconName: list[i].iconName, enabled: list[i].enabled });
    }
    return out;
  }

  async setAlternateIcon(name: string): Promise<void> {
    await bundleManager.setAlternateIcon(name);
  }
}

interface ErrorWithCode {
  code?: number;
}

function readErrorCode(err: Object): number {
  const candidate: ErrorWithCode = err as ErrorWithCode;
  return typeof candidate.code === 'number' ? candidate.code : -1;
}

/** 静态映射每套图标的 256² 预览资源（ArkTS `$r` 仅接受字面量）。 */
export function appIconPreviewResource(name: string): Resource {
  switch (name) {
    case 'icon_script_green':
      return $r('app.media.app_icon_script_green');
    case 'icon_italic_green':
      return $r('app.media.app_icon_italic_green');
    case 'icon_clean_green':
      return $r('app.media.app_icon_clean_green');
    case 'icon_pine_white':
      return $r('app.media.app_icon_pine_white');
    case 'icon_azure_white':
      return $r('app.media.app_icon_azure_white');
    default:
      return $r('app.media.app_icon');
  }
}

@ObservedV2
export class AppIconStore {
  @Trace currentName: string = DEFAULT_APP_ICON_NAME;
  @Trace loaded: boolean = false;
  @Trace busy: boolean = false;
  @Trace loadError: string = '';
  @Trace switchError: string = '';
  private service: AppIconService;
  private requestSeq: number = 0;

  constructor(service: AppIconService = new SystemAppIconService()) {
    this.service = service;
  }

  async refresh(): Promise<void> {
    if (this.busy) { return; }
    const seq: number = ++this.requestSeq;
    try {
      const entries: AlternateIconState[] = await this.service.getAlternateIcons();
      if (seq !== this.requestSeq) { return; }
      this.currentName = resolveEnabledAlternateIcon(entries);
      this.loaded = true;
      this.loadError = '';
    } catch (err) {
      if (seq !== this.requestSeq) { return; }
      const code: number = readErrorCode(err as Object);
      this.loadError = formatAppIconError(code === -1 ? 17700311 : code);
      hilog.warn(DOMAIN, TAG, 'getAlternateIcons failed: %{public}d', code);
    }
  }

  async select(name: string): Promise<boolean> {
    const target: string = normalizeAppIconName(name);
    if (this.busy) { return false; }
    if (this.loaded && target === this.currentName && this.switchError.length === 0) {
      return true;
    }
    this.busy = true;
    this.switchError = '';
    const seq: number = ++this.requestSeq;
    try {
      await this.service.setAlternateIcon(target);
      if (seq === this.requestSeq) {
        this.currentName = target;
        this.loaded = true;
        this.loadError = '';
      }
      return true;
    } catch (err) {
      const code: number = readErrorCode(err as Object);
      // 传空串恢复默认且系统未启用备用图标时会返回 17700309，按已处于默认态处理。
      if (code === 17700309 && target === DEFAULT_APP_ICON_NAME) {
        if (seq === this.requestSeq) {
          this.currentName = DEFAULT_APP_ICON_NAME;
          this.loaded = true;
          this.loadError = '';
          this.switchError = '';
        }
        return true;
      }
      if (seq === this.requestSeq) {
        this.switchError = formatAppIconError(code);
      }
      hilog.warn(DOMAIN, TAG, 'setAlternateIcon failed: target=%{public}s code=%{public}d', target, code);
      return false;
    } finally {
      this.busy = false;
    }
  }
}

export const appIconStore: AppIconStore = new AppIconStore();
