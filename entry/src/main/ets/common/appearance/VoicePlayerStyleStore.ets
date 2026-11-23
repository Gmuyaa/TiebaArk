import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { VoicePlayerStyle, normalizeVoicePlayerStyle } from '../../model/VoicePlayerStyle';
import { PreferenceGate } from './PreferenceGate';

const STORE: string = 'tieba_voice_player_style_prefs';
const STYLE_KEY: string = 'style';

/** 独立的本机存储边界；测试可控制读写顺序与失败，不接触用户偏好。 */
export interface VoicePlayerStylePersistence {
  read(context?: common.UIAbilityContext): Promise<number | undefined>;
  write(style: VoicePlayerStyle, context?: common.UIAbilityContext): Promise<void>;
}

class PreferencesVoicePlayerStylePersistence implements VoicePlayerStylePersistence {
  async read(context?: common.UIAbilityContext): Promise<number | undefined> {
    if (context === undefined) { throw new Error('Voice player style preferences need an ability context'); }
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
    const raw = await store.get(STYLE_KEY, VoicePlayerStyle.SLIDER);
    return typeof raw === 'number' ? raw : undefined;
  }

  async write(style: VoicePlayerStyle, context?: common.UIAbilityContext): Promise<void> {
    if (context === undefined) { throw new Error('Voice player style preferences need an ability context'); }
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
    await store.put(STYLE_KEY, style as number);
    await store.flush();
  }
}

/** 本机阅读偏好；默认滑块条，退出登录与切换账号均不清除。 */
@ObservedV2
export class VoicePlayerStyleStore {
  @Trace style: VoicePlayerStyle = VoicePlayerStyle.SLIDER;
  @Trace loadError: string = '';
  @Trace saveError: string = '';
  private gate: PreferenceGate = new PreferenceGate();
  private persistence: VoicePlayerStylePersistence;

  constructor(persistence: VoicePlayerStylePersistence = new PreferencesVoicePlayerStylePersistence()) {
    this.persistence = persistence;
  }

  async load(context?: common.UIAbilityContext): Promise<void> {
    await this.gate.loadOnce(async (revision: number): Promise<void> => {
      try {
        const raw: number | undefined = await this.persistence.read(context);
        if (revision !== this.gate.revision()) { return; }
        const valid: boolean = raw === VoicePlayerStyle.SLIDER ||
          raw === VoicePlayerStyle.WAVEFORM || raw === VoicePlayerStyle.BUBBLE;
        this.style = normalizeVoicePlayerStyle(raw === undefined ? -1 : raw);
        this.loadError = valid ? '' : '语音样式设置未识别，暂用滑块条，请重新选择';
        // 只有读到合法值才算"已加载"：非法值保留重读机会。
        if (valid) { this.gate.markLoaded(); }
      } catch (_) {
        if (revision === this.gate.revision()) {
          this.loadError = '语音样式读取失败，暂时保留当前样式';
        }
        hilog.warn(0x0, 'TiebaVoiceStyle', 'voice player style preference load failed');
      }
    });
  }

  async setStyle(style: VoicePlayerStyle, context?: common.UIAbilityContext): Promise<void> {
    this.style = normalizeVoicePlayerStyle(style as number);
    await this.retrySave(context);
  }

  /** 即时生效、串行落盘；旧读取与旧写入的结果不得覆盖最新选择或错误。 */
  async retrySave(context?: common.UIAbilityContext): Promise<void> {
    const style: VoicePlayerStyle = this.style;
    const revision: number = this.gate.bump();
    this.gate.markLoaded();
    this.loadError = '';
    try {
      await this.gate.enqueue(async (): Promise<void> => {
        await this.persistence.write(style, context);
      });
      if (revision === this.gate.revision()) { this.saveError = ''; }
    } catch (_) {
      if (revision === this.gate.revision()) {
        this.saveError = '语音样式本次已生效，保存失败，重启后可能恢复旧值';
      }
      hilog.warn(0x0, 'TiebaVoiceStyle', 'voice player style preference save failed');
    }
  }
}

export const voicePlayerStyleStore: VoicePlayerStyleStore = new VoicePlayerStyleStore();
