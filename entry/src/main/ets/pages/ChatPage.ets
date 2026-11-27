/**
 * 私信会话页：历史消息 + 悬浮多行输入栏 + 原生材质表情面板。
 *
 * 页面结构沿用帖子正文页：列表铺满整页、`ignoreLayoutSafeArea` 到屏底、头尾走内容占位，
 * 以便标题栏滚动模糊、输入栏与表情面板的官方材质都能对背后消息实时取样。
 */

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KeyboardAvoidMode as PageKeyboardAvoidMode, LengthMetrics, display, window } from '@kit.ArkUI';
import { HdsNavDestination, ScrollEffectType } from '@kit.UIDesignKit';
import { ChatBubble } from '../components/ChatBubble';
import { emojiPanelDialogOptions, emojiPanelGridHeight, emojiPanelHeight } from '../components/EmojiPanelDialog';
import { GlassBackButton } from '../components/GlassBackButton';
import { ImageViewer } from '../components/ImageViewer';
import { MaterialTabs } from '../components/MaterialTabs';
import { PageState } from '../components/PageState';
import { authSession } from '../auth/AuthSession';
import { MotionEffect } from '../common/appearance/MotionConfig';
import { motionDuration } from '../common/appearance/MotionPolicy';
import { motionStore } from '../common/appearance/MotionStore';
import { ThemeModeStore, themeModeStore } from '../common/appearance/ThemeModeStore';
import { VisualThemeStore, visualThemeStore } from '../common/appearance/VisualThemeStore';
import { windowBreakpoint } from '../common/appearance/WindowBreakpointStore';
import { emojiSrc } from '../common/emoji/EmojiSrc';
import { MaterialSlot } from '../common/material/MaterialConfig';
import { materialManager } from '../common/material/MaterialManager';
import { ChatImageContent, ChatMessage, MSG_TYPE_IMAGE } from '../model/Chat';
import { ListDataSource } from '../model/ListDataSource';
import { UploadedPostImage } from '../model/ImageUpload';
import { REPLY_EMOTICON_CODES, emojiImageUrl, emojiTokenFromUrl } from '../model/ThreadDetail';
import { ChatPageParams, NavigationService } from '../navigation/AppNavigation';
import { AppTheme, DetailTheme } from '../theme/Theme';
import { readEmojiEditor, updateEmojiEditorTextColor } from '../utils/EmojiEditor';
import { STATUS_BAR_FALLBACK_VP, readBottomInsetVp, readStatusBarVp } from '../utils/SafeArea';
import { ChatVM } from '../viewmodel/ChatVM';
import { ImageUploadVM } from '../viewmodel/ImageUploadVM';

const TIME_GAP_MS: number = 5 * 60 * 1000;
const COMPOSER_MIN_HEIGHT: number = 48;
const COMPOSER_MAX_HEIGHT: number = 116;
const COMPOSER_RADIUS: number = 24;
const COMPOSER_GAP: number = 10;
const BAR_SIDE_MARGIN: number = 16;
const ACTION_BUTTON_SIZE: number = 36;
const NAV_BAR_HEIGHT: number = 52;
const EMOJI_COLUMNS: string = '1fr 1fr 1fr 1fr 1fr 1fr 1fr';
const EMOJI_ICON: number = 30;
const EMOJI_VISIBLE_ROWS: number = 5;
const EMOJI_ROW_GAP: number = 14;
const EMOJI_TAB_SIZE: number = 36;
const EMOJI_TAB_BAR_H: number = 40;
const EMOJI_PANEL_TOP_PADDING: number = 8;
const EMOJI_PANEL_BOTTOM_PADDING: number = 12;
const EMOJI_TRANSITION_MS: number = 220;
const LIST_DISMISS_DRAG_VP: number = 12;

@ComponentV2
export struct ChatPage {
  @Param routeParams: ChatPageParams | undefined = undefined;
  @Local visualSettings: VisualThemeStore = visualThemeStore;
  @Local themeSettings: ThemeModeStore = themeModeStore;
  @Local vm: ChatVM = new ChatVM();
  @Local imageUpload: ImageUploadVM = new ImageUploadVM();
  @Local viewerOpen: boolean = false;
  @Local viewerUrls: string[] = [];
  @Local viewerIndex: number = 0;
  @Local msgSource: ListDataSource<ChatMessage> = new ListDataSource<ChatMessage>();
  private loadingOlder: boolean = false;

  private syncMessageSource(): void {
    this.msgSource.sync(this.vm.messages,
      (item: ChatMessage): string => `${item.key()}-${item.sendState}`,
      (item: ChatMessage): string => item.key());
  }
  @Local draft: string = '';
  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;
  @Local bottomInset: number = 0;
  @Local showEmoji: boolean = false;
  @Local emojiAwaitKeyboard: boolean = false;
  @Local lastKeyboardVp: number = 0;
  @Local keyboardVp: number = 0;
  @Local screenW: number = 0;
  @Local barWidth: number = 0;
  @Local composerHeight: number = COMPOSER_MIN_HEIGHT;

  private editor: RichEditorController = new RichEditorController();
  private editorReady: boolean = false;
  private editorFocused: boolean = false;
  private syncingDraft: boolean = false;
  private previousKeyboardMode: PageKeyboardAvoidMode | undefined = undefined;
  private scroller: Scroller = new Scroller();
  private scrollTimer: number = -1;
  private retryTimers: number[] = [];
  private listHeightVp: number = 0;
  private avoidWin: window.Window | undefined = undefined;
  private avoidAreaCb: ((data: window.AvoidAreaOptions) => void) | undefined = undefined;
  private keyboardWatchSeq: number = 0;
  private keyboardWaitTimer: number = -1;
  private emojiDialogId: number = 0;
  private emojiDialogSeq: number = 0;
  private emojiDialogOpening: boolean = false;
  private listTouching: boolean = false;
  private listTouchY: number = 0;

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    try { this.screenW = this.getUIContext().px2vp(display.getDefaultDisplaySync().width); } catch (_) {}
    readStatusBarVp(this.context())
      .then((vp: number): void => { this.statusBarH = vp; }).catch(() => {});
    readBottomInsetVp(this.context())
      .then((vp: number): void => { this.bottomInset = vp; }).catch(() => {});
    this.useEditorKeyboardMode();
    this.trackKeyboard();
    void this.open();
  }

  aboutToDisappear(): void {
    this.clearScrollTimers();
    this.stopKeyboardTracking();
    this.restoreKeyboardMode();
    this.imageUpload.dispose();
    this.vm.dispose();
  }

  private useEditorKeyboardMode(): void {
    if (this.previousKeyboardMode !== undefined) { return; }
    const ui: UIContext = this.getUIContext();
    this.previousKeyboardMode = ui.getKeyboardAvoidMode();
    // 页面不随键盘整体缩放：输入栏抬起量自行计算，保证键盘与表情面板切换零跳变。
    ui.setKeyboardAvoidMode(PageKeyboardAvoidMode.NONE);
  }

  private restoreKeyboardMode(): void {
    if (this.previousKeyboardMode === undefined) { return; }
    this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardMode);
    this.previousKeyboardMode = undefined;
  }

  private trackKeyboard(): void {
    if (this.avoidWin !== undefined) { return; }
    const seq: number = ++this.keyboardWatchSeq;
    window.getLastWindow(this.context()).then((win: window.Window): void => {
      if (seq !== this.keyboardWatchSeq) { return; }
      this.avoidWin = win;
      const ui = this.getUIContext();
      this.screenW = ui.px2vp(win.getWindowProperties().windowRect.width);
      this.bottomInset = ui.px2vp(win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height);
      this.updateKeyboard(ui.px2vp(win.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD).bottomRect.height));
      this.avoidAreaCb = (data: window.AvoidAreaOptions): void => {
        if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
          this.updateKeyboard(ui.px2vp(data.area.bottomRect.height));
        } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          this.bottomInset = ui.px2vp(data.area.bottomRect.height);
        }
      };
      win.on('avoidAreaChange', this.avoidAreaCb);
    }).catch((err: Error): void => {
      hilog.warn(0x0000, 'ChatPage', 'keyboard listener failed: %{public}s', err.message);
    });
  }

  private stopKeyboardTracking(): void {
    ++this.keyboardWatchSeq;
    this.clearKeyboardWait();
    this.closeEmojiPanelDialog();
    if (this.avoidWin !== undefined && this.avoidAreaCb !== undefined) {
      this.avoidWin.off('avoidAreaChange', this.avoidAreaCb);
    }
    this.avoidWin = undefined;
    this.avoidAreaCb = undefined;
    this.emojiAwaitKeyboard = false;
    this.showEmoji = false;
    this.keyboardVp = 0;
  }

  private updateKeyboard(height: number): void {
    const next: number = Math.max(0, height);
    if (next > 0) { this.lastKeyboardVp = next; }
    const handoff: boolean = next > 0 && (this.showEmoji || this.emojiAwaitKeyboard);
    if (next > 0 && this.showEmoji) { this.awaitEmojiKeyboard(); }
    if (handoff) {
      this.keyboardVp = next;
      this.emojiAwaitKeyboard = false;
      this.clearKeyboardWait();
    } else if (Math.abs(next - this.keyboardVp) >= 0.5) {
      this.getUIContext().animateTo({
        duration: motionDuration(200, MotionEffect.MOVE),
        curve: Curve.EaseOut
      }, (): void => {
        this.keyboardVp = next;
      });
    }
    this.scrollToBottom();
  }

  private clearKeyboardWait(): void {
    if (this.keyboardWaitTimer >= 0) {
      clearTimeout(this.keyboardWaitTimer);
      this.keyboardWaitTimer = -1;
    }
  }

  private animateEmojiLayout(action: () => void): void {
    this.getUIContext().animateTo({
      duration: motionDuration(EMOJI_TRANSITION_MS, MotionEffect.MOVE),
      curve: Curve.EaseOut
    }, action);
  }

  private awaitEmojiKeyboard(): void {
    if (!this.showEmoji) { return; }
    this.emojiAwaitKeyboard = true;
    this.showEmoji = false;
    this.closeEmojiPanelDialog();
    this.clearKeyboardWait();
    this.keyboardWaitTimer = setTimeout((): void => {
      this.keyboardWaitTimer = -1;
      this.animateEmojiLayout((): void => { this.emojiAwaitKeyboard = false; });
    }, 1200);
  }

  private collapseEmoji(): void {
    this.clearKeyboardWait();
    this.closeEmojiPanelDialog();
    this.animateEmojiLayout((): void => {
      this.showEmoji = false;
      this.emojiAwaitKeyboard = false;
    });
    this.scrollToBottom();
  }

  private dismissInput(): void {
    if (this.showEmoji || this.emojiAwaitKeyboard) {
      this.collapseEmoji();
    }
    if (this.keyboardVp > 0 || this.editorFocused) {
      this.editor.stopEditing();
      this.getUIContext().getFocusController().clearFocus();
    }
  }

  private openEmojiPanelDialog(): void {
    if (this.emojiDialogId !== 0 || this.emojiDialogOpening || !this.showEmoji) { return; }
    this.emojiDialogOpening = true;
    const seq: number = ++this.emojiDialogSeq;
    const prompt = this.getUIContext().getPromptAction();
    prompt.openCustomDialog(emojiPanelDialogOptions(
      (): void => { this.ChatEmojiSheet(); },
      this.screenW,
      this.emojiPanelVp(),
      (): void => { if (this.emojiDialogSeq === seq) { this.collapseEmoji(); } },
      (): void => {
        if (this.emojiDialogSeq === seq) {
          this.emojiDialogId = 0;
          this.emojiDialogOpening = false;
          this.collapseEmoji();
        }
      }
    )).then((id: number): void => {
      if (this.emojiDialogSeq !== seq || !this.showEmoji) {
        prompt.closeCustomDialog(id);
        return;
      }
      this.emojiDialogId = id;
      this.emojiDialogOpening = false;
    }).catch((): void => {
      if (this.emojiDialogSeq === seq) {
        this.emojiDialogOpening = false;
        this.collapseEmoji();
      }
    });
  }

  private closeEmojiPanelDialog(): void {
    ++this.emojiDialogSeq;
    this.emojiDialogOpening = false;
    const id: number = this.emojiDialogId;
    this.emojiDialogId = 0;
    if (id !== 0) {
      try { this.getUIContext().getPromptAction().closeCustomDialog(id); } catch (_) { /* 已被系统回收 */ }
    }
  }

  @Monitor('vm.messages')
  onMessagesChanged(): void {
    this.syncMessageSource();
    if (this.loadingOlder) { return; }
    this.scrollToBottom();
  }

  @Monitor('visualSettings.theme', 'themeSettings.isDark')
  refreshEditorColors(): void {
    if (!this.editorReady) { return; }
    try {
      this.applyTypingStyle();
      updateEmojiEditorTextColor(this.editor, AppTheme.TEXT_MAIN);
    } catch (_) { /* 编辑器尚未挂载或已卸载 */ }
  }

  private applyTypingStyle(): void {
    this.editor.setTypingStyle({
      fontColor: AppTheme.TEXT_MAIN,
      fontSize: 15,
      lineHeight: 22,
      halfLeading: true
    });
  }

  private async open(): Promise<void> {
    const groupIdText: string = this.routeParams?.groupIdText ?? '';
    const peerUidText: string = this.routeParams?.peerUidText ?? '';
    if (groupIdText.length === 0 && peerUidText.length === 0) {
      this.vm.error = '缺少会话标识';
      return;
    }
    await this.vm.open(this.context(), groupIdText, peerUidText,
      this.routeParams?.peerName ?? '', this.routeParams?.peerPortrait ?? '');
    this.syncMessageSource();
    this.scrollToBottom();
  }

  /** 首次进页列表会二次量尺，单次 scrollEdge 常停在末条上方，按 30/160/380ms 补滚。 */
  private scrollToBottom(): void {
    this.clearScrollTimers();
    this.scrollTimer = setTimeout((): void => {
      this.scrollTimer = -1;
      this.pinToBottom();
    }, 30);
    this.retryTimers.push(setTimeout((): void => { this.pinToBottom(); }, 160));
    this.retryTimers.push(setTimeout((): void => { this.pinToBottom(); }, 380));
  }

  private clearScrollTimers(): void {
    if (this.scrollTimer >= 0) { clearTimeout(this.scrollTimer); this.scrollTimer = -1; }
    for (const id of this.retryTimers) { clearTimeout(id); }
    this.retryTimers = [];
  }

  private pinToBottom(): void {
    try { this.scroller.scrollEdge(Edge.Bottom); } catch (_) { /* 列表尚未挂载 */ }
  }

  private repinAfterResize(height: number): void {
    if (!(height > 0) || Math.abs(height - this.listHeightVp) < 0.5) { return; }
    this.listHeightVp = height;
    this.scrollToBottom();
  }

  /** 传原始 portrait（`tb.1.xxx`）给 ChatBubble 统一拼 URL，避免二次拼接导致头像加载失败。 */
  private selfPortrait(): string {
    return authSession.snapshot.portrait;
  }

  private showTime(index: number): boolean {
    const list: ChatMessage[] = this.vm.messages;
    if (index <= 0) { return true; }
    if (index >= list.length) { return false; }
    const current: ChatMessage = list[index];
    const previous: ChatMessage = list[index - 1];
    if (current.createTimeMs <= 0 || previous.createTimeMs <= 0) { return false; }
    return current.createTimeMs - previous.createTimeMs > TIME_GAP_MS;
  }

  private loadOlderMessages(): void {
    if (!this.vm.hasOlderHistory) { return; }
    this.clearScrollTimers();
    this.loadingOlder = true;
    try {
      const added: number = this.vm.loadOlder();
      if (added > 0) {
        this.syncMessageSource();
      }
    } finally {
      setTimeout((): void => { this.loadingOlder = false; }, 120);
    }
  }

  private openChatImage(targetUrl: string): void {
    this.dismissInput();
    const urls: string[] = [];
    for (let i: number = 0; i < this.vm.messages.length; i++) {
      const m: ChatMessage = this.vm.messages[i];
      if (m.msgType !== MSG_TYPE_IMAGE) { continue; }
      const img: ChatImageContent | undefined = m.imageContent();
      if (img === undefined) { continue; }
      const url: string = img.bigSrc.length > 0 ? img.bigSrc : img.src;
      if (url.length > 0) { urls.push(url); }
    }
    let idx: number = urls.indexOf(targetUrl);
    if (idx < 0) {
      urls.push(targetUrl);
      idx = urls.length - 1;
    }
    this.viewerUrls = urls;
    this.viewerIndex = idx;
    this.viewerOpen = true;
  }

  private async pickAndSendImage(): Promise<void> {
    if (this.vm.sending || this.imageUpload.busy || this.imageUpload.selecting) { return; }
    this.dismissInput();
    const imGroupId: string = this.vm.uploadGroupId();
    await this.imageUpload.pickAndUpload(this.context(), '', true, imGroupId);
    const uploaded: UploadedPostImage | undefined = this.imageUpload.image;
    if (uploaded === undefined) {
      if (this.imageUpload.error.length > 0) {
        try { this.getUIContext().getPromptAction().showToast({ message: this.imageUpload.error }); } catch (_) {}
      }
      return;
    }
    const srcUrl: string = uploaded.smallUrl.length > 0 ? uploaded.smallUrl
      : (uploaded.bigUrl.length > 0 ? uploaded.bigUrl : uploaded.previewUrl);
    const bigUrl: string = uploaded.bigUrl.length > 0 ? uploaded.bigUrl
      : (uploaded.previewUrl.length > 0 ? uploaded.previewUrl : srcUrl);
    if (srcUrl.length === 0) {
      try { this.getUIContext().getPromptAction().showToast({ message: '图片上传未返回可用地址' }); } catch (_) {}
      return;
    }
    const sendW: number = uploaded.smallWidth > 0 && uploaded.smallHeight > 0 ? uploaded.smallWidth : uploaded.width;
    const sendH: number = uploaded.smallWidth > 0 && uploaded.smallHeight > 0 ? uploaded.smallHeight : uploaded.height;
    const err: string = await this.vm.sendImage(this.context(), srcUrl, sendW, sendH,
      (): void => { this.scrollToBottom(); }, bigUrl);
    if (err.length > 0) {
      try { this.getUIContext().getPromptAction().showToast({ message: err }); } catch (_) {}
    }
  }

  private async send(): Promise<void> {
    this.syncDraft();
    const text: string = this.draft;
    if (text.trim().length === 0 || this.vm.sending) { return; }
    // 仅在消息通过前置校验并写入本地气泡后清空草稿，拦截报错时保留用户输入。
    const failure: string = await this.vm.send(this.context(), text, (): void => {
      this.clearDraft();
      this.scrollToBottom();
    });
    if (failure.length > 0) {
      try { this.getUIContext().getPromptAction().showToast({ message: failure }); } catch (_) {}
    }
    this.scrollToBottom();
  }

  private canSend(): boolean {
    return this.draft.trim().length > 0 && !this.vm.sending;
  }

  private syncDraft(): void {
    if (this.syncingDraft) { return; }
    this.syncingDraft = true;
    try {
      this.draft = readEmojiEditor(this.editor, new Map<string, string>(), new Map<string, string>()).text;
    } catch (_) {
      // 编辑器尚未就绪时保留上次镜像，不误清草稿
    } finally {
      this.syncingDraft = false;
    }
  }

  private clearDraft(): void {
    try {
      this.editor.deleteSpans();
      this.applyTypingStyle();
    } catch (_) { /* 编辑器未挂载 */ }
    this.draft = '';
  }

  private focusInput(): void {
    try {
      const focusController = this.getUIContext().getFocusController();
      focusController.activate(true, false);
      focusController.requestFocus('chat-input');
    } catch (_) {}
  }

  private toggleEmoji(): void {
    if (this.showEmoji) {
      this.awaitEmojiKeyboard();
      this.focusInput();
      return;
    }
    this.clearKeyboardWait();
    this.animateEmojiLayout((): void => {
      this.emojiAwaitKeyboard = false;
      this.showEmoji = true;
    });
    this.editor.stopEditing();
    this.getUIContext().getFocusController().clearFocus();
    this.openEmojiPanelDialog();
    this.scrollToBottom();
    setTimeout((): void => { this.scrollToBottom(); }, 120);
  }

  private insertEmoji(code: number): void {
    const url: string = emojiImageUrl(`image_emoticon${code}`);
    if (emojiTokenFromUrl(url).length === 0) { return; }
    try {
      const caret: number = this.editor.getCaretOffset();
      const options: RichEditorImageSpanOptions = {
        imageStyle: { size: [20, 20], verticalAlign: ImageSpanAlignment.CENTER }
      };
      if (caret >= 0) { options.offset = caret; }
      this.editor.addImageSpan(emojiSrc(url), options);
    } catch (_) {
      return;
    }
    this.syncDraft();
  }

  private deleteBackward(): void {
    try {
      const spans: Array<RichEditorImageSpanResult | RichEditorTextSpanResult> = this.editor.getSpans();
      if (spans.length === 0) { return; }
      const caret: number = this.editor.getCaretOffset();
      const last: RichEditorImageSpanResult | RichEditorTextSpanResult = spans[spans.length - 1];
      const fallbackEnd: number = last.spanPosition.spanRange[1];
      const end: number = caret > 0 ? caret : fallbackEnd;
      if (end <= 0) { return; }
      this.editor.deleteSpans({ start: end - 1, end: end });
      this.syncDraft();
    } catch (_) { /* 编辑器未就绪 */ }
  }

  private async retry(message: ChatMessage): Promise<void> {
    const failure: string = await this.vm.retry(this.context(), message);
    if (failure.length > 0) {
      try { this.getUIContext().getPromptAction().showToast({ message: failure }); } catch (_) {}
    }
    this.scrollToBottom();
  }

  private conversationBroken(): boolean {
    return !this.vm.exists && this.vm.error.length > 0;
  }

  private bottomLift(): number {
    if (this.showEmoji || this.emojiAwaitKeyboard) { return this.emojiPanelVp(); }
    return this.keyboardVp;
  }

  private barBottomMargin(): number {
    const lift: number = this.bottomLift();
    return COMPOSER_GAP + (lift > 0 ? lift : this.bottomInset);
  }

  private listTailSpace(): number {
    return this.composerHeight + this.barBottomMargin() + 8;
  }

  private emojiPanelVp(): number {
    return emojiPanelHeight(this.lastKeyboardVp);
  }

  private emojiGridHeight(): number {
    return emojiPanelGridHeight(this.emojiPanelVp());
  }

  private emojiGridRowGap(gridHeight: number): number {
    return Math.max(0, Math.min(EMOJI_ROW_GAP, (gridHeight - EMOJI_ICON * EMOJI_VISIBLE_ROWS) / (EMOJI_VISIBLE_ROWS - 1)));
  }

  private emojiGridRowHeight(gridHeight: number): number {
    const gap: number = this.emojiGridRowGap(gridHeight);
    return Math.max(EMOJI_ICON, (gridHeight - gap * (EMOJI_VISIBLE_ROWS - 1)) / EMOJI_VISIBLE_ROWS);
  }

  private handleListTouch(event: TouchEvent): void {
    if (!event.touches || event.touches.length === 0) { return; }
    if (event.type === TouchType.Down) {
      this.listTouching = true;
      this.listTouchY = event.touches[0].y;
    } else if (event.type === TouchType.Move && this.listTouching) {
      if (Math.abs(event.touches[0].y - this.listTouchY) >= LIST_DISMISS_DRAG_VP) {
        this.listTouching = false;
        this.dismissInput();
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.listTouching = false;
    }
  }

  @Builder
  ChatNavBar() {
    Row({ space: 4 }) {
      GlassBackButton({ onTap: (): void => { NavigationService.back(); } })

      Text(this.vm.title.length > 0 ? this.vm.title : '私信')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_MAIN)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .height(40)
        .padding({ left: 4, right: 6 })
    }
    .width('100%')
    .height(NAV_BAR_HEIGHT)
    .margin({ top: this.statusBarH })
    .padding({ left: 8, right: 12 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  MessageList() {
    List({ space: 0, scroller: this.scroller }) {
      ListItem() {
        Column() {
          Row().width('100%').height(this.statusBarH + NAV_BAR_HEIGHT).hitTestBehavior(HitTestMode.None)
          if (this.vm.hasOlderHistory && this.vm.messages.length > 0) {
            Row() {
              Text('查看更早消息')
                .fontSize(13)
                .fontColor(AppTheme.ACCENT)
                .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                .borderRadius(14)
                .backgroundColor(AppTheme.SURFACE_MUTED)
                .onClick((): void => { this.loadOlderMessages(); })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 10, bottom: 6 })
          }
        }
        .width('100%')
      }
      if (this.vm.loading && this.vm.messages.length === 0) {
        ListItem() { PageState({ loading: true, message: '正在读取聊天记录…' }).height(240) }
      } else if (this.vm.error.length > 0 && this.vm.messages.length === 0) {
        ListItem() {
          PageState({ title: '打不开这个会话', message: this.vm.error, actionLabel: '重试',
            onAction: (): void => { void this.open(); } }).height(260)
        }
      } else if (this.vm.messages.length === 0) {
        ListItem() { PageState({ message: '还没有聊天记录，打个招呼吧' }).height(240) }
      } else {
        if (this.vm.error.length > 0) {
          ListItem() {
            PageState({ compact: true, message: this.vm.error, actionLabel: '重试',
              onAction: (): void => { void this.open(); } })
          }
        }
        LazyForEach(this.msgSource, (item: ChatMessage, index: number) => {
          ListItem() {
            ChatBubble({
              message: item,
              showTime: this.showTime(index),
              selfPortrait: this.selfPortrait(),
              onRetry: (message: ChatMessage): void => { void this.retry(message); },
              onOpenImage: (url: string): void => { this.openChatImage(url); }
            });
          }
        }, (item: ChatMessage) => `${item.key()}-${item.sendState}`)
        // 末尾避让放在列表内容里而不是 padding：padding 会在底部留出不画内容的死带，破坏悬浮材质透视。
        ListItem() {
          Row().width('100%').height(this.listTailSpace())
        }
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .constraintSize({ maxWidth: windowBreakpoint.readingMaxWidth() })
    .alignSelf(ItemAlign.Center)
    .height('100%')
    .cachedCount(6)
    .maintainVisibleContentPosition(true)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off)
    .onClick((): void => { this.dismissInput(); })
    .onTouch((event: TouchEvent): void => { this.handleListTouch(event); })
    .onAreaChange((_old: Area, area: Area): void => {
      this.repinAfterResize(Number(area.height));
    })
  }

  /**
   * 悬浮单胶囊输入栏：底层官方材质与前景编辑层分离，避免 TabBar 截获选词/拖光标手势；
   * 外层不裁切，保留官方材质外部阴影。
   */
  @Builder
  ComposerBar() {
    Row() {
      Stack({ alignContent: Alignment.Bottom }) {
        this.ComposerMaterialShell()
        this.ComposerContent()
      }
      .width('100%')
      .borderRadius(COMPOSER_RADIUS)
      .clip(false)
      .onAreaChange((_old: Area, area: Area): void => {
        const width: number = Number(area.width);
        if (width > 0 && Math.abs(width - this.barWidth) >= 0.5) { this.barWidth = width; }
      })
    }
    .width('100%')
    .constraintSize({ maxWidth: windowBreakpoint.readingMaxWidth() })
    .padding({ left: BAR_SIDE_MARGIN, right: BAR_SIDE_MARGIN, bottom: this.barBottomMargin() })
  }

  @Builder
  ComposerMaterialShell() {
    if (materialManager.useArkUI) {
      MaterialTabs({
        slot: MaterialSlot.BOTTOM_BAR,
        barHeight: this.composerHeight,
        componentMaterial: true,
        barContent: (): void => { this.ArkUIComposerShell(); }
      })
        .width('100%')
        .height(this.composerHeight)
        .clip(false)
        .hitTestBehavior(HitTestMode.None)
    } else if (this.barWidth > 0) {
      MaterialTabs({
        slot: MaterialSlot.BOTTOM_BAR,
        barHeight: this.composerHeight,
        barWidth: this.barWidth
      })
        .width('100%')
        .height(this.composerHeight)
        .borderRadius(COMPOSER_RADIUS)
        .clip(false)
        .hitTestBehavior(HitTestMode.None)
    }
  }

  @Builder
  ArkUIComposerShell() {
    // 固定 24vp 圆角保证多行增高时不把左右首尾字符挤成椭圆；forceStatic 关闭纯背景壳按压形变。
    Row()
      .width('100%')
      .height(this.composerHeight)
      .borderRadius(COMPOSER_RADIUS)
      .systemMaterial(materialManager.officialOf(MaterialSlot.BOTTOM_BAR, true, true))
  }

  @Builder
  ComposerContent() {
    Row({ space: 4 }) {
      this.DraftInput()
      this.ImagePickAction()
      this.EmojiToggleAction()
      this.SendAction()
    }
    .width('100%')
    .constraintSize({ minHeight: COMPOSER_MIN_HEIGHT })
    .padding({ left: 6, right: 6, top: 4, bottom: 4 })
    .alignItems(VerticalAlign.Bottom)
    .onAreaChange((_old: Area, area: Area): void => {
      const measured: number = Math.max(COMPOSER_MIN_HEIGHT, Math.min(COMPOSER_MAX_HEIGHT, Number(area.height)));
      if (Math.abs(measured - this.composerHeight) >= 0.5) {
        this.composerHeight = measured;
        this.scrollToBottom();
      }
    })
  }

  @Builder
  ImagePickAction() {
    Row() {
      if (this.imageUpload.busy || this.imageUpload.selecting) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(AppTheme.ACCENT)
      } else {
        SymbolGlyph($r('sys.symbol.picture'))
          .fontSize(21)
          .maxFontScale(1)
          .fontColor([AppTheme.TEXT_MAIN])
      }
    }
    .width(ACTION_BUTTON_SIZE)
    .height(ACTION_BUTTON_SIZE)
    .margin({ bottom: 2 })
    .justifyContent(FlexAlign.Center)
    .borderRadius(ACTION_BUTTON_SIZE / 2)
    .id('chat-image-button')
    .accessibilityText('发送图片')
    .onClick((): void => { void this.pickAndSendImage(); })
  }

  @Builder
  EmojiToggleAction() {
    Row() {
      SymbolGlyph(this.showEmoji ? $r('sys.symbol.keyboard') : $r('sys.symbol.face_smiling'))
        .fontSize(22)
        .maxFontScale(1)
        .fontColor([AppTheme.TEXT_MAIN])
    }
    .width(ACTION_BUTTON_SIZE)
    .height(ACTION_BUTTON_SIZE)
    .margin({ bottom: 2 })
    .justifyContent(FlexAlign.Center)
    .borderRadius(ACTION_BUTTON_SIZE / 2)
    .id('chat-emoji-button')
    .accessibilityText(this.showEmoji ? '切换到键盘' : '表情')
    .onClick((): void => { this.toggleEmoji(); })
  }

  @Builder
  SendAction() {
    Row() {
      if (this.vm.sending) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color(AppTheme.ON_ACCENT)
      } else {
        SymbolGlyph($r('sys.symbol.paperplane'))
          .fontSize(18)
          .maxFontScale(1)
          .fontColor([this.canSend() ? AppTheme.ON_ACCENT : AppTheme.TEXT_MUTED])
      }
    }
    .width(ACTION_BUTTON_SIZE)
    .height(ACTION_BUTTON_SIZE)
    .margin({ bottom: 2 })
    .justifyContent(FlexAlign.Center)
    .borderRadius(ACTION_BUTTON_SIZE / 2)
    .backgroundColor(this.vm.sending ? AppTheme.BUSY_ACCENT :
      (this.canSend() ? AppTheme.ACCENT : AppTheme.SURFACE_MUTED))
    .id('chat-send-button')
    .accessibilityText(this.vm.sending ? '正在发送' : '发送')
    .onClick((): void => { void this.send(); })
  }

  @Builder
  DraftInput() {
    // RichEditor 内容默认顶对齐：由外层 Row(minHeight=40) 负责单行垂直居中，避免纯文字偏上。
    Row() {
      // 发送在途不设 enabled(false)，避免连续聊天时把软键盘踢掉；节流由 send() 与发送按钮态负责。
      RichEditor({ controller: this.editor })
        .id('chat-input')
        .width('100%')
        .backgroundColor(Color.Transparent)
        .padding({ left: 10, right: 4, top: 8, bottom: 8 })
        .constraintSize({ maxHeight: COMPOSER_MAX_HEIGHT - 8 })
        .enterKeyType(EnterKeyType.NEW_LINE)
        .caretColor(AppTheme.ACCENT)
        .selectedBackgroundColor(AppTheme.SELECTION_BACKGROUND)
        .placeholder('发消息…', { font: { size: 15 }, fontColor: AppTheme.TEXT_SUB })
        .focusBox({ strokeWidth: LengthMetrics.vp(0) })
        .onReady((): void => {
          this.editorReady = true;
          this.applyTypingStyle();
        })
        .onDisAppear((): void => { this.editorReady = false; })
        .onIMEInputComplete((): void => { this.syncDraft(); })
        .onDeleteComplete((): void => { this.syncDraft(); })
        // 粘贴回调先于 spans 落地触发，延后同步镜像。
        .onPaste((): void => { setTimeout((): void => { this.syncDraft(); }, 100); })
        .onFocus((): void => {
          this.editorFocused = true;
          if (this.showEmoji) { this.awaitEmojiKeyboard(); }
          this.scrollToBottom();
          setTimeout((): void => { this.scrollToBottom(); }, 280);
        })
        .onBlur((): void => {
          this.editorFocused = false;
        })
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: COMPOSER_MIN_HEIGHT - 8 })
    .alignItems(VerticalAlign.Center)
    .onClick((): void => { this.focusInput(); })
  }

  /** 原生材质弹窗内的内置表情面板：材质、圆角与升降由 `emojiPanelDialogOptions` 统一提供。 */
  @Builder
  ChatEmojiSheet() {
    Column() {
      Row({ space: 14 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.face_smiling'))
            .fontSize(20)
            .fontColor([AppTheme.ACCENT])
        }
        .width(EMOJI_TAB_SIZE)
        .height(EMOJI_TAB_SIZE)
        .borderRadius(EMOJI_TAB_SIZE / 2)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(AppTheme.CARD)
        .id('chat-emoji-tab-builtin')
        .accessibilityText('贴吧表情')
        .accessibilitySelected(true)

        Blank()

        Row() {
          SymbolGlyph($r('sys.symbol.delete_left'))
            .fontSize(20)
            .fontColor([DetailTheme.EMOJI_PANEL_TEXT])
        }
        .width(EMOJI_TAB_SIZE)
        .height(EMOJI_TAB_SIZE)
        .borderRadius(EMOJI_TAB_SIZE / 2)
        .justifyContent(FlexAlign.Center)
        .id('chat-emoji-delete')
        .accessibilityText('删除表情或文字')
        .onClick((): void => { this.deleteBackward(); })
      }
      .width('100%')
      .height(EMOJI_TAB_BAR_H)

      Grid() {
        ForEach(REPLY_EMOTICON_CODES, (code: number) => {
          GridItem() {
            Image(emojiSrc(emojiImageUrl(`image_emoticon${code}`)))
              .width(EMOJI_ICON)
              .height(EMOJI_ICON)
              .objectFit(ImageFit.Contain)
              .interpolation(ImageInterpolation.High)
          }
          .height(this.emojiGridRowHeight(this.emojiGridHeight()))
          .id(`chat-emoji-${code}`)
          .accessibilityText(emojiTokenFromUrl(emojiImageUrl(`image_emoticon${code}`)))
          .onClick((): void => { this.insertEmoji(code); })
        }, (code: number) => `chat_emoticon_${code}`)
      }
      .columnsTemplate(EMOJI_COLUMNS)
      .rowsGap(this.emojiGridRowGap(this.emojiGridHeight()))
      .height(this.emojiGridHeight())
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: EMOJI_PANEL_TOP_PADDING,
      bottom: EMOJI_PANEL_BOTTOM_PADDING + this.bottomInset
    })
    .id('chat-emoji-panel')
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        this.MessageList()

        if (!this.conversationBroken()) {
          this.ComposerBar()
        }

        if (this.viewerOpen && this.viewerUrls.length > 0) {
          ImageViewer({
            imageUrls: this.viewerUrls,
            initialIndex: this.viewerIndex,
            onClose: (): void => { this.viewerOpen = false; }
          })
            .zIndex(100)
        }
      }
      .width('100%')
      .height('100%')
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .clip(false)
      .backgroundColor(AppTheme.BG)
      .onAreaChange((_old: Area, area: Area): void => {
        const width: number = Number(area.width);
        if (width > 0 && Math.abs(width - this.screenW) >= 0.5) { this.screenW = width; }
      })
    }
    .titleBar({
      style: {
        scrollEffectOpts: {
          enableScrollEffect: motionStore.isOn(MotionEffect.HDS_SCROLL_BLUR),
          scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
        },
        scrollEffectStyle: {
          backgroundStyle: {
            maskExtraHeight: motionStore.isOn(MotionEffect.HDS_SCROLL_BLUR) ? 32 : 0,
            blurRadius: motionStore.isOn(MotionEffect.HDS_SCROLL_BLUR) ? 80 : 0
          }
        }
      },
      content: { stackBuilder: (): void => { this.ChatNavBar(); } }
    })
    .hideBackButton(true)
    .hideTitleBar(this.viewerOpen)
    .systemBarStyle(
      { statusBarContentColor: this.viewerOpen || themeModeStore.isDark ? '#F2F3F4' : '#1B1B1B' },
      { statusBarContentColor: this.viewerOpen || themeModeStore.isDark ? '#F2F3F4' : '#1B1B1B' }
    )
    .bindToScrollable([this.scroller])
    .onShown((): void => {
      this.useEditorKeyboardMode();
      this.trackKeyboard();
    })
    .onHidden((): void => {
      this.stopKeyboardTracking();
      this.restoreKeyboardMode();
    })
    .onBackPressed((): boolean => {
      if (this.viewerOpen) {
        this.viewerOpen = false;
        return true;
      }
      if (this.showEmoji || this.emojiAwaitKeyboard) {
        this.collapseEmoji();
        return true;
      }
      return false;
    })
  }
}
