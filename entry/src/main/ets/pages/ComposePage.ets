import { common } from '@kit.AbilityKit';
import { KeyboardAvoidMode as PageKeyboardAvoidMode, LengthMetrics, window } from '@kit.ArkUI';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { ComposeMaterialBar } from '../components/ComposeMaterialBar';
import { EmojiPickerPanel, EMOJI_GRID_MIN_HEIGHT } from '../components/EmojiPickerPanel';
import { EmojiPickerVM } from '../viewmodel/EmojiPickerVM';
import { MemePicItem } from '../model/MemeEmoji';
import { emojiImageUrl } from '../model/ThreadDetail';
import { emojiSrc } from '../common/emoji/EmojiSrc';
import { readEmojiEditor, restoreEmojiEditor } from '../utils/EmojiEditor';
import { materialManager } from '../common/material/MaterialManager';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { ComposeOptionSheet } from '../components/ComposeOptionSheet';
import { CloseIcon } from '../components/CloseIcon';
import { GlassCircleButton } from '../components/GlassCircleButton';
import { NavigationService } from '../navigation/AppNavigation';
import { AppTheme } from '../theme/Theme';
import { readStatusBarVp, STATUS_BAR_FALLBACK_VP } from '../utils/SafeArea';
import { COMPOSE_TYPES, ComposeDraft, ComposePublishResult, ComposeVM, unsupportedComposeOptions } from '../viewmodel/ComposeVM';

const TOP_BAR_HEIGHT: number = 40;

@ComponentV2
export struct ComposePage {
  @Local vm: ComposeVM = new ComposeVM();
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;
  @Local sheet: boolean = false;
  @Local sheetKind: string = '';
  @Local optionDraft: ComposeDraft = new ComposeDraft();
  @Local emojiPicker: EmojiPickerVM = new EmojiPickerVM();
  @Local emojiOpen: boolean = false;
  @Local emojiManaging: boolean = false;
  @Local emojiTab: number = 0;
  @Local keyboardVp: number = 0;
  @Local lastKeyboardVp: number = 0;
  @Local emojiAwaitKeyboard: boolean = false;
  private keyboardWin: window.Window | undefined = undefined;
  private keyboardAreaCb: ((data: window.AvoidAreaOptions) => void) | undefined = undefined;
  private keyboardWatchSeq: number = 0;
  private keyboardWaitTimer: number = -1;
  private bodyControllers: RichEditorController[] = [new RichEditorController(), new RichEditorController(),
    new RichEditorController(), new RichEditorController()];
  private rebuildingBodies: boolean[] = [false, false, false, false];
  private bodyReady: boolean[] = [false, false, false, false];
  private closing: boolean = false;
  private previousKeyboardMode: PageKeyboardAvoidMode | undefined = undefined;

  aboutToAppear(): void {
    this.useEditorKeyboardMode();
    this.trackKeyboard();
    readStatusBarVp(this.getUIContext().getHostContext() as common.UIAbilityContext)
      .then((height: number): void => { this.statusBarH = height; }).catch((): void => {});
  }

  aboutToDisappear(): void { this.stopKeyboardTracking(); this.vm.dispose(); this.restoreKeyboardMode(); }

  private trackKeyboard(): void {
    if (this.keyboardWin !== undefined) { return; }
    const seq: number = ++this.keyboardWatchSeq;
    window.getLastWindow(this.getUIContext().getHostContext() as common.UIAbilityContext).then((win: window.Window): void => {
      if (seq !== this.keyboardWatchSeq) { return; }
      this.keyboardWin = win;
      this.updateKeyboard(px2vp(win.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD).bottomRect.height));
      this.keyboardAreaCb = (data: window.AvoidAreaOptions): void => {
        if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
          this.updateKeyboard(px2vp(data.area.bottomRect.height));
        }
      };
      win.on('avoidAreaChange', this.keyboardAreaCb);
    }).catch((): void => {});
  }

  private updateKeyboard(height: number): void {
    this.keyboardVp = Math.max(0, height);
    if (this.keyboardVp > 0) {
      this.lastKeyboardVp = this.keyboardVp;
      if (this.emojiAwaitKeyboard) {
        this.emojiAwaitKeyboard = false;
        this.clearKeyboardWait();
      }
    }
  }

  private clearKeyboardWait(): void {
    if (this.keyboardWaitTimer >= 0) { clearTimeout(this.keyboardWaitTimer); this.keyboardWaitTimer = -1; }
  }

  private stopKeyboardTracking(): void {
    ++this.keyboardWatchSeq;
    this.clearKeyboardWait();
    if (this.keyboardWin !== undefined && this.keyboardAreaCb !== undefined) {
      this.keyboardWin.off('avoidAreaChange', this.keyboardAreaCb);
    }
    this.keyboardWin = undefined;
    this.keyboardAreaCb = undefined;
    this.emojiAwaitKeyboard = false;
    this.emojiOpen = false;
    this.keyboardVp = 0;
  }

  private emojiPanelHeight(): number {
    // 沿用键盘高度，并保证能完整显示五行放大的表情。
    return Math.max(EMOJI_GRID_MIN_HEIGHT + 60 + AppTheme.BAR_SAFE_H,
      this.lastKeyboardVp > 0 ? this.lastKeyboardVp : 314);
  }

  private inputPanelHeight(): number {
    return this.emojiOpen || this.emojiAwaitKeyboard ? this.emojiPanelHeight() : this.keyboardVp;
  }

  private awaitEmojiKeyboard(): void {
    if (!this.emojiOpen) { return; }
    this.emojiAwaitKeyboard = true;
    this.emojiOpen = false;
    this.clearKeyboardWait();
    this.keyboardWaitTimer = setTimeout((): void => {
      this.keyboardWaitTimer = -1;
      this.emojiAwaitKeyboard = false;
    }, 1200);
  }

  private useEditorKeyboardMode(): void {
    if (this.previousKeyboardMode !== undefined) { return; }
    const ui = this.getUIContext();
    this.previousKeyboardMode = ui.getKeyboardAvoidMode();
    // 与详情页固定输入卡片相同：系统不移动页面，由固定层统一安排键盘/表情占位。
    ui.setKeyboardAvoidMode(PageKeyboardAvoidMode.NONE);
  }

  private restoreKeyboardMode(): void {
    if (this.previousKeyboardMode === undefined) { return; }
    this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardMode);
    this.previousKeyboardMode = undefined;
  }

  private close(): void {
    if (this.closing) { return; }
    if (this.vm.publishing) {
      this.getUIContext().getPromptAction().showToast({ message: '正在发布中，请稍候' });
      return;
    }
    if (!this.vm.hasContent()) { NavigationService.back(); return; }
    this.closing = true;
    this.getUIContext().getPromptAction().showDialog({ title: '放弃本次编辑？', message: '离开后，本页所有类型的未发布内容都会清空。',
      buttons: [{ text: '继续编辑', color: AppTheme.TEXT_MAIN }, { text: '放弃', color: AppTheme.ACCENT }]
    }).then((result): void => {
      if (result.index === 1) { NavigationService.back(); }
    }).catch((): void => {}).finally((): void => { this.closing = false; });
  }

  private openOption(kind: string): void {
    this.emojiOpen = false;
    this.emojiAwaitKeyboard = false;
    this.clearKeyboardWait();
    this.getUIContext().getFocusController().clearFocus();
    this.sheetKind = kind;
    this.optionDraft = this.vm.draft;
    this.sheet = true;
  }

  private syncBody(type: number): void {
    if (!this.bodyReady[type] || this.rebuildingBodies[type]) { return; }
    this.vm.drafts[type].body = readEmojiEditor(this.bodyControllers[type], this.emojiPicker.memeTokenTable(),
      new Map<string, string>()).text;
  }

  private restoreBody(type: number): void {
    this.bodyReady[type] = true;
    this.rebuildingBodies[type] = true;
    try {
      this.bodyControllers[type].setTypingStyle({ fontSize: 16, fontColor: AppTheme.TEXT_MAIN });
      restoreEmojiEditor(this.bodyControllers[type], this.vm.drafts[type].body, this.emojiPicker.memeTokenTable(), AppTheme.TEXT_MAIN);
    }
    finally { this.rebuildingBodies[type] = false; }
  }

  private toggleEmoji(): void {
    this.syncBody(this.vm.type);
    if (this.emojiOpen) {
      this.awaitEmojiKeyboard();
      this.getUIContext().getFocusController().requestFocus('compose-body');
    } else {
      this.emojiAwaitKeyboard = false;
      this.clearKeyboardWait();
      this.emojiOpen = true;
      this.bodyControllers[this.vm.type].stopEditing();
      this.getUIContext().getFocusController().clearFocus();
    }
  }

  private insertEmoji(url: string): void {
    if (url.length === 0) { return; }
    const controller: RichEditorController = this.bodyControllers[this.vm.type];
    const caret: number = controller.getCaretOffset();
    const options: RichEditorImageSpanOptions = { imageStyle: { size: [22, 22] } };
    if (caret >= 0) { options.offset = caret; }
    controller.addImageSpan(emojiSrc(url), options);
    this.syncBody(this.vm.type);
  }

  private deleteEmoji(): void {
    const controller: RichEditorController = this.bodyControllers[this.vm.type];
    const spans: Array<RichEditorImageSpanResult | RichEditorTextSpanResult> = controller.getSpans();
    if (spans.length === 0) { return; }
    const caret: number = controller.getCaretOffset();
    const end: number = caret >= 0 ? caret : spans[spans.length - 1].offsetInSpan[1];
    if (end <= 0) { return; }
    controller.deleteSpans({ start: end - 1, end: end });
    this.syncBody(this.vm.type);
  }

  @Builder
  EmojiPanel() {
    EmojiPickerPanel({ picker: this.emojiPicker, tab: this.emojiTab,
      gridHeight: Math.max(0, this.emojiPanelHeight() - 60 - AppTheme.BAR_SAFE_H), safeBottom: AppTheme.BAR_SAFE_H,
      onTabChange: (tab: number): void => { this.emojiTab = tab; },
      onManagerChange: (open: boolean): void => { this.emojiManaging = open; },
      onLoad: (): void => { void this.emojiPicker.loadMemePics(this.getUIContext().getHostContext() as common.UIAbilityContext); },
      onRetry: (): void => { void this.emojiPicker.retryMemePics(this.getUIContext().getHostContext() as common.UIAbilityContext); },
      onBuiltin: (code: number): void => { this.insertEmoji(emojiImageUrl(`image_emoticon${code}`)); },
      onMeme: (item: MemePicItem): void => { this.insertEmoji(this.emojiPicker.memeDisplayUrl(item)); },
      onDelete: (): void => { this.deleteEmoji(); } })
      .backgroundColor(AppTheme.CARD)
      .backgroundEffect(materialManager.glassOf(MaterialSlot.REPLY_SHEET))
      .borderRadius({ topLeft: 16, topRight: 16 }).clip(true)
  }

  private isOptionPanel(): boolean {
    return ['选择的吧', '添加话题', '设置展示范围', '内容声明'].includes(this.sheetKind);
  }

  private async pick(asVideo: boolean = false): Promise<void> {
    await this.vm.pickMedia(asVideo);
    if (this.vm.error.length > 0) { this.getUIContext().getPromptAction().showToast({ message: this.vm.error }); }
  }

  private bodyHint(): string {
    if (this.vm.type === 3) { return '请输入问题描述，提供的信息越全，解答越准确哦'; }
    if (this.vm.type === 0) { return '请输入正文，分享你的想法（最多添加9张图片）'; }
    return '请输入正文（建议200–2000字）';
  }

  @Builder
  TypeTabs() {
    Row() {
      ForEach(COMPOSE_TYPES, (label: string, index: number) => {
        Column() {
          Text(label).fontSize(16).fontWeight(this.vm.type === index ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.vm.type === index ? AppTheme.TEXT_MAIN : AppTheme.TEXT_SUB).maxLines(1)
        }.layoutWeight(1).height(TOP_BAR_HEIGHT).justifyContent(FlexAlign.Center)
          .accessibilityText(label).accessibilitySelected(this.vm.type === index)
          .id(`compose-type-${index}`)
          .onClick((): void => {
            this.syncBody(this.vm.type);
            this.emojiOpen = false;
            this.emojiAwaitKeyboard = false;
            this.clearKeyboardWait();
            this.getUIContext().getFocusController().clearFocus(); this.vm.type = index;
          })
      }, (label: string): string => label)
    }.width('100%').height('100%').padding({ left: 4, right: 4 })
  }

  @Builder
  PublishAction() {
    Row() {
      Text(this.vm.publishing ? '发布中…' : '发布').fontSize(15).fontWeight(FontWeight.Medium)
        .fontColor(this.vm.publishing ? AppTheme.TEXT_SUB : AppTheme.TEXT_MAIN).maxLines(1)
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      .id('compose-publish').accessibilityGroup(true)
      .accessibilityText(this.vm.publishing ? '正在发布' : '发布')
      .onClick((): void => { void this.startPublish(); })
  }

  /**
   * 发布入口：先同步编辑器里的正文，再走本地校验 → 未支持选项确认 → 提交。
   *
   * 未支持的选项（展示范围/内容声明/话题/心情）先让用户确认会被忽略，
   * 而不是发出去之后才发现设置没生效。
   */
  private async startPublish(): Promise<void> {
    if (this.vm.publishing) { return; }
    this.syncBody(this.vm.type);
    const blocked: string = this.vm.publishBlocked();
    if (blocked.length > 0) {
      this.getUIContext().getPromptAction().showToast({ message: blocked });
      return;
    }
    const ignored: string[] = unsupportedComposeOptions(this.vm.draft);
    if (ignored.length > 0) {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '这些选项本次发布不会生效',
        message: `${ignored.join('、')}尚未接入发布接口，继续发布将忽略以上设置。`,
        buttons: [{ text: '取消', color: AppTheme.TEXT_MAIN }, { text: '继续发布', color: AppTheme.ACCENT }]
      });
      if (result.index !== 1 || this.vm.publishing) { return; }
    }
    this.emojiOpen = false;
    this.getUIContext().getFocusController().clearFocus();
    // 发布成功会清空草稿，吧名必须在提交前留住
    const forumName: string = this.vm.draft.forum;
    const outcome: ComposePublishResult =
      await this.vm.publish(this.getUIContext().getHostContext() as common.UIAbilityContext);
    if (!outcome.ok) {
      this.getUIContext().getPromptAction().showToast({ message: outcome.message });
      return;
    }
    this.getUIContext().getPromptAction().showToast({ message: '发布成功' });
    // 先关掉发帖页再进新帖：返回时回到吧页/首页，而不是回到已清空的编辑器
    NavigationService.back();
    if (outcome.tid > 0) {
      NavigationService.openThreadDetail({ tid: outcome.tid, forumName: forumName });
    }
  }

  @Builder
  Header() {
    Row({ space: 8 }) {
      GlassCircleButton({ symbol: $r('sys.symbol.xmark'), diameter: TOP_BAR_HEIGHT,
        iconWeight: FontWeight.Regular, shadowEnabled: false, accessibilityLabel: '关闭发帖页',
        onTap: (): void => { this.close(); } })
        .borderRadius(TOP_BAR_HEIGHT / 2)
        .shadow({ radius: 14, color: '#18000000', offsetY: 4 })
      ComposeMaterialBar({ barHeight: TOP_BAR_HEIGHT, content: (): void => { this.TypeTabs(); } }).layoutWeight(1)
      ComposeMaterialBar({ barHeight: TOP_BAR_HEIGHT, content: (): void => { this.PublishAction(); } }).width(56)
    }.width('100%').padding({ left: 16, right: 16, top: this.statusBarH + 8, bottom: 16 })
  }

  @Builder
  Media() {
    Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(10), cross: LengthMetrics.vp(10) } }) {
      ForEach(this.vm.draft.media, (uri: string) => {
        Stack({ alignContent: Alignment.TopEnd }) {
          if (this.vm.type === 2) {
            Column({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.video')).fontSize(30).fontColor([AppTheme.ACCENT])
              Text('已选择视频').fontSize(13).fontColor(AppTheme.TEXT_MAIN)
            }.width(112).height(112).justifyContent(FlexAlign.Center).backgroundColor(AppTheme.SURFACE_MUTED)
          } else {
            Image(uri).width(112).height(112).objectFit(ImageFit.Cover)
          }
          Row() { CloseIcon({ iconSize: 14 }).width(14).height(14) }
            .width(32).height(32).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
            .backgroundColor(AppTheme.CARD).borderRadius(16).accessibilityText('移除附件')
            .onClick((): void => { this.vm.draft.media = this.vm.draft.media.filter((value: string): boolean => value !== uri); })
        }.borderRadius(16).clip(true)
      }, (uri: string): string => uri)
      if (this.vm.draft.video.length > 0) {
        Stack({ alignContent: Alignment.TopEnd }) {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.video')).fontSize(30).fontColor([AppTheme.ACCENT])
            Text('已选择视频').fontSize(13).fontColor(AppTheme.TEXT_MAIN)
          }.width(112).height(112).justifyContent(FlexAlign.Center).backgroundColor(AppTheme.SURFACE_MUTED)
          Row() { CloseIcon({ iconSize: 14 }).width(14).height(14) }
            .width(32).height(32).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
            .backgroundColor(AppTheme.CARD).borderRadius(16).accessibilityText('移除视频')
            .onClick((): void => { this.vm.draft.video = ''; })
        }.borderRadius(16).clip(true)
      }
      if ((this.vm.type === 2 && this.vm.draft.media.length === 0) ||
        (this.vm.type !== 2 && this.vm.draft.media.length < 9)) {
        Column({ space: 8 }) {
          SymbolGlyph(this.vm.type === 2 ? $r('sys.symbol.video') : $r('sys.symbol.plus'))
            .fontSize(32).fontWeight(FontWeight.Lighter).fontColor([AppTheme.TEXT_SUB])
          Text(this.vm.picking ? '选择中…' : (this.vm.type === 2 ? '选择视频' : '添加图片'))
            .fontSize(12).fontColor(AppTheme.TEXT_SUB)
        }.width(112).height(112).justifyContent(FlexAlign.Center).backgroundColor(AppTheme.SURFACE_MUTED)
          .borderRadius(16).enabled(!this.vm.picking).onClick((): void => { void this.pick(); })
      }
    }.width('100%').padding({ top: 16, bottom: 24 })
  }

  private optionValue(title: string): string {
    if (title === '选择的吧') { return this.vm.draft.forum || '选择合适的吧'; }
    if (title === '添加心情') { return this.vm.draft.mood || '选择心情'; }
    if (title === '悬赏帖贝') { return '暂未开放'; }
    if (title === '添加话题') { return this.vm.draft.topic || '添加话题'; }
    if (title === '设置展示范围') { return this.vm.draft.visibility; }
    return this.vm.draft.declaration || '未设置';
  }

  @Builder
  OptionRow(symbol: Resource, title: string) {
    Row({ space: 12 }) {
      SymbolGlyph(symbol).fontSize(21).fontColor([AppTheme.TEXT_MAIN])
      Text(title).fontSize(16).fontColor(AppTheme.TEXT_MAIN).maxLines(1)
      Blank()
      Text(this.optionValue(title)).fontSize(13).fontColor(AppTheme.TEXT_SUB).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: '48%' })
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor([AppTheme.TEXT_MUTED])
    }.width('100%').constraintSize({ minHeight: 56 }).onClick((): void => { this.openOption(title); })
  }

  @Builder
  Options() {
    Column() {
      this.OptionRow($r('sys.symbol.message'), '选择的吧')
      if (this.vm.type === 3) {
        this.OptionRow($r('sys.symbol.face_smiling'), '添加心情')
        this.OptionRow($r('sys.symbol.gift'), '悬赏帖贝')
      } else {
        this.OptionRow($r('sys.symbol.hash'), '添加话题')
      }
      this.OptionRow($r('sys.symbol.eye'), '设置展示范围')
      if (this.vm.type !== 3) {
        this.OptionRow($r('sys.symbol.info_circle'), '内容声明')
      }
    }.width('100%').border({ width: { top: 0.5 }, color: AppTheme.DIVIDER }).padding({ top: 8 })
  }

  @Builder
  BodyEditor(type: number) {
    RichEditor({ controller: this.bodyControllers[type] })
      .id('compose-body').width('100%').height(type === 0 ? 270 : 144).maxLength(20000)
      .placeholder(this.bodyHint(), { font: { size: 16 }, fontColor: AppTheme.TEXT_MUTED })
      .backgroundColor(Color.Transparent).padding({ top: 18, left: 0, right: 0, bottom: 0 })
      .focusBox({ strokeWidth: LengthMetrics.vp(0) })
      .onReady((): void => { this.restoreBody(type); })
      .onDisAppear((): void => { this.bodyReady[type] = false; })
      .onDidChange((): void => { this.syncBody(type); })
      .onFocus((): void => { this.awaitEmojiKeyboard(); })
  }

  @Builder
  Editor() {
    Column() {
      if (this.vm.type !== 2 || this.vm.draft.media.length > 0) {
        Row({ space: 6 }) {
          if (this.vm.type === 3) {
            Text('求助').fontSize(11).fontColor(AppTheme.ACCENT_DARK).padding(3).borderRadius(4)
              .border({ width: 0.5, color: AppTheme.ACCENT })
          }
          TextInput({ text: this.vm.draft.title,
            placeholder: this.vm.type === 3 ? '请输入完整问题（5–31个字）' : '请输入完整帖子标题（5–31个字）' })
            .id('compose-title').layoutWeight(1).height(64).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.TEXT_MAIN).placeholderColor(AppTheme.TEXT_MUTED).maxLength(31)
            .backgroundColor(Color.Transparent).padding(0)
            .onChange((value: string): void => { this.vm.draft.title = value; })
        }.width('100%').border({ width: { bottom: 0.5 }, color: AppTheme.DIVIDER })
        ForEach([this.vm.type], (type: number) => { this.BodyEditor(type) }, (type: number): string => String(type))
      }
      this.Media()
      if (this.vm.type !== 2 || this.vm.draft.media.length > 0) { this.Options() }
    }.width('100%').padding({ left: 20, right: 20 })
  }

  @Builder
  Tool(symbol: Resource, label: string, enabled: boolean, action: () => void) {
    Row() {
      if (label === '表情' && this.emojiOpen) {
        SymbolGlyph($r('sys.symbol.keyboard')).fontSize(24).maxFontScale(1).fontColor([AppTheme.TEXT_MAIN])
      } else {
        SymbolGlyph(symbol).fontSize(24).maxFontScale(1).fontColor([enabled ? AppTheme.TEXT_MAIN : AppTheme.TEXT_MUTED])
      }
    }.layoutWeight(1).height(AppTheme.BAR_CONTENT_H).justifyContent(FlexAlign.Center).enabled(enabled)
      .onClick(action).accessibilityText(enabled ? (label === '表情' && this.emojiOpen ? '键盘' : label) : label + '，暂未开放')
  }

  @Builder
  Tools() {
    Row() {
      if (this.vm.type === 0) {
        this.Tool($r('sys.symbol.picture'), '图片', true, (): void => { void this.pick(); })
        this.Tool($r('sys.symbol.face_smiling'), '表情', true, (): void => { this.toggleEmoji(); })
        this.Tool($r('sys.symbol.at'), '提及用户', false, (): void => {})
        this.Tool($r('sys.symbol.crown'), '会员工具', false, (): void => {})
      } else {
        this.Tool($r('sys.symbol.picture'), '图片', true, (): void => { void this.pick(); })
        this.Tool($r('sys.symbol.video'), '视频', true, (): void => { void this.pick(true); })
        this.Tool($r('sys.symbol.mic'), '语音', false, (): void => {})
        this.Tool($r('sys.symbol.link'), '链接', false, (): void => {})
        this.Tool($r('sys.symbol.face_smiling'), '表情', true, (): void => { this.toggleEmoji(); })
        this.Tool($r('sys.symbol.crown'), '会员工具', false, (): void => {})
        this.Tool($r('sys.symbol.plus'), '更多', true, (): void => { this.openOption('更多'); })
      }
    }.id(this.vm.type === 0 ? 'compose-article-tools' : 'compose-post-tools')
      .width('100%').height('100%').padding({ left: 8, right: 8 })
  }

  @Builder
  Choice(value: string) {
    Text(value || '不声明').fontSize(16).fontColor(AppTheme.TEXT_MAIN).width('100%').padding(16)
      .onClick((): void => {
        if (this.sheetKind === '添加心情') { this.vm.draft.mood = value; }
        else { this.vm.draft.declaration = value; }
        this.sheet = false;
      })
  }

  @Builder
  SheetContent() {
    if (this.isOptionPanel()) {
      ComposeOptionSheet({ kind: this.sheetKind, draft: this.optionDraft,
        onClose: (): void => { this.sheet = false; } })
    } else {
    Scroll() {
      Column({ space: 12 }) {
        Text(this.sheetKind).fontSize(20).fontWeight(FontWeight.Bold).fontColor(AppTheme.TEXT_MAIN)
        if (this.sheetKind === '添加心情') {
          this.Choice('在线等')
          this.Choice('人麻了')
          this.Choice('纠结中')
        } else if (this.sheetKind === '更多') {
          ForEach(['添加话题', '设置展示范围', '内容声明'], (title: string) => {
            Text(title).fontSize(16).fontColor(AppTheme.TEXT_MAIN).width('100%').padding(16)
              .onClick((): void => { this.openOption(title); })
          }, (title: string): string => title)
        } else {
          Text('悬赏功能暂未开放。')
            .fontSize(16).fontColor(AppTheme.TEXT_SUB)
        }
      }.width('100%').padding(24)
    }.width('100%').height('100%').align(Alignment.TopStart).backgroundColor(AppTheme.CARD)
    }
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Scroll() {
          Column() {
            this.Editor()
            if (this.vm.publishing || this.vm.publishStep.length > 0) {
              Text(this.vm.publishStep.length > 0 ? this.vm.publishStep : '正在发布…')
                .fontSize(11).fontColor(AppTheme.TEXT_SUB).padding({ top: 8, bottom: 8 })
            } else if (this.vm.error.length > 0) {
              // 失败原因常驻：toast 一闪而过，hilog 缓冲也留不住，界面必须能读到整句。
              Text(`发布失败：${this.vm.error}`)
                .fontSize(11).fontColor(AppTheme.TEXT_SUB).width('100%')
                .padding({ top: 8, bottom: 8, left: 16, right: 16 })
            }
          }.width('100%').padding({ top: this.statusBarH + TOP_BAR_HEIGHT + 24 })
        }.id('compose-editor-scroll').width('100%').height(`calc(100% - ${this.inputPanelHeight()}vp)`)
          .scrollBar(BarState.Off).align(Alignment.TopStart)
        this.Header()
        if (this.vm.type === 0 || this.vm.type === 1) {
          Stack({ alignContent: Alignment.Bottom }) {
            Column() {
              ComposeMaterialBar({ barHeight: AppTheme.BAR_CONTENT_H, content: (): void => { this.Tools(); } })
                .padding({ left: 16, right: 16 }).margin({ bottom: AppTheme.BAR_SAFE_H + this.inputPanelHeight() })
            }.width('100%')
            if (this.emojiOpen) { this.EmojiPanel() }
          }.width('100%').height('100%').hitTestBehavior(HitTestMode.Transparent)
        }
      }.width('100%').height('100%').backgroundColor(AppTheme.CARD)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
        .bindSheet($$this.sheet, this.SheetContent(), {
          height: this.sheetKind === '设置展示范围' ? 220 : (this.sheetKind === '内容声明' ? 240 : SheetSize.LARGE),
          showClose: !this.isOptionPanel(), dragBar: false,
          backgroundColor: AppTheme.CARD })
    }.hideTitleBar(true)
      .onShown((): void => { this.useEditorKeyboardMode(); this.trackKeyboard(); })
      .onHidden((reason: VisibilityChangeReason): void => {
        // 收藏管理覆盖当前编辑页，保留源面板以便返回；真实离场仍释放监听。
        if (reason === VisibilityChangeReason.CONTENT_COVER && this.emojiManaging) { return; }
        this.stopKeyboardTracking(); this.restoreKeyboardMode();
      })
      .onBackPressed((): boolean => {
        if (this.emojiOpen || this.emojiAwaitKeyboard) {
          this.emojiOpen = false; this.emojiAwaitKeyboard = false; this.clearKeyboardWait(); return true;
        }
        this.close(); return true;
      })
  }
}
