/**
 * 吧头像补图的统一编排：**内存表 → 落盘 TTL → 有界并发反查 → 回写**。
 *
 * 三个列表入口（我的收藏/浏览历史、个人主页「关注吧」、个人主页「帖子栏」）原本各写一遍
 * 同样的流程，且各自决定并发与上限。2026-11-13 已经踩过一次坑：
 * 把落盘 URL 读出来再写回会刷新写入时刻，TTL 就永远不过期。这里把它固化成两条规则：
 *
 * 1. **落盘命中只上屏，不写回**（写回会续命）；
 * 2. **网络确认才走 `recordFetchedForumAvatar`**（刷新写入时刻）。
 *
 * 各入口只需要提供「怎么取」（`fetch`）与「取到之后给谁用」（`apply`）；
 * 并发上限全站统一 4（持有者 2026-11-14 定），单次条数上限由调用方给。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FORUM_AVATAR_URL_TTL_MS } from '../model/CachePolicy';
import {
  getCachedForumAvatarUrl, getForumAvatar, recordFetchedForumAvatar
} from '../model/ForumAvatarStore';

/** 一个待补的吧 */
export class ForumAvatarNeed {
  readonly name: string;
  readonly forumId: number;

  constructor(name: string, forumId: number = 0) {
    this.name = name;
    this.forumId = forumId;
  }
}

/** 一次补图任务的参数（各入口只填自己关心的） */
export class ForumAvatarBackfillPlan {
  /** 日志标签：出问题时能分清是哪个列表 */
  label: string = 'avatar';
  /** 同时反查的上限，全站统一 4 */
  limit: number = 4;
  /** 单次最多反查多少条；0 = 不限（收藏页用它把首屏请求压到 20 条内） */
  maxFetch: number = 0;
  /** 页面/VM 已失效时返回 true：立即停止派发，结果也不再上屏 */
  stopped: () => boolean = (): boolean => false;
  /** 各入口自己的取图方式（`getforumdetail` / 目录 / 搜索详情） */
  fetch: (name: string, forumId: number) => Promise<string> = async (): Promise<string> => '';
  /** 取到地址后交给页面（全局表与落盘索引已由本函数写好） */
  apply: (name: string, forumId: number, url: string) => void = (): void => {};
}

/** 一次补图的结果，用于日志与用例断言 */
export class ForumAvatarBackfillResult {
  /** 落盘 TTL 命中，零请求 */
  cached: number = 0;
  /** 真正发出的请求数 */
  fetched: number = 0;
  /** 成功拿到地址并回写 */
  resolved: number = 0;
}

/**
 * 执行一次补图。返回计数；抛不出去（单个吧失败只记日志，不拖累整页）。
 */
export async function backfillForumAvatars(needs: ForumAvatarNeed[],
  plan: ForumAvatarBackfillPlan): Promise<ForumAvatarBackfillResult> {
  const result: ForumAvatarBackfillResult = new ForumAvatarBackfillResult();
  const now: number = Date.now();
  const seen: Set<string> = new Set<string>();
  const pending: ForumAvatarNeed[] = [];

  for (const need of needs) {
    const name: string = need.name.trim();
    if (name.length === 0 || seen.has(name)) { continue; }
    seen.add(name);
    const known: string = getForumAvatar(name);
    if (known.length > 0) {
      plan.apply(name, need.forumId, known);
      continue;
    }
    const cached: string = getCachedForumAvatarUrl(name, now, FORUM_AVATAR_URL_TTL_MS);
    if (cached.length > 0) {
      result.cached++;
      // 只上屏：写回会刷新写入时刻，TTL 就永远不过期。
      plan.apply(name, need.forumId, cached);
      continue;
    }
    if (plan.maxFetch > 0 && pending.length >= plan.maxFetch) { continue; }
    pending.push(new ForumAvatarNeed(name, need.forumId));
  }

  if (pending.length === 0) { return result; }

  let next: number = 0;
  const worker = async (): Promise<void> => {
    while (next < pending.length && !plan.stopped()) {
      const need: ForumAvatarNeed = pending[next++];
      let url: string = '';
      try {
        url = await plan.fetch(need.name, need.forumId);
      } catch (e) {
        hilog.warn(0x0000, plan.label, 'avatar %{public}s failed: %{public}s',
          need.name, (e as Error).message);
      }
      if (plan.stopped()) { return; }
      result.fetched++;
      if (url.length === 0) { continue; }
      // 网络刚确认：刷新落盘索引的写入时刻，别的页面也能白拿这份。
      recordFetchedForumAvatar(need.name, url, need.forumId);
      result.resolved++;
      plan.apply(need.name, need.forumId, url);
    }
  };

  const width: number = Math.min(plan.limit, pending.length);
  const workers: Promise<void>[] = [];
  for (let i: number = 0; i < width; i++) { workers.push(worker()); }
  await Promise.all(workers);
  hilog.info(0x0000, plan.label,
    'avatars: %{public}d cached, %{public}d fetched, %{public}d resolved',
    result.cached, result.fetched, result.resolved);
  return result;
}
