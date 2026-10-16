import { common } from '@kit.AbilityKit';
import { display } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { AuthSession, authSession } from '../auth/AuthSession';
import { CommentTarget, commentLink, commentText } from '../model/CommentAction';
import { materialManager } from '../common/material/MaterialManager';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { DetailTheme } from '../theme/Theme';
import { AuthorBlockVM, authorBlockAction } from '../viewmodel/AuthorBlockVM';
import { shareWebPage } from '../utils/SystemShare';

@ComponentV2
export struct CommentActionHost {
  @Require @Param target: CommentTarget;
  @BuilderParam content: () => void = this.emptyContent;
  @Local popup: boolean = false;
  @Local copying: boolean = false;
  @Local selectionStart: number = 0;
  @Local selectionEnd: number = 0;
  @Local selectionText: string = '';
  @Local menuWidth: number = 336;
  @Local blockVM: AuthorBlockVM = new AuthorBlockVM(0);
  private busy: boolean = false;
  @Local auth: AuthSession = authSession;

  aboutToAppear(): void {
    this.menuWidth = Math.min(336, px2vp(display.getDefaultDisplaySync().width) - 24);
    this.bindAuthor();
  }

  @Monitor('target', 'auth.snapshot')
  bindAuthor(): void {
    const vm: AuthorBlockVM = authorBlockAction(this.target.author.id);
    if (vm !== this.blockVM) { this.popup = false; this.blockVM = vm; }
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }
  private toast(message: string): void { this.getUIContext().getPromptAction().showToast({ message }); }

  private async copy(text: string): Promise<void> {
    if (text.length === 0) { this.toast('没有可复制的文字'); return; }
    await pasteboard.getSystemPasteboard().setData(pasteboard.createPlainTextData(text));
    this.toast('已复制');
  }

  private async action(index: number): Promise<void> {
    if (this.busy) { return; }
    this.popup = false;
    this.busy = true;
    let reportCopied: boolean = false;
    try {
      if (index === 0) {
        const link: string = commentLink(this.target);
        if (link.length === 0) { this.toast('评论链接暂不可用'); return; }
        await shareWebPage(this.context(), this.target.title.length > 0 ? this.target.title : '贴吧评论', link);
      } else if (index === 1) {
        await this.copy(commentText(this.target));
      } else if (index === 2) {
        this.selectionText = commentText(this.target);
        if (this.selectionText.length === 0) { this.toast('没有可复制的文字'); return; }
        this.selectionStart = 0;
        this.selectionEnd = this.selectionText.length;
        this.copying = true;
      } else if (index === 3) {
        const link: string = commentLink(this.target);
        if (link.length === 0) { this.toast('评论链接暂不可用'); return; }

        await pasteboard.getSystemPasteboard().setData(pasteboard.createPlainTextData(link));
        reportCopied = true;
        await this.context().openLink('https://tieba.baidu.com/tousu/new');
        this.toast('评论链接已复制，请在官方举报页面填写');
      } else {
        if (!this.auth.isLoggedIn()) { this.toast('需要登录后才能拉黑'); return; }
        if (this.target.author.id <= 0 || this.target.author.id === this.auth.snapshot.uid) {
          this.toast('不能拉黑当前作者'); return;
        }
        const vm: AuthorBlockVM = this.blockVM;
        const confirm = await this.getUIContext().getPromptAction().showDialog({
          title: '拉黑作者', message: '将该作者加入贴吧黑名单，限制关注、互动和私信，并隐藏其评论。',
          buttons: [{ text: '取消', color: $r('app.color.detail_text_secondary') },
            { text: '屏蔽', color: $r('app.color.detail_accent') }]
        });
        if (confirm.index === 1 && vm === this.blockVM) {
          const message: string = await vm.set(this.context(), true);
          if (message.length > 0) { this.toast(message); }
          else if (vm.known && vm.blocked) { this.toast('已拉黑该作者'); }
        }
      }
    } catch (err) {
      this.toast(index === 0 ? '暂时无法打开系统分享' : index === 3 ?
        (reportCopied ? '无法打开官方举报页面，评论链接已复制' : '复制评论链接失败，请重试') :
        index === 4 ? '拉黑操作失败，请重试' : '复制失败，请重试');
    } finally { this.busy = false; }
  }

  private async unmute(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      const message: string = await this.blockVM.set(this.context(), false);
      if (message.length > 0) { this.toast(message); }
    }
    catch (err) { this.toast('取消拉黑失败，请重试'); }
    finally { this.busy = false; }
  }

  @Builder emptyContent() {}

  private selectionIconPath(): string {

    const p4: number = vp2px(4);
    const p7: number = vp2px(7);
    const p8: number = vp2px(8);
    const p9: number = vp2px(9);
    const p12: number = vp2px(12);
    const p15: number = vp2px(15);
    const p16: number = vp2px(16);
    const p17: number = vp2px(17);
    const p20: number = vp2px(20);
    return `M ${p7} ${p4} H ${p4} V ${p7} M ${p17} ${p4} H ${p20} V ${p7}` +
      ` M ${p4} ${p17} V ${p20} H ${p7} M ${p20} ${p17} V ${p20} H ${p17}` +
      ` M ${p9} ${p8} H ${p15} M ${p12} ${p8} V ${p16} M ${p9} ${p16} H ${p15}`;
  }

  @Builder
  Item(symbol: Resource, label: string, index: number) {
    Column({ space: 7 }) {
      if (index === 2) {

        Path().commands(this.selectionIconPath())
          .fill(Color.Transparent).stroke(DetailTheme.ICON).strokeWidth(1.7)
          .strokeLineCap(LineCapStyle.Round).strokeLineJoin(LineJoinStyle.Round)
          .width(24).height(24)
      } else {
        SymbolGlyph(symbol).fontSize(24).fontColor([DetailTheme.ICON])
      }
      Text(label).fontSize(12).fontColor(DetailTheme.TEXT_MAIN).maxLines(1)
    }
    .layoutWeight(1).height(72).justifyContent(FlexAlign.Center)
    .accessibilityText(label)
    .onClick((): void => { this.action(index); })
  }

  @Builder
  Menu() {
    Row() {
      this.Item($r('sys.symbol.share'), '分享', 0)
      this.Item($r('sys.symbol.doc_text_on_doc_text'), '复制全部', 1)
      this.Item($r('sys.symbol.character_textbox'), '自由复制', 2)
      this.Item($r('sys.symbol.flag'), '举报', 3)
      this.Item($r('sys.symbol.nosign'), '屏蔽', 4)
    }.width('100%').padding({ left: 6, right: 6 })
  }

  @Builder
  CopySheet() {
    Column({ space: 16 }) {
      Text('拖动选区两端，选择要复制的文字').fontSize(13).fontColor(DetailTheme.TEXT_SUB)
      Scroll() {
        Text(this.selectionText).fontSize(16).lineHeight(26).fontColor(DetailTheme.TEXT_MAIN)
          .width('100%').copyOption(CopyOptions.LocalDevice)
          .selection(this.selectionStart, this.selectionEnd)
          .onTextSelectionChange((start: number, end: number): void => {
            this.selectionStart = start; this.selectionEnd = end;
          })
      }.layoutWeight(1).width('100%').align(Alignment.TopStart)
      Button('复制所选').onClick((): void => {
        if (this.selectionStart < 0 || this.selectionEnd <= this.selectionStart ||
          this.selectionEnd > this.selectionText.length) { this.toast('请先选择要复制的文字'); return; }
        this.copy(this.selectionText.substring(this.selectionStart, this.selectionEnd))
          .then((): void => { this.copying = false; }).catch((): void => { this.toast('复制失败，请重试'); });
      })
    }.width('100%').height('100%').padding(20)
  }

  build() {
    Column() {
      if (this.blockVM.known && this.blockVM.blocked) {
        Row({ space: 12 }) {
          Text('已屏蔽该作者的评论').fontSize(12).fontColor(DetailTheme.TEXT_SUB).layoutWeight(1)
          Text('取消屏蔽').fontSize(12).fontColor(DetailTheme.ACCENT).constraintSize({ minHeight: 40 })
            .onClick((): void => { this.unmute(); })
        }.width('100%').padding({ left: 16, right: 16 })
      } else {
        Column() { this.content(); }
          .width('100%')
          .gesture(LongPressGesture({ duration: 500 }).onAction((): void => { this.popup = true; }))
      }
    }.width('100%')
    .id(`commentAction_${this.target.pid}`)
    .onVisibleAreaChange([0.1], (visible: boolean): void => {
      if (visible) { this.bindAuthor(); void this.blockVM.load(this.context()); }
      else { this.popup = false; }
    })
    .bindPopup(this.popup, {
      builder: (): void => { this.Menu(); }, placement: Placement.Top, enableArrow: false,
      width: this.menuWidth, radius: 14, targetSpace: 8, mask: { color: Color.Transparent }, autoCancel: true,
      backgroundEffect: materialManager.glassOf(MaterialSlot.SHEET),
      systemMaterial: materialManager.officialOf(MaterialSlot.SHEET),
      onStateChange: (event: PopupStateChangeParam): void => { if (!event.isVisible) { this.popup = false; } }
    })
    .bindSheet(this.copying, this.CopySheet(), {
      height: SheetSize.LARGE, title: { title: '自由复制' }, showClose: true,
      backgroundColor: DetailTheme.BG, onDisappear: (): void => { this.copying = false; }
    })
  }
}
