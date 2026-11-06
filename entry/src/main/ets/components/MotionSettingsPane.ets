import { common } from '@kit.AbilityKit';
import { SettingsLayout } from '../common/appearance/SettingsLayout';
import { ARKUI_MOTIONS, HDS_MOTIONS, MotionGroup, MotionOption } from '../common/appearance/MotionConfig';
import { motionStore, MotionStore } from '../common/appearance/MotionStore';
import { SettingsCard, SettingsGroupTitle, SettingsNote, SettingsSwitchRow } from './SettingsComponents';

@ComponentV2
export struct MotionSettingsPane {
  @Local prefs: MotionStore = motionStore;

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  @Builder
  Master() {
    SettingsSwitchRow({ label: '启用动效', checked: this.prefs.enabled, showDivider: false,
      onToggle: (next: boolean): void => { void this.prefs.setEnabled(next, this.context()); } })
      .id('motion-master')
  }

  @Builder
  GroupRows(group: MotionGroup, options: MotionOption[]) {
    SettingsSwitchRow({ label: group === MotionGroup.ARKUI ? 'ArkUI 动效' : 'HDS 动效',
      checked: group === MotionGroup.ARKUI ? this.prefs.arkuiEnabled : this.prefs.hdsEnabled,
      interactionEnabled: this.prefs.enabled,
      onToggle: (next: boolean): void => { void this.prefs.setGroup(group, next, this.context()); } })
      .id(group === MotionGroup.ARKUI ? 'motion-arkui' : 'motion-hds')
    ForEach(options, (option: MotionOption, index: number) => {
      SettingsSwitchRow({ label: option.label, checked: this.prefs.selectedOf(option.effect),
        interactionEnabled: this.prefs.groupEnabled(group), showDivider: index < options.length - 1,
        onToggle: (next: boolean): void => { void this.prefs.setEffect(option.effect, next, this.context()); } })
        .id(`motion-effect-${option.effect}`)
    }, (option: MotionOption): string => `${option.effect}`)
  }

  build() {
    Column() {
      SettingsCard({ content: (): void => { this.Master(); } })
      SettingsGroupTitle({ title: 'ArkUI' })
      SettingsCard({ content: (): void => { this.GroupRows(MotionGroup.ARKUI, ARKUI_MOTIONS); } })
      SettingsGroupTitle({ title: 'HDS' })
      SettingsCard({ content: (): void => { this.GroupRows(MotionGroup.HDS, HDS_MOTIONS); } })
      SettingsNote({ text: '实际动效随设备和系统设置变化。' })
      if (this.prefs.systemReducedMotion) { SettingsNote({ text: '系统已开启减少动态效果，应用自定义过渡已简化。' }) }
      if (this.prefs.systemMotionError.length > 0) { SettingsNote({ text: this.prefs.systemMotionError }) }
      if (this.prefs.saveError.length > 0) { SettingsNote({ text: this.prefs.saveError }) }
    }.width('100%')
  }
}
