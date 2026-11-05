import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { DEFAULT_MOTION_MASK, MOTION_STORE, MotionEffect, MotionGroup,
  motionGroupOf, normalizeMotionMask, validMotion } from './MotionConfig';

/** 默认开启；总关和分组关闭均保留单项偏好。串行写入快照，避免快速切换后旧值覆盖新值。 */
@ObservedV2
export class MotionStore {
  @Trace enabled: boolean = true;
  @Trace arkuiEnabled: boolean = true;
  @Trace hdsEnabled: boolean = true;
  @Trace selected: number = DEFAULT_MOTION_MASK;
  @Trace saveError: string = '';
  private loaded: boolean = false;
  private writes: Promise<void> = Promise.resolve();

  load(context: common.UIAbilityContext): void {
    if (this.loaded) { return; }
    this.loaded = true;
    try {
      const store = preferences.getPreferencesSync(context, { name: MOTION_STORE });
      const enabled = store.getSync('enabled', true);
      const arkui = store.getSync('arkui', true);
      const hds = store.getSync('hds', true);
      const selected = store.getSync('selected', DEFAULT_MOTION_MASK);
      this.enabled = typeof enabled === 'boolean' ? enabled : true;
      this.arkuiEnabled = typeof arkui === 'boolean' ? arkui : true;
      this.hdsEnabled = typeof hds === 'boolean' ? hds : true;
      this.selected = typeof selected === 'number' ? normalizeMotionMask(selected) : DEFAULT_MOTION_MASK;
    } catch (_) { this.saveError = '动效偏好读取失败，本次使用默认设置'; }
  }

  selectedOf(effect: MotionEffect): boolean {
    return validMotion(effect) && (this.selected & (1 << effect)) !== 0;
  }

  groupEnabled(group: MotionGroup): boolean {
    return this.enabled && (group === MotionGroup.ARKUI ? this.arkuiEnabled : this.hdsEnabled);
  }

  isOn(effect: MotionEffect): boolean {
    return this.groupEnabled(motionGroupOf(effect)) && this.selectedOf(effect);
  }

  async setEnabled(value: boolean, context: common.UIAbilityContext): Promise<void> {
    this.enabled = value;
    await this.save(context);
  }

  async setGroup(group: MotionGroup, value: boolean, context: common.UIAbilityContext): Promise<void> {
    if (!this.enabled) { return; }
    if (group === MotionGroup.ARKUI) { this.arkuiEnabled = value; } else { this.hdsEnabled = value; }
    await this.save(context);
  }

  async setEffect(effect: MotionEffect, value: boolean, context: common.UIAbilityContext): Promise<void> {
    if (!validMotion(effect) || !this.groupEnabled(motionGroupOf(effect))) { return; }
    this.selected = value ? this.selected | (1 << effect) : this.selected & ~(1 << effect);
    await this.save(context);
  }

  private async save(context: common.UIAbilityContext): Promise<void> {
    const enabled = this.enabled;
    const arkui = this.arkuiEnabled;
    const hds = this.hdsEnabled;
    const selected = this.selected;
    const operation = this.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, MOTION_STORE);
      await store.put('enabled', enabled);
      await store.put('arkui', arkui);
      await store.put('hds', hds);
      await store.put('selected', selected);
      await store.flush();
    });
    this.writes = operation.catch(() => {});
    try { await operation; this.saveError = ''; }
    catch (_) { this.saveError = '动效设置本次已生效，保存失败，重启后可能恢复旧值'; }
  }
}

export const motionStore: MotionStore = new MotionStore();
