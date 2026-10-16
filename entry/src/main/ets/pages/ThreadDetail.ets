import { ForumLevelBadge } from '../components/ForumLevelBadge';
import { forumLevelStore } from '../common/appearance/ForumLevelStore';
import { PullRefreshHeader, PULL_REFRESH_OFFSET } from '../components/RefreshSpinner';
import { FollowButton } from '../components/FollowButton';
import { commentText, postCommentTarget } from '../model/CommentAction';

import { openUserByIdentity } from '../navigation/UserNavigation';
import { common } from '@kit.AbilityKit';
import { VoicePlayer } from '../components/VoicePlayer';
import { VideoPlayer } from '../components/VideoPlayer';
import { videoPlayback } from '../viewmodel/VideoPlaybackVM';
import { voicePlayback } from '../viewmodel/VoicePlaybackVM';
import { shareWebPage } from '../utils/SystemShare';
import { PostContentInline } from '../components/PostContentInline';
import { openContentPiece } from '../navigation/ContentNavigation';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { LengthMetrics, promptAction, uiMaterial, window } from '@kit.ArkUI';

import { HdsNavDestination, HdsTabs, ScrollEffectType } from '@kit.UIDesignKit';
import {
  ContentBlock, ContentKind, ContentPiece, PostItem, ReplySortType, SubPostItem, UserBrief,
  REPLY_EMOTICON_CODES, collectPreviewImageUrls, emojiCodeFromReplyToken, emojiImageUrl,
  formatThreadHeadTime, forumChipText, groupContentBlocks,
  isReplySortSupported, resolveForumName, subPostsHaveThreadAuthor, unsupportedSortTip
} from '../model/ThreadDetail';
import { emojiSrc } from '../common/emoji/EmojiSrc';
import { POST_BODY_SIZE, POST_NICKNAME_SIZE, POST_TITLE_SIZE,
  COMMENT_BODY_SIZE, SUB_REPLY_BODY_SIZE, SUB_REPLY_LINE_HEIGHT } from '../common/appearance/PostTypography';
import { MemePicItem } from '../model/MemeEmoji';
import { AgreeState, ThreadDetailVM } from '../viewmodel/ThreadDetailVM';
import { MyListVM } from '../viewmodel/MyListVM';
import { ReplyImagesVM } from '../viewmodel/ReplyImagesVM';
import { UploadedPostImage } from '../model/ImageUpload';
import { ReplyEditorContent, ReplyEditorSpan, serializeReplyEditor } from '../model/ReplyEditor';
import { ERRNO_THREAD_DELETED } from '../api/TiebaApi';
import { AgreeObjType } from '../net/TiebaParams';
import { ImageViewer } from '../components/ImageViewer';
import { GlassBackButton } from '../components/GlassBackButton';
import { GlassMoreButton } from '../components/GlassMoreButton';
import { PostImageGallery } from '../components/PostImageGallery';
import { ReplyItem } from '../components/ReplyItem';
import { AvatarComponent } from '../components/AvatarComponent';
import { ForumAvatarImage, forumAvatarRadius } from '../components/ForumAvatarImage';
import { ThreadAuthorBadge } from '../components/ThreadAuthorBadge';
import { SubReplyDetailSheet } from '../components/SubReplyDetailSheet';
import { DetailTheme as AppTheme } from '../theme/Theme';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { materialManager } from '../common/material/MaterialManager';
import { CapsuleEdge, MaterialSlot, SPLIT_PILL_GRADIENT_MASK } from '../common/material/MaterialConfig';

import { ThreadActionBarStyle } from '../common/appearance/ThreadActionBarStyle';
import { threadActionBarStore } from '../common/appearance/ThreadActionBarStore';
import { NavigationService, ThreadDetailParams } from '../navigation/AppNavigation';

const BODY_EMOJI_SIZE: number = 21;

function capsuleEdgeWidth(): number | EdgeWidths {
  const edge: CapsuleEdge | undefined =
    materialManager.capsuleEdgeOf(MaterialSlot.BOTTOM_FLOATING_BAR);
  return edge === undefined ? 0 : { top: 0, right: 0, bottom: edge.width, left: 0 };
}

const NO_EDGE_COLOR: string = 'rgba(0, 0, 0, 0)';

function capsuleEdgeColor(): ResourceColor | EdgeColors {
  const edge: CapsuleEdge | undefined =
    materialManager.capsuleEdgeOf(MaterialSlot.BOTTOM_FLOATING_BAR);
  return edge === undefined ? NO_EDGE_COLOR
    : { top: NO_EDGE_COLOR, right: NO_EDGE_COLOR, bottom: edge.color, left: NO_EDGE_COLOR };
}

const ACTION_PILL_HEIGHT: number = 52;

const REPLY_PILL_WIDTH: number = 143;

const ACTION_PILL_WIDTH: number = 197;

const ACTION_PILL_GAP: number = 8;

const ACTION_PILL_RADIUS: number = 26;

const REPLY_PILL_PADDING: number = 17;

const ACTION_QUAD_PADDING: number = 8;

const BOTTOM_BAR_SIDE_MARGIN: number = 14;
const BOTTOM_BAR_BOTTOM_MARGIN: number = 24;

const REPLY_SHEET_SIDE_MARGIN: number = 12;

const REPLY_SHEET_BOTTOM_GAP: number = 8;

const REPLY_SHEET_RADIUS: number = 16;

const REPLY_INPUT_MIN_H: number = 60;

const REPLY_TOOL_GAP: number = 20;

const REPLY_PUBLISH_W: number = 92;
const REPLY_PUBLISH_H: number = 32;

const REPLY_EMOJI_PANEL_FALLBACK_GRID_H: number = 248;

const REPLY_EMOJI_COLUMNS: string = '1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr';

const REPLY_EMOJI_SIZE: number = 24;
const REPLY_EMOJI_ROW_GAP: number = 14;

const REPLY_EMOJI_TAB_SIZE: number = 36;

const REPLY_EMOJI_INLINE: number = 22;

const REPLY_EMOTICON_QUICK_CODES: number[] = REPLY_EMOTICON_CODES.slice(0, 7);

const REPLY_QUICK_EMOJI_SIZE: number = 28;

const EMOJI_PANEL_TOP_PADDING: number = 8;
const EMOJI_PANEL_BOTTOM_PADDING: number = 12;
const EMOJI_PANEL_TAB_H: number = 40;

const REPLY_INPUT_PANEL_GAP: number = 16;

const EMOJI_PANEL_VISIBLE_EXTRA_H: number = 6;

const REPLY_PANEL_TRANSITION_MS: number = 220;

const EMOJI_PANEL_BOTTOM_INSET_COMP: number = 50;

function richEditorReplyText(controller: RichEditorController,
  memeTokens: Map<string, string>, imageTokens: Map<string, string>): ReplyEditorContent {
  const adapted: ReplyEditorSpan[] = [];
  const spans: Array<RichEditorImageSpanResult | RichEditorTextSpanResult> = controller.getSpans();
  for (const span of spans) {
    const item: ReplyEditorSpan = new ReplyEditorSpan();
    item.text = (span as RichEditorTextSpanResult).value ?? '';
    item.imageSource = String((span as RichEditorImageSpanResult).valueResourceStr ?? '');
    item.editorLength = span.spanPosition.spanRange[1] - span.spanPosition.spanRange[0];
    adapted.push(item);
  }
  return serializeReplyEditor(adapted, memeTokens, imageTokens);
}
function replyImageSize(image: UploadedPostImage): [number, number] {
  const scale: number = Math.min(160 / image.width, 112 / image.height);
  return [Math.max(1, Math.floor(image.width * scale)), Math.max(1, Math.floor(image.height * scale))];
}

const REPLY_MAX_LENGTH: number = 500;

function popupSystemMaterial(): uiMaterial.Material {
  return new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THICK });
}

@ComponentV2
export struct ThreadDetailPage {
  @Local pullRefreshDragging: boolean = false;

  @Param routeParams: ThreadDetailParams | undefined = undefined;

  @Local vm: ThreadDetailVM = new ThreadDetailVM();

  @Local sourceReplyCount: number = -1;

  @Local viewerUrl: string = '';

  @Local viewerUrls: string[] = [];
  @Local viewerIndex: number = 0;

  @Local refreshing: boolean = false;

  @Local subDetailPid: number = 0;

  @Local showSubSheet: boolean = false;
  private pendingUser: UserBrief | undefined = undefined;

  @Local popupMenuShow: boolean = false;

  @Local safeBottomVp: number = 0;

  @Local keyboardVp: number = 0;

  @Local lastKeyboardVp: number = 0;

  private avoidWin: window.Window | null = null;
  private keyboardAreaCb: ((data: window.AvoidAreaOptions) => void) | null = null;

  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;

  @Local titleBarH: number = STATUS_BAR_FALLBACK_VP + 52;

  @Local showJump: boolean = false;

  @Local jumpText: string = '';

  @Local showReply: boolean = false;

  @Local screenWvp: number = 0;

  private replyDialogId: number = 0;

  private replyCardPinned: boolean = false;

  private replyCardSwitching: boolean = false;

  private replyAwaitKeyboard: boolean = false;

  private dismissVetoUntilMs: number = 0;

  private replyDialogSeq: number = 0;

  private emojiDialogId: number = 0;

  private emojiDialogSeq: number = 0;

  @Local replyText: string = '';
  @Local replyImages: ReplyImagesVM = new ReplyImagesVM();
  private replyEditEpoch: number = 0;
  private rebuildingReply: boolean = false;
  private videoFullscreen: boolean = false;

  @Local replyTargetPid: number = 0;

  @Local replyTargetName: string = '';

  @Local showEmojiPanel: boolean = false;

  @Local emojiTab: number = 0;

  richCtl: RichEditorController = new RichEditorController();

  @Local showMore: boolean = false;

  @Local navScrollOffset: number = 0;

  private scroller: ListScroller = new ListScroller();

  private goBack(): void {
    NavigationService.back();
  }

  private handleSystemBack(): boolean {
    if (this.viewerUrl.length > 0 || this.viewerUrls.length > 0) {
      this.viewerUrl = '';
      this.viewerUrls = [];
      this.viewerIndex = 0;
      return true;
    }
    return false;
  }

  aboutToAppear(): void {

    let tid: number = 0;
    if (this.routeParams !== undefined) {
      if (this.routeParams.tid > 0) {
        tid = this.routeParams.tid;
      }
      if (this.routeParams.replyCount !== undefined && this.routeParams.replyCount >= 0) {
        this.sourceReplyCount = this.routeParams.replyCount;
      }

      this.vm.setForumNameHint(this.routeParams.forumName);
    }
    if (tid === 0) {
      hilog.error(0x0, 'ThreadDetail', 'no valid tid in routeParams');
    }
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;

    const tidForHistory: number = this.vm.tid > 0 ? this.vm.tid : tid;
    const targetPid: number = this.routeParams?.targetPid ?? 0;
    this.vm.load(context, tid, targetPid).then(() => {
      if (targetPid > 0 && this.vm.errorText.length === 0) {
        const index: number = this.vm.visiblePosts.findIndex((post: PostItem) => post.pid === targetPid);
        if (index >= 0) {
          this.getUIContext().runScopedTask(() => {
            setTimeout(() => {
              if (index === 0) {
                this.scroller.scrollToIndex(0, true, ScrollAlign.START);
              } else {
                this.scroller.scrollToItemInGroup(2, index - 1, true, ScrollAlign.START);
              }
            }, 200);
          });
        } else {
          this.getUIContext().getPromptAction().showToast({
            message: '已打开原帖，暂未定位到这条回复', duration: 2000
          });
        }
      }

      if (this.vm.lastErrorCode === ERRNO_THREAD_DELETED) {
        MyListVM.markDeleted(context, tidForHistory);
        return;
      }

      let cover: string = '';
      for (const post of this.vm.posts) {
        if (post.floor === 1) {
          const urls: string[] = collectPreviewImageUrls(post.contents);
          if (urls.length > 0) {
            cover = urls[0];
          }
          break;
        }
      }
      const forumName: string = this.vm.detail.forumName;
      MyListVM.record(context, tidForHistory,
        this.vm.detail.title, forumName,
        cover, this.vm.detail.forumAvatar,

        this.vm.detail.title.length === 0 && forumName.length === 0);
    }).catch(() => {

    });

    this.readSafeArea();
    this.readStatusBar();
  }

  aboutToDisappear(): void {
    this.videoFullscreen = false;

    this.closeReplyBox();
    this.replyImages.dispose();

    if (this.avoidWin !== null && this.keyboardAreaCb !== null) {
      try {
        this.avoidWin.off('avoidAreaChange', this.keyboardAreaCb);
      } catch (err) {

      }
      this.avoidWin = null;
      this.keyboardAreaCb = null;
    }
  }

  private readStatusBar(): void {
    readStatusBarVp(this.hostContext()).then((vp: number) => {
      this.statusBarH = vp;

      this.titleBarH = vp + 52;
    }).catch(() => {

    });
  }

  private readSafeArea(): void {
    try {
      window.getLastWindow(this.hostContext()).then((win: window.Window) => {
        const area: window.AvoidArea =
          win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        this.safeBottomVp = px2vp(area.bottomRect.height);

        this.screenWvp = px2vp(win.getWindowProperties().windowRect.width);

        this.keyboardAreaCb = (data: window.AvoidAreaOptions) => {
          if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
            this.keyboardVp = px2vp(data.area.bottomRect.height);
            if (this.keyboardVp > 0) {
              this.lastKeyboardVp = this.keyboardVp;
              this.replyAwaitKeyboard = false;
            }

            if (this.keyboardVp > 0 && this.showEmojiPanel) {
              this.setEmojiPanel(false, true);
            } else if (this.keyboardVp === 0 && !this.showEmojiPanel && this.replyCardPinned
              && !this.replyAwaitKeyboard && this.showReply) {
              this.switchReplyCard(false);
            }
          }
        };
        win.on('avoidAreaChange', this.keyboardAreaCb);
        this.avoidWin = win;
      }).catch(() => {

      });
    } catch (err) {

    }
  }

  private emojiPanelHeight(): number {
    return this.lastKeyboardVp > 0 ? this.lastKeyboardVp
      : REPLY_EMOJI_PANEL_FALLBACK_GRID_H + EMOJI_PANEL_TOP_PADDING + EMOJI_PANEL_TAB_H
        + EMOJI_PANEL_BOTTOM_PADDING + EMOJI_PANEL_VISIBLE_EXTRA_H;
  }

  private emojiGridHeight(): number {
    return Math.max(160, this.emojiPanelHeight() - EMOJI_PANEL_TOP_PADDING - EMOJI_PANEL_TAB_H
      - EMOJI_PANEL_BOTTOM_PADDING - EMOJI_PANEL_VISIBLE_EXTRA_H);
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private displayedReplyCount(): number {
    return this.sourceReplyCount >= 0 ? this.sourceReplyCount : this.vm.detail.replyCount;
  }

  private async handleRefresh(): Promise<void> {
    if (this.refreshing) {
      return;
    }
    this.refreshing = true;
    try {
      await this.vm.refresh(this.hostContext());
    } finally {
      this.refreshing = false;
    }
  }

  private previewSubPosts(item: PostItem): SubPostItem[] {
    const source: SubPostItem[] = this.vm.subState(item.pid).subPosts;
    return source.length > 3 ? source.slice(0, 3) : source;
  }

  private hasAuthorReply(item: PostItem): boolean {
    return subPostsHaveThreadAuthor(this.vm.subState(item.pid).subPosts);
  }

  private openSubDetailByPid(pid: number): void {
    if (pid <= 0) {
      return;
    }
    const anchor: PostItem = this.anchorPost(pid);
    if (anchor.pid <= 0) {
      this.toastNotAvailable('回复');
      return;
    }
    const authorId: number = this.vm.detail.author.id;
    this.subDetailPid = pid;
    this.showSubSheet = true;
    const state = this.vm.subState(pid);
    if (!state.loadedOnce && !state.loading) {
      if (state.errorText.length > 0) {
        this.vm.retrySubPosts(this.hostContext(), pid, authorId);
      } else {
        this.vm.ensureSubPostPreview(this.hostContext(), pid, authorId);
      }
    }
  }

  private closeSubSheet(): void {
    this.showSubSheet = false;
  }

  private anchorPost(pid: number): PostItem {
    const posts: PostItem[] = this.vm.visiblePosts;
    for (let i = 0; i < posts.length; i++) {
      if (posts[i].pid === pid) {
        return posts[i];
      }
    }
    return new PostItem();
  }

  private retrySubSheet(pid: number): void {
    const authorId: number = this.vm.detail.author.id;
    if (this.vm.subState(pid).loadedOnce) {
      this.vm.loadMoreSubPosts(this.hostContext(), pid, authorId);
    } else {
      this.vm.retrySubPosts(this.hostContext(), pid, authorId);
    }
  }

  private toggleLike(item: PostItem, objType: AgreeObjType = AgreeObjType.POST): void {
    this.vm.toggleAgree(this.hostContext(), item, objType).then((reason: string) => {
      if (reason.length > 0) {
        promptAction.showToast({ message: reason, duration: 1800 });
      }
    });
  }

  private toggleMainLike(): void {
    const main: PostItem | undefined = this.vm.mainPost();
    if (main === undefined) {
      return;
    }
    this.toggleLike(main, AgreeObjType.THREAD);
  }

  private openPreviewImage(url: string): void {
    if (url.length === 0) {
      return;
    }
    this.viewerUrls = [url];
    this.viewerIndex = 0;
    this.viewerUrl = url;
  }

  private openReplyBox(pid: number): void {
    if (this.vm.replyPending) { return; }
    this.replyEditEpoch++;
    this.replyImages.reset();
    this.replyTargetPid = pid > 0 ? pid : 0;
    this.replyTargetName = pid > 0 ? this.authorNameOf(pid) : '';

    this.richCtl.deleteSpans();
    this.replyText = '';

    this.showEmojiPanel = false;
    this.replyCardPinned = false;
    this.replyCardSwitching = false;
    this.replyAwaitKeyboard = false;
    this.closeEmojiPanelDialog();
    this.showReply = true;
    this.openReplyDialog(false);
  }

  private openReplyDialog(lifted: boolean, replacing: boolean = false): void {
    if (this.replyDialogId !== 0 && !replacing) {
      return;
    }
    if (this.replyCardSwitching) {
      return;
    }
    const oldId: number = replacing ? this.replyDialogId : 0;
    this.replyCardSwitching = replacing;
    let oldClosed: boolean = false;

    const seq: number = ++this.replyDialogSeq;
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: (): void => {
        this.ReplyDialog()
      },

      alignment: DialogAlignment.Bottom,
      offset: {
        dx: 0,

        dy: lifted
          ? -(this.emojiPanelHeight() + REPLY_INPUT_PANEL_GAP - this.safeBottomVp)
          : -(REPLY_SHEET_BOTTOM_GAP + this.safeBottomVp)
      },

      keyboardAvoidMode: lifted ? KeyboardAvoidMode.NONE : KeyboardAvoidMode.DEFAULT,

      dialogTransition: replacing ? (lifted ? TransitionEffect.IDENTITY
        : TransitionEffect.translate({ y: -this.emojiPanelHeight() })
          .animation({ duration: REPLY_PANEL_TRANSITION_MS })) : undefined,
      maskTransition: replacing ? TransitionEffect.IDENTITY : undefined,
      autoCancel: true,

      width: this.screenWvp > 0 ? this.screenWvp - REPLY_SHEET_SIDE_MARGIN * 2 : 336,
      cornerRadius: REPLY_SHEET_RADIUS,

      systemMaterial: materialManager.officialOf(MaterialSlot.REPLY_SHEET),
      backgroundEffect: materialManager.glassOf(MaterialSlot.REPLY_SHEET),
      onWillAppear: (): void => {
        if (oldId !== 0 && !oldClosed && this.replyDialogSeq === seq) {
          oldClosed = true;
          try {
            this.getUIContext().getPromptAction().closeCustomDialog(oldId);
          } catch (err) {

          }
        }
      },
      onDidAppear: (): void => {

        if (this.replyDialogSeq !== seq || !this.showReply || replacing || lifted) {
          return;
        }
        try {
          const focusController = this.getUIContext().getFocusController();
          focusController.activate(true, false);
          focusController.requestFocus('tdReplyRich');
        } catch (err) {
          hilog.warn(0x0, 'ReplyFocus', 'initial focus failed code=%{public}s',
            String((err as BusinessError).code ?? '?'));
        }
      },
      onWillDismiss: (action: DismissDialogAction): void => {

        if (Date.now() < this.dismissVetoUntilMs) {
          hilog.info(0x0, 'ReplyFocus', 'onWillDismiss vetoed (reopen echo)');
          return;
        }

        action.dismiss();
        if (this.replyDialogSeq === seq) {
          this.showReply = false;
          this.replyEditEpoch++;
          this.replyImages.cancel();
          this.closeEmojiPanelDialog();
        }
      },
      onDidDisappear: (): void => {

        hilog.info(0x0, 'ReplyFocus', 'card onDidDisappear seqMatch=%{public}s',
          String(this.replyDialogSeq === seq));
        if (this.replyDialogSeq === seq) {
          this.replyDialogId = 0;
          this.replyCardPinned = false;
          this.replyCardSwitching = false;
          this.showReply = false;
          this.replyEditEpoch++;
          this.replyImages.cancel();
          this.closeEmojiPanelDialog();
        }
      }
    }).then((id: number) => {
      hilog.info(0x0, 'ReplyFocus', 'openReplyDialog ok id=%{public}d lifted=%{public}s',
        id, String(lifted));
      if (this.replyDialogSeq !== seq) {
        this.getUIContext().getPromptAction().closeCustomDialog(id);
        return;
      }
      if (oldId !== 0 && !oldClosed) {
        oldClosed = true;
        try {
          this.getUIContext().getPromptAction().closeCustomDialog(oldId);
        } catch (err) {

        }
      }
      this.replyDialogId = id;
      this.replyCardPinned = lifted;
      this.replyCardSwitching = false;
      if (lifted && this.showEmojiPanel) {
        this.openEmojiPanelDialog();
      } else if (lifted !== this.showEmojiPanel && this.keyboardVp === 0) {
        this.switchReplyCard(this.showEmojiPanel);
      }
    }).catch((err: BusinessError) => {

      hilog.error(0x0, 'ReplyFocus', 'openReplyDialog reject code=%{public}d msg=%{public}s',
        err.code ?? -1, String(err.message ?? ''));
      if (this.replyDialogSeq === seq) {
        this.replyCardSwitching = false;
        if (oldId !== 0 && !oldClosed) {
          try {
            this.getUIContext().getPromptAction().closeCustomDialog(oldId);
          } catch (closeErr) {

          }
        }
        this.replyDialogId = 0;
        this.replyCardPinned = false;
        this.showReply = false;
        this.replyEditEpoch++;
        this.replyImages.cancel();
        this.closeEmojiPanelDialog();
      }
    });
  }

  private closeReplyBox(): void {
    this.replyEditEpoch++;
    this.replyImages.cancel();
    if (this.replyDialogId !== 0) {
      try {
        this.getUIContext().getPromptAction().closeCustomDialog(this.replyDialogId);
      } catch (err) {

      }
      this.replyDialogId = 0;
    }

    this.replyDialogSeq++;
    this.showReply = false;
    this.replyCardPinned = false;
    this.replyCardSwitching = false;
    this.replyAwaitKeyboard = false;

    this.closeEmojiPanelDialog();
  }

  private openEmojiPanelDialog(): void {
    if (this.emojiDialogId !== 0) {
      return;
    }
    const seq: number = ++this.emojiDialogSeq;
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: (): void => {
        this.EmojiSheet()
      },

      alignment: DialogAlignment.Bottom,
      offset: { dx: 0, dy: EMOJI_PANEL_BOTTOM_INSET_COMP },
      keyboardAvoidMode: KeyboardAvoidMode.NONE,
      dialogTransition: TransitionEffect.translate({ y: this.emojiPanelHeight() })
        .animation({ duration: REPLY_PANEL_TRANSITION_MS }),
      width: this.screenWvp > 0 ? this.screenWvp : 360,

      cornerRadius: {
        topLeft: REPLY_SHEET_RADIUS,
        topRight: REPLY_SHEET_RADIUS,
        bottomLeft: 0,
        bottomRight: 0
      },

      isModal: false,
      autoCancel: false,

      systemMaterial: materialManager.officialOf(MaterialSlot.REPLY_SHEET),
      backgroundEffect: materialManager.glassOf(MaterialSlot.REPLY_SHEET),
      onWillDismiss: (action: DismissDialogAction): void => {

        hilog.info(0x0, 'ReplyFocus', 'panel onWillDismiss');
        action.dismiss();
        if (this.emojiDialogSeq === seq) {
          this.setEmojiPanel(false);
        }
      },
      onDidDisappear: (): void => {
        if (this.emojiDialogSeq === seq) {
          this.emojiDialogId = 0;
          this.showEmojiPanel = false;
        }
      }
    }).then((id: number) => {
      if (this.emojiDialogSeq === seq) {
        this.emojiDialogId = id;
      }
    }).catch(() => {

      if (this.emojiDialogSeq === seq) {
        this.setEmojiPanel(false);
      }
    });
  }

  private closeEmojiPanelDialog(): void {
    if (this.emojiDialogId === 0) {
      return;
    }
    try {
      this.getUIContext().getPromptAction().closeCustomDialog(this.emojiDialogId);
    } catch (err) {

    }
    this.emojiDialogId = 0;
    this.emojiDialogSeq++;
  }

  setEmojiPanel(open: boolean, refocusAfterCollapse: boolean = false): void {
    if (open === this.showEmojiPanel) {
      return;
    }
    hilog.info(0x0, 'ReplyFocus', 'setEmojiPanel open=%{public}s refocus=%{public}s',
      String(open), String(refocusAfterCollapse));
    this.showEmojiPanel = open;
    if (open) {
      this.replyAwaitKeyboard = false;
      this.richCtl.stopEditing();
      if (this.replyCardPinned) {
        this.openEmojiPanelDialog();
      } else {
        this.switchReplyCard(true);
      }
    } else {
      this.closeEmojiPanelDialog();
      if (refocusAfterCollapse) {

        this.replyAwaitKeyboard = this.keyboardVp === 0;
        setTimeout(() => {
          if (this.replyAwaitKeyboard && this.keyboardVp === 0 && !this.showEmojiPanel) {
            this.replyAwaitKeyboard = false;
            this.switchReplyCard(false);
          }
        }, 1200);
      } else {
        this.replyAwaitKeyboard = false;
        this.switchReplyCard(false);
      }
    }
  }

  private showReplyKeyboard(): void {
    if (!this.showReply || !this.showEmojiPanel) {
      return;
    }
    this.setEmojiPanel(false, true);
    try {
      const focusController = this.getUIContext().getFocusController();
      focusController.activate(true, false);
      focusController.requestFocus('tdReplyRich');
    } catch (err) {
      hilog.warn(0x0, 'ReplyFocus', 'keyboard button focus failed code=%{public}s',
        String((err as BusinessError).code ?? '?'));
    }
  }

  private switchReplyCard(lifted: boolean): void {
    if (this.replyDialogId === 0 || this.replyCardSwitching || this.replyCardPinned === lifted) {
      return;
    }
    this.dismissVetoUntilMs = Date.now() + REPLY_PANEL_TRANSITION_MS + 100;
    this.openReplyDialog(lifted, true);
  }

  private rebuildReplySpansIfAny(): void {
    if (this.replyText.length === 0) {
      return;
    }
    const text: string = this.replyText;
    this.rebuildingReply = true;
    try {
      this.richCtl.deleteSpans();
      let i: number = 0;
      while (i < text.length) {
        if (text.charAt(i) === '#') {
          if (text.startsWith('#(pic,', i)) {
            const close: number = text.indexOf(')', i);
            const image: UploadedPostImage | undefined = close > i ?
              this.replyImages.inlineImageFor(text.substring(i, close + 1)) : undefined;
            if (image !== undefined) {
              try {
                if (this.richCtl.addImageSpan(image.localPreview,
                  { imageStyle: { size: replyImageSize(image) } }) < 0) { this.replyImages.restoreAttachment(image); }
              } catch (err) { this.replyImages.restoreAttachment(image); }
              i = close + 1; continue;
            }
          }

          if (text.startsWith('#(meme,', i)) {
            const close: number = text.indexOf(')', i);
            if (close > i) {
              const url: string = this.vm.memeUrlFor(text.substring(i, close + 1));
              if (url.length > 0) {
                this.richCtl.addImageSpan(url, {
                  imageStyle: { size: [REPLY_EMOJI_INLINE, REPLY_EMOJI_INLINE] }
                });
                i = close + 1;
                continue;
              }
            }
          }
          const close: number = text.indexOf(')', i);
          if (text.startsWith('#(', i) && close > i) {
            const code: string = emojiCodeFromReplyToken(text.substring(i, close + 1));
            if (code.length > 0) {
              this.richCtl.addImageSpan(emojiSrc(emojiImageUrl(code)), {
                imageStyle: { size: [REPLY_EMOJI_INLINE, REPLY_EMOJI_INLINE] }
              });
              i = close + 1;
              continue;
            }
          }
        }

        let k: number = text.indexOf('#', i + 1);
        if (k < 0) {
          k = text.length;
        }
        this.richCtl.addTextSpan(text.substring(i, k));
        i = k;
      }
    } finally { this.rebuildingReply = false; }

    this.syncReplyMirror();
  }

  async submitReplyText(): Promise<void> {
    if (this.vm.replyPending) { return; }
    this.syncReplyMirror();
    const invalid: string = this.replyImages.submissionError(this.replyText, REPLY_MAX_LENGTH);
    if (invalid.length > 0) {
      promptAction.showToast({ message: invalid, duration: 1800 });
      return;
    }
    const text: string = this.replyImages.content(this.replyText);
    const editEpoch: number = this.replyEditEpoch;
    const targetPid: number = this.replyTargetPid;

    const tip: string = await this.vm.submitReply(this.hostContext(), text, targetPid);
    if (editEpoch !== this.replyEditEpoch) { return; }
    if (tip.length > 0) {
      promptAction.showToast({ message: tip, duration: 2200 });
      return;
    }
    this.closeReplyBox();

    this.richCtl.deleteSpans();
    this.replyText = '';
    this.replyImages.reset();

    if (this.vm.containsPid(this.vm.lastReplyPid)) {
      promptAction.showToast({
        message: targetPid > 0 ? '回复已发布' : '评论已发布',
        duration: 1800
      });
    } else {
      promptAction.showToast({
        message: targetPid > 0 ? '回复已发布，可在最新回复里查看' : '评论已发布，可在最新回复里查看',
        duration: 2200
      });
    }
    this.scrollToPost(this.vm.lastReplyPid);
  }

  private authorNameOf(pid: number): string {
    const post: PostItem | undefined = this.vm.postByPid(pid);

    return post === undefined ? '' : post.author.displayName;
  }

  private scrollToPost(pid: number): void {
    if (pid <= 0) {
      return;
    }
    const posts: PostItem[] = this.vm.visiblePosts;
    for (let i: number = 0; i < posts.length; i++) {
      if (posts[i].pid === pid) {
        this.scroller.scrollToIndex(i, true, ScrollAlign.START);
        return;
      }
    }
  }

  private shareOpening: boolean = false;

  private async shareThread(): Promise<void> {
    if (this.shareOpening) {
      return;
    }
    const tid: number = this.vm.tid;
    if (!Number.isSafeInteger(tid) || tid <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '帖子链接暂不可用' });
      return;
    }
    this.shareOpening = true;
    try {
      const title: string = this.vm.detail.title.trim();
      await shareWebPage(this.hostContext(), title.length > 0 ? title : '贴吧帖子',
        `https://tieba.baidu.com/p/${tid}`);
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      hilog.error(0x0, 'ThreadShare', 'system share failed code=%{public}d', error.code);
      this.getUIContext().getPromptAction().showToast({ message: '暂时无法打开系统分享，请稍后重试' });
    } finally {
      this.shareOpening = false;
    }
  }

  toastNotAvailable(action: string): void {
    promptAction.showToast({ message: `${action}暂未开放`, duration: 2000 });
  }

  private forumTitleText(): string {
    return forumChipText(this.vm.detail.forumName, this.vm.forumNameHint);
  }

  private openForum(): void {
    const name: string = resolveForumName(this.vm.detail.forumName, this.vm.forumNameHint);
    if (name.length === 0) {
      promptAction.showToast({ message: '吧信息还没加载出来', duration: 1800 });
      return;
    }

    NavigationService.openForum({ forumName: name });
  }

  private authorLevelText(): string {
    const author: UserBrief = this.vm.detail.author;
    if (author.levelName.length > 0) {
      return author.levelName;
    }
    return author.level > 0 ? `Lv.${author.level}` : '';
  }

  private authorMetaLine(): string {
    const time: string = this.mainPostTimeText();
    const region: string = this.vm.detail.author.ipLocation;
    if (time.length === 0) {
      return region;
    }
    if (region.length === 0) {
      return time;
    }
    return `${time} · ${region}`;
  }

  private mainPostTimeText(): string {
    const posts: PostItem[] = this.vm.visiblePosts;
    if (posts.length === 0) {
      return '';
    }
    return formatThreadHeadTime(posts[0].timeMs, Date.now());
  }

  private onNavTap(label: string): void {
    if (label === '更多') {
      this.showMore = !this.showMore;
      return;
    }
    this.toastNotAvailable(label);
  }

  private jumpToFloor(): void {
    const floor: number = Number.parseInt(this.jumpText.trim(), 10);
    if (!Number.isNaN(floor)) {
      const posts: PostItem[] = this.vm.visiblePosts;
      for (let i = 0; i < posts.length; i++) {
        if (posts[i].floor === floor) {
          if (i === 0) {
            this.scroller.scrollToIndex(0, true);
          } else {

            this.scroller.scrollToItemInGroup(2, i - 1, true, ScrollAlign.START);
          }
          break;
        }
      }
    }
    this.showJump = false;
  }

  @Builder
  PullHeader() { PullRefreshHeader({ inset: this.titleBarH, active: this.refreshing || this.pullRefreshDragging }) }

  build() {

    HdsNavDestination() {
        Stack({ alignContent: Alignment.Bottom }) {
          Column() {
            if (this.vm.loading && !this.vm.loadedOnce) {
              this.StatusView('正在加载…');
            } else if (this.vm.errorText.length > 0 && this.vm.posts.length === 0) {
              this.ErrorView();
            } else {
              this.PostList();
            }
          }
          .width('100%')
          .height(LayoutPolicy.matchParent)
          .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
          .clip(false)
          .backgroundColor(AppTheme.BG)

          if (this.vm.posts.length > 0 && this.viewerUrl.length === 0 && !this.showJump
            && !this.showReply && this.subDetailPid === 0) {
            this.BottomActionBar();
          }

          if (this.showMore && this.viewerUrl.length === 0 && !this.showJump && !this.showReply) {
            this.MoreMenuLayer();
          }

          if (this.showJump) {
            this.JumpDialog();
          }

          if (this.viewerUrl.length > 0) {
            ImageViewer({
              imageUrl: this.viewerUrl,
              imageUrls: this.viewerUrls,
              initialIndex: this.viewerIndex,
              onClose: (): void => {
                this.viewerUrl = '';
                this.viewerUrls = [];
                this.viewerIndex = 0;
              }
            });
          }

        }
        .width('100%')
        .height(LayoutPolicy.matchParent)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
        .clip(false)
        .backgroundColor(AppTheme.BG)

        .bindContentCover(this.showSubSheet, this.SubReplySheet(), {
          enableSafeArea: false,
          backgroundColor: AppTheme.BG,

          onDisappear: (): void => {
            this.showSubSheet = false;
            this.subDetailPid = 0;
            const user: UserBrief | undefined = this.pendingUser;
            this.pendingUser = undefined;
            if (user !== undefined) {
              openUserByIdentity(user.id, user.portraitUrl, user.displayName, this.getUIContext());
            }
          }
        })
      }
      .titleBar({
        style: {
          scrollEffectOpts: {
            enableScrollEffect: true,
            scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
          },
          scrollEffectStyle: {
            backgroundStyle: {

              maskExtraHeight: 32,
              blurRadius: 80
            }
          }

        },

        content: { stackBuilder: (): void => { this.HdsNavBar(); } }
      })

      .hideBackButton(true)

      .hideTitleBar(this.viewerUrl.length > 0 || this.viewerUrls.length > 0)
      .onHidden((reason: VisibilityChangeReason): void => {

        if (reason === VisibilityChangeReason.CONTENT_COVER && this.videoFullscreen) { return; }
        void voicePlayback.stop();
        void videoPlayback.stop();
      })
      .bindToScrollable([this.scroller])

      .onBackPressed((): boolean => {
        return this.handleSystemBack();
      })

  }

  @Builder
  SubReplySheet() {
    SubReplyDetailSheet({
      tid: this.vm.tid,
      threadTitle: this.vm.detail.title,
      onOpenUser: (user: UserBrief): void => {
        if (user.id <= 0 && user.portraitUrl.length === 0) {
          openUserByIdentity(user.id, user.portraitUrl, user.displayName, this.getUIContext());
          return;
        }
        this.pendingUser = user;
        this.closeSubSheet();
      },
      anchor: this.anchorPost(this.subDetailPid),
      anchorIsThreadAuthor: this.anchorPost(this.subDetailPid).author.id === this.vm.detail.author.id,
      anchorAgreeState: this.vm.agreeState(this.subDetailPid),
      subPosts: this.vm.subState(this.subDetailPid).subPosts,
      totalReplies: this.vm.subState(this.subDetailPid).loadedOnce
        ? this.vm.subState(this.subDetailPid).page.totalCount
        : this.anchorPost(this.subDetailPid).subPostCount > 0
          ? this.anchorPost(this.subDetailPid).subPostCount : -1,
      subAgreeState: (sub: SubPostItem): AgreeState => this.vm.subAgreeState(sub),
      loading: this.vm.subState(this.subDetailPid).loading,
      errorText: this.vm.subState(this.subDetailPid).errorText,
      hasMore: this.vm.subState(this.subDetailPid).hasMore,
      safeTopVp: this.statusBarH,
      safeBottomVp: this.safeBottomVp,

      anchorBody: (): void => {
        this.SheetAnchorBody();
      },
      subBody: (sub: SubPostItem): void => {
        this.SheetSubBody(sub);
      },
      onClose: (): void => {
        this.closeSubSheet();
      },
      onToggleAnchorLike: (): void => {
        this.toggleLike(this.anchorPost(this.subDetailPid));
      },
      onToggleSubLike: (sub: SubPostItem): void => {
        this.vm.toggleAgree(this.hostContext(), sub, AgreeObjType.SUB_POST, this.subDetailPid)
          .then((reason: string) => {
            if (reason.length > 0) {
              promptAction.showToast({ message: reason, duration: 1800 });
            }
          });
      },
      onReply: (): void => {

        this.openReplyBox(this.subDetailPid);
      },
      onRetry: (): void => {
        this.retrySubSheet(this.subDetailPid);
      },
      onLoadMore: (): void => {
        this.vm.loadMoreSubPosts(this.hostContext(), this.subDetailPid,
          this.vm.detail.author.id);
      }
    })
  }

  @Builder
  SheetAnchorBody() {
    this.RichBody(this.anchorPost(this.subDetailPid));
  }

  @Builder
  SheetSubBody(sub: SubPostItem) {
    this.RichPieces(this.subReplyPieces(sub), COMMENT_BODY_SIZE, 24, AppTheme.SUB_REPLY_BODY);
  }

  private subReplyPieces(sub: SubPostItem): ContentPiece[] {
    if (sub.replyToName.length === 0) {
      return sub.contents;
    }
    const lead: ContentPiece = new ContentPiece();
    lead.kind = ContentKind.TEXT;
    lead.text = '回复 ';
    const target: ContentPiece = new ContentPiece();
    target.kind = ContentKind.REPLY_TARGET;
    target.text = sub.replyToName;
    const separator: ContentPiece = new ContentPiece();
    separator.kind = ContentKind.TEXT;
    separator.text = '：';
    return [lead, target, separator, ...sub.contents];
  }

  @Builder
  HdsNavBar() {
    Column() {
      this.ForumNavBar()
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ForumNavBar() {
    Row({ space: 4 }) {

      GlassBackButton({
        onTap: (): void => {
          this.goBack();
        }
      })

      Row({ space: 8 }) {
        this.ForumAvatar(30)
        Text(this.forumTitleText())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_MAIN)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .height(40)
      .padding({ left: 4, right: 6 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.openForum();
      })

      GlassMoreButton({
        onTap: (): void => {
          this.onNavTap('更多');
        }
      })
    }
    .width('100%')

    .height(52)
    .margin({ top: this.statusBarH })
    .padding({ left: 8, right: 12 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  AuthorBar() {
    Row({ space: 10 }) {
      AvatarComponent({ url: this.vm.detail.author.portraitUrl, avatarSize: 40, fallbackName: this.vm.detail.author.displayName })
        .onClick(() => { openUserByIdentity(this.vm.detail.author.id, this.vm.detail.author.portraitUrl, this.vm.detail.author.displayName, this.getUIContext()); })

      Column({ space: 4 }) {
        Row({ space: 10 }) {
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
            Text(this.vm.detail.author.displayName.length > 0
              ? this.vm.detail.author.displayName : '匿名用户')
              .fontSize(POST_NICKNAME_SIZE)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.TEXT_MAIN)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick(() => { openUserByIdentity(this.vm.detail.author.id, this.vm.detail.author.portraitUrl, this.vm.detail.author.displayName, this.getUIContext()); })
              .margin({ right: 6 })

            if (this.authorLevelText().length > 0) {
              if (forumLevelStore.style === 1 && this.vm.detail.author.level > 0) {
                ForumLevelBadge({ level: this.vm.detail.author.level, levelName: this.vm.detail.author.levelName })
              } else {
                this.LevelChip(this.authorLevelText())
              }
            }
            if (this.vm.detail.author.isBawu) {
              Row() {
                this.Badge(this.vm.detail.author.bawuTitle.length > 0
                  ? this.vm.detail.author.bawuTitle : '吧务', false)
              }
              .margin({ right: 6 })
            }
          }
          .layoutWeight(1)

          FollowButton({ kind: 'user', targetId: this.vm.detail.author.id,
            portrait: this.vm.detail.author.portraitUrl, targetName: this.vm.detail.author.displayName })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.authorMetaLine().length > 0) {
          Text(this.authorMetaLine())
            .fontSize(12)
            .fontColor(AppTheme.TEXT_SUB)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')

    .padding({ bottom: 2 })
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  ForumAvatar(size: number) {
    ForumAvatarImage({ url: this.vm.detail.forumAvatar, glyphText: '吧',
      avatarSize: size, radius: forumAvatarRadius(size), fontSize: 13, bgColor: AppTheme.SURFACE_MUTED })
  }

  @Builder
  LevelChip(text: string) {
    Text(text)
      .fontSize(10)
      .fontColor(AppTheme.ACCENT_DARK)
      .backgroundColor(AppTheme.ACCENT_LIGHT)
      .borderRadius(5)
      .padding({ left: 5, right: 5, top: 2, bottom: 2 })
      .margin({ right: 6 })
  }

  @Builder
  MoreMenuLayer() {
    Column()
      .width('100%')
      .height('100%')
      .onClick(() => {
        this.showMore = false;
      })

    Row() {
      this.MoreMenu()
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .alignItems(VerticalAlign.Top)

    .padding({ top: this.titleBarH + 4, right: 14 })
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  MoreMenu() {
    Column({ space: 2 }) {
      Text(this.vm.sortType === ReplySortType.ONLY_AUTHOR ? '显示全部回复' : '只看楼主')
        .fontSize(14)
        .fontColor(AppTheme.TEXT_MAIN)
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .onClick(() => {
          const target: ReplySortType = this.vm.sortType === ReplySortType.ONLY_AUTHOR
            ? ReplySortType.ASC : ReplySortType.ONLY_AUTHOR;
          this.vm.switchReplySort(this.hostContext(), target);
          this.showMore = false;
        })

      Text('跳转到楼层')
        .fontSize(14)
        .fontColor(AppTheme.TEXT_MAIN)
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .onClick(() => {
          this.jumpText = '';
          this.showMore = false;
          this.showJump = true;
        })

      Text('回到顶部')
        .fontSize(14)
        .fontColor(AppTheme.TEXT_MAIN)
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .onClick(() => {
          this.scroller.scrollToIndex(0, true);
          this.showMore = false;
        })

      Text('搜索')
        .fontSize(14)
        .fontColor(AppTheme.TEXT_MAIN)
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .onClick(() => {
          this.showMore = false;
          this.toastNotAvailable('搜索');
        })

      Text('分享')
        .fontSize(14)
        .fontColor(AppTheme.TEXT_MAIN)
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .onClick(() => {
          this.showMore = false;
          this.shareThread();
        })
    }
    .width(164)
    .padding({ top: 4, bottom: 4 })
    .borderRadius(16)
    .backgroundColor(AppTheme.CARD)
    .shadow({ radius: 18, color: '#26000000', offsetY: 5 })
  }

  @Builder
  JumpDialog() {
    Stack() {
      Column({ space: 14 }) {
        Text('跳转到楼层')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_MAIN)

        TextInput({ text: this.jumpText, placeholder: '输入楼层号，如 25' })
          .type(InputType.Number)
          .fontSize(15)
          .fontColor(AppTheme.TEXT_MAIN)
          .placeholderColor(AppTheme.TEXT_MUTED)
          .width(210)
          .height(44)
          .backgroundColor(AppTheme.SURFACE_MUTED)
          .borderRadius(12)
          .onChange((value: string) => {
            this.jumpText = value;
          })
          .onSubmit(() => {
            this.jumpToFloor();
          })

        Row({ space: 12 }) {
          Text('取消')
            .fontSize(14)
            .fontColor(AppTheme.TEXT_SUB)
            .textAlign(TextAlign.Center)
            .width(92)
            .height(38)
            .borderRadius(19)
            .backgroundColor(AppTheme.SURFACE_MUTED)
            .onClick(() => {
              this.showJump = false;
            })

          Text('跳转')
            .fontSize(14)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .width(92)
            .height(38)
            .borderRadius(19)
            .backgroundColor(AppTheme.ACCENT)
            .onClick(() => {
              this.jumpToFloor();
            })
        }
      }
      .padding({ left: 22, right: 22, top: 22, bottom: 20 })
      .borderRadius(18)
      .backgroundColor(AppTheme.CARD)
      .shadow({ radius: 24, color: '#40000000', offsetY: 8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.OVERLAY)
    .onClick(() => {
      this.showJump = false;
    })
  }

  @Builder
  ReplyDialog() {

    Column({ space: 8 }) {

      Row({ space: 8 }) {
        Text(this.replyTargetLine())
          .fontSize(13)
          .fontColor(AppTheme.TEXT_MUTED)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.replyText.length}/${REPLY_MAX_LENGTH}`)
          .fontSize(12)
          .fontColor(AppTheme.TEXT_MUTED)
      }
      .width('100%')

      RichEditor({ controller: this.richCtl })
        .enabled(!this.vm.replyPending)
        .placeholder('说点什么吧…', { font: { size: 15 }, fontColor: AppTheme.TEXT_MUTED })
        .padding({ left: 0, right: 0 })
        .backgroundColor(Color.Transparent)

        .focusBox({ strokeWidth: LengthMetrics.vp(0) })
        .width('100%')

        .constraintSize({ minHeight: REPLY_INPUT_MIN_H })
        .onIMEInputComplete(() => {
          this.syncReplyMirror();
        })
        .onDeleteComplete(() => {
          this.syncReplyMirror();
        })
        .onPaste(() => {

          setTimeout(() => {
            this.syncReplyMirror();
          }, 100);
        })

        .onReady(() => {
          this.rebuildReplySpansIfAny();
        })

        .onFocus(() => {
          this.setEmojiPanel(false, true);
        })
        .id('tdReplyRich')

      if (this.replyImages.images.length > 0) {
        Scroll() {
          Column({ space: 4 }) {
            ForEach(this.replyImages.images, (image: UploadedPostImage, index: number) => {
              Row({ space: 8 }) {
                if (image.previewUrl.length > 0) {
                  Image(image.previewUrl).width(44).height(44)
                    .objectFit(ImageFit.Contain).borderRadius(6)
                    .accessibilityText(`回复图片 ${index + 1}`)
                } else {
                  SymbolGlyph($r('sys.symbol.picture')).fontSize(20).fontColor([AppTheme.ICON])
                }
                Text(`图片 ${index + 1} · ${image.width} × ${image.height}`)
                  .fontSize(12).fontColor(AppTheme.TEXT_MAIN).layoutWeight(1)
                Text('移除').fontSize(12).fontColor(AppTheme.ACCENT)
                  .onClick(() => { if (!this.vm.replyPending) { this.replyImages.remove(index); } })
              }.width('100%')
            })
            Text('图片按顺序附在回复文字之后')
              .fontSize(11).fontColor(AppTheme.TEXT_MUTED)
          }.width('100%')
        }.width('100%').constraintSize({ maxHeight: 112 })
      }
      if (this.replyImages.upload.selecting || this.replyImages.upload.busy) {
        Row({ space: 8 }) {
          Text(this.replyImages.upload.selecting ? '正在选择和准备图片…' :
            `正在上传图片 ${Math.floor(this.replyImages.upload.uploadedBytes * 100 /
              Math.max(1, this.replyImages.upload.totalBytes))}%`)
            .fontSize(12).fontColor(AppTheme.TEXT_MUTED).layoutWeight(1)
          Text('停止').fontSize(12).fontColor(AppTheme.ACCENT)
            .onClick(() => { this.replyImages.cancel(); })
        }.width('100%')
      } else if (this.replyImages.upload.error.length > 0) {
        Text(this.replyImages.upload.error).fontSize(12).fontColor(AppTheme.TEXT_MUTED).width('100%')
      }

      Row({ space: REPLY_TOOL_GAP }) {

        Row() {
          SymbolGlyph(this.showEmojiPanel ? $r('sys.symbol.keyboard') : $r('sys.symbol.face_smiling'))
            .fontSize(22)
            .fontColor([AppTheme.ICON])
        }
        .width(32)
        .height(32)
        .justifyContent(FlexAlign.Center)
        .accessibilityText(this.showEmojiPanel ? '切换到键盘' : '切换到表情')
        .onClick(() => {
          if (this.showEmojiPanel) {
            this.showReplyKeyboard();
          } else {
            this.setEmojiPanel(true);
          }
        })
        Row() {
          SymbolGlyph($r('sys.symbol.picture'))
            .fontSize(22)
            .fontColor([AppTheme.ICON])
        }
        .width(32)
        .height(32)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (this.vm.replyPending) { return; }
          this.setEmojiPanel(false, true);
          void this.pickReplyImage();
        })
        Text('@')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT_MAIN)
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.appendReplyText('@');
          })
        Text('#')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT_MAIN)
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.appendReplyText('#');
          })

        Blank()

        Text(this.vm.replyPending ? '发布中…' : '发布')
          .fontSize(14)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .width(REPLY_PUBLISH_W)
          .height(REPLY_PUBLISH_H)
          .borderRadius(REPLY_PUBLISH_H / 2)

          .backgroundColor(this.vm.replyPending ? '#800A59F7' : AppTheme.ACCENT)
          .onClick(() => {
            if (this.vm.replyPending) {
              return;
            }
            this.submitReplyText();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        ForEach(REPLY_EMOTICON_QUICK_CODES, (code: number) => {
          Image(emojiSrc(emojiImageUrl(`image_emoticon${code}`)))
            .width(REPLY_QUICK_EMOJI_SIZE)
            .height(REPLY_QUICK_EMOJI_SIZE)
            .objectFit(ImageFit.Contain)

            .interpolation(ImageInterpolation.High)

            .onClick(() => {
              this.insertReplyEmoji(code);
            })
        }, (code: number) => `quick_${code}`)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .padding({ left: 4, right: 4 })
    }
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })

    .width('100%')
  }

  @Builder
  EmojiSheet() {
    Column() {
      Row({ space: 14 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.face_smiling'))
            .fontSize(20)
            .fontColor([this.emojiTab === 0 ? AppTheme.ACCENT : AppTheme.EMOJI_PANEL_TEXT])
        }
        .width(REPLY_EMOJI_TAB_SIZE)
        .height(REPLY_EMOJI_TAB_SIZE)
        .borderRadius(REPLY_EMOJI_TAB_SIZE / 2)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.emojiTab === 0 ? '#FFFFFF' : Color.Transparent)
        .onClick(() => {
          this.emojiTab = 0;
        })

        Row() {
          SymbolGlyph($r('sys.symbol.heart'))
            .fontSize(20)
            .fontColor([this.emojiTab === 1 ? AppTheme.ACCENT : AppTheme.EMOJI_PANEL_TEXT])
        }
        .width(REPLY_EMOJI_TAB_SIZE)
        .height(REPLY_EMOJI_TAB_SIZE)
        .borderRadius(REPLY_EMOJI_TAB_SIZE / 2)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.emojiTab === 1 ? '#FFFFFF' : Color.Transparent)
        .onClick(() => {
          this.emojiTab = 1;
          this.vm.loadMemePics(this.hostContext());
        })

        Blank()

        Row() {
          SymbolGlyph($r('sys.symbol.delete_left'))
            .fontSize(20)
            .fontColor([AppTheme.EMOJI_PANEL_TEXT])
        }
        .width(REPLY_EMOJI_TAB_SIZE)
        .height(REPLY_EMOJI_TAB_SIZE)
        .borderRadius(REPLY_EMOJI_TAB_SIZE / 2)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.deleteReplyLastChar();
        })
      }
      .width('100%')
      .height(EMOJI_PANEL_TAB_H)

      if (this.emojiTab === 0) {
        Grid() {
          ForEach(REPLY_EMOTICON_CODES, (code: number) => {

            GridItem() {
              Image(emojiSrc(emojiImageUrl(`image_emoticon${code}`)))
                .width(REPLY_EMOJI_SIZE)
                .height(REPLY_EMOJI_SIZE)
                .objectFit(ImageFit.Contain)

                .interpolation(ImageInterpolation.High)
            }
            .onClick(() => {
              this.insertReplyEmoji(code);
            })
          }, (code: number) => `emoticon_${code}`)
        }
        .columnsTemplate(REPLY_EMOJI_COLUMNS)
        .rowsGap(REPLY_EMOJI_ROW_GAP)
        .height(this.emojiGridHeight())
        .width('100%')
      } else {
        this.MemeEmojiGrid()
      }
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: EMOJI_PANEL_TOP_PADDING,
      bottom: EMOJI_PANEL_BOTTOM_PADDING + this.safeBottomVp
    })
  }

  replyTargetLine(): string {
    if (this.replyTargetPid <= 0) {
      return '';
    }
    const target: PostItem | undefined = this.vm.postByPid(this.replyTargetPid);
    const name: string = target === undefined ? this.replyTargetName : target.author.displayName;
    if (name.length === 0) { return '回复该评论'; }
    const text: string = target === undefined ? '' :
      commentText(postCommentTarget(target, this.vm.tid, this.vm.detail.title));
    return text.length > 0 ? `回复 ${name}：${text}` : `回复 ${name}`;
  }

  private async pickReplyImage(): Promise<void> {
    if (this.vm.replyPending || this.replyImages.upload.busy || this.replyImages.upload.selecting) { return; }
    this.syncReplyMirror();
    const original: string = this.replyText;
    const caret: number = this.richCtl.getCaretOffset();
    const editEpoch: number = this.replyEditEpoch;
    const image: UploadedPostImage | undefined = await this.replyImages.pick(this.hostContext(),
      resolveForumName(this.vm.detail.forumName, this.vm.forumNameHint));
    if (image === undefined || editEpoch !== this.replyEditEpoch || !this.showReply || this.vm.replyPending) { return; }
    this.syncReplyMirror();
    if (!this.replyImages.canInline(image) || this.vm.memeTokenTable().has(image.localPreview)) { return; }
    const offset: number = original === this.replyText ? caret : this.richCtl.getCaretOffset();
    if (!this.replyImages.moveInline(image)) { return; }
    this.rebuildingReply = true;
    try {
      const options: RichEditorImageSpanOptions = { imageStyle: { size: replyImageSize(image) } };
      if (offset >= 0) { options.offset = offset; }
      const inserted: number = this.richCtl.addImageSpan(image.localPreview, options);
      if (inserted < 0) { this.replyImages.restoreAttachment(image); return; }
    } catch (err) {
      this.replyImages.restoreAttachment(image);
      promptAction.showToast({ message: '图片未插入输入框，已保留为回复附件', duration: 1800 });
    } finally { this.rebuildingReply = false; }
    this.syncReplyMirror();
  }

  syncReplyMirror(): void {
    if (this.rebuildingReply) { return; }
    const content: ReplyEditorContent = richEditorReplyText(this.richCtl, this.vm.memeTokenTable(),
      this.replyImages.inlineTokenTable());
    this.replyText = content.text;
    this.replyImages.reconcileInline(content.imageCounts);

  }

  appendReplyText(text: string): void {
    if (this.vm.replyPending) { return; }
    if (this.replyText.length + text.length > REPLY_MAX_LENGTH) {
      promptAction.showToast({ message: '已达 500 字上限', duration: 1500 });
      return;
    }
    this.richCtl.addTextSpan(text);
    this.syncReplyMirror();
  }

  insertReplyEmoji(code: number): void {
    if (this.vm.replyPending) { return; }
    const url: string = emojiImageUrl(`image_emoticon${code}`);
    this.richCtl.addImageSpan(emojiSrc(url), {
      imageStyle: { size: [REPLY_EMOJI_INLINE, REPLY_EMOJI_INLINE] }
    });
    this.syncReplyMirror();
  }

  private insertMemeEmoji(item: MemePicItem): void {
    if (this.vm.replyPending) { return; }
    const url: string = this.vm.memeDisplayUrl(item);
    if (url.length === 0) {
      return;
    }
    this.richCtl.addImageSpan(url, {
      imageStyle: { size: [REPLY_EMOJI_INLINE, REPLY_EMOJI_INLINE] }
    });
    this.syncReplyMirror();
  }

  private deleteReplyLastChar(): void {
    if (this.vm.replyPending) { return; }
    const spans: Array<RichEditorImageSpanResult | RichEditorTextSpanResult> = this.richCtl.getSpans();
    if (spans.length === 0) {
      return;
    }
    const last: RichEditorImageSpanResult | RichEditorTextSpanResult = spans[spans.length - 1];
    const endPos: number = last.offsetInSpan[1];
    if (endPos <= 0) {
      return;
    }
    const range: RichEditorRange = { start: endPos - 1, end: endPos };
    this.richCtl.deleteSpans(range);
    this.syncReplyMirror();
  }

  @Builder
  MemeEmojiGrid() {
    if (this.vm.memeStateText === 'loading') {
      Column() {
        Text('收藏表情加载中…')
          .fontSize(13)
          .fontColor(AppTheme.EMOJI_PANEL_TEXT)
      }
      .width('100%')
      .height(this.emojiGridHeight())
      .justifyContent(FlexAlign.Center)
    } else if (this.vm.memeStateText.length > 0) {
      Column() {
        Text(this.vm.memeStateText)
          .fontSize(13)
          .fontColor(AppTheme.EMOJI_PANEL_TEXT)
          .textAlign(TextAlign.Center)
        Text('点此重试')
          .fontSize(13)
          .fontColor(AppTheme.ACCENT)
          .margin({ top: 10 })
          .onClick(() => {
            this.vm.retryMemePics(this.hostContext());
          })
      }
      .width('100%')
      .height(this.emojiGridHeight())
      .justifyContent(FlexAlign.Center)
    } else if (this.vm.memePics.length === 0) {
      Column() {
        Text('还没有收藏表情')
          .fontSize(14)
          .fontColor(AppTheme.EMOJI_PANEL_TEXT)
        Text('在官方贴吧客户端长按表情即可收藏，收藏后这里同步显示')
          .fontSize(12)
          .fontColor(AppTheme.EMOJI_PANEL_SUB_TEXT)
          .margin({ top: 6 })
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .height(this.emojiGridHeight())
      .justifyContent(FlexAlign.Center)
      .padding({ left: 24, right: 24 })
    } else {
      Grid() {
        ForEach(this.vm.memePics, (item: MemePicItem) => {
          GridItem() {
            Image(this.vm.memeDisplayUrl(item))
              .width(REPLY_EMOJI_SIZE)
              .height(REPLY_EMOJI_SIZE)
              .objectFit(ImageFit.Contain)
          }
          .onClick(() => {
            this.insertMemeEmoji(item);
          })
        }, (item: MemePicItem) => `meme_${item.picId}_${item.picUrl}`)
      }
      .columnsTemplate(REPLY_EMOJI_COLUMNS)
      .rowsGap(REPLY_EMOJI_ROW_GAP)
      .height(this.emojiGridHeight())
      .width('100%')
    }
  }

  @Builder
  PostList() {
    Refresh({ refreshing: this.refreshing, builder: (): void => { this.PullHeader(); } }) {
      List({ space: 0, scroller: this.scroller }) {
        if (this.vm.visiblePosts.length > 0) {
          ListItem() {
            this.ThreadIntro(this.vm.visiblePosts[0])
          }
          .backgroundColor(Color.Transparent)
        }

        ListItem() {
          this.ReplySummary()
        }
        .backgroundColor(Color.Transparent)

        ListItemGroup() {
          ForEach(this.vm.visiblePosts, (item: PostItem, index: number) => {
            if (index > 0) {
              ListItem() {

                Column() {
                  ReplyItem({
                    tid: this.vm.tid,
                    threadTitle: this.vm.detail.title,
                    item: item,
                    isThreadAuthor: item.author.id === this.vm.detail.author.id,
                    agreeState: this.vm.agreeState(item.pid),
                    subPosts: this.previewSubPosts(item),
                    subTotalCount: item.subPostCount,
                    subLoading: this.vm.subState(item.pid).loading,
                    subErrorText: this.vm.subState(item.pid).errorText,
                    hasAuthorReply: this.hasAuthorReply(item),
                    bodyBuilder: (): void => {
                      this.RichBody(item);
                    },
                    onToggleLike: (): void => {
                      this.toggleLike(item);
                    },
                    onReply: (): void => {
                      this.openReplyBox(item.pid);
                    },
                    onOpenSubDetail: (): void => {
                      this.openSubDetailByPid(item.pid);
                    },
                    onRetrySubPosts: (): void => {
                      this.vm.retrySubPosts(this.hostContext(), item.pid, this.vm.detail.author.id);
                    },
                    onViewImage: (url: string): void => {
                      this.openPreviewImage(url);
                    }
                  })
                }
                .onVisibleAreaChange([0.1, 1.0], (isVisible: boolean) => {
                  if (isVisible) {
                    this.vm.ensureSubPostPreview(this.hostContext(), item.pid,
                      this.vm.detail.author.id);
                  }
                })
              }
              .backgroundColor(Color.Transparent)
            }
          }, (item: PostItem) => `${item.pid}`)

          if (this.vm.visiblePosts.length <= 1 && !this.vm.loading && !this.vm.isSwitchingSort) {
            ListItem() {
              this.EmptyReplies()
            }
            .backgroundColor(Color.Transparent)
          }

          ListItem() {
            this.Footer()
          }
          .backgroundColor(Color.Transparent)
        }
        .backgroundColor(Color.Transparent)
      }
      .width('100%')
      .layoutWeight(1)

      .padding({ top: this.titleBarH, bottom: 8 })
      .clip(false)
      .backgroundColor(Color.Transparent)
      .divider({ strokeWidth: 0 })

       .scrollBar(BarState.Off)
       .onReachEnd(() => {
        this.vm.loadMore(this.hostContext());
      })
    }.refreshOffset(PULL_REFRESH_OFFSET)
        .onStateChange((state: RefreshStatus) => {
          this.pullRefreshDragging = state === RefreshStatus.Drag || state === RefreshStatus.OverDrag;
        })
    .onRefreshing(() => {
      this.handleRefresh();
    })
    .layoutWeight(1)
  }

  @Builder
  ThreadIntro(item: PostItem) {
    Column({ space: 14 }) {

      this.AuthorBar()

      Column({ space: 9 }) {
        if (item.title.length > 0) {
          Text(item.title)
            .fontSize(POST_TITLE_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT_MAIN)
            .lineHeight(25)
            .width('100%')
        }

        if (this.vm.detail.video !== undefined) {
          VideoPlayer({ video: this.vm.detail.video,
            onFullscreenChange: (shown: boolean): void => { this.videoFullscreen = shown; } })
        }
        this.RichPieces(item.contents)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (item.subPostCount > 0) {
        this.SubPostEntry(item)

        if (this.vm.subState(item.pid).expanded) {
          this.SubPostList(item)
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 18 })
    .backgroundColor(Color.Transparent)
  }

  @Builder
  ReplySummary() {
    Row() {
      Text(`共 ${this.displayedReplyCount()} 回复`)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_MAIN)
      Blank()
        .layoutWeight(1)
      Row() {
        this.ReplySortSegment('热门', ReplySortType.HOT)
        this.ReplySortSegment('正序', ReplySortType.ASC)
        this.ReplySortSegment('倒序', ReplySortType.DESC)
        this.ReplySortSegment('楼主', ReplySortType.ONLY_AUTHOR)
      }
      .padding(1.5)
      .borderRadius(13.5)
      .backgroundColor(AppTheme.SURFACE_MUTED)
    }
    .width('100%')
    .height(42)
    .padding({ left: 16, right: 16, top: 7.5, bottom: 6 })
    .backgroundColor(AppTheme.BG)
  }

  @Builder
  ReplySortSegment(label: string, type: ReplySortType) {
    Text(label)
      .fontSize(9.75)
      .fontColor(this.vm.sortType === type ? AppTheme.TEXT_MAIN : AppTheme.TEXT_SUB)
      .textAlign(TextAlign.Center)
      .height(24)
      .padding({ left: 8.25, right: 8.25 })
      .borderRadius(12)
      .backgroundColor(this.vm.sortType === type ? AppTheme.CARD : Color.Transparent)
      .opacity(isReplySortSupported(type) ? 1 : 0.45)
      .onClick(() => {
        if (!isReplySortSupported(type)) {
          promptAction.showToast({ message: unsupportedSortTip(type), duration: 2200 });
          return;
        }
        this.vm.switchReplySort(this.hostContext(), type);
      })
  }

  @Builder
  Badge(text: string, filled: boolean) {
    Text(text)
      .fontSize(10)
      .fontColor(filled ? Color.White : AppTheme.ACCENT_DARK)
      .backgroundColor(filled ? AppTheme.ACCENT : AppTheme.ACCENT_LIGHT)
      .border({ width: 1, color: AppTheme.ACCENT })
      .borderRadius(5)
      .padding({ left: 5, right: 5, top: 2, bottom: 2 })
  }

  @Builder
  RichBody(item: PostItem) {
    this.RichPieces(item.contents, COMMENT_BODY_SIZE, 24, AppTheme.COMMENT_BODY)
  }

  @Builder
  RichPieces(pieces: ContentPiece[], fontSize: number = POST_BODY_SIZE, lineHeight: number = 24,
    textColor: ResourceColor = AppTheme.TEXT_MAIN) {
    Column({ space: 9 }) {
      ForEach(groupContentBlocks(pieces), (block: ContentBlock, index: number) => {
        if (block.isVoice && block.voice !== undefined) {
          VoicePlayer({ voice: block.voice })
        } else if (block.isImage) {
          this.ImageBlock(block, collectPreviewImageUrls(pieces))
        } else {
          this.TextBlock(block, fontSize, lineHeight, textColor)
        }
      }, (block: ContentBlock, index: number) => `${index}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  TextBlock(block: ContentBlock, fontSize: number, lineHeight: number, textColor: ResourceColor) {
    Text() {
      PostContentInline({
        pieces: block.pieces,
        emojiSize: lineHeight === SUB_REPLY_LINE_HEIGHT ? 18 : BODY_EMOJI_SIZE,
        textColor: textColor,
        accentColor: AppTheme.ACCENT_DARK,
        onActivate: (piece: ContentPiece): void => { openContentPiece(piece, this.getUIContext()); }
      })
    }
    .fontSize(fontSize)
    .fontColor(textColor)
    .lineHeight(lineHeight)
    .width('100%')
  }

  @Builder
  ImageBlock(block: ContentBlock, imageUrls: string[]) {
    PostImageGallery({
      images: block.images,
      startIndex: block.imageStartIndex,
      onOpenImage: (globalIndex: number): void => {
        this.openGalleryImage(imageUrls, globalIndex);
      }
    })
  }

  private openGalleryImage(imageUrls: string[], globalIndex: number): void {
    if (imageUrls.length === 0) {
      return;
    }
    const index: number = Math.max(0, Math.min(imageUrls.length - 1, globalIndex));
    this.viewerUrls = imageUrls;
    this.viewerIndex = index;
    this.viewerUrl = imageUrls[index];
  }

  @Builder
  SubPostEntry(item: PostItem) {
    Row() {
      Text(this.vm.subState(item.pid).expanded ? '收起回复' : `${item.subPostCount} 条回复`)
        .fontSize(13)
        .fontColor(AppTheme.ACCENT_DARK)
      Blank()
        .layoutWeight(1)
      Text(this.vm.subState(item.pid).expanded ? '⌃' : '⌄')
        .fontSize(16)
        .fontColor(AppTheme.ACCENT_DARK)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(10)
    .backgroundColor(AppTheme.ACCENT_LIGHT)
    .onClick(() => {
      this.vm.toggleSubPosts(this.hostContext(), item.pid, this.vm.detail.author.id);
    })
  }

  @Builder
  SubPostList(item: PostItem) {
    Column({ space: 8 }) {
      if (this.vm.subState(item.pid).loading && !this.vm.subState(item.pid).loadedOnce) {
        Text('正在加载回复…')
          .fontSize(13)
          .fontColor(AppTheme.TEXT_SUB)
          .padding({ top: 4, bottom: 4 })
      } else if (this.vm.subState(item.pid).errorText.length > 0
        && this.vm.subState(item.pid).subPosts.length === 0) {
        Text(this.vm.subState(item.pid).errorText)
          .fontSize(12)
          .fontColor(AppTheme.ERROR)
        Text('重试')
          .fontSize(13)
          .fontColor(AppTheme.ACCENT_DARK)
          .onClick(() => {
            this.vm.retrySubPosts(this.hostContext(), item.pid, this.vm.detail.author.id);
          })
      } else {
        ForEach(this.previewSubPosts(item), (sub: SubPostItem) => {
          this.SubPostRow(sub)
        }, (sub: SubPostItem) => `${sub.pid}`)
        if (this.vm.subState(item.pid).subPosts.length > 0) {
          Text(`查看 ${item.subPostCount} 条回复 ›`)
            .fontSize(14)
            .fontColor(AppTheme.ACCENT_DARK)
            .padding({ top: 5, bottom: 4 })
            .onClick(() => {
              this.openSubDetailByPid(item.pid);
            })
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 12, top: 10, bottom: 8 })
    .borderRadius(14)
    .backgroundColor(AppTheme.SURFACE_MUTED)
  }

  @Builder
  EmptyReplies() {
    Column({ space: 6 }) {
      Text('暂无回复')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_MAIN)
      Text('来抢沙发吧')
        .fontSize(13)
        .fontColor(AppTheme.TEXT_SUB)
    }
    .width('100%')
    .padding({ top: 44, bottom: 44 })
  }

  @Builder
  SubPostRow(sub: SubPostItem) {
    Column({ space: 5 }) {
      Row({ space: 8 }) {
        AvatarComponent({ url: sub.author.portraitUrl, avatarSize: 28, fallbackName: sub.author.displayName })
        Column({ space: 2 }) {
          Row({ space: 6 }) {
            Text(sub.author.displayName)
              .fontSize(POST_NICKNAME_SIZE)
              .fontColor(AppTheme.SUB_REPLY_NAME)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (sub.isThreadAuthor) {
              ThreadAuthorBadge()
            }
          }
          if (sub.timeText.length > 0) {
            Text(sub.timeText)
              .fontSize(11)
              .fontColor(AppTheme.TEXT_SUB)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (sub.replyToName.length > 0) {
        Row({ space: 5 }) {
          Text('回复')
            .fontSize(12)
            .fontColor(AppTheme.TEXT_SUB)
          Text(sub.replyToName)
            .fontSize(12)
            .fontColor(AppTheme.COMMENT_ACTION)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (sub.replyToIsThreadAuthor) {
            ThreadAuthorBadge()
          }
        }
        .width('100%')
      }

      this.RichPieces(sub.contents, SUB_REPLY_BODY_SIZE, SUB_REPLY_LINE_HEIGHT, AppTheme.SUB_REPLY_BODY)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 7, bottom: 7 })
  }

  @Builder
  ClassicGlassReplyPill() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(22)
        .fontColor([AppTheme.TEXT_MAIN])
      Text('回复楼主…')
        .fontSize(15)
        .fontColor(AppTheme.TEXT_MAIN)
    }
    .height(ACTION_PILL_HEIGHT)
    .padding({ left: REPLY_PILL_PADDING, right: REPLY_PILL_PADDING })
    .borderRadius(ACTION_PILL_RADIUS)
    .backgroundEffect(materialManager.glassOf(MaterialSlot.BOTTOM_FLOATING_BAR))
    .systemMaterial(materialManager.officialOf(MaterialSlot.BOTTOM_FLOATING_BAR))
    .border({ width: capsuleEdgeWidth(), color: capsuleEdgeColor() })
    .onClick(() => {
      this.openReplyBox(0);
    })
  }

  @Builder
  GlassActionCapsule() {
    Row() {
      this.BottomReplyCount()
      this.BottomLikeAction()
      this.BottomStoreAction()
      this.BottomAction($r('sys.symbol.share'), '分享', (): void => { this.shareThread(); })
      if (threadActionBarStore.style === ThreadActionBarStyle.POPUP) {
        this.PopupMoreAnchor()
      }
    }
    .layoutWeight(1)
    .height(ACTION_PILL_HEIGHT)
    .padding({ left: ACTION_QUAD_PADDING, right: ACTION_QUAD_PADDING })
    .borderRadius(ACTION_PILL_RADIUS)
    .backgroundEffect(materialManager.glassOf(MaterialSlot.BOTTOM_FLOATING_BAR))
    .systemMaterial(materialManager.officialOf(MaterialSlot.BOTTOM_FLOATING_BAR))
    .border({ width: capsuleEdgeWidth(), color: capsuleEdgeColor() })
  }

  @Builder
  SplitImmersiveReplyPill() {
    HdsTabs({ barPosition: BarPosition.End }) {
      TabContent() {
      }
      .tabBar(this.SplitReplyTab())
    }
    .barHeight(ACTION_PILL_HEIGHT)
    .barMode(BarMode.Fixed)
    .scrollable(false)
    .animationDuration(0)
    .barOverlap(true)

    .barBackgroundColor(Color.Transparent)
    .barBackgroundBlurStyle(BlurStyle.NONE)

    .barFloatingStyle({
      barWidth: { smallWidth: REPLY_PILL_WIDTH, mediumWidth: REPLY_PILL_WIDTH, largeWidth: REPLY_PILL_WIDTH },
      barSideMargin: 0,
      barBottomMargin: 0,

      gradientMask: SPLIT_PILL_GRADIENT_MASK,
      thermoCtrl: true,
      systemMaterialEffect: materialManager.hdsEffectOf(MaterialSlot.BOTTOM_BAR)
    })

    .borderRadius(ACTION_PILL_RADIUS)
    .clip(true)
    .width(REPLY_PILL_WIDTH)
    .height(ACTION_PILL_HEIGHT)
  }

  @Builder
  SplitReplyTab() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.pencil_line'))
        .fontSize(22)
        .fontColor([AppTheme.TEXT_MAIN])
      Text('写评论')
        .fontSize(15)
        .fontColor(AppTheme.TEXT_MAIN)
    }

    .height('100%')

    .width('100%')

    .padding({ left: 14, right: REPLY_PILL_PADDING })
    .onClick(() => {
      this.openReplyBox(0);
    })
  }

  @Builder
  SplitImmersiveActionPill() {
    HdsTabs({ barPosition: BarPosition.End }) {
      TabContent() {
      }
      .tabBar(this.SplitActionTab())
    }
    .barHeight(ACTION_PILL_HEIGHT)
    .barMode(BarMode.Fixed)
    .scrollable(false)
    .animationDuration(0)
    .barOverlap(true)
    .barBackgroundColor(Color.Transparent)
    .barBackgroundBlurStyle(BlurStyle.NONE)

    .barFloatingStyle({
      barWidth: { smallWidth: ACTION_PILL_WIDTH, mediumWidth: ACTION_PILL_WIDTH, largeWidth: ACTION_PILL_WIDTH },
      barSideMargin: 0,
      barBottomMargin: 0,

      gradientMask: SPLIT_PILL_GRADIENT_MASK,
      thermoCtrl: true,
      systemMaterialEffect: materialManager.hdsEffectOf(MaterialSlot.BOTTOM_BAR)
    })

    .borderRadius(ACTION_PILL_RADIUS)
    .clip(true)
    .width(ACTION_PILL_WIDTH)
    .height(ACTION_PILL_HEIGHT)
  }

  @Builder
  SplitActionTab() {
    Row() {
      this.BottomReplyCount()
      this.BottomLikeAction()
      this.BottomStoreAction()
      this.BottomAction($r('sys.symbol.share'), '分享', (): void => { this.shareThread(); })
    }

    .height('100%')
    .padding({ left: ACTION_QUAD_PADDING, right: ACTION_QUAD_PADDING })
  }

  @Builder
  PopupMoreAnchor() {
    Column() {
      SymbolGlyph($r('sys.symbol.dot_grid_1x2'))
        .fontSize(22)
        .fontColor([AppTheme.TEXT_MAIN])
    }
    .width(44)
    .height(ACTION_PILL_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.popupMenuShow = !this.popupMenuShow;
    })
    .bindPopup(this.popupMenuShow, this.popupOptions())
  }

  @Builder
  PopupActionList() {
    Column({ space: 0 }) {
      this.PopupMenuItem($r('sys.symbol.message'), '评论', (): void => {
        this.popupMenuShow = false;
        this.scroller.scrollToIndex(1, true, ScrollAlign.START);
      });
      this.PopupMenuItem(this.mainLiked() ? $r('sys.symbol.hand_thumbsup_fill')
        : $r('sys.symbol.hand_thumbsup'), '点赞', (): void => {
        this.popupMenuShow = false;
        this.toggleMainLike();
      });
      this.PopupMenuItem(this.vm.collected ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'),
        this.vm.collected ? '已收藏' : '收藏', (): void => {
        this.popupMenuShow = false;
        this.toggleMainStore();
      });
      this.PopupMenuItem($r('sys.symbol.share'), '分享', (): void => {
        this.popupMenuShow = false;
        this.shareThread();
      });
    }
    .width(180)
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  PopupMenuItem(icon: Resource, label: string, onTap: () => void) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([AppTheme.TEXT_MAIN])
      Text(label)
        .fontSize(16)
        .fontColor(AppTheme.TEXT_MAIN)
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      onTap();
    })
  }

  private popupOptions(): CustomPopupOptions {
    return {
      builder: (): void => {
        this.PopupActionList();
      },
      placement: Placement.Top,
      enableArrow: false,
      autoCancel: true,
      systemMaterial: popupSystemMaterial(),
      onStateChange: (event: PopupStateChangeParam): void => {

        this.popupMenuShow = event.isVisible;
      }
    };
  }

  @Builder
  BottomActionBar() {
    if (threadActionBarStore.style === ThreadActionBarStyle.SPLIT_IMMERSIVE) {
      this.SplitImmersiveActionBar()
    } else {
      this.GlassActionBar()
    }
  }

  @Builder
  SplitImmersiveActionBar() {
    Row({ space: ACTION_PILL_GAP }) {

      Stack() {
        this.SplitImmersiveReplyPill()
      }
      .width(REPLY_PILL_WIDTH)
      .height(ACTION_PILL_HEIGHT)

      .borderRadius(ACTION_PILL_RADIUS)
      .shadow({ radius: 18, color: AppTheme.BOTTOM_FLOAT_SHADOW, offsetX: 0, offsetY: 6 })

      Stack() {
        this.SplitImmersiveActionPill()
      }
      .width(ACTION_PILL_WIDTH)
      .height(ACTION_PILL_HEIGHT)
      .borderRadius(ACTION_PILL_RADIUS)
      .shadow({ radius: 18, color: AppTheme.BOTTOM_FLOAT_SHADOW, offsetX: 0, offsetY: 6 })
    }
    .width('100%')
    .padding({
      left: BOTTOM_BAR_SIDE_MARGIN,
      right: BOTTOM_BAR_SIDE_MARGIN,
      bottom: BOTTOM_BAR_BOTTOM_MARGIN
    })
  }

  @Builder
  GlassActionBar() {
    Row({ space: ACTION_PILL_GAP }) {
      this.ClassicGlassReplyPill()
      this.GlassActionCapsule()
    }
    .width('100%')
    .padding({
      left: BOTTOM_BAR_SIDE_MARGIN,
      right: BOTTOM_BAR_SIDE_MARGIN,
      bottom: BOTTOM_BAR_BOTTOM_MARGIN
    })
  }

  @Builder
  BottomLikeAction() {
    Column({ space: 1 }) {
      SymbolGlyph(this.mainLiked() ? $r('sys.symbol.hand_thumbsup_fill')
        : $r('sys.symbol.hand_thumbsup'))
        .fontSize(22)
        .fontColor([this.mainLiked() ? AppTheme.ACCENT : AppTheme.TEXT_MAIN])
      Text(this.mainLikeCount() > 0 ? `${this.mainLikeCount()}` : '点赞')
        .fontSize(10)
        .fontColor(this.mainLiked() ? AppTheme.ACCENT : AppTheme.TEXT_SUB)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.toggleMainLike();
    })
  }

  private mainLiked(): boolean {
    const main: PostItem | undefined = this.vm.mainPost();
    return main === undefined ? false : this.vm.isLiked(main);
  }

  private mainLikeCount(): number {
    const main: PostItem | undefined = this.vm.mainPost();
    return main === undefined ? 0 : this.vm.agreeCountOf(main);
  }

  @Builder
  BottomStoreAction() {
    Column({ space: 1 }) {
      SymbolGlyph(this.vm.collected ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
        .fontSize(22)
        .fontColor([this.vm.collected ? AppTheme.ACCENT : AppTheme.TEXT_MAIN])
      Text(this.vm.collected ? '已收藏' : '收藏')
        .fontSize(10)
        .fontColor(AppTheme.COMMENT_ACTION)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.toggleMainStore();
    })
  }

  private toggleMainStore(): void {
    this.vm.toggleStore(this.hostContext()).then((reason: string) => {
      if (reason.length > 0) {
        promptAction.showToast({ message: reason, duration: 1800 });
      }
    });
  }

  @Builder
  BottomReplyCount() {
    Column({ space: 1 }) {

      SymbolGlyph($r('sys.symbol.message'))
        .fontSize(22)
        .fontColor([AppTheme.TEXT_MAIN])
      Text(`${this.displayedReplyCount()}`)
        .fontSize(10)
        .fontColor(AppTheme.TEXT_SUB)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {

      this.scroller.scrollToIndex(1, true, ScrollAlign.START);
    })
  }

  @Builder
  BottomAction(icon: Resource, label: string, onTap: () => void) {
    Column({ space: 1 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([AppTheme.TEXT_MAIN])
      Text(label)
        .fontSize(10)
        .fontColor(AppTheme.TEXT_SUB)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  Footer() {
    Column({ space: 8 }) {
      if (this.vm.errorText.length > 0) {
        Text(this.vm.errorText)
          .fontSize(12)
          .fontColor(AppTheme.ERROR)
          .textAlign(TextAlign.Center)
        Text('重试')
          .fontSize(13)
          .fontColor(AppTheme.ACCENT_DARK)
          .onClick(() => {
            this.vm.loadMore(this.hostContext());
          })
      } else if (this.vm.isSwitchingSort) {
        Text('正在切换回复…')
          .fontSize(12)
          .fontColor(AppTheme.TEXT_SUB)
      } else if (this.vm.isLoadingMore) {
        Text('正在加载…')
          .fontSize(12)
          .fontColor(AppTheme.TEXT_SUB)
      } else if (this.vm.focusedReplyPid > 0) {
        Text('当前显示定位回复 · 查看全部回复')
          .fontSize(13)
          .fontColor(AppTheme.ACCENT_DARK)
          .onClick(() => {
            this.vm.load(this.hostContext(), this.vm.tid).then(() => {
              this.scroller.scrollToIndex(1, true, ScrollAlign.START);
            });
          })
      } else if (this.vm.hasMore) {
        Text('上拉加载更多')
          .fontSize(12)
          .fontColor(AppTheme.TEXT_SUB)
      } else if (this.vm.posts.length > 0) {
        Text('已经到底了')
          .fontSize(12)
          .fontColor(AppTheme.TEXT_SUB)
      }
    }
    .width('100%')
    .padding({ top: 18, bottom: 88 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  StatusView(text: string) {
    Column() {
      Text(text)
        .fontSize(14)
        .fontColor(AppTheme.TEXT_SUB)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  ErrorView() {
    Column({ space: 10 }) {
      Text('加载失败')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_MAIN)
      Text(this.vm.errorText)
        .fontSize(13)
        .fontColor(AppTheme.TEXT_SUB)
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
      Text('重试')
        .fontSize(14)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .width(96)
        .height(38)
        .borderRadius(19)
        .backgroundColor(AppTheme.ACCENT)
        .onClick(() => {
          this.vm.load(this.hostContext(), this.vm.tid);
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }
}
