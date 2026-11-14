import { EmojiPickerPanel } from '../components/EmojiPickerPanel';
import { emojiPanelHeight as sharedEmojiPanelHeight, emojiPanelGridHeight,
  emojiPanelDialogOptions } from '../components/EmojiPanelDialog';
import { CloseIcon } from '../components/CloseIcon';
import { VisualThemeStore, visualThemeStore } from '../common/appearance/VisualThemeStore';
import { TaggedThreadText } from '../components/TaggedThreadText';
import { PaperLayout } from '../common/appearance/VisualTheme';
import { PageState, ListFooter } from '../components/PageState';
import { ThemeModeStore, themeModeStore } from '../common/appearance/ThemeModeStore';
import { ForumLevelBadge } from '../components/ForumLevelBadge';
import { forumLevelStore } from '../common/appearance/ForumLevelStore';
import { PullRefreshHeader, PULL_REFRESH_OFFSET } from '../components/RefreshSpinner';
import { FollowButton } from '../components/FollowButton';
import { commentText, postCommentTarget, subCommentTarget } from '../model/CommentAction';
/**
 * 帖子详情页。
 *
 * 页面只负责展示与发起已有的阅读动作：详情分页、楼中楼分页、排序筛选（正序/倒序/楼主）、
 * 跳层、回顶和图片查看器均继续交给 ThreadDetailVM；写评论走已有回复链路，分享调用华为官方面板，
 * 点赞走 VM 的"乐观更新 + 服务端写接口"，收藏走 `toggleStore`（addstore/rmstore），
 * 未登录时如实提示而不是伪造成成功。
 */

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

import { FrameCallback, LengthMetrics, promptAction, UIUtils, window, display } from '@kit.ArkUI';

import { HdsNavDestination, ScrollEffectType } from '@kit.UIDesignKit';
import {
  ContentBlock, ContentImage, ContentKind, ContentPiece, PostItem, ReplySortType, SubPostItem, UserBrief,
  REPLY_EMOTICON_CODES, collectPreviewImageUrls, emojiCodeFromReplyToken, emojiImageUrl,
  forumChipText, groupContentBlocks,
  isReplySortSupported, resolveForumName, subPostsHaveThreadAuthor, unsupportedSortTip
} from '../model/ThreadDetail';
import { formatTimeText } from '../model/TimeText';
import { emojiSrc } from '../common/emoji/EmojiSrc';
import { POST_BODY_SIZE, POST_NICKNAME_SIZE, POST_TITLE_SIZE,
  COMMENT_BODY_SIZE, COMMENT_NICKNAME_SIZE, SUB_REPLY_BODY_SIZE, SUB_REPLY_LINE_HEIGHT } from '../common/appearance/PostTypography';
import { MemePicItem } from '../model/MemeEmoji';
import { ThreadDetailVM } from '../viewmodel/ThreadDetailVM';
import { AgreeState } from '../viewmodel/AgreeActionVM';
import { MyListVM } from '../viewmodel/MyListVM';
import { ReplyImagesVM } from '../viewmodel/ReplyImagesVM';
import { UploadedPostImage } from '../model/ImageUpload';
import { ReplyEditorContent } from '../model/ReplyEditor';
import { readEmojiEditor, updateEmojiEditorTextColor } from '../utils/EmojiEditor';
import { ERRNO_THREAD_DELETED } from '../api/TiebaApi';
import { AgreeObjType } from '../net/TiebaParams';
import { ImageViewer } from '../components/ImageViewer';
import { ImageTransitionGallery, closeImageTransition } from '../components/ImageTransition';
import { ImageTransitionGalleryScope } from '../components/ImageTransitionGalleryScope';
import { GlassBackButton } from '../components/GlassBackButton';
import { GlassMoreButton } from '../components/GlassMoreButton';
import { ThreadPopupButton } from '../components/ThreadPopupButton';
import { GlassCircleButton } from '../components/GlassCircleButton';
import { THREAD_ACTION_BUTTON_SIZE, floatingButtonHitRegion } from '../model/SmartReach';
import { PostImageGallery } from '../components/PostImageGallery';
import { PostImageFlow } from '../components/PostImageFlow';
import { readingViewerIndex } from '../model/PostImageLayout';
import { ImageLayoutMode } from '../model/ImageLayout';
import { ImageLayoutStore, imageLayoutStore } from '../common/appearance/ImageLayoutStore';
import { ReplyItem } from '../components/ReplyItem';
import { ModernThreadPreviewImage } from '../components/ThreadPreviewImages';
import {
  modernFeedColumns, modernFeedGapForColumns, modernFeedPreviewIndices
} from '../model/FeedImageLayout';
import { AvatarComponent } from '../components/AvatarComponent';
import { ForumAvatarImage, forumAvatarRadius } from '../components/ForumAvatarImage';
import { ThreadAuthorBadge } from '../components/ThreadAuthorBadge';
import { ThreadBawuBadge } from '../components/ThreadBawuBadge';
import { SubReplyDetailSheet } from '../components/SubReplyDetailSheet';
import { AppTheme as BrandTheme, DetailTheme as AppTheme } from '../theme/Theme';
import { STATUS_BAR_FALLBACK_VP, readStatusBarVp } from '../utils/SafeArea';
import { materialManager } from '../common/material/MaterialManager';
import { MotionEffect } from '../common/appearance/MotionConfig';
import { motionStore } from '../common/appearance/MotionStore';
import { motionDuration, motionTransition, motionContentCover, popupMotion } from '../common/appearance/MotionPolicy';
import { MaterialTabs } from '../components/MaterialTabs';
import { MaterialSlot } from '../common/material/MaterialConfig';
// 底部操作栏样式：设置页「鸿蒙特性设置」可切，`@Trace` 下一帧生效。
import { ThreadActionBarStyle } from '../common/appearance/ThreadActionBarStyle';
import { threadActionBarStore } from '../common/appearance/ThreadActionBarStore';
import { NavigationService, ThreadDetailParams } from '../navigation/AppNavigation';

/**
 * 正文行内表情的边长（vp）。
 *
 * 正文字号 15、行高 24，表情取 21 视觉上与汉字等高略大，且小于行高，
 * 不会把所在行撑高（撑高会让含表情的行与纯文字行不一致，行距看着一跳一跳）。
 */
const BODY_EMOJI_SIZE: number = 21;

/** 帖子页底栏支持分离式与弹出式，切换时复用点赞、收藏和回复状态。 */

/** 帖子操作胶囊内容高（vp），独立于主界面导航底栏。 */
const ACTION_PILL_HEIGHT: number = 52;
/** 左胶囊宽（vp）：现网「回复楼主…」实测 501px ÷ 3.5 */
const REPLY_PILL_WIDTH: number = 143;
/** 右胶囊宽（vp）：现网四操作大胶囊实测 690px ÷ 3.5 */
const ACTION_PILL_WIDTH: number = 197;
/** 两胶囊间距（vp）；143 + 8 + 197 = 348 = 屏宽 − 左右各 14vp，正好填满一行 */
const ACTION_PILL_GAP: number = 8;
/** 胶囊圆角（vp）= 高度的一半 */
const ACTION_PILL_RADIUS: number = 26;
/** 左胶囊左右内边距（vp） */
const REPLY_PILL_PADDING: number = 17;
/** 右胶囊内四操作的左右内边距（vp） */
const ACTION_QUAD_PADDING: number = 8;
/** 底部行距屏幕两侧 / 屏底的边距（vp） */
const BOTTOM_BAR_SIDE_MARGIN: number = 14;
const BOTTOM_BAR_BOTTOM_MARGIN: number = 24;

/** 弹窗左右外边距（vp）：与顶栏「更多」按钮外侧 padding(12) 同值 */
const REPLY_SHEET_SIDE_MARGIN: number = 12;
/** 弹窗距键盘 / 屏底的间距（vp） */
const REPLY_SHEET_BOTTOM_GAP: number = 8;
/** 弹窗圆角（vp） */
const REPLY_SHEET_RADIUS: number = 16;
/** 输入框最小高度（vp）= 两行（lineHeight 22 × 2）+ 上下内边距 16 */
const REPLY_INPUT_MIN_H: number = 60;
/** 工具行四个入口的间距（vp）：参考图量得相邻图标**中心距** 184px ÷ 3.5 ≈ 52，
 * 图标盒 32 → 间隙 = 52 − 32 = 20。写成间隙而不是中心距，否则加上「发布」会放不下 */
const REPLY_TOOL_GAP: number = 20;
/** 「发布」按钮尺寸（vp）。参考图量宽 ≈112、高 ≈18；高度按可点性抬到 32（18vp 点不中） */
const REPLY_PUBLISH_W: number = 92;
const REPLY_PUBLISH_H: number = 32;
/** 输入框内嵌表情的 ImageSpan 尺寸（vp）：≈15 号字两倍行高，与文本基线自然对齐 */
const REPLY_EMOJI_INLINE: number = 22;

const REPLY_EMOTICON_QUICK_CODES: number[] = REPLY_EMOTICON_CODES.slice(0, 7);
/** 常用表情行图标的显示边长（vp）：参考图量得 ≈62px ÷ 3.5 ≈ 18 → 取整 28 保可点性 */
const REPLY_QUICK_EMOJI_SIZE: number = 28;

/** 键盘避让模式在输入卡片与键盘顶之间留下的实测距离。 */
const REPLY_INPUT_PANEL_GAP: number = 16;
/** 面板升降动画：跟手且避免键盘收起后长时间留白。 */
const REPLY_PANEL_TRANSITION_MS: number = 220;

function replyImageSize(image: UploadedPostImage): [number, number] {
  const scale: number = Math.min(160 / image.width, 112 / image.height);
  return [Math.max(1, Math.floor(image.width * scale)), Math.max(1, Math.floor(image.height * scale))];
}

/**
 * 单条回复的最大字数。
 *
 * 贴吧网页端的限制也是数百字这个量级；这里**先在输入阶段截断**并给出计数，
 * 比写满一篇才发现被服务端拒要好。服务端另有自己的限制（未实测），
 * 真被拒时 VM 会把服务端给的原因原样透出来。
 */
const REPLY_MAX_LENGTH: number = 500;

/**
 * 弹出菜单的系统材质经SHEET槽位读取厚度设置，跟随系统时默认THICK。
 *
 * ★ `systemMaterial` 是 **popup 选项里的字段**，不是组件属性 —— 这是一条独立的官方通道
 * （`PopupCommonOptions.systemMaterial`，@since 26.0.0）。普通组件那条
 * `CommonMethod.systemMaterial` 在本机真机上是空操作（TD-12），**这条不是**。
 * 真机对照（同一弹层、材质开 / 关两组帧）：等效 α 从 ≈0.98 掉到 ≈0.90 ——
 * 选项确实被系统接受并生效，但只到"弱玻璃"（无折射 / 高光 / 边缘光学）。
 */

class ThreadCommentsFrame extends FrameCallback {
  private ready: () => void;
  constructor(ready: () => void) { super(); this.ready = ready; }
  onIdle(_timeLeft: number): void { this.ready(); }
}

@ComponentV2
export struct ThreadDetailPage {
  private commentsJumpPending: boolean = false;
  private commentsFramePending: boolean = false;
  private commentsActive: boolean = false;
  @Local pullRefreshDragging: boolean = false;

  @Param routeParams: ThreadDetailParams | undefined = undefined;

  @Local vm: ThreadDetailVM = new ThreadDetailVM();
  /** 从列表进入时，以列表页已经归一化的回复数为准；直接打开详情时为 -1 */
  @Local sourceReplyCount: number = -1;
  /** 正在全屏查看的图片地址。空串表示查看器未挂载 */
  @Local viewerUrl: string = '';
  /** 正在预览的同一楼层图片集合与初始位置 */
  @Local viewerUrls: string[] = [];
  @Local viewerIndex: number = 0;
  // 标题栏单独控制：恢复材质必须先于图片关闭动画同步落地。
  @Local viewerHidesTitleBar: boolean = false;
  /** 下拉刷新状态 */
  @Local refreshing: boolean = false;
  /** 非零表示正在展开该一级回复的全屏回复详情面板 */
  @Local subDetailPid: number = 0;
  /** 回复详情面板是否可见。内容层关闭后要在 onDisappear 里同步回落 */
  @Local showSubSheet: boolean = false;
  private pendingUser: UserBrief | undefined = undefined;
  /**
   * 底部操作栏「弹出式」样式的操作菜单可见性。
   *
   * `bindPopup` 的 `show` 参数在新 SDK 里是**单向**的（不是 `$$`），
   * 点外部 / 按系统 Back 关闭时系统不会回写状态，必须用 `onStateChange` 自己同步，
   * 否则开关停在 true、下次再点不再弹出。
   */
  @Local popupMenuShow: boolean = false;
  @Local popupViewportWidth: number = 0;
  @Local popupViewportHeight: number = 0;
  @Local pageVisible: boolean = true;

  /**
   * 底部系统手势区（导航条）高度，单位 vp。
   *
   * 由官方避让区接口在运行时读出，**不写死** —— `bottom = 34` 这类常量在换机型、
   * 或用户从手势导航切成三键导航后必然错位。取不到时保持 0，由使用方用视觉间距兜底。
   */
  @Local safeBottomVp: number = 0;

  @Local keyboardVp: number = 0;
  /** 最近一次真实键盘高度；键盘收起后仍用于表情面板和输入卡片的等高定位。 */
  @Local lastKeyboardVp: number = 0;
  /** 键盘避让监听的窗口与回调引用（`aboutToDisappear` 注销用；未注册时为 null） */
  private avoidWin: window.Window | null = null;
  private keyboardWatchSeq: number = 0;
  private keyboardAreaCb: ((data: window.AvoidAreaOptions) => void) | null = null;

  @Local statusBarH: number = STATUS_BAR_FALLBACK_VP;

  @Local titleBarH: number = STATUS_BAR_FALLBACK_VP + 52;
  /** 跳层弹层是否可见 */
  @Local showJump: boolean = false;
  /** 跳层输入框内容 */
  @Local jumpText: string = '';

  @Local showReply: boolean = false;

  @Local screenWvp: number = 0;
  /** 屏幕密度（px/vp），方阵瓦片按源图原始像素计算解码预算用 */
  private screenDensity: number = 1;
  /** 回复弹窗句柄；0 表示未打开。页面销毁时关闭弹窗，避免其生命周期超出页面。 */
  private replyDialogId: number = 0;
  /** 表情态卡片使用固定屏幕位置，不随输入法开合移动。 */
  private replyCardPinned: boolean = false;
  /** 替换弹窗尚未打开完成时阻止第二次替换。 */
  private replyCardSwitching: boolean = false;
  /** 从表情面板点输入框后，等待键盘升起期间不把卡片落回屏底。 */
  private replyAwaitKeyboard: boolean = false;

  private dismissVetoUntilMs: number = 0;
  /** 打开代次（序号守卫，见 `openReplyDialog`）：每次打开/关闭自增，作废在途回调 */
  private replyDialogSeq: number = 0;

  private emojiDialogId: number = 0;
  private emojiDialogOpening: boolean = false;
  /** 面板弹窗的代次守卫（同 `replyDialogSeq` 的道理） */
  private emojiDialogSeq: number = 0;
  /**
   * 回复内容的**纯文本镜像**（RichEditor 化后）：表情以 token 形态（`#25`）
   * 计入，由 `syncReplyMirror()` 在每次内容变化后从 RichEditor 提取刷新；
   * 只喂字数计数与提交校验，不回写输入框。
   */
  @Local replyText: string = '';
  @Local replyImages: ReplyImagesVM = new ReplyImagesVM();
  private replyEditEpoch: number = 0;
  private rebuildingReply: boolean = false;
  private videoFullscreen: boolean = false;
  @Local videoMode: boolean = false;
  @Local videoComments: boolean = false;
  /**
   * 回复目标楼层 pid：**0 = 对主帖发表一级评论**，>0 = 回复某一层楼。
   * 子评论再由 replyTargetSubPost 指定，三种入口共用编辑器。
   */
  @Local replyTargetPid: number = 0;
  /** 回复目标的作者昵称，资料暂不可用时作为提示行回退。 */
  @Local replyTargetName: string = '';
  /** 回复某条楼中楼时，独立保留子评论；replyTargetPid 仍指所属父楼层。 */
  @Local replyTargetSubPost: SubPostItem | undefined = undefined;

  @Local showEmojiPanel: boolean = false;

  @Local emojiTab: number = 0;

  richCtl: RichEditorController = new RichEditorController();
  private replyEditorReady: boolean = false;
  @Local visualSettings: VisualThemeStore = visualThemeStore;
  @Local themeSettings: ThemeModeStore = themeModeStore;

  @Monitor('visualSettings.theme', 'themeSettings.isDark')
  refreshReplyEditorColors(): void {
    if (!this.replyEditorReady || this.rebuildingReply) { return; }
    this.richCtl.setTypingStyle({ fontColor: AppTheme.TEXT_MAIN });
    updateEmojiEditorTextColor(this.richCtl, AppTheme.TEXT_MAIN);
  }
  /** 顶部更多菜单是否可见 */
  @Local showMore: boolean = false;
  private deleteConfirming: boolean = false;
  /** 列表滚动位置（vp），由 onDidScroll 回报；标题栏渐变由原生导航负责。 */
  @Local navScrollOffset: number = 0;
  /** 回顶与跳层都走 scrollToIndex，不自己估算像素偏移；统一入口见 `jumpToTop`/`jumpToReplies`/`jumpToPost` */
  private scroller: ListScroller = new ListScroller();
  /** 自动补页的探测定时器；-1 表示当前没有排队中的探测 */
  private atEndProbeTimer: number = -1;

  /**
   * 楼层列表变化后补一次"是否已停在末尾"的探测。
   *
   * 每页 10 层时，第一页有可能撑不满一屏，这时 List 不会触发 `onReachEnd`，
   * 界面就停在底部不动了。数据落地后量一次滚动位置：确实在末尾且还有下一页，
   * 就继续请求。用户还能往下滚时不动——请求时机仍然是"滑到底部"。
   */
  @Monitor('vm.visiblePosts', 'vm.hasMore')
  onReplyListChanged(): void {
    this.loadNextPageIfAtEnd();
  }

  private loadNextPageIfAtEnd(): void {
    if (this.atEndProbeTimer >= 0 || !this.vm.hasMore || this.vm.isLoadingMore || this.vm.loading ||
      this.vm.isRefreshing || this.vm.isSwitchingSort) {
      return;
    }
    // 新楼层要等这一帧布局算完高度，否则量到的还是上一帧的位置
    this.atEndProbeTimer = setTimeout((): void => {
      this.atEndProbeTimer = -1;
      if (!this.vm.hasMore || this.vm.isLoadingMore || this.vm.loading || this.vm.isRefreshing ||
        this.vm.isSwitchingSort) {
        return;
      }
      // 滚动器还没绑定到列表时会抛异常，这一帧就不判断了，等下一次数据变化
      let atEnd: boolean = false;
      try {
        atEnd = this.scroller.isAtEnd();
      } catch (err) {
        return;
      }
      if (atEnd) {
        void this.vm.loadMore(this.hostContext());
      }
    }, 120);
  }

  @Local imageLayout: ImageLayoutStore = imageLayoutStore;
  /** 仅记当前内容的横向图集页码；弱键不延长已移除正文的生命周期。 */
  private galleryPages: WeakMap<ContentPiece[], Map<number, number>> = new WeakMap<ContentPiece[], Map<number, number>>();

  private goBack(): void {
    NavigationService.back();
  }

  /** 确认时绑定当前账号和内容代次，等待期间离页或换账号由 VM 拒绝旧操作。 */
  private async confirmDeleteThread(): Promise<void> {
    if (this.deleteConfirming || this.vm.deletePending || !this.vm.canDeleteThread()) { return; }
    const owner: string = this.vm.deletionOwner();
    const tid: number = this.vm.tid;
    this.showMore = false;
    this.deleteConfirming = true;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '删除帖子',
        message: '确定删除这条帖子？帖子及其评论将无法恢复。',
        buttons: [{ text: '取消', color: BrandTheme.TEXT_SUB },
          { text: '删除', color: BrandTheme.DANGER_TEXT }]
      });
      if (result.index !== 1 || !this.commentsActive) { return; }
      const message: string = await this.vm.deleteThread(this.hostContext(), owner);
      if (!this.commentsActive) { return; }
      if (message.length > 0) {
        this.getUIContext().getPromptAction().showToast({ message });
      } else if (this.vm.threadDeleted) {
        await MyListVM.markDeleted(this.hostContext(), tid).catch((): void => {});
        if (!this.commentsActive) { return; }
        this.getUIContext().getPromptAction().showToast({ message: '帖子已删除' });
        this.goBack();
      }
    } catch (_) {
      // 关闭确认框不发请求，接口失败由 VM 提供真实结果。
    } finally { this.deleteConfirming = false; }
  }

  private async confirmDeleteComment(post: PostItem, sub?: SubPostItem): Promise<void> {
    if (this.deleteConfirming || this.vm.deletePending ||
      !(sub === undefined ? this.vm.canDeletePost(post) : this.vm.canDeleteSubPost(post.pid, sub))) { return; }
    const owner: string = this.vm.deletionOwner();
    this.deleteConfirming = true;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '删除评论',
        message: sub === undefined && post.subPostCount > 0
          ? '确定删除这条评论及其楼中楼回复？删除后无法恢复。' : '确定删除这条评论？删除后无法恢复。',
        buttons: [{ text: '取消', color: BrandTheme.TEXT_SUB },
          { text: '删除', color: BrandTheme.DANGER_TEXT }]
      });
      if (result.index !== 1 || !this.commentsActive) { return; }
      const message: string = sub === undefined
        ? await this.vm.deletePost(this.hostContext(), post, owner)
        : await this.vm.deleteSubPost(this.hostContext(), post.pid, sub, owner);
      if (!this.commentsActive) { return; }
      if (message.length > 0) {
        this.getUIContext().getPromptAction().showToast({ message });
        return;
      }
      this.sourceReplyCount = -1;
      if (sub === undefined && this.subDetailPid === post.pid) { this.closeSubSheet(); }
      this.getUIContext().getPromptAction().showToast({ message: '评论已删除' });
    } catch (_) {
      // 取消确认不改变评论；请求异常由 VM 处理。
    } finally { this.deleteConfirming = false; }
  }

  private prepareImageClose(): void {
    // V2 状态普通赋值可能与随后的 animateTo 合批，用同步刷新隔离标题栏恢复。
    UIUtils.applySync((): void => { this.viewerHidesTitleBar = false; });
  }

  private clearImagePreview(): void {
    this.viewerUrl = '';
    this.viewerUrls = [];
    this.viewerIndex = 0;
    this.viewerHidesTitleBar = false;
  }

  private handleSystemBack(): boolean {
    if (this.popupMenuShow) { this.popupMenuShow = false; return true; }
    if (this.showJump) { this.showJump = false; return true; }
    if (this.viewerUrl.length > 0 || this.viewerUrls.length > 0) {
      closeImageTransition(this.getUIContext(), (): void => {
        this.clearImagePreview();
      }, (): void => { this.prepareImageClose(); });
      return true;
    }
    if (this.videoMode && this.videoComments) { this.videoComments = false; return true; }
    return false;
  }

  aboutToAppear(): void {
    this.commentsActive = true;
    this.commentsJumpPending = this.routeParams?.openComments === true;
    this.videoMode = this.routeParams?.videoMode === true;

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
      this.requestCommentsJump();
      if (targetPid > 0 && this.vm.errorText.length === 0) {
        const index: number = this.vm.visiblePosts.findIndex((post: PostItem) => post.pid === targetPid);
        if (index >= 0) {
          this.getUIContext().runScopedTask(() => {
            setTimeout(() => {
              this.jumpToPost(index);
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
      if (this.vm.errorText.length > 0 || !this.vm.loadedOnce) { return; }
      // 封面 = 首楼第一张图的展示地址（列表卡片右侧要用）；没有图就存空串
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
        // 标题与吧名都没有 → 这个帖子在服务端已经不存在，历史里就标成已删除
        this.vm.detail.title.length === 0 && forumName.length === 0,
        this.vm.detail.forumId);
    }).catch(() => {
      // 加载失败不记历史，也不打断页面
    });

    this.readSafeArea();
    this.readStatusBar();
  }

  private requestCommentsJump(): void {
    if (!this.commentsJumpPending || !this.commentsActive || this.commentsFramePending ||
      this.vm.loading || !this.vm.loadedOnce || this.vm.errorText.length > 0) { return; }
    this.commentsFramePending = true;
    this.getUIContext().postFrameCallback(new ThreadCommentsFrame((): void => {
      this.commentsFramePending = false;
      if (!this.commentsActive || !this.commentsJumpPending || this.vm.loading || this.vm.errorText.length > 0) { return; }
      this.commentsJumpPending = false;
      if (this.videoMode) { this.videoComments = true; }
      else { this.jumpToReplies(false); }
    }));
  }

  /** 滚动动画跟随设置里的「动画效果」。 */
  private scrollAnimate(): boolean {
    return motionStore.isOn(MotionEffect.MOVE);
  }

  private jumpToTop(): void {
    this.scroller.scrollToIndex(0, this.scrollAnimate(), ScrollAlign.START);
  }

  /**
   * 滚到楼层区第 1 楼。
   *
   * 列表结构（见 `PostList`）：下标 0 是主帖、1 是回复摘要、2 起才是楼层，所以「回复区」
   * 的锚点固定是 2；一条楼层都没有时退化为回顶，避免滚到空提示或 Footer 上。
   */
  private jumpToReplies(animate: boolean = this.scrollAnimate()): void {
    this.scroller.scrollToIndex(this.vm.visiblePosts.length > 0 ? 2 : 0, animate, ScrollAlign.START);
  }

  /**
   * 按 `visiblePosts` 的下标定位精确到某一楼（0 = 主帖）。
   *
   * 楼层 2026-10-18 起不再挂在 `ListItemGroup` 里，而是与主帖、摘要条平铺在同一个 List 下，
   * 所以只能用 `scrollToIndex`。`visibleReplies = visiblePosts.slice(1)`，第 i 个帖子在列表
   * 里的下标是 `i + 1`（原实现调 `scrollToItemInGroup(2, i - 1)`，找不到分组、静默不滚动）。
   */
  private jumpToPost(index: number): void {
    if (index <= 0) {
      this.jumpToTop();
      return;
    }
    this.scroller.scrollToIndex(index + 1, this.scrollAnimate(), ScrollAlign.START);
  }

  aboutToDisappear(): void {
    ++this.keyboardWatchSeq;
    this.commentsActive = false;
    // 离页后不再补页：探测回调哪怕排上了队也一并撤掉
    if (this.atEndProbeTimer >= 0) {
      clearTimeout(this.atEndProbeTimer);
      this.atEndProbeTimer = -1;
    }
    this.galleryPages = new WeakMap<ContentPiece[], Map<number, number>>();
    this.vm.dispose();
    void voicePlayback.stop();
    this.videoFullscreen = false;

    this.closeReplyBox();
    this.replyImages.dispose();

    if (this.avoidWin !== null && this.keyboardAreaCb !== null) {
      try {
        this.avoidWin.off('avoidAreaChange', this.keyboardAreaCb);
      } catch (err) {
        // 窗口可能已随页面释放，静默兜底
      }
      this.avoidWin = null;
      this.keyboardAreaCb = null;
    }
  }

  /**
   * 读状态栏高度（vp），供页头让位。
   *
   * 与 `readSafeArea` 分开是因为用途不同：那个管底部手势区（弹层用），
   * 这个管顶部（页头用）。拿不到就保持兜底值，界面只偏差几像素，不打断加载。
   */
  private readStatusBar(): void {
    readStatusBarVp(this.hostContext()).then((vp: number) => {
      this.statusBarH = vp;
      // HDS titleBar 接管后顶栏悬浮层没了，onAreaChange 不再有回调来源；
      // 全高改由「状态栏 + 导航行 52」推导，供 PostList 顶部让位与 MoreMenu 定位。
      this.titleBarH = vp + 52;
    }).catch(() => {
      // 保持兜底值
    });
  }

  /**
   * 读取底部系统避让区高度，供弹层底部悬浮胶囊避让手势条。
   *
   * 用官方 `getWindowAvoidArea(TYPE_NAVIGATION_INDICATOR)`：返回值随系统配置变化，
   * 是"不写死"的正确做法。接口给的是 **px**，必须 `px2vp` 转成 vp 才能参与 ArkUI 布局
   * （设备是 2.63 倍密度，直接用 px 当 vp 会大出两倍多）。实测本机为 28vp。
   * 取不到时保持 0，弹层退化成纯视觉间距，不会把胶囊顶出屏幕。
   */
  private readSafeArea(): void {
    const seq: number = ++this.keyboardWatchSeq;
    try {
      window.getLastWindow(this.hostContext()).then((win: window.Window) => {
        if (seq !== this.keyboardWatchSeq) { return; }
        const area: window.AvoidArea =
          win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        this.safeBottomVp = px2vp(area.bottomRect.height);

        this.screenWvp = px2vp(win.getWindowProperties().windowRect.width);
        try {
          this.screenDensity = display.getDefaultDisplaySync().densityPixels;
        } catch (_) {
          // 密度拿不到就用 1：只影响瓦片解码预算的精度，不影响布局
        }

        this.keyboardAreaCb = (data: window.AvoidAreaOptions) => {
          if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
            this.keyboardVp = px2vp(data.area.bottomRect.height);
            if (this.keyboardVp > 0) {
              this.lastKeyboardVp = this.keyboardVp;
              this.replyAwaitKeyboard = false;
            }
            // 表情面板与键盘互斥（同一块屏下区域）：键盘弹起（用户点了输入框）
            // → 面板让位（独立弹窗一并关掉 + 输入卡片落回键盘档）；
            // 面板开着时点表情钮是收键盘（keyboardVp 归 0，不进这分支）
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
        // 拿不到就保持 0，弹层用兜底间距
      });
    } catch (err) {
      // 同上：静默兜底，不影响详情页其他功能
    }
  }

  /** 表情面板占据最近一次输入法占据的屏幕高度。 */
  private emojiPanelHeight(): number {
    return sharedEmojiPanelHeight(this.lastKeyboardVp);
  }

  /** 固定 tab 与内边距后，剩余高度全给两类可滚动表情格子。 */
  private emojiGridHeight(): number {
    return emojiPanelGridHeight(this.emojiPanelHeight());
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  /** 列表上下文存在时保持两页一致；直接进入详情时使用详情协议归一化结果。 */
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
    // 展示上限只由预览组件负责，页面不再提前丢弃第四、第五条。
    return this.vm.subState(item.pid).subPosts;
  }

  /** ForEach 同 pid 会复用原回调，数量必须读当前状态，不能取闭包里的旧楼层。 */
  private subPreviewCount(item: PostItem): number {
    const state = this.vm.subState(item.pid);
    if (state.loadedOnce) { return state.page.totalCount; }
    const current: PostItem | undefined = this.vm.postByPid(item.pid);
    return current === undefined ? item.subPostCount : current.subPostCount;
  }

  /** 楼中楼里是否出现过楼主回复。预览没加载出来时不猜，按"没有"处理 */
  private hasAuthorReply(item: PostItem): boolean {
    return subPostsHaveThreadAuthor(this.vm.subState(item.pid).subPosts);
  }

  /**
   * 打开某条一级回复的全屏回复详情面板。
   *
   * 面板里既要有锚点回复的完整内容，也要有完整回复列表，所以：
   *   1. 先记下 pid 并打开弹层——锚点卡立刻就有内容，不存在整页空白；
   *   2. 列表数据若还没加载过，补一次首屏请求（失败过则走重试），
   *      加载态只体现在列表区域。
   * `item` 为空表示从别处（如主帖展开区）按 pid 打开。
   */
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

  /** 按 pid 找已加载的楼层，用作面板顶部的锚点回复；找不到返回空对象（与 `vm.postByPid` 同源，不再自己扫一遍） */
  private anchorPost(pid: number): PostItem {
    return this.vm.postByPid(pid) ?? new PostItem();
  }

  /** 面板里列表区失败后的重试：首屏没过就重拉首屏，否则重试翻页 */
  private retrySubSheet(pid: number): void {
    const authorId: number = this.vm.detail.author.id;
    if (this.vm.subState(pid).loadedOnce) {
      this.vm.loadMoreSubPosts(this.hostContext(), pid, authorId);
    } else {
      this.vm.retrySubPosts(this.hostContext(), pid, authorId);
    }
  }

  /**
   * 点赞 / 取消点赞。
   *
   * 写接口需要登录态：未登录时 VM 直接返回"需要登录"，界面如实提示，不假装成功；
   * 已登录时走"乐观更新 → 调服务端 → 失败回滚"，失败文案由 VM 给出。
   *
   * `objType` 只影响发给服务端的 `obj_type`/`post_id`（协议目标），**不改界面**：
   * 楼层与楼中楼都是"对某一层 post 点赞"，主帖则要按"赞主题"发（`obj_type=3`、`post_id=0`）。
   */
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

  /** 楼中楼预览里的图片：只用单图打开查看器，不改动楼层图片集合 */
  private openPreviewImage(url: string): void {
    if (url.length === 0) {
      return;
    }
    this.viewerHidesTitleBar = true;
    this.viewerUrls = [url];
    this.viewerIndex = 0;
    this.viewerUrl = url;
  }

  private openReplyBox(pid: number, sub?: SubPostItem): void {
    if (this.vm.replyPending) { return; }
    this.replyEditEpoch++;
    this.replyImages.reset();
    this.replyTargetPid = pid > 0 ? pid : 0;
    this.replyTargetSubPost = sub;
    this.replyTargetName = sub !== undefined ? sub.author.displayName : pid > 0 ? this.authorNameOf(pid) : '';
    // RichEditor 是同一 controller 跨弹窗复用：先清掉上一次的图文残留
    this.richCtl.deleteSpans();
    this.replyText = '';
    // 表情面板回到收起态：上次展开的面板不带进下一次（参考图：打开即紧凑输入形态）
    this.showEmojiPanel = false;
    this.replyCardPinned = false;
    this.replyCardSwitching = false;
    this.replyAwaitKeyboard = false;
    this.closeEmojiPanelDialog(); // 防御：面板弹窗理论上随上一次回复一起关了
    this.showReply = true;
    this.openReplyDialog(false);
  }

  /** 打开回复弹窗。使用组件上下文创建内容，使本地状态变化能更新弹窗；句柄用于关闭和重复打开保护。 */
  private openReplyDialog(lifted: boolean, replacing: boolean = false): void {
    if (this.replyDialogId !== 0 && !replacing) {
      return; // 已开着（操作栏在 showReply 时隐藏，正常不会走到，防重入兜底）
    }
    if (this.replyCardSwitching) {
      return;
    }
    const oldId: number = replacing ? this.replyDialogId : 0;
    this.replyCardSwitching = replacing;
    let oldClosed: boolean = false;
    /*
     * 序号守卫：弹窗的消失回调是异步迟到的——「卡片交接 / 发送成功关窗」场景下，
     * 旧弹窗的 onDidDisappear 可能在新弹窗打开之后才触发，无守卫会把新弹窗的
     * 句柄和 showReply 一并误清。每次打开自增，回调只认自己那一代。
     */
    const seq: number = ++this.replyDialogSeq;
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: (): void => {
        this.ReplyDialog()
      },
      // 贴窗口底 + 上抬手势区：弹窗底边离屏幕底 = 8vp 视觉间距 + 手势条高度
      // （⚠️ offset 类型是 Offset{dx,dy}，bindPopup 是 Position{x,y}，相反！）
      alignment: DialogAlignment.Bottom,
      offset: {
        dx: 0,
        /*
         * 键盘态的卡片底边距屏底 = 实测键盘高度 + 系统默认的 16vp 避让距离。
         * 键盘收起后弹窗容器会重新让出手势区，故这里减去 safeBottomVp，
         * 让卡片在键盘和表情面板两态保持同一垂直位置。
         */
        dy: lifted
          ? -(this.emojiPanelHeight() + REPLY_INPUT_PANEL_GAP - this.safeBottomVp)
          : -(REPLY_SHEET_BOTTOM_GAP + this.safeBottomVp)
      },
      // 表情态卡片固定在键盘态的位置，键盘收起或重新弹起时不再跟随系统移动。
      keyboardAvoidMode: lifted ? KeyboardAvoidMode.NONE : KeyboardAvoidMode.DEFAULT,
      // 替换卡片时两张卡从同一位置交接；收面板时新卡随面板一起滑回屏底。
      dialogTransition: replacing ? (lifted ? TransitionEffect.IDENTITY
        : TransitionEffect.translate({ y: -this.emojiPanelHeight() })
          .animation({ duration: motionDuration(REPLY_PANEL_TRANSITION_MS) })) : popupMotion(),
      maskTransition: replacing ? TransitionEffect.IDENTITY : popupMotion(),
      autoCancel: true,

      width: this.screenWvp > 0 ? this.screenWvp - REPLY_SHEET_SIDE_MARGIN * 2 : 336,
      cornerRadius: REPLY_SHEET_RADIUS,

      systemMaterial: materialManager.officialOf(MaterialSlot.REPLY_SHEET),
      onWillAppear: (): void => {
        if (oldId !== 0 && !oldClosed && this.replyDialogSeq === seq) {
          oldClosed = true;
          try {
            this.getUIContext().getPromptAction().closeCustomDialog(oldId);
          } catch (err) {
            // 旧卡可能已被系统回收；新卡继续接替。
          }
        }
      },
      onDidAppear: (): void => {
        // 写评论入口都走首次打开；等编辑器进入弹窗节点树后再唤起输入法。
        // 卡片因表情面板切换而重建时不抢焦点。
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
        // 点蒙层 / Back / Esc 等系统关闭路径统一从这里放行并同步状态；
        // 面板还开着的话一并收掉（点空白 = 整组回复 UI 关闭，口径不变）
        action.dismiss();
        if (this.replyDialogSeq === seq) {
          this.showReply = false;
          this.replyEditEpoch++;
          this.replyImages.cancel();
          this.closeEmojiPanelDialog();
        }
      },
      onDidDisappear: (): void => {
        // 兜底同步：任何绕过 onWillDismiss 的消失路径也不留悬挂句柄
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
          // 旧卡可能已被系统回收。
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
      // 打开失败（页面已在销毁流程等）：回退语义状态，不留"看起来开着"的假象。
      // hilog 探针：新旧卡交接异常定位用
      hilog.error(0x0, 'ReplyFocus', 'openReplyDialog reject code=%{public}d msg=%{public}s',
        err.code ?? -1, String(err.message ?? ''));
      if (this.replyDialogSeq === seq) {
        this.replyCardSwitching = false;
        if (oldId !== 0 && !oldClosed) {
          try {
            this.getUIContext().getPromptAction().closeCustomDialog(oldId);
          } catch (closeErr) {
            // 旧卡可能已被系统回收。
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

  /** 关闭回复输入框。内容不清，误触出去还能回来接着写 */
  private closeReplyBox(): void {
    this.replyEditEpoch++;
    this.replyImages.cancel();
    if (this.replyDialogId !== 0) {
      try {
        this.getUIContext().getPromptAction().closeCustomDialog(this.replyDialogId);
      } catch (err) {
        // 弹窗可能已被系统回收，静默兜底
      }
      this.replyDialogId = 0;
    }
    // 序号自增 = 作废所有在途回调（迟到的 onDidDisappear 不再误清新弹窗状态）
    this.replyDialogSeq++;
    this.showReply = false;
    this.replyCardPinned = false;
    this.replyCardSwitching = false;
    this.replyAwaitKeyboard = false;

    this.closeEmojiPanelDialog();
  }

  /** 表情选择使用独立弹窗；回复框关闭时同步关闭，避免遗留面板。 */
  private openEmojiPanelDialog(): void {
    if (this.emojiDialogId !== 0 || this.emojiDialogOpening || !this.showReply || !this.showEmojiPanel) {
      return;
    }
    const seq: number = ++this.emojiDialogSeq;
    this.emojiDialogOpening = true;
    this.getUIContext().getPromptAction().openCustomDialog(emojiPanelDialogOptions(
      (): void => {
        this.EmojiSheet()
      },
      this.screenWvp, this.emojiPanelHeight(),
      (): void => {
        // Back 只收面板、不动输入卡片（对齐输入法面板的返回语义）；
        // 必须走 setEmojiPanel——除了关弹窗还要把输入卡片落回原位
        hilog.info(0x0, 'ReplyFocus', 'panel onWillDismiss');
        if (this.emojiDialogSeq === seq) {
          this.setEmojiPanel(false);
        }
      },
      (): void => {
        if (this.emojiDialogSeq === seq) {
          this.emojiDialogId = 0;
          this.emojiDialogOpening = false;
          ++this.emojiDialogSeq;
          this.showEmojiPanel = false;
        }
      }
    )).then((id: number) => {
      if (this.emojiDialogSeq !== seq || !this.showReply || !this.showEmojiPanel) {
        if (this.emojiDialogSeq === seq) {
          this.emojiDialogOpening = false;
          ++this.emojiDialogSeq;
        }
        try {
          this.getUIContext().getPromptAction().closeCustomDialog(id);
        } catch (err) {
          // 面板已由系统回收；迟到句柄不再写回当前代次。
        }
        return;
      }
      this.emojiDialogOpening = false;
      this.emojiDialogId = id;
    }).catch(() => {
      // 打开失败：走唯一入口回收——除状态外还要把已抬起的输入卡片落回
      if (this.emojiDialogSeq === seq) {
        this.emojiDialogOpening = false;
        this.setEmojiPanel(false);
      }
    });
  }

  /** 收表情面板弹窗并作废尚未返回的打开请求，不动 `showEmojiPanel` 语义态。 */
  private closeEmojiPanelDialog(): void {
    const id: number = this.emojiDialogId;
    ++this.emojiDialogSeq;
    this.emojiDialogOpening = false;
    this.emojiDialogId = 0;
    if (id === 0) { return; }
    try {
      this.getUIContext().getPromptAction().closeCustomDialog(id);
    } catch (err) {
      // 弹窗可能已被系统回收，静默兜底
    }
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
        // 点输入框时保留固定卡片；键盘从下方升起，卡片始终留在原位。
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

  /** 表情态工具按钮：收起表情面板并主动唤起输入法。 */
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

  /** 新卡先在旧卡位置接替，再关旧卡；避免先关后开造成的空白帧。 */
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
          // 收藏表情：#(meme,collect_...) —— 反查 VM 的 url→token 表
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
        // 普通文本：吃到下一个 '#'（没有就到串尾）
        let k: number = text.indexOf('#', i + 1);
        if (k < 0) {
          k = text.length;
        }
        this.richCtl.addTextSpan(text.substring(i, k), { style: { fontColor: AppTheme.TEXT_MAIN } });
        i = k;
      }
    } finally { this.rebuildingReply = false; }
    // 重建后镜像重算（幂等：结果应与原值一致；有漂移也以 spans 为准自愈）
    this.syncReplyMirror();
  }

  /**
   * 提交回复。
   *
   * 失败文案**由 VM 返回**（未登录 / 在途 / 缺少吧信息 / 服务端报错都在这里出），
   * 页面只负责展示——这样以后把 toast 换成行内提示不用动业务层。
   * 成功后保留阅读位置；主帖新评论由用户主动刷新查看。
   */
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
    const targetSubPost: SubPostItem | undefined = this.replyTargetSubPost;

    const tip: string = await this.vm.submitReply(this.hostContext(), text, targetPid,
      undefined, targetSubPost);
    if (editEpoch !== this.replyEditEpoch) { return; }
    if (tip.length > 0) {
      promptAction.showToast({ message: tip, duration: 2200 });
      return;
    }
    this.closeReplyBox();
    // 成功后清输入区：图文一起删（deleteSpans 不传参 = 全部），镜像归零
    this.richCtl.deleteSpans();
    this.replyText = '';
    this.replyImages.reset();
    if (targetPid > 0) {
      const visible: boolean = this.vm.subState(targetPid).subPosts.some(
        (sub: SubPostItem): boolean => sub.pid === this.vm.lastReplyPid);
      promptAction.showToast({ message: visible ? '回复已发布' : '回复已发布，可在本层回复里查看', duration: 2200 });
      return;
    }
    promptAction.showToast({ message: '评论已发布，可刷新查看', duration: 2200 });
  }

  /** 回复目标作者的昵称。找不到返回空串，占位文案退回通用的「发表评论」 */
  private authorNameOf(pid: number): string {
    const post: PostItem | undefined = this.vm.postByPid(pid);
    // `displayName` 是 name_show 优先的结果，与楼层里显示的名字同源
    return post === undefined ? '' : post.author.displayName;
  }

  /** 防止分享面板启动期间连续点击重复打开。 */
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

  /** 写接口尚未实现时的统一反馈，避免给出虚假的操作结果 */
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

  /**
   * 主帖作者名后的等级文案。
   *
   * 贴吧展示的是等级名（"高级粉丝""核心吧友"）而不是裸数字，所以 level_name 优先；
   * 服务端只给了数字时才退回 `Lv.N`；两者都没有就不显示徽章，不编一个 Lv.0。
   */
  private authorLevelText(): string {
    const author: UserBrief = this.vm.detail.author;
    if (author.levelName.length > 0) {
      return author.levelName;
    }
    return author.level > 0 ? `Lv.${author.level}` : '';
  }

  /**
   * 作者行第二行的 `时间 · 地区 · 内容声明`。
   *
   * 时间取 1 楼的发布时间（与列表、楼层同一套文案，见 `model/TimeText`），
   * 地区取作者 IP 归属地（`thread.author` 常缺这个字段，由 `mergeAuthorFallback`
   * 从 `user_list` 补齐），声明取 `thread.content_statement`（发帖时选的那一项，
   * 官方 App 也是把它接在时间、地区之后）。三段都缺返回空串——界面据此整行不渲染。
   */
  private authorMetaLine(): string {
    const parts: string[] = [];
    const time: string = this.mainPostTimeText();
    if (time.length > 0) {
      parts.push(time);
    }
    const region: string = this.vm.detail.author.ipLocation;
    if (region.length > 0) {
      parts.push(region);
    }
    // 没写内容声明的帖子这个字段是空串，不显示（不是所有帖子都有声明）
    const statement: string = this.vm.detail.contentStatement;
    if (statement.length > 0) {
      parts.push(statement);
    }
    return parts.join(' · ');
  }

  /** 主帖（1 楼）的发布时间文案；详情还没回来时为空串 */
  private mainPostTimeText(): string {
    const posts: PostItem[] = this.vm.visiblePosts;
    if (posts.length === 0) {
      return '';
    }
    return formatTimeText(posts[0].timeMs, Date.now());
  }

  /**
   * 导航层右侧三个图标的点击分发。
   *
   * 没有把回调当参数传进 `@Builder`：Builder 的参数是"按值"传入的，
   * 传函数引用在本项目里已有过崩溃先例（`@BuilderParam` 传方法引用），
   * 这里按 label 分发，逻辑一眼能看完，也不依赖编译器对函数参数的处理。
   */
  private onNavTap(label: string): void {
    if (label === '更多') {
      this.showMore = !this.showMore;
      return;
    }
    this.toastNotAvailable(label);
  }

  /** 跳到指定楼层号，只在当前已加载且可见的楼层中精确匹配 */
  private jumpToFloor(): void {
    const floor: number = Number.parseInt(this.jumpText.trim(), 10);
    if (!Number.isNaN(floor)) {
      const posts: PostItem[] = this.vm.visiblePosts;
      for (let i = 0; i < posts.length; i++) {
        if (posts[i].floor === floor) {
          this.jumpToPost(i);
          break;
        }
      }
    }
    this.showJump = false;
  }

  @Builder
  PullHeader() { PullRefreshHeader({ inset: this.titleBarH, active: this.refreshing || this.pullRefreshDragging }) }

  @Builder
  VideoRailAction(icon: Resource, label: string, selected: boolean, tap: () => void) {
    Column({ space: 4 }) {
      SymbolGlyph(icon).fontSize(30).fontColor([selected ? BrandTheme.MEDIA_ACCENT : Color.White])
      Text(label).fontSize(11).fontColor(Color.White).maxLines(1)
    }.width(48).height(62).justifyContent(FlexAlign.Center).onClick(tap)
  }
  @Builder
  VideoExperience() {
    Column() {
      Stack() {
        if (this.vm.detail.video !== undefined) {
          VideoPlayer({ video: this.vm.detail.video, stage: true, autoPlay: true,
            controlBottomGap: this.videoComments ? 0 : this.safeBottomVp })
        } else if (this.vm.loading) {
          Text('正在加载视频…').fontColor(Color.White)
        } else {
          Column({ space: 14 }) {
            Text(this.vm.errorText || '视频暂不可播放').fontColor(Color.White)
            Button('重试').fontColor(BrandTheme.ON_ACCENT).backgroundColor(AppTheme.ACCENT)
              .onClick(() => { void this.handleRefresh(); })
          }
        }
        if (!this.videoComments) {
          Column() {
            Row() {
              SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([Color.White])
                .width(44).height(44).onClick(() => { NavigationService.back(); })
              Row({ space: 8 }) {
                ForumAvatarImage({ url: this.vm.detail.forumAvatar, forumName: this.vm.forumNameHint,
                  avatarSize: 28, radius: forumAvatarRadius(28), onHero: true })
                Text(forumChipText(this.vm.detail.forumName, this.vm.forumNameHint)).fontSize(16).fontWeight(FontWeight.Medium)
                  .fontColor(Color.White).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.layoutWeight(1).justifyContent(FlexAlign.Center).onClick(() => { this.openForum(); })
              Blank().width(44)
            }.width('100%').padding({ top: this.statusBarH, left: 8, right: 8 })
              .linearGradient({ angle: 180, colors: [['#88000000', 0], ['#00000000', 1]] })
            Blank()
            Row({ space: 12 }) {
              Column({ space: 10 }) {
                Row({ space: 8 }) {
                  AvatarComponent({ url: this.vm.detail.author.portraitUrl, avatarSize: 32, fallbackName: this.vm.detail.author.displayName })
                  Text(this.vm.detail.author.displayName || '用户').fontSize(16).fontWeight(FontWeight.Medium)
                    .fontColor(Color.White).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.onClick(() => { openUserByIdentity(this.vm.detail.author.id, this.vm.detail.author.portraitUrl,
                  this.vm.detail.author.displayName, this.getUIContext()); })
                Text(this.vm.detail.title || '查看帖子与评论').fontSize(15).fontColor(Color.White).maxLines(3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  .onClick(() => { this.videoComments = true; })
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Column({ space: 8 }) {
                this.VideoRailAction(this.mainLiked() ? $r('sys.symbol.hand_thumbsup_fill') : $r('sys.symbol.hand_thumbsup'),
                  `${this.mainLikeCount()}`, this.mainLiked(), (): void => { this.toggleMainLike(); })
                this.VideoRailAction($r('sys.symbol.message'), `${this.displayedReplyCount()}`, false,
                  (): void => { this.videoComments = true; })
                this.VideoRailAction(this.vm.collected ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'),
                  this.vm.collected ? '已收藏' : '收藏', this.vm.collected, (): void => { this.toggleMainStore(); })
                this.VideoRailAction($r('sys.symbol.share'), '分享', false, (): void => { this.shareThread(); })
              }.margin({ bottom: 24 })
            }.width('100%').alignItems(VerticalAlign.Bottom).padding({ left: 16, right: 12, bottom: 40 + this.safeBottomVp })
              .linearGradient({ angle: 180, colors: [['#00000000', 0], ['#B3000000', 1]] })
          }.width('100%').height('100%').hitTestBehavior(HitTestMode.Transparent)
        }
      }.width('100%').height(this.videoComments ? '28%' : '100%').backgroundColor(Color.Black).clip(true)
      if (this.videoComments) {
        Column() {
          Row() {
            Row() {
              CloseIcon({ iconSize: 20 }).width(20).height(20)
            }.width(44).height(44).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
              .accessibilityText('关闭回复').onClick(() => { this.videoComments = false; })
            Text(`${this.displayedReplyCount()}条回复`).fontSize(15).fontColor(AppTheme.TEXT_MAIN)
              .layoutWeight(1).textAlign(TextAlign.Center)
            Blank().width(44)
          }.width('100%').height(48)
          this.PostList()
          Row({ space: 12 }) {
            Text('发帖千百度 文明第一步').fontSize(14).fontColor(AppTheme.TEXT_SUB).layoutWeight(1)
              .padding(12).backgroundColor(AppTheme.CARD).borderRadius(24).onClick(() => { this.openReplyBox(0); })
            SymbolGlyph(this.vm.collected ? $r('sys.symbol.star_fill') : $r('sys.symbol.star')).fontSize(24)
              .fontColor([this.vm.collected ? AppTheme.ACCENT : AppTheme.TEXT_MAIN]).onClick(() => { this.toggleMainStore(); })
            SymbolGlyph($r('sys.symbol.share')).fontSize(24).fontColor([AppTheme.TEXT_MAIN]).onClick(() => { this.shareThread(); })
          }.width('100%').padding({ left: 12, right: 16, top: 8, bottom: 8 })
        }.width('100%').layoutWeight(1).backgroundColor(AppTheme.BG).borderRadius({ topLeft: 20, topRight: 20 }).clip(true)
      }
    }.width('100%').height('100%').backgroundColor(Color.Black)
  }

  private lightStatusBar(): boolean {
    return themeModeStore.isDark || this.videoMode || this.viewerUrl.length > 0 || this.viewerUrls.length > 0;
  }

  build() {
    /** 详情页使用根共享导航栈，打开吧页与用户页时保持返回路径。 */
    HdsNavDestination() {
        Stack({ alignContent: Alignment.Bottom }) {
          if (this.videoMode) {
            this.VideoExperience()
          } else {
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
          .onTouch((event: TouchEvent): void => {
            if (event.type === TouchType.Down) { this.popupMenuShow = false; }
          })
          }

          // 查看图片时保留底栏原生材质，仅暂停交互，避免关闭动画里重新创建悬浮面。
          // 底部操作栏 / 菜单 / 弹层 / 查看器：悬浮层语义不变（Stack 后声明者在上）
          if (!this.videoMode && this.vm.posts.length > 0 && !this.showJump
            && !this.showReply && this.subDetailPid === 0) {
            this.BottomActionBar();
          }

          if (this.showJump) {
            this.JumpDialog();
          }

          if (this.viewerUrl.length > 0 && !this.showSubSheet) {
            this.ImagePreview();
          }

        }
        .width('100%')
        .height(LayoutPolicy.matchParent)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
        .clip(false)
        .backgroundColor(AppTheme.BG)
        .onAreaChange((_old: Area, area: Area): void => {
          this.popupViewportWidth = Number(area.width);
          this.popupViewportHeight = Number(area.height);
        })
        // 楼中楼内容需画到屏幕底部；bindSheet 的内容区仍会在手势区上沿截断。
        .bindContentCover(this.showSubSheet, this.SubReplySheet(), {
          modalTransition: motionContentCover(),
          enableSafeArea: false,
          backgroundColor: AppTheme.BG,
          onWillDismiss: (action: DismissContentCoverAction): void => {
            if (this.viewerUrl.length > 0 || this.viewerUrls.length > 0) {
              this.handleSystemBack();
              return;
            }
            action.dismiss();
          },
          // 点 X 或系统返回关闭时把状态收回来，
          // 否则开关停在 true 会让下一次"打开"变成无效操作
          onDisappear: (): void => {
            this.showSubSheet = false;
            this.subDetailPid = 0;
            this.clearImagePreview();
            const user: UserBrief | undefined = this.pendingUser;
            this.pendingUser = undefined;
            if (user !== undefined) {
              openUserByIdentity(user.id, user.portraitUrl, user.displayName, this.getUIContext());
            }
          }
        })
      } // HdsNavDestination 内容
      .titleBar({
        style: {
          scrollEffectOpts: {
            enableScrollEffect: motionStore.isOn(MotionEffect.HDS_SCROLL_BLUR),
            scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
          },
          scrollEffectStyle: {
            backgroundStyle: {
              // maskExtraHeight 只控渐隐带长度（SDK 默认 32）；blurRadius 控模糊强度
              //（0~128，仅两种 GRADIENT 模式生效）。取实验页同款观感值。
              maskExtraHeight: motionStore.isOn(MotionEffect.HDS_SCROLL_BLUR) ? 32 : 0,
              blurRadius: motionStore.isOn(MotionEffect.HDS_SCROLL_BLUR) ? 80 : 0
            }
          }
          // systemMaterialEffect 实测与效果主体（渐变模糊本身）几乎无叠加差异，先不开；
          // 要开：systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE,
          //   materialLevel: hdsMaterial.MaterialLevel.EXQUISITE }（底栏同款参数）
        },

        content: { stackBuilder: (): void => { this.HdsNavBar(); } }
      })

      .hideBackButton(true)

      .hideTitleBar(this.videoMode || this.viewerHidesTitleBar)
      .systemBarStyle(
        { statusBarContentColor: this.lightStatusBar() ? '#F2F3F4' : '#1B1B1B' },
        { statusBarContentColor: this.lightStatusBar() ? '#F2F3F4' : '#1B1B1B' }
      )
      .onShown((): void => { this.pageVisible = true; })
      .onHidden((reason: VisibilityChangeReason): void => {
        this.pageVisible = false;
        // 全屏视频的 ContentCover 会隐藏 destination，但仍使用同一 AVPlayer。
        // 导航离开、退后台及其它覆盖层仍释放；未知原因也不跳过释放。
        if (reason === VisibilityChangeReason.CONTENT_COVER && this.videoFullscreen) { return; }
        void voicePlayback.stop();
        void videoPlayback.stop();
      })
      .bindToScrollable([this.scroller])

      .onBackPressed((): boolean => {
        return this.handleSystemBack();
      })

  }

  /**
   * 回复详情面板内容。锚点回复按 pid 从已加载楼层里取，
   * 列表数据直接挂 VM 的楼中楼状态——分页、重试与主列表走同一份逻辑。
   */
  @Builder
  SubReplySheet() {
    Stack() {
      this.SubReplyContent();
      if (this.viewerUrl.length > 0) {
        this.ImagePreview();
      }
    }
    .width('100%')
    .height(LayoutPolicy.matchParent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  ImagePreview() {
    ImageViewer({
      imageUrl: this.viewerUrl,
      imageUrls: this.viewerUrls,
      initialIndex: this.viewerIndex,
      onBeforeClose: (): void => { this.prepareImageClose(); },
      onClose: (): void => { this.clearImagePreview(); }
    });
  }

  @Builder
  SubReplyContent() {
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
      canDeleteAnchor: this.vm.canDeletePost(this.anchorPost(this.subDetailPid)),
      canDeleteSub: (sub: SubPostItem): boolean => this.vm.canDeleteSubPost(this.subDetailPid, sub),
      deletePending: this.vm.deletePending,
      onDeleteAnchor: (): void => { void this.confirmDeleteComment(this.anchorPost(this.subDetailPid)); },
      onDeleteSub: (sub: SubPostItem): void => {
        void this.confirmDeleteComment(this.anchorPost(this.subDetailPid), sub);
      },
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
      // 必须传箭头函数而不是 `this.xxx` 方法引用：
      // 方法引用会把 `this` 摘掉，Builder 内部再调 this.RichBody 时读到 undefined，
      // 实测崩在 "Cannot read property bind of undefined"。
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
      onReplySub: (sub: SubPostItem): void => {
        this.openReplyBox(this.subDetailPid, sub);
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

  /** 面板顶部锚点回复的正文：与面板内楼中楼同一宽度口径，多图走方阵 */
  @Builder
  SheetAnchorBody() {
    this.RichPieces(this.anchorPost(this.subDetailPid).contents, COMMENT_BODY_SIZE, 24,
      AppTheme.COMMENT_BODY, 9, true, true, true, this.sheetImageWidth());
  }

  /** 面板里一条回复的正文：多图同样走方阵；宽度与面板内锚点卡一致 */
  @Builder
  SheetSubBody(sub: SubPostItem) {
    this.RichPieces(this.subReplyPieces(sub), COMMENT_BODY_SIZE, 24, AppTheme.SUB_REPLY_BODY, 9, true, true,
      true, this.sheetImageWidth())
  }

  /** 将服务端已有的回复对象前缀放回正文首行，沿用正文的图文混排。 */
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

  /**
   * HDS titleBar 的内容外壳。ForumNavBar 以 52vp 内容高并下移 statusBarH，
   * 从槽顶计算按钮位置；本外壳不重复添加状态栏 padding。
   */
  @Builder
  HdsNavBar() {
    Column() {
      this.ForumNavBar()
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .transition(TransitionEffect.IDENTITY)
  }

  @Builder
  ForumNavBar() {
    Row({ space: 4 }) {
      // 返回：全站统一的玻璃圆按钮（`components/GlassBackButton.ets`），出口见 goBack。
      GlassBackButton({
        onTap: (): void => {
          this.goBack();
        }
      })

      // 吧标：**恒显示**。加载中与"审核中拿不到吧名"都用占位（「吧」圆 + 「贴吧」），
      // 见 forumTitleText()。曾短暂改成"没吧名就整块不画"，会只剩返回+更多两个

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

      // 更多：玻璃圆按钮，与返回按钮同一套玻璃参数（底层同为 GlassCircleButton）
      GlassMoreButton({
        onTap: (): void => {
          this.onNavTap('更多');
        }
      })
      .bindPopup(this.showMore, {
        builder: (): void => { this.MoreMenu(); },
        placement: Placement.BottomRight, enableArrow: false,
        width: 120, radius: 16, targetSpace: 8,
        mask: { color: Color.Transparent }, autoCancel: true,
        systemMaterial: materialManager.officialOf(MaterialSlot.SHEET),
        transition: popupMotion(),
        onStateChange: (event: PopupStateChangeParam): void => {
          this.showMore = event.isVisible;
        }
      })
    }
    .width('100%')

    .height(52)
    .margin({ top: this.statusBarH })
    .padding({ left: 8, right: 12 })
    .alignItems(VerticalAlign.Center)
  }

  /** 作者信息区展示头像、身份、时间与来源信息，位于主帖正文顶部。 */
  @Builder
  AuthorBar() {
    Row({ space: 10 }) {
      AvatarComponent({ url: this.vm.detail.author.portraitUrl, avatarSize: 40, fallbackName: this.vm.detail.author.displayName })
        .id('thread-author-avatar').flexShrink(0)
        .onClick(() => { openUserByIdentity(this.vm.detail.author.id, this.vm.detail.author.portraitUrl, this.vm.detail.author.displayName, this.getUIContext()); })

      Column({ space: 4 }) {
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          Text(this.vm.detail.author.displayName.length > 0
            ? this.vm.detail.author.displayName : '匿名用户')
            .fontSize(POST_NICKNAME_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT_MAIN)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .id('thread-author-name')
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
              ThreadBawuBadge({ text: this.vm.detail.author.bawuTitle.length > 0
                ? this.vm.detail.author.bawuTitle : '吧务', textColor: AppTheme.ACCENT_DARK,
                backgroundColor: AppTheme.ACCENT_LIGHT, borderColor: AppTheme.ACCENT })
            }
            .margin({ right: 6 })
          }
        }
        .width('100%')
        .id('thread-author-identities')

        // 第二行：`时间 · 地区`。两段都缺时整行不渲染，不留空
        if (this.authorMetaLine().length > 0) {
          Text(this.authorMetaLine())
            .fontSize(12)
            .fontColor(AppTheme.TEXT_SUB)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .id('thread-author-meta')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .id('thread-author-info')

      FollowButton({ kind: 'user', targetId: this.vm.detail.author.id,
        portrait: this.vm.detail.author.portraitUrl, targetName: this.vm.detail.author.displayName })
        .id('thread-author-follow').flexShrink(0)
    }
    .width('100%')

    .padding({ bottom: 2 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  ForumAvatar(size: number) {
    ForumAvatarImage({ url: this.vm.detail.forumAvatar, glyphText: '吧',
      avatarSize: size, radius: forumAvatarRadius(size), fontSize: 13, bgColor: AppTheme.SURFACE_MUTED })
  }

  /** 吧内等级：贴吧用等级名而不是裸数字，样式与"楼主/吧务"区分开（浅底无边框） */
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
  MoreMenu() {
    Column({ space: 2 }) {
      Text(this.vm.sortType === ReplySortType.ONLY_AUTHOR ? '显示全部回复' : '只看楼主')
        .fontSize(14)
        .textAlign(TextAlign.Center)
        .fontColor(AppTheme.TEXT_MAIN)
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .onClick(() => {
          const target: ReplySortType = this.vm.sortType === ReplySortType.ONLY_AUTHOR
            ? ReplySortType.ASC : ReplySortType.ONLY_AUTHOR;
          this.vm.switchReplySort(this.hostContext(), target);
          this.showMore = false;
        })

      Text('跳转楼层')
        .fontSize(14)
        .textAlign(TextAlign.Center)
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
        .textAlign(TextAlign.Center)
        .fontColor(AppTheme.TEXT_MAIN)
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .onClick(() => {
          this.jumpToTop();
          this.showMore = false;
        })

      Text('分享')
        .fontSize(14)
        .textAlign(TextAlign.Center)
        .fontColor(AppTheme.TEXT_MAIN)
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .onClick(() => {
          this.showMore = false;
          this.shareThread();
        })
      if (this.vm.canDeleteThread()) {
        Text(this.vm.deletePending ? '正在删除…' : '删除帖子')
          .fontSize(14)
          .textAlign(TextAlign.Center)
          .fontColor(BrandTheme.DANGER_TEXT)
          .width('100%')
          .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          .enabled(!this.vm.deletePending)
          .id('thread-delete-entry')
          .onClick((): void => { void this.confirmDeleteThread(); })
      }
    }
    .width(120)
    .padding({ top: 4, bottom: 4 })
    .id('thread-more-menu')
  }

  /** 跳层弹层。暗色遮罩点击关闭；输入楼层号后跳转 */
  @Builder
  JumpDialog() {
    Stack() {
      Column({ space: 14 }) {
        Text('跳转楼层')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_MAIN)

        TextInput({ text: this.jumpText, placeholder: '输入楼层号，如 25' })
          .caretColor(AppTheme.ACCENT)
          .selectedBackgroundColor(BrandTheme.SELECTION_BACKGROUND)
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
            .fontColor(BrandTheme.ON_ACCENT)
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
    .transition(motionTransition(TransitionEffect.OPACITY, MotionEffect.FADE)
      .animation({ duration: motionDuration(180, MotionEffect.FADE), curve: Curve.EaseOut }))
    .onClick(() => {
      this.showJump = false;
    })
  }

  /** 回复弹窗内容：输入、字数与表情入口。尺寸和圆角由弹窗配置统一提供，键盘避让交由弹窗处理。 */
  @Builder
  ReplyDialog() {

    Column({ space: 8 }) {
      // 提示行：作者和评论摘要 + 字数；摘要单行省略，避免挤走字数。
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
        .caretColor(AppTheme.ACCENT)
        .selectedBackgroundColor(BrandTheme.SELECTION_BACKGROUND)
        .enabled(!this.vm.replyPending)
        .placeholder('说点什么吧…', { font: { size: 15 }, fontColor: AppTheme.TEXT_MUTED })
        .padding({ left: 0, right: 0 })
        .backgroundColor(Color.Transparent)
        // 保留光标与输入法焦点，只去掉系统绘制在整块编辑区外的蓝色焦点框。
        .focusBox({ strokeWidth: LengthMetrics.vp(0) })
        .width('100%')
        // 两行起步、内容变多自动向上长（弹窗 Bottom 对齐 → 顶边被推上去）
        .constraintSize({ minHeight: REPLY_INPUT_MIN_H })
        .onIMEInputComplete(() => {
          this.syncReplyMirror();
        })
        .onDeleteComplete(() => {
          this.syncReplyMirror();
        })
        .onPaste(() => {
          // 粘贴回调先于内容落地触发，稍等一拍再提取（丢一次也只是计数滞后）
          setTimeout(() => {
            this.syncReplyMirror();
          }, 100);
        })
        // 首次进入表情态和最终落回仍需重挂——
        // 镜像非空时把草稿（文本 + 表情 token）重建回 spans，见 rebuildReplySpansIfAny
        .onReady(() => {
          this.replyEditorReady = true;
          this.richCtl.setTypingStyle({ fontColor: AppTheme.TEXT_MAIN });
          this.rebuildReplySpansIfAny();
          this.refreshReplyEditorColors();
        })
        .onDisAppear((): void => { this.replyEditorReady = false; })
        // 表情面板让位：用户点输入框时保留当前卡片，键盘从下方升起。
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
            }, (image: UploadedPostImage, index: number) => image.id.length > 0 ? image.id : `local:${index}`)
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

      // 工具行：四个入口 + 发布按钮（无分隔线，参考图口径）
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
          .fontColor(BrandTheme.ON_ACCENT)
          .textAlign(TextAlign.Center)
          .width(REPLY_PUBLISH_W)
          .height(REPLY_PUBLISH_H)
          .borderRadius(REPLY_PUBLISH_H / 2)
          // 在途时不改宽度只改底色的 alpha，避免"按钮变窄"把整行推着动
          .backgroundColor(this.vm.replyPending ? BrandTheme.BUSY_ACCENT : AppTheme.ACCENT)
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
            // 内置源 90px 在 28vp（约 74px 物理）内 1:1 以内：高插值只作保险
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
    EmojiPickerPanel({ picker: this.vm.emojiPicker, tab: this.emojiTab,
      gridHeight: this.emojiGridHeight(), safeBottom: this.safeBottomVp,
      onTabChange: (tab: number): void => { this.emojiTab = tab; },
      onLoad: (): void => { void this.vm.loadMemePics(this.hostContext()); },
      onRetry: (): void => { void this.vm.retryMemePics(this.hostContext()); },
      onBuiltin: (code: number): void => { this.insertReplyEmoji(code); },
      onMeme: (item: MemePicItem): void => { this.insertMemeEmoji(item); },
      onDelete: (): void => { this.deleteReplyLastChar(); } })
  }

  replyTargetLine(): string {
    if (this.replyTargetPid <= 0) {
      return '';
    }
    const sub: SubPostItem | undefined = this.replyTargetSubPost;
    if (sub !== undefined) {
      const text: string = commentText(subCommentTarget(sub, this.vm.tid, this.replyTargetPid,
        this.vm.detail.title));
      const name: string = sub.author.displayName;
      return text.length > 0 ? `回复 ${name}：${text}` : `回复 ${name}`;
    }
    const target: PostItem | undefined = this.vm.postByPid(this.replyTargetPid);
    const name: string = target === undefined ? this.replyTargetName : target.author.displayName;
    if (name.length === 0) { return '回复该评论'; }
    const text: string = target === undefined ? '' :
      commentText(postCommentTarget(target, this.vm.tid, this.vm.detail.title));
    return text.length > 0 ? `回复 ${name}：${text}` : `回复 ${name}`;
  }

  /** 选图前记录光标；若上传期间文字改变，采用编辑器当前光标。 */
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

  /** IME/删除/粘贴/插入后提取实际span，更新正文及行内图片引用。 */
  syncReplyMirror(): void {
    if (this.rebuildingReply) { return; }
    const content: ReplyEditorContent = readEmojiEditor(this.richCtl, this.vm.memeTokenTable(),
      this.replyImages.inlineTokenTable());
    this.replyText = content.text;
    this.replyImages.reconcileInline(content.imageCounts);

  }

  /**
   * 追加文本（@、# 等符号入口）：addTextSpan 不传 offset = **追加到末尾**
   * （SDK 官方注释口径，与旧 TextArea 的追加语义一致）。
   * 超限直接丢弃——计数器已提示，再塞进去会被服务端拒。
   */
  appendReplyText(text: string): void {
    if (this.vm.replyPending) { return; }
    if (this.replyText.length + text.length > REPLY_MAX_LENGTH) {
      promptAction.showToast({ message: '已达 500 字上限', duration: 1500 });
      return;
    }
    this.richCtl.addTextSpan(text, { style: { fontColor: AppTheme.TEXT_MAIN } });
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

  /**
   * 插入收藏表情：ImageSpan 显示缩略图（任意图片，Contain 保比例）。
   *
   * token 不走 `emojiTokenFromUrl` 的文件名提取（收藏表情的 picId/原图尺寸
   * 从 URL 反推不可行），而是镜像提取时查 VM 的映射表——映射在加载完成时
   * 已全量预计算（VM 保证先建表后放列表），这里只管插图。
   */
  private insertMemeEmoji(item: MemePicItem): void {
    if (this.vm.replyPending) { return; }
    const url: string = this.vm.memeDisplayUrl(item);
    if (url.length === 0 || this.vm.memeTokenFor(url).length === 0) {
      return;
    }
    this.richCtl.addImageSpan(url, {
      imageStyle: { size: [REPLY_EMOJI_INLINE, REPLY_EMOJI_INLINE] }
    });
    this.syncReplyMirror();
  }

  /**
   * 右下角退格键（参考图分离式面板）：删 RichEditor 末尾一个字符位。
   *
   * ImageSpan 占 1 个字符位——恰好整删一个表情（含收藏表情）；文字 span 一次
   * 退 1 字符（对齐键盘退格语义，不整段删）。API 形态（API 26 d.ts 实查）：
   * span 结果的 `offsetInSpan: [number, number]` 是**全局文档坐标**的有效内容
   * 区间，末尾 = 最后一个 span 的 offsetInSpan[1]；`deleteSpans(RichEditorRange)`
   * 收 `{ start, end }` 对象（不是两个数字）。
   * 内容为空直接吞掉；删除后镜像同步（计数联动）。
   */
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

  /** 主帖 + 回复分组；回复排序栏是普通 ListItem，随内容滚动（不吸顶） */
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

        // 楼层直接挂在 List 下（与官方分页示例同构）：`ListItemGroup` 里的追加走的是
        // 分组布局，触底补页时整组重排；平铺后只插入新的 ListItem，已有项位置不动。
        LazyForEach(this.vm.floors, (row: PostItem) => {
              ListItem() {
                // 楼中楼预览由 VM 跟这一页楼层一起预取，楼层显示时预览已在路上
                Column() {
                  ReplyItem({
                    tid: this.vm.tid,
                    threadTitle: this.vm.detail.title,
                    item: this.vm.postByPid(row.pid) ?? row,
                    isThreadAuthor: row.author.id === this.vm.detail.author.id,
                    agreeState: this.vm.agreeState(row.pid),
                    canDelete: this.vm.canDeletePost(this.vm.postByPid(row.pid) ?? row),
                    canDeleteSub: (sub: SubPostItem): boolean => this.vm.canDeleteSubPost(row.pid, sub),
                    deletePending: this.vm.deletePending,
                    onDelete: (): void => {
                      void this.confirmDeleteComment(this.vm.postByPid(row.pid) ?? row);
                    },
                    onDeleteSub: (sub: SubPostItem): void => {
                      void this.confirmDeleteComment(this.vm.postByPid(row.pid) ?? row, sub);
                    },
                    subPosts: this.previewSubPosts(row),
                    subTotalCount: this.subPreviewCount(row),
                    subLoading: this.vm.subState(row.pid).loading,
                    subErrorText: this.vm.subState(row.pid).errorText,
                    hasAuthorReply: this.hasAuthorReply(row),
                    bodyBuilder: (): void => {
                      this.RichBody(row, true);
                    },
                    onToggleLike: (): void => {
                      this.toggleLike(row);
                    },
                    onReply: (): void => {
                      this.openReplyBox(row.pid);
                    },
                    onOpenSubDetail: (): void => {
                      this.openSubDetailByPid(row.pid);
                    },
                    onRetrySubPosts: (): void => {
                      this.vm.retrySubPosts(this.hostContext(), row.pid, this.vm.detail.author.id);
                    },
                    onViewImage: (url: string): void => {
                      this.openPreviewImage(url);
                    }
                  })
                }
              }
              .backgroundColor(Color.Transparent)
            }, (row: PostItem): string => `${row.pid}`)

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
      .width('100%')
      .layoutWeight(1)
      .padding({ top: this.videoMode ? 0 : this.titleBarH })
      .cachedCount(2)
      /*
       * 必须开：触底追加一页后，列表默认会跟随到新的底部，把当前读的位置往上顶。
       * 实测关掉后分页位移从 -73～0 恶化到 +478～+1379（正数就是内容被顶走）。
       */
      .maintainVisibleContentPosition(true)
      .clip(false)
      .backgroundColor(Color.Transparent)
      .divider({ strokeWidth: 0 })
      .onAppear(() => {
        this.requestCommentsJump();
      })

       .scrollBar(BarState.Off)
       .onReachEnd(() => {
        /*
         * 先挪开 1px 再请求：`maintainVisibleContentPosition` 只管"可视区外插入时保持
         * 锚点"，而列表**精确贴底**时还有一套"跟随到新底部"的逻辑，属性拦不住。
         * 脱离贴底后，追加按当前偏移插入，新楼层留在下面。
         */
        this.scroller.scrollBy(0, -1);
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
  MainThreadTitle(title: string) {
    TaggedThreadText({ text: title, labels: this.vm.detail.isHelp ? ['求助'] : [],
      textSize: visualThemeStore.isPaper ? PaperLayout.READING_TITLE : POST_TITLE_SIZE,
      lineSize: visualThemeStore.isPaper ? 34 : 26,
      weight: visualThemeStore.isPaper ? FontWeight.Bold : FontWeight.Medium,
      textColor: AppTheme.TEXT_MAIN, lines: Number.MAX_SAFE_INTEGER })
  }

  /**
   * 主帖标题 → 正文的堆叠间距。两者都是文本，行盒上下各自留白，按 9vp 给会让标题到正文的
   * 墨迹间距明显大于正文到图片（真机 20.0vp 对 12.6vp），无视频时收到 2vp 后两者一致。
   * 有视频时视频框本身没有留白，标题到视频已是 12.9vp，保持 9vp 不动。
   */
  private introStackGap(): number {
    if (visualThemeStore.isPaper) { return 9; }
    return (!this.videoMode && this.vm.detail.video !== undefined) ? 9 : 2;
  }

  /** 主帖区域包括作者信息、标题、正文与首帖楼中楼。 */
  @Builder
  ThreadIntro(item: PostItem) {
    Column({ space: 14 }) {

      if (visualThemeStore.isPaper && item.title.length > 0) {
        this.MainThreadTitle(item.title)
      }
      this.AuthorBar()

      // 外层标题/视频间距按 introStackGap()；纸境仅对下方主帖富文本内部传入独立块距。
      Column({ space: this.introStackGap() }) {
        if (!visualThemeStore.isPaper && item.title.length > 0) {
          this.MainThreadTitle(item.title)
        }

        if (!this.videoMode && this.vm.detail.video !== undefined) {
          VideoPlayer({ video: this.vm.detail.video,
            onFullscreenChange: (shown: boolean): void => { this.videoFullscreen = shown; } })
        }
        // 正文多图走等大方格（gridImages = true），且铺开全部图片（gridAll = true）。
        // 单图走正文几何（commentPreview = false）：宽度撑满，高度超约一屏就顶部裁切
        // 并挂「长图」角标——以前这里传 true，正文单图被按评论口径压在 200vp 以内，
        // 一张长截图只剩几十 vp 宽的细条。
        this.RichPieces(this.videoMode ? item.contents.filter((piece: ContentPiece): boolean =>
          !(piece.kind === ContentKind.LINK && (piece.link === this.vm.detail.video?.url || /^https?:\/\/tb-video\.bdstatic\.com\//.test(piece.link)))) : item.contents, visualThemeStore.isPaper ? PaperLayout.READING_BODY : POST_BODY_SIZE,
          visualThemeStore.isPaper ? PaperLayout.READING_LINE : 24, AppTheme.TEXT_MAIN,
          visualThemeStore.isPaper ? PaperLayout.READING_BLOCK_GAP : 9, true, false, true,
          this.mainImageWidth(), true)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (item.subPostCount > 0) {
        this.SubPostEntry(item)
        // 主帖的楼中楼仍旧就地展开：它不在回复列表里，没有"点进详情"的去处
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

  /** 回复区标题。数量来自详情模型；数量与排序字号统一复用评论昵称 */
  @Builder
  ReplySummary() {
    Row() {
      Text(`共 ${this.displayedReplyCount()} 回复`)
        .fontSize(COMMENT_NICKNAME_SIZE)
        .fontWeight(FontWeight.Normal)
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
    .id('thread-comments-summary')
    .height(42)
    .margin({ top: 12, bottom: 12 })
    .padding({ left: 16, right: 16, top: 7.5, bottom: 6 })
    .backgroundColor(AppTheme.BG)
  }

  /**
   * 四项共用同一个胶囊容器；每项按文字和水平内边距自然撑开。
   *
   * 热门实测不被服务端支持（排序参数被静默忽略），所以点它不会切过去，
   * 而是明确提示——不拿"按点赞数排当前页"伪造热门。样式上只压低透明度，
   * 其余保持不变。
   */
  @Builder
  ReplySortSegment(label: string, type: ReplySortType) {
    Text(label)
      .fontSize(COMMENT_NICKNAME_SIZE)
      .fontWeight(FontWeight.Medium)
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

  /**
   * 评论及面板锚点正文，图片使用紧凑预览；主帖正文由 ThreadIntro 单独传入。
   *
   * `inCommentList` 只在真正的一级评论列表里为 true：那里图片宽度可以由
   * 屏宽推出（评论右侧省略头像列），多图也能按方阵显示。详情面板的宽度
   * 与列表不同，由 `SheetSubBody`/`SheetAnchorBody` 自行传 `imageWidth`。
   */
  @Builder
  RichBody(item: PostItem, mainList: boolean = false, inCommentList: boolean = true) {
    this.RichPieces(item.contents, COMMENT_BODY_SIZE, 24, AppTheme.COMMENT_BODY, 9, mainList, true,
      inCommentList, inCommentList ? this.commentImageWidth() : 0)
  }

  /** 主帖正文图片可用宽度：页面左右各 16vp */
  private mainImageWidth(): number {
    return this.screenWvp > 0 ? this.screenWvp - 32 : 0;
  }

  /** 评论正文图片可用宽度：左右各 16vp + 头像 36vp + 头像与正文间距 12vp */
  private commentImageWidth(): number {
    return this.screenWvp > 0 ? this.screenWvp - 80 : 0;
  }

  /**
   * 方格内容宽：调用方给的内容宽优先，没给才按评论口径兜底。
   *
   * 主帖正文没有头像列（可用宽 = 屏宽 − 32），评论有（屏宽 − 80）。
   * 方格若一律按评论口径算，主帖那一行会窄 48vp、右边空出一条。
   */
  private gridContentWidth(widthHint: number): number {
    if (Number.isFinite(widthHint) && widthHint > 0) { return widthHint; }
    return this.commentImageWidth();
  }

  /** 详情面板内图片可用宽度：面板左右各 14+16vp + 头像 32vp + 间距 10vp */
  private sheetImageWidth(): number {
    return this.screenWvp > 0 ? this.screenWvp - 86 : 0;
  }

  /** 富文本片段渲染：文本块流式排布，图片块独占一行 */
  @Builder
  RichPieces(pieces: ContentPiece[], fontSize: number = POST_BODY_SIZE, lineHeight: number = 24,
    textColor: ResourceColor = AppTheme.TEXT_MAIN, blockGap: number = 9, mainList: boolean = false,
    commentPreview: boolean = false, gridImages: boolean = false, imageWidth: number = 0,
    gridAll: boolean = false) {
    ImageTransitionGalleryScope({ blockGap: blockGap,
      content: (gallery: ImageTransitionGallery): void => {
        this.RichPiecesBlocks(pieces, fontSize, lineHeight, textColor, mainList, commentPreview, gallery,
          gridImages, imageWidth, gridAll);
      } })
  }

  /** 图片被文字拆成不同区段时，仍共享当前渲染实例的完整图库。 */
  @Builder
  RichPiecesBlocks(pieces: ContentPiece[], fontSize: number, lineHeight: number, textColor: ResourceColor,
    mainList: boolean, commentPreview: boolean, gallery: ImageTransitionGallery,
    gridImages: boolean = false, imageWidth: number = 0, gridAll: boolean = false) {
    ForEach(groupContentBlocks(pieces), (block: ContentBlock, index: number) => {
      if (block.isVoice && block.voice !== undefined) {
        VoicePlayer({ voice: block.voice })
      } else if (block.isImage) {
        this.ImageBlock(block, collectPreviewImageUrls(pieces), pieces, mainList, commentPreview, gallery,
          gridImages, imageWidth, gridAll)
      } else {
        this.TextBlock(block, fontSize, lineHeight, textColor)
      }
    }, (block: ContentBlock, index: number) => `${index}`)
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

  /** 主帖、评论及楼中楼按图片排布偏好切换，旧版保留原有图集。 */
  @Builder
  ImageBlock(block: ContentBlock, imageUrls: string[], pieces: ContentPiece[], mainList: boolean = false,
    commentPreview: boolean = false, gallery: ImageTransitionGallery | undefined = undefined,
    gridImages: boolean = false, imageWidth: number = 0, gridAll: boolean = false) {
    if (gridImages && block.images.length >= 2) {
      // 多图一律等大方格：高度不随图片比例变化，连发几张照片也不会把首楼撑成长龙。
      // 格子宽度取调用方传来的内容宽——主帖没有头像列，不能按评论口径留白。
      // 主帖正文（gridAll）铺开全部图片，评论只露前三张并用「共 N 张」收口。
      this.CommentImageGrid(block, imageUrls, pieces, gallery, imageWidth, gridAll);
    } else if (mainList && this.imageLayout.mode === ImageLayoutMode.MODERN) {
      PostImageFlow({
        images: block.images, startIndex: block.imageStartIndex,
        viewerIndices: this.blockViewerIndices(pieces, block), transitionGallery: gallery,
        commentPreview: commentPreview,
        contentWidthHint: imageWidth,
        onOpenImage: (globalIndex: number): void => {
          const index: number = readingViewerIndex(pieces, globalIndex);
          if (index >= 0) { this.openGalleryImage(imageUrls, index); }
        }
      })
    } else {
      PostImageGallery({
        images: block.images,
        startIndex: block.imageStartIndex,
        viewerIndices: this.blockViewerIndices(pieces, block), transitionGallery: gallery,
        initialPage: this.galleryPage(pieces, block.imageStartIndex),
        widthHint: imageWidth,
        onPageChange: (page: number): void => {
          this.rememberGalleryPage(pieces, block.imageStartIndex, page);
        },
        onOpenImage: (globalIndex: number): void => {
          const index: number = readingViewerIndex(pieces, globalIndex);
          if (index >= 0) { this.openGalleryImage(imageUrls, index); }
        }
      })
    }
  }

  /**
   * 内容多图方阵，两个入口共用一套瓦片：
   *
   * - 主帖正文（`all`）：铺开**全部**图片，三列等大方格自动换行，最后一行不满三张时左对齐；
   *   图都在眼前了，就不再挂「共 N 张」角标。
   * - 评论（默认）：只露前三张，第三张右下角标总数。
   *
   * 瓦片直接复用首页的 `ModernThreadPreviewImage`，转场链路也与首页一致：
   * 瓦片 `index` 用**查看器序号**注册进 gallery（首页注册的是卡片相对下标，
   * 与查看器 initialIndex 的换算在 `openFeedImages` 的 URLs 顺序上完成），
   * 这里 viewers 序号就是查看器页码本身，注册键与翻页后 `gallery.prepare`
   * 查询键天然一致，切图再返回也能重新配对，不会退化成淡入淡出。
   * 每格高度 = (行宽 − (列数−1)×间距) / 列数，首帧即定，不依赖图片实测尺寸；
   * 列数按可见张数走 `modernFeedColumns`：2 张、4 张两列（4 张排 2+2，不留孤儿格），
   * 3、5~9 张三列，9 张正好 3×3。
   */
  @Builder
  CommentImageGrid(block: ContentBlock, imageUrls: string[], pieces: ContentPiece[],
    gallery: ImageTransitionGallery | undefined = undefined, widthHint: number = 0,
    all: boolean = false) {
    if (all) {
      Flex({ wrap: FlexWrap.Wrap,
        space: {
          main: LengthMetrics.vp(this.gridGap(widthHint, block.images.length, true)),
          cross: LengthMetrics.vp(this.gridGap(widthHint, block.images.length, true))
        } }) {
        ForEach(this.gridIndices(block.images.length, true), (i: number) => {
          ModernThreadPreviewImage({
            url: this.gridImageSource(block, i),
            origin: this.gridImageOrigin(block, i),
            index: this.gridViewerIndex(pieces, block, i),
            total: block.images.length,
            columns: this.gridColumns(block.images.length, true),
            contentWidth: this.gridContentWidth(widthHint),
            density: this.screenDensity,
            transitionGallery: gallery,
            showTotalLabel: false,
            onOpen: (): void => {
              const viewer: number = this.gridViewerIndex(pieces, block, i);
              if (viewer >= 0) { this.openGalleryImage(imageUrls, viewer); }
            }
          })
        }, (i: number) => `${i}:${this.gridImageSource(block, i)}`)
      }
      .width('100%')
    } else {
      Row({ space: this.gridGap(widthHint, block.images.length, false) }) {
        ForEach(modernFeedPreviewIndices(block.images.length), (i: number) => {
          ModernThreadPreviewImage({
            url: this.gridImageSource(block, i),
            origin: this.gridImageOrigin(block, i),
            index: this.gridViewerIndex(pieces, block, i),
            total: block.images.length,
            contentWidth: this.gridContentWidth(widthHint),
            density: this.screenDensity,
            transitionGallery: gallery,
            onOpen: (): void => {
              const index: number = this.gridViewerIndex(pieces, block, i);
              if (index >= 0) { this.openGalleryImage(imageUrls, index); }
            }
          })
        }, (i: number) => `${i}:${this.gridImageSource(block, i)}`)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
  }

  /** 图格间距：与首页卡片同一口径，按内容宽和列数收缩 */
  private gridGap(widthHint: number, total: number, all: boolean): number {
    return modernFeedGapForColumns(this.gridContentWidth(widthHint), this.gridColumns(total, all));
  }

  /** 方阵列数：全量模式看真实张数，收口模式看实际露出的张数 */
  private gridColumns(total: number, all: boolean): number {
    return modernFeedColumns(all ? total : modernFeedPreviewIndices(total).length);
  }

  /** 方阵下标：全量模式铺开所有图，收口模式只给前 3 张预览 */
  private gridIndices(total: number, all: boolean): number[] {
    if (!all) { return modernFeedPreviewIndices(total); }
    const indices: number[] = [];
    for (let index: number = 0; index < total; index++) { indices.push(index); }
    return indices;
  }

  /** 方阵里第 i 张的展示地址：活动图优先，缺失时退回原图 */
  private gridImageSource(block: ContentBlock, index: number): string {
    if (index < 0 || index >= block.images.length) {
      return '';
    }
    const image: ContentImage = block.images[index];
    return image.imageUrl.length > 0 ? image.imageUrl : image.originImageUrl;
  }

  /**
   * 方阵里第 i 张的原图地址（转场身份与查看器配对用）。
   *
   * 与 `openGalleryImage` 的 `viewerUrls` 口径一致：原图优先、缺失退展示图。
   * 瓦片侧空 origin 会跳过返回注册，查看器就找不到返回目标。
   */
  private gridImageOrigin(block: ContentBlock, index: number): string {
    if (index < 0 || index >= block.images.length) {
      return '';
    }
    const image: ContentImage = block.images[index];
    return image.originImageUrl.length > 0 ? image.originImageUrl : image.imageUrl;
  }

  /** 方阵里第 i 张在整篇内容图片序列里的查看器下标；无效返回 -1 */
  private gridViewerIndex(pieces: ContentPiece[], block: ContentBlock, index: number): number {
    return readingViewerIndex(pieces, block.imageStartIndex + index);
  }

  private blockViewerIndices(pieces: ContentPiece[], block: ContentBlock): number[] {
    const indices: number[] = [];
    for (let index: number = 0; index < block.images.length; index++) {
      indices.push(readingViewerIndex(pieces, block.imageStartIndex + index));
    }
    return indices;
  }

  private galleryPage(pieces: ContentPiece[], startIndex: number): number {
    return this.galleryPages.get(pieces)?.get(startIndex) ?? 0;
  }

  private rememberGalleryPage(pieces: ContentPiece[], startIndex: number, page: number): void {
    if (!Number.isInteger(page) || page < 0 || startIndex < 0) { return; }
    let pages: Map<number, number> | undefined = this.galleryPages.get(pieces);
    if (page === 0) {
      if (pages !== undefined) {
        pages.delete(startIndex);
        if (pages.size === 0) { this.galleryPages.delete(pieces); }
      }
      return;
    }
    if (pages === undefined) {
      pages = new Map<number, number>();
      this.galleryPages.set(pieces, pages);
    }
    pages.set(startIndex, page);
  }

  /**
   * 打开图集里的某一张（`globalIndex` 是它在**整篇内容图片序列**里的下标）。
   *
   * 查看器需要整篇的图片序列，这样进去之后还能左右滑其余图片；
   * 初始页直接用全局下标算，不再按 URL 反查——同一张图可能在正文里出现多次，
   * 反查会永远定位到第一处。
   */
  private openGalleryImage(imageUrls: string[], globalIndex: number): void {
    if (imageUrls.length === 0) {
      return;
    }
    const index: number = Math.max(0, Math.min(imageUrls.length - 1, globalIndex));
    this.viewerHidesTitleBar = true;
    this.viewerUrls = imageUrls;
    this.viewerIndex = index;
    this.viewerUrl = imageUrls[index];
  }

  /** 首帖回复入口，展开后显示为浅灰圆角聚合卡 */
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

  /** 主帖的回复聚合区：仍是就地展开（它不在回复列表里，没有可弹层的锚点） */
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

  /** 一条楼中楼回复 */
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

      // "回复某人"的前缀在解析层已从正文里拆走（见 model.parseReplyTarget），
      // 完整列表这边要自己补回来，否则会丢掉"谁回复谁"
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

      this.RichPieces(sub.contents, SUB_REPLY_BODY_SIZE, SUB_REPLY_LINE_HEIGHT, AppTheme.SUB_REPLY_BODY, 9,
        true, true, true, this.commentImageWidth())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 7, bottom: 7 })
  }

  /**
   * 左胶囊 ——「分离式」：玻璃由 `MaterialTabs` 的**官方悬浮面**提供。
   *
   * 与首页底栏共用 BOTTOM_BAR 槽位，优先使用 ArkUI 官方薄材质。
   * 外层只控制布局与圆角，不裁剪官方材质向外绘制的阴影。
   */
  @Builder
  SplitImmersiveReplyPill() {
    MaterialTabs({ slot: MaterialSlot.BOTTOM_BAR, barHeight: ACTION_PILL_HEIGHT, barWidth: REPLY_PILL_WIDTH,
        barContent: (): void => { this.SplitReplyTab(); } })

    .borderRadius(ACTION_PILL_RADIUS)
    .clip(false)
    .width(REPLY_PILL_WIDTH)
    .height(ACTION_PILL_HEIGHT)
  }

  /** 「分离式」左胶囊内容；玻璃由外层系统材质完整渲染。 */
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
    // 图标左沿钉在「左半圆与上下边切点」的垂线上 = 节点左沿 + 半径 26vp；
    // 容器左沿在节点内 12vp → 左内边距 = 26 − 12 = 14vp（真机实测 140px 命中）。
    .padding({ left: 14, right: REPLY_PILL_PADDING })
    .onClick(() => {
      this.openReplyBox(0);
    })
  }

  /**
   * 右胶囊 ——「分离式」：官方悬浮面承载四个操作。
   *
   * 宽度钉 `ACTION_PILL_WIDTH`（现网右大胶囊实测 197vp）：底栏行可用宽 348vp，
   * 左 143 + 间距 8 + 右 197 正好填满。
   * 与左胶囊一样保留官方悬浮面及其外部阴影。
   */
  @Builder
  SplitImmersiveActionPill() {
    MaterialTabs({ slot: MaterialSlot.BOTTOM_BAR, barHeight: ACTION_PILL_HEIGHT, barWidth: ACTION_PILL_WIDTH,
        barContent: (): void => { this.SplitActionTab(); } })

    .borderRadius(ACTION_PILL_RADIUS)
    .clip(false)
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

  /** 弹出式的全部操作；选择后先关闭菜单，再复用现有处理方法。 */
  @Builder
  PopupActionAt(index: number) {
    if (index === 0) {
      this.PopupMenuItem($r('sys.symbol.pencil_line'), '回复', 'reply', '回复', (): void => {
        this.popupMenuShow = false;
        this.openReplyBox(0);
      });
    } else if (index === 1) {
      this.PopupMenuItem($r('sys.symbol.message'), `${this.displayedReplyCount()}`, 'comments', '查看评论', (): void => {
        this.popupMenuShow = false;
        this.jumpToReplies();
      });
    } else if (index === 2) {
      this.PopupMenuItem(this.mainLiked() ? $r('sys.symbol.hand_thumbsup_fill')
        : $r('sys.symbol.hand_thumbsup'), `${this.mainLikeCount()}`, 'like', '点赞', (): void => {
        this.popupMenuShow = false;
        this.toggleMainLike();
      });
    } else if (index === 3) {
      this.PopupMenuItem(this.vm.collected ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'),
        this.popupCount(this.vm.detail.collectCount), 'collect', this.vm.collected ? '取消收藏，累计收藏' : '收藏，累计收藏', (): void => {
        this.popupMenuShow = false;
        this.toggleMainStore();
      });
    } else if (index === 4) {
      this.PopupMenuItem($r('sys.symbol.share'), this.popupCount(this.vm.detail.shareCount), 'share', '分享', (): void => {
        this.popupMenuShow = false;
        this.shareThread();
      });
    }
  }

  private popupCount(count: number): string { return count >= 0 ? `${count}` : '—'; }

  /** 每个操作各有一个沉浸光感圆面，图标与计数复用原业务状态。 */
  @Builder
  PopupMenuItem(icon: Resource, label: string, action: string, description: string, onTap: () => void) {
    Stack() {
      GlassCircleButton({
        diameter: THREAD_ACTION_BUTTON_SIZE,
        slot: MaterialSlot.BOTTOM_BAR,
        useCustomIcon: true,
        customIcon: (): void => { this.PopupActionContent(icon, label); }
      }).hitTestBehavior(HitTestMode.BLOCK_DESCENDANTS)
    }
    .width(THREAD_ACTION_BUTTON_SIZE).height(THREAD_ACTION_BUTTON_SIZE)
    .responseRegion(floatingButtonHitRegion(THREAD_ACTION_BUTTON_SIZE))
    .id(`thread-popup-${action}`)
    .accessibilityGroup(true)
    .accessibilityText(action === 'reply' ? description : `${description} ${label}`)
    .onClick((): void => { onTap(); })
  }

  @Builder
  PopupActionContent(icon: Resource, label: string) {
    Column({ space: 1 }) {
      SymbolGlyph(icon).fontSize(21).maxFontScale(1).fontColor([AppTheme.TEXT_MAIN])
      Text(label).fontSize(12).maxFontScale(1).fontColor(AppTheme.TEXT_MAIN)
        .width(44).maxLines(1).minFontSize(8).maxFontSize(12).textAlign(TextAlign.Center)
    }
    .justifyContent(FlexAlign.Center)
    .width(THREAD_ACTION_BUTTON_SIZE).height(THREAD_ACTION_BUTTON_SIZE)
  }

  /** 按已保存偏好显示分离式双胶囊或弹出式单按钮。 */
  @Builder
  BottomActionBar() {
    if (visualThemeStore.isPaper) {
      this.PaperActionBar()
    } else if (threadActionBarStore.style === ThreadActionBarStyle.SPLIT_IMMERSIVE) {
      this.SplitImmersiveActionBar()
    } else {
      this.PopupActionBar()
    }
  }

  /** 纸境单片悬浮操作面，业务操作和键盘处理沿用原入口。 */
  @Builder
  PaperActionBar() {
    MaterialTabs({ slot: MaterialSlot.BOTTOM_BAR, barHeight: 56, barWidth: Math.max(240, this.popupViewportWidth - 24),
        barContent: (): void => { this.PaperActionContent(); } })
    .width(Math.max(240, this.popupViewportWidth - 24)).height(56).borderRadius(28).clip(false)
    .margin({ bottom: BOTTOM_BAR_BOTTOM_MARGIN })
    .id('paper-thread-action-bar')
    .hitTestBehavior(this.viewerUrl.length === 0 ? HitTestMode.Default : HitTestMode.BLOCK_DESCENDANTS)
    .accessibilityLevel(this.viewerUrl.length === 0 ? 'auto' : 'no-hide-descendants')
  }

  @Builder
  PaperActionContent() {
    Row({ space: 4 }) {
      Stack() {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.pencil_line')).fontSize(18).maxFontScale(1).fontColor([AppTheme.TEXT_SUB])
          Text('写评论').fontSize(14).fontColor(AppTheme.TEXT_SUB).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        }.width('100%').height(36).padding({ left: 10, right: 8 })
      }.layoutWeight(2.3).height(44)
        .id('paper-write-comment').accessibilityGroup(true).accessibilityText('写评论')
        .onClick((): void => { this.openReplyBox(0); })
      this.BottomReplyCount()
      this.BottomLikeAction()
      this.BottomStoreAction()
      if (this.popupViewportWidth >= 360) {
        this.BottomAction($r('sys.symbol.share'), '分享', (): void => { this.shareThread(); })
      }
    }
    // HDS内容盒已扣上下各4vp，跟随其可用高度，避免再次撑满整栏而下溢。
    .width('100%').height('100%')
  }

  /** 「分离式」：左右各一个 `MaterialTabs`，玻璃全由官方系统材质提供 */
  @Builder
  SplitImmersiveActionBar() {
    Row({ space: ACTION_PILL_GAP }) {

      Stack() {
        this.SplitImmersiveReplyPill()
      }
      .width(REPLY_PILL_WIDTH)
      .height(ACTION_PILL_HEIGHT)

      .borderRadius(ACTION_PILL_RADIUS)

      Stack() {
        this.SplitImmersiveActionPill()
      }
      .width(ACTION_PILL_WIDTH)
      .height(ACTION_PILL_HEIGHT)
      .borderRadius(ACTION_PILL_RADIUS)

    }
    .width('100%')
    .padding({
      left: BOTTOM_BAR_SIDE_MARGIN,
      right: BOTTOM_BAR_SIDE_MARGIN,
      bottom: BOTTOM_BAR_BOTTOM_MARGIN
    })
    .hitTestBehavior(this.viewerUrl.length === 0 ? HitTestMode.Default : HitTestMode.BLOCK_DESCENDANTS)
    .accessibilityLevel(this.viewerUrl.length === 0 ? 'auto' : 'no-hide-descendants')
  }

  /** 弹出式按钮的位置、触摸与握姿由独立组件管理。 */
  @Builder
  PopupActionBar() {
    ThreadPopupButton({
      viewportWidth: this.popupViewportWidth,
      viewportHeight: this.popupViewportHeight,
      topInset: this.titleBarH,
      active: this.pageVisible && !this.showMore && this.viewerUrl.length === 0,
      open: this.popupMenuShow,
      onOpenChange: (open: boolean): void => { this.popupMenuShow = open; },
      action: (index: number): void => { this.PopupActionAt(index); }
    })
  }

  /**
   * 底栏点赞按钮。
   *
   * 状态与计数**读主帖对象**（`vm.mainPost()`），而不是 `vm.detail.agreeCount`：
   * 楼层列表渲染的也是 `posts` 里的对象，读同一份才不会出现"楼里已高亮、底栏还显示未点赞"。
   * 主帖定位不到（`mainPostId` 缺失且无 `floor===1`）时按未点赞态渲染，
   * 点击由 `toggleMainLike()` 直接忽略。
   */
  @Builder
  BottomLikeAction() {
    Column({ space: 1 }) {
      SymbolGlyph(this.mainLiked() ? $r('sys.symbol.hand_thumbsup_fill')
        : $r('sys.symbol.hand_thumbsup'))
        .fontSize(22)
        .fontColor([visualThemeStore.isPaper ? (this.mainLiked() ? BrandTheme.EMPHASIS : AppTheme.TEXT_SUB) :
          (this.mainLiked() ? AppTheme.ACCENT : AppTheme.TEXT_MAIN)])
      Text(this.mainLikeCount() > 0 ? `${this.mainLikeCount()}` : '点赞')
        .fontSize(10)
        .fontColor(this.mainLiked() ? (visualThemeStore.isPaper ? BrandTheme.EMPHASIS : AppTheme.ACCENT) : AppTheme.TEXT_SUB)
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: visualThemeStore.isPaper ? 44 : 0 })
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.toggleMainLike();
    })
  }

  /** 底栏点赞态：主帖定位不到时按未点赞渲染（不猜） */
  private mainLiked(): boolean {
    const main: PostItem | undefined = this.vm.mainPost();
    return main === undefined ? false : this.vm.isLiked(main);
  }

  /** 底栏点赞数：主帖定位不到时显示 0 */
  private mainLikeCount(): number {
    const main: PostItem | undefined = this.vm.mainPost();
    return main === undefined ? 0 : this.vm.agreeCountOf(main);
  }

  /**
   * 底栏收藏 / 取消收藏。
   *
   * 状态读 `vm.collected`（可观察字段）：权威值来自详情响应 `thread.is_stored`
   * （每次 load/refresh 重置），点击走 `vm.toggleStore` 的乐观翻转 + 失败回滚，
   * 与点赞按钮同一套交互语义（成功不改文案以外的任何东西，失败弹服务端原因）。
   * 图标与文字随状态切换（收藏 ↔ 已收藏），三种底栏形态共用本 builder。
   */
  @Builder
  BottomStoreAction() {
    Column({ space: 1 }) {
      SymbolGlyph(this.vm.collected ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
        .fontSize(22)
        .fontColor([visualThemeStore.isPaper ? (this.vm.collected ? BrandTheme.GOLD : AppTheme.TEXT_SUB) : (this.vm.collected ? AppTheme.ACCENT : AppTheme.TEXT_MAIN)])
      Text(this.vm.collected ? '已收藏' : '收藏')
        .fontSize(10)
        .fontColor(visualThemeStore.isPaper ? (this.vm.collected ? BrandTheme.GOLD : AppTheme.TEXT_SUB) : AppTheme.COMMENT_ACTION)
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: visualThemeStore.isPaper ? 44 : 0 })
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.toggleMainStore();
    })
  }

  /**
   * 收藏 / 取消收藏主帖（三形态底栏 + 弹出菜单共用）。
   * 交互与 `toggleLike` 同构：VM 返回非空文案时 toast，成功保持静默（文案已变）。
   */
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
      // 回复数入口：官方 Symbol `message`（原为字符 ▤）
      SymbolGlyph($r('sys.symbol.message'))
        .fontSize(22)
        .fontColor([visualThemeStore.isPaper ? AppTheme.TEXT_SUB : AppTheme.TEXT_MAIN])
      Text(`${this.displayedReplyCount()}`)
        .fontSize(10)
        .fontColor(AppTheme.TEXT_SUB)
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: visualThemeStore.isPaper ? 44 : 0 })
    .justifyContent(FlexAlign.Center)
    .onClick(() => {

      this.jumpToReplies();
    })
  }

  @Builder
  BottomAction(icon: Resource, label: string, onTap: () => void) {
    Column({ space: 1 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([visualThemeStore.isPaper ? AppTheme.TEXT_SUB : AppTheme.TEXT_MAIN])
      Text(label)
        .fontSize(10)
        .fontColor(AppTheme.TEXT_SUB)
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: visualThemeStore.isPaper ? 44 : 0 })
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      onTap();
    })
  }

  /** 列表底部：加载中 / 没有更多 / 加载失败可重试 */
  @Builder
  Footer() {
    Column() {
      if (this.vm.isSwitchingSort) {
        PageState({ compact: true, loading: true, message: '正在切换回复…' })
      } else if (this.vm.focusedReplyPid > 0 && this.vm.errorText.length === 0) {
        PageState({ compact: true, message: '当前显示定位回复', actionLabel: '查看全部回复',
          onAction: (): void => {
            this.vm.load(this.hostContext(), this.vm.tid).then(() => {
              this.jumpToReplies();
            });
          } })
      } else {
        // moreText 让"还有下一页"在底部有常驻提示：滑到底先看到"上拉加载更多"，
        // 请求发出后原位换成"正在加载更多…"，不会整块跳出来
        ListFooter({ loading: this.vm.isLoadingMore, error: this.vm.errorText, hasMore: this.vm.hasMore,
          moreText: '上拉加载更多',
          endText: this.vm.posts.length > 0 ? '已经到底了' : '',
          onRetry: (): void => { void this.vm.loadMore(this.hostContext()); } })
      }
    }.width('100%').padding({ bottom: this.videoMode ? 0 : 88 })
  }

  @Builder
  StatusView(text: string) {
    PageState({ fillRemaining: true, message: text, loading: this.vm.loading && !this.vm.loadedOnce }).layoutWeight(1)
  }

  @Builder
  ErrorView() {
    PageState({ fillRemaining: true, title: '加载失败', message: this.vm.errorText, actionLabel: '重试',
      onAction: (): void => { void this.vm.load(this.hostContext(), this.vm.tid); } }).layoutWeight(1)
  }
}
