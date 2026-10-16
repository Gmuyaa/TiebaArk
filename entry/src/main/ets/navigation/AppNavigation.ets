

import { hilog } from '@kit.PerformanceAnalysisKit';
import { DirectoryKind } from '../model/PageDirectory';

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

export interface ThreadDetailParams {
  tid: number;

  targetPid?: number;

  replyCount?: number;

  forumName?: string;
}

export interface ForumPageParams {

  forumName?: string;
}

export interface SearchResultParams {

  word?: string;

  forumName?: string;
}

export interface MyListParams {

  kind?: string;
}

export interface HotTopicParams {
  topicId: number;
  topicName: string;
}

export interface UserPageParams {
  uid: number;
  tab?: number;

  portrait?: string;
  name?: string;
}

export interface NotifyListParams {
  kind?: string;
}

export interface DirectoryPageParams {
  kind: DirectoryKind;
  id: number;
  title?: string;
  forumName?: string;
}

export interface ForumMemberPageParams {
  forumId: number;
  forumName?: string;
  title?: string;
}

const TAG: string = 'NavigationService';

export class NavigationService {

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
    stack.pushPathByName(AppRoute.SEARCH_RESULT_PAGE, params);
  }

  static openSearchPage(): void {
    const stack: NavPathStack | null = NavigationService.stack;
    if (stack === null) {
      hilog.error(0x0, TAG, 'openSearchPage failed: stack not set');
      return;
    }
    stack.pushPathByName(AppRoute.SEARCH_PAGE, null);
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

  static openForumMember(params: ForumMemberPageParams): void {
    const stack: NavPathStack | null = NavigationService.stack;
    if (stack === null) {
      hilog.error(0x0, TAG, 'openForumMember failed: stack not set');
      return;
    }
    stack.pushPathByName(AppRoute.FORUM_MEMBER_PAGE, params);
  }

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
    stack.pop();
  }
}
