/** 共享导航入口。业务组件通过 NavigationService 使用根 NavPathStack。 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { DirectoryKind } from '../model/PageDirectory';

/** 路由名注册表。只登记真实有 Shared 消费者的页面；测试页继续用 debug 常量 */
export class AppRoute {
  static readonly THREAD_DETAIL: string = 'ThreadDetail';
  static readonly FORUM_PAGE: string = 'ForumPage';
  static readonly SEARCH_RESULT_PAGE: string = 'SearchResultPage';
  static readonly SEARCH_PAGE: string = 'SearchPage';
  static readonly MY_LIST_PAGE: string = 'MyListPage';
  static readonly HOT_TOPIC_PAGE: string = 'HotTopicPage';
  static readonly USER_PAGE: string = 'UserPage';
  static readonly DIRECTORY_PAGE: string = 'DirectoryPage';
  static readonly FORUM_MEMBER_PAGE: string = 'ForumMemberPage';
  static readonly NOTIFY_LIST_PAGE: string = 'NotifyListPage';
  static readonly SCAN_PAGE: string = 'ScanPage';
  static readonly VIDEO_FEED_PAGE: string = 'VideoFeedPage';
}

/** 详情页路由参数。页面参数由 Index.PageMap 注入，不再从 router 读取。 */
export interface ThreadDetailParams {
  tid: number;
  /** 吧内视频卡进入沉浸观看，仍共享原帖回复与写操作。 */
  videoMode?: boolean;
  /** 我的回复入口携带真实回复 id；缺省仍按普通首页加载。 */
  targetPid?: number;
  /** 列表页已归一化的回复数；详情页拿它先显示，加载完成后以详情响应为准。没有就缺省 */
  replyCount?: number;
  /** 来源吧名兜底（见上方说明）。不知道就别传，空串等同缺省 */
  forumName?: string;
}

export interface ForumPageParams {
  /** 吧名。缺省时页面走「没有拿到吧名」空态，不发空请求 */
  forumName?: string;
}

export interface SearchResultParams {
  /** 搜索关键词。缺省/空串时页面走空关键词状态，不发起请求（原 router 行为一致） */
  word?: string;
  /** 吧内搜索的范围（吧名）。缺省/空串 = 全站搜索；只影响请求的 `kw` 与文案，不影响结果解析 */
  forumName?: string;
}

export interface MyListParams {
  /** 列表类型：'history' | 'fav' | 'reply' | 'thread'。缺省时按浏览历史处理 */
  kind?: string;
}

/** 热榜话题网页仅使用服务端返回的 ID 和标题构造地址。 */
export interface HotTopicParams {
  topicId: number;
  topicName: string;
}

export interface UserPageParams {
  uid: number;
  tab?: number;
  /** 可传原始头像标识或列表中的完整头像 URL；页面只提取已知的头像路径。 */
  portrait?: string;
  name?: string;
}

/**
 * 通知列表页（F-01）的唯一路由参数。
 *
 * `reply`＝回复我，`agree`＝赞我，`at`＝表单/JSON @我；未知值由页面回退到 reply。
 */
export interface NotifyListParams {
  kind?: string;
}

export interface DirectoryPageParams {
  kind: DirectoryKind;
  id: number;
  title?: string;
  forumName?: string;
}

/**
 * 吧成员页（A-01）的唯一路由参数。
 *
 * `forumId` 是**必需**的：官方 `getMemberInfo` 只认 `forum_id`，不认吧名，
 * 所以入口必须先把 fid 拿到（吧页的 `vm.forum.id`）。缺失时页面如实报"拿不到吧 id"，
 * 不发一个必然失败的请求。`forumName` 只用于标题与"点人进主页"的兜底，不参与请求。
 */
export interface ForumMemberPageParams {
  forumId: number;
  forumName?: string;
  title?: string;
}

/** 共享导航错误日志标签 */
const TAG: string = 'NavigationService';

export class NavigationService {
  /** Root 共享导航栈。由 Index 在 aboutToAppear 注入一次 */
  private static stack: NavPathStack | null = null;

  static openUser(params: UserPageParams): void {
    if (NavigationService.stack === null) {
      hilog.error(0x0, TAG, 'openUser failed: stack not set'); return;
    }
    NavigationService.stack.pushPathByName(AppRoute.USER_PAGE, params);
  }

  static openDirectory(params: DirectoryPageParams): void {
    if (NavigationService.stack === null) {
      hilog.error(0x0, TAG, 'openDirectory failed: stack not set'); return;
    }
    NavigationService.stack.pushPathByName(AppRoute.DIRECTORY_PAGE, params);
  }

  /** Index aboutToAppear 调用；重复调用以最后一次为准（幂等，无害） */
  static setStack(stack: NavPathStack): void {
    NavigationService.stack = stack;
  }

  static openThreadDetail(params: ThreadDetailParams): void {
    const stack: NavPathStack | null = NavigationService.stack;
    if (stack === null) {
      hilog.error(0x0, TAG, 'openThreadDetail failed: stack not set');
      return;
    }
    stack.pushPathByName(AppRoute.THREAD_DETAIL, params);
  }

  static openForum(params: ForumPageParams): void {
    const stack: NavPathStack | null = NavigationService.stack;
    if (stack === null) {
      hilog.error(0x0, TAG, 'openForum failed: stack not set');
      return;
    }
    stack.pushPathByName(AppRoute.FORUM_PAGE, params);
  }

  static openSearchResult(params: SearchResultParams): void {
    const stack: NavPathStack | null = NavigationService.stack;
    if (stack === null) {
      hilog.error(0x0, TAG, 'openSearchResult failed: stack not set');
      return;
    }
    // 搜索过程保持顶部原位；destination 的 NONE 不会关闭导航栈自身的过渡。
    stack.pushPathByName(AppRoute.SEARCH_RESULT_PAGE, params, false);
  }

  static openSearchPage(): void {
    const stack: NavPathStack | null = NavigationService.stack;
    if (stack === null) {
      hilog.error(0x0, TAG, 'openSearchPage failed: stack not set');
      return;
    }
    stack.pushPathByName(AppRoute.SEARCH_PAGE, null, false);
  }

  static openScanPage(): void {
    const stack: NavPathStack | null = NavigationService.stack;
    if (stack === null) {
      hilog.error(0x0, TAG, 'openScanPage failed: stack not set');
      return;
    }
    stack.pushPathByName(AppRoute.SCAN_PAGE, null);
  }

  static openVideoFeed(): void {
    const stack: NavPathStack | null = NavigationService.stack;
    if (stack === null) { hilog.error(0x0, TAG, 'openVideoFeed failed: stack not set'); return; }
    stack.pushPathByName(AppRoute.VIDEO_FEED_PAGE, null);
  }

  static openMyList(params: MyListParams): void {
    const stack: NavPathStack | null = NavigationService.stack;
    if (stack === null) {
      hilog.error(0x0, TAG, 'openMyList failed: stack not set');
      return;
    }
    stack.pushPathByName(AppRoute.MY_LIST_PAGE, params);
  }

  static openHotTopic(params: HotTopicParams): void {
    const stack: NavPathStack | null = NavigationService.stack;
    if (stack === null) {
      hilog.error(0x0, TAG, 'openHotTopic failed: stack not set');
      return;
    }
    stack.pushPathByName(AppRoute.HOT_TOPIC_PAGE, params);
  }

  /**
   * 打开吧成员页（A-01）。失败语义与其它 open* 一致：栈未注入时错误日志 + 不跳转。
   * 日志只带 fid 与吧名（都不是凭据），便于复核"入口有没有把 fid 正确带进来"。
   */
  static openForumMember(params: ForumMemberPageParams): void {
    const stack: NavPathStack | null = NavigationService.stack;
    if (stack === null) {
      hilog.error(0x0, TAG, 'openForumMember failed: stack not set');
      return;
    }
    stack.pushPathByName(AppRoute.FORUM_MEMBER_PAGE, params);
  }

  /**
   * 打开通知列表页（F-01）。失败语义与其它 open* 一致：栈未注入时错误日志 + 不跳转。
   */
  static openNotifyList(params: NotifyListParams): void {
    const stack: NavPathStack | null = NavigationService.stack;
    if (stack === null) {
      hilog.error(0x0, TAG, 'openNotifyList failed: stack not set');
      return;
    }
    stack.pushPathByName(AppRoute.NOTIFY_LIST_PAGE, params);
  }

  static back(): void {
    const stack: NavPathStack | null = NavigationService.stack;
    if (stack === null || stack.size() === 0) {
      hilog.error(0x0, TAG, 'back failed: stack empty or not set');
      return;
    }
    const names: string[] = stack.getAllPathName();
    const current: string = names[names.length - 1];
    const search: boolean = current === AppRoute.SEARCH_PAGE || current === AppRoute.SEARCH_RESULT_PAGE;
    stack.pop(!search);
  }
}
