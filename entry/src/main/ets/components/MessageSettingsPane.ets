
import { common } from '@kit.AbilityKit';
import {
  messageMaskLabel, messageMaskOptionIndex, messageMaskOptionLabels, messageMaskOptionValue, messagePushLabel
} from '../model/MessageSettings';
import { buildOptions, SettingsOptionItem } from '../model/SettingsModel';
import { MessageSettingsVM } from '../viewmodel/MessageSettingsVM';
import {
  SettingsCard, SettingsEntryRow, SettingsInfoRow, SettingsOptionRow, SettingsStatusKind, SettingsStatusLine
} from './SettingsComponents';

@ComponentV2
export struct MessageSettingsPane {
  @Event onOpenOfficial: () => void = (): void => {};
  @Local vm: MessageSettingsVM = new MessageSettingsVM();
  @Local maskPopupOpen: boolean = false;

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(message: string): void {
    try { this.getUIContext().getPromptAction().showToast({ message }); } catch (_) {}
  }

  aboutToAppear(): void {
    void this.vm.load(this.context());
  }

  aboutToDisappear(): void {
    this.maskPopupOpen = false;
    this.vm.dispose();
  }

  private maskOptions(): SettingsOptionItem[] {
    return buildOptions(messageMaskOptionLabels(), messageMaskOptionIndex(this.vm.data.maskType), 'msg_mask');
  }

  private maskDisplayValue(): string {
    if (this.vm.pending) { return '正在保存…'; }
    if (this.vm.loading && this.vm.data.maskType < 0) { return '正在读取…'; }
    return messageMaskLabel(this.vm.data.maskType);
  }

  private openMaskPopup(): void {
    if (this.vm.loading || this.vm.pending) { return; }
    if (this.vm.data.maskType < 0) {
      if (this.vm.error.length > 0) { this.toast(this.vm.error); }
      return;
    }
    this.maskPopupOpen = true;
  }

  private async pickMask(index: number): Promise<void> {
    this.maskPopupOpen = false;
    const nextValue: number = messageMaskOptionValue(index);
    if (nextValue < 0 || nextValue === this.vm.data.maskType) { return; }
    await this.vm.set(this.context(), 'maskType', nextValue);
    if (this.vm.notice.length > 0) {
      this.toast(this.vm.notice);
    } else if (this.vm.error.length > 0) {
      this.toast(this.vm.error);
    }
  }

  build() {
    Column() {
      SettingsCard({
        content: (): void => { this.MessageRows() }
      })
      if (this.vm.error.length > 0) {
        SettingsStatusLine({
          kind: SettingsStatusKind.ERROR,
          message: this.vm.error,
          retryLabel: '重试',
          onRetry: (): void => {
            void this.vm.load(this.context());
          }
        })
      }
    }
    .width('100%')
  }

  @Builder
  MessageRows() {
    SettingsOptionRow({
      label: '私信接收范围',
      value: this.maskDisplayValue(),
      popupOpen: this.maskPopupOpen,
      items: this.maskOptions(),
      onTap: (): void => { this.openMaskPopup(); },
      onPick: (index: number): void => { void this.pickMask(index); },
      onPopupClosed: (): void => { this.maskPopupOpen = false; }
    })
    SettingsInfoRow({
      label: '好友私信提醒',
      value: this.vm.loading && this.vm.data.pushType < 0 ? '正在读取…' : messagePushLabel(this.vm.data.pushType)
    })
    SettingsEntryRow({
      label: '官方账号消息提醒',
      showDivider: false,
      onTap: this.onOpenOfficial
    })
  }
}
