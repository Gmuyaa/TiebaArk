import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { ContentDestination, ContentDestinationKind } from '../model/ThreadDetail';
import { scanDestination, scanFailureMessage } from '../model/ScanLink';

/** 系统扫码结果仅保存在页面生命周期中；不记录原文或落盘。 */
@ObservedV2
export class ScanVM {
  @Trace scanning: boolean = false;
  @Trace message: string = '';
  @Trace target: ContentDestination = new ContentDestination();
  private epoch: number = 0;
  private disposed: boolean = false;

  async scan(context: common.UIAbilityContext): Promise<void> {
    if (this.scanning || this.disposed) { return; }
    const mine: number = ++this.epoch;
    this.scanning = true;
    this.message = '';
    this.target = new ContentDestination();
    try {
      const result: scanBarcode.ScanResult = await scanBarcode.startScanForResult(context, {
        scanTypes: [scanCore.ScanType.QR_CODE], enableMultiMode: false, enableAlbum: true
      });
      if (mine !== this.epoch) { return; }
      this.target = scanDestination(result.originalValue);
      this.message = this.target.kind === ContentDestinationKind.INVALID ?
        '仅支持贴吧帖子或吧链接二维码' : '已识别贴吧链接';
    } catch (err) {
      if (mine === this.epoch) { this.message = scanFailureMessage((err as BusinessError).code); }
    } finally {
      if (mine === this.epoch) { this.scanning = false; }
    }
  }

  dispose(): void {
    this.disposed = true;
    this.epoch++;
    this.scanning = false;
    this.target = new ContentDestination();
  }
}
