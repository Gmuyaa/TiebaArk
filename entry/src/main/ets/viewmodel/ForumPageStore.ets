/**
 * 吧页会话态托管与点击预发起入口：按账号隔离、有界 LRU（`CachePolicy.FORUM_PAGE_STATE_CACHE_ENTRIES`）。
 * 供 `NavigationService.openForum` 在推页动画前同步预填充吧头并启动首包请求，进入 `ForumPage` 时
 * 直接复用同一 `ForumPageState` 实例，避免重复发包。
 */
import { common } from '@kit.AbilityKit';
import { authSession } from '../auth/AuthSession';
import { forumDefaultTabStore } from '../common/appearance/ForumDefaultTabStore';
import { FORUM_AVATAR_URL_TTL_MS, FORUM_PAGE_STATE_CACHE_ENTRIES } from '../model/CachePolicy';
import { getCachedForumAvatarUrl, getForumAvatar, getForumAvatarId } from '../model/ForumAvatarStore';
import { ForumDefaultTab } from '../model/ForumDefaultTab';
import { getForumHeadline } from '../model/ForumHeadline';
import { cachedForumAvatar, cachedForumHeroColor, cachedForumId, cachedForumTabs } from './ForumReadCache';
import { markFirstPageRead } from './ForumStateStore';
import { ThreadListVM } from './ThreadListVM';

export class ForumPageState {
  vm: ThreadListVM = new ThreadListVM();
  scrollOffset: number = 0;
  defaultTab: ForumDefaultTab = ForumDefaultTab.HOT;
}

const states: Map<string, ForumPageState> = new Map<string, ForumPageState>();
let boundOwner: string = '';

function bindAccount(): void {
  const next: string = authSession.forumCacheSessionKey();
  if (boundOwner === next) { return; }
  boundOwner = next;
  states.forEach((state: ForumPageState): void => {
    state.vm.cancelPrefetch();
  });
  states.clear();
}

function touchState(name: string, state: ForumPageState): void {
  states.delete(name);
  states.set(name, state);
  while (states.size > FORUM_PAGE_STATE_CACHE_ENTRIES) {
    const oldest: IteratorResult<string> = states.keys().next();
    if (oldest.done || oldest.value === name) { return; }
    const evicted: ForumPageState | undefined = states.get(oldest.value);
    if (evicted !== undefined) { evicted.vm.cancelPrefetch(); }
    states.delete(oldest.value);
  }
}

/** 用本地已缓存的 fid / 头像 / 主题色 / 头图 / 分类预填吧头，让首帧立即有内容。 */
export function seedForumPageHeader(vm: ThreadListVM, forumName: string): void {
  const name: string = forumName.trim();
  if (name.length === 0 || vm.loadedOnce) { return; }
  const fid: number = cachedForumId(name) || getForumAvatarId(name);
  const avatar: string = cachedForumAvatar(name, fid) || getForumAvatar(name) ||
    getCachedForumAvatarUrl(name, Date.now(), FORUM_AVATAR_URL_TTL_MS);
  const heroColor: string = cachedForumHeroColor(name);
  const headline: string = getForumHeadline(name);
  const tabs = cachedForumTabs(name);
  vm.seedHeader(name, fid, avatar, heroColor, headline, tabs);
}

/** 获取或创建当前账号下指定吧的页面状态（按 LRU 保活并同步预填吧头）。 */
export function acquireForumPageState(forumName: string): ForumPageState {
  bindAccount();
  const name: string = forumName.trim();
  if (name.length === 0) { return new ForumPageState(); }
  let state: ForumPageState | undefined = states.get(name);
  if (state === undefined) {
    state = new ForumPageState();
    state.defaultTab = forumDefaultTabStore.value;
  }
  touchState(name, state);
  seedForumPageHeader(state.vm, name);
  return state;
}

/** 点击进吧时提前准备状态并发起首包，与页面推入转场动画并行。 */
export function prepareForumPage(context: common.UIAbilityContext, forumName: string): ForumPageState {
  const name: string = forumName.trim();
  const state: ForumPageState = acquireForumPageState(name);
  if (name.length === 0) { return state; }
  if (state.defaultTab !== forumDefaultTabStore.value) {
    state.defaultTab = forumDefaultTabStore.value;
    state.scrollOffset = 0;
    state.vm.selectedTabId = 0;
    state.vm.loadedOnce = false;
  }
  if (!state.vm.loadedOnce && !state.vm.loading) {
    markFirstPageRead(name);
    void state.vm.refresh(context, name);
  }
  return state;
}

export function forumPageStateCount(): number {
  bindAccount();
  return states.size;
}

/** 仅用例调用：清空全部吧页会话状态。 */
export function resetForumPageStore(): void {
  states.forEach((state: ForumPageState): void => {
    state.vm.cancelPrefetch();
  });
  states.clear();
  boundOwner = '';
}
