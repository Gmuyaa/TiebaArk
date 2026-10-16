
import { common } from '@kit.AbilityKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { GlassBackButton } from '../components/GlassBackButton';
import { ContentDestinationKind } from '../model/ThreadDetail';
import { NavigationService } from '../navigation/AppNavigation';
import { AppTheme } from '../theme/Theme';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { ScanVM } from '../viewmodel/ScanVM';

@ComponentV2
export struct ScanPage {
  @Local vm: ScanVM = new ScanVM();
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    readStatusBarVp(this.context()).then((vp: number) => { this.statusBarH = vp; }).catch(() => {});
  }

  aboutToDisappear(): void { this.vm.dispose(); }

  private async startScan(): Promise<void> {
    await this.vm.scan(this.context());
    if (this.vm.target.kind === ContentDestinationKind.THREAD) {
      NavigationService.openThreadDetail({ tid: this.vm.target.tid });
    } else if (this.vm.target.kind === ContentDestinationKind.FORUM) {
      NavigationService.openForum({ forumName: this.vm.target.word });
    }
  }

  build() {
    HdsNavDestination() {
      Column() {
        Row({ space: 14 }) {
          GlassBackButton({ onTap: (): void => { NavigationService.back(); } })
          Text('扫一扫').fontSize(19).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT_MAIN)
        }.width('100%').height(60).padding({ left: 16, right: 16 })
        Column({ space: 20 }) {
          SymbolGlyph($r('sys.symbol.qrcode')).fontSize(64).fontColor([AppTheme.ACCENT])
          Text('扫描贴吧帖子或吧链接').fontSize(18).fontColor(AppTheme.TEXT_MAIN)
            .textAlign(TextAlign.Center)
          Text('支持相机扫码，也可从系统扫码界面选择相册图片。其他二维码不会打开。')
            .fontSize(14).fontColor(AppTheme.TEXT_SUB).lineHeight(22).textAlign(TextAlign.Center)
          Button(this.vm.scanning ? '正在扫码…' : '开始扫码')
            .fontSize(16).fontColor(Color.White).backgroundColor(AppTheme.ACCENT)
            .enabled(!this.vm.scanning).onClick(() => { void this.startScan(); })
          if (this.vm.message.length > 0) {
            Text(this.vm.message).fontSize(14).fontColor(AppTheme.TEXT_SUB).textAlign(TextAlign.Center)
          }
        }.width('100%').padding({ left: 24, right: 24, top: 64 })
      }.width('100%').height('100%').padding({ top: this.statusBarH }).backgroundColor(AppTheme.BG)
    }.hideTitleBar(true)
  }
}
