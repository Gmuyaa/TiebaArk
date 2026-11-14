/**
 * 吧头像落盘索引的读写（平台层）。纯逻辑在 `model/ForumAvatarCache.ets`。
 *
 * 落盘时机：内容变化后由本文件的定时器兜底刷新（最多 10s 一次），
 * 不在每次补图时都写 Preferences —— 收藏页首进会连续学到十几个吧的 fid。
 * 整个快照只有几百条、几十 KB，读写在后台线程队列里串行执行。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { forumAvatarCache } from '../model/ForumAvatarCache';

const STORE_NAME: string = 'tieba_forum_avatar_cache';
const KEY_SNAPSHOT: string = 'snapshot';
/** 兜底刷新间隔：有改动才真的写盘 */
const FLUSH_INTERVAL_MS: number = 10000;

let hostContext: common.UIAbilityContext | undefined = undefined;
let loaded: boolean = false;
let flushTimer: number = -1;
let writeQueue: Promise<void> = Promise.resolve();

/** 启动时读一次；重复调用直接返回（读失败就是空表，补图退化成"按吧名查"，不影响功能） */
export async function initForumAvatarCache(context: common.UIAbilityContext): Promise<void> {
  hostContext = context;
  if (flushTimer < 0) {
    flushTimer = setInterval((): void => {
      if (forumAvatarCache.isDirty()) {
        void flushForumAvatarCache();
      }
    }, FLUSH_INTERVAL_MS);
  }
  if (loaded) {
    return;
  }
  loaded = true;
  try {
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
    const text: string = (await store.get(KEY_SNAPSHOT, '')) as string;
    if (text.length > 0) {
      const count: number = forumAvatarCache.hydrate(text);
      hilog.info(0x0000, 'ForumAvatarPrefs', 'loaded entries=%{public}d', count);
    }
  } catch (err) {
    hilog.warn(0x0000, 'ForumAvatarPrefs', 'load failed: %{public}s', (err as Error).message);
  }
}

/** 立刻落盘（页面隐藏 / 退出前可主动调；定时器也会兜底） */
export async function flushForumAvatarCache(): Promise<void> {
  const context: common.UIAbilityContext | undefined = hostContext;
  if (context === undefined || !forumAvatarCache.isDirty()) {
    return;
  }
  const text: string = forumAvatarCache.serialize();
  forumAvatarCache.markSaved();
  writeQueue = writeQueue.then(async (): Promise<void> => {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
      await store.put(KEY_SNAPSHOT, text);
      await store.flush();
    } catch (err) {
      // 写失败就把脏标记放回来，下次定时器再试；缓存丢一次不影响功能
      forumAvatarCache.markDirty();
      hilog.warn(0x0000, 'ForumAvatarPrefs', 'save failed: %{public}s', (err as Error).message);
    }
  });
  return writeQueue;
}

/** 停止兜底定时器（进程/页面生命周期收尾用；读回后可通过 init 重新装） */
export function disposeForumAvatarCache(): void {
  if (flushTimer >= 0) {
    clearInterval(flushTimer);
    flushTimer = -1;
  }
}
