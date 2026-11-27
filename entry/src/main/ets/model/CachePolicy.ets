
export const IMAGE_DISK_CACHE_BYTES: number = 32 * 1024 * 1024;
export const EXPORT_CACHE_BYTES: number = 32 * 1024 * 1024;
export const EXPORT_CACHE_FILES: number = 32;
export const EXPORT_CACHE_MAX_AGE_MS: number = 24 * 60 * 60 * 1000;

/** 只接纳单 entry 模块由 Context 返回的 EL1/EL2 缓存根目录。 */
export function isApplicationCacheRoot(path: string): boolean {
  return /^\/data\/storage\/el[12]\/base(?:\/haps\/entry)?\/cache$/.test(path);
}

export function isCacheEntryName(name: string): boolean {
  return name.length > 0 && name !== '.' && name !== '..' && name.indexOf('/') < 0 &&
    name.indexOf('\\') < 0;
}

/** 最近关注状态强引用上限；活跃页面另通过弱索引共享实例。 */
export const FOLLOW_ACTION_CACHE_ENTRIES: number = 256;

/**
 * 吧级身份状态（关注关系 + 今日签到 + 等级/经验/连签）的内存预算，真值源在本文件。
 *
 * `viewmodel/ForumStateStore` 按「账号 + fid」一份实例，页面只订阅不各自读；回前台与写核对
 * 一律 force 绕过复用期。条目按最近使用淘汰，换号整体清空。
 *
 * 今日签到：今天已确认「已签到」是单调事实（一天只能签一次），不论过期都直接采用、不再请求；
 * 未签到/未知才按复用期重读，以捕捉在其它客户端签到的情况。
 */
export const FORUM_FOLLOW_FRESH_MS: number = 10 * 60 * 1000;
export const FORUM_SIGN_FRESH_MS: number = 5 * 60 * 1000;
export const FORUM_IDENTITY_CACHE_ENTRIES: number = 256;

/**
 * 落盘吧头像 URL 的复用时长（`model/ForumAvatarCache` 用）。
 *
 * 服务端给的地址带时效签名（`?tbpicau=<年-月-日-时>_<hex>`），不能无限复用；过期或加载失败
 * 都会重新取一次并覆盖写入（见 `getCachedForumAvatarUrl` / `forgetCachedForumAvatar`）。
 */
export const FORUM_AVATAR_URL_TTL_MS: number = 6 * 60 * 60 * 1000;

/** 吧页会话态（`viewmodel/ForumPageStore`）的 LRU 上限；换号整体清空，进程结束释放。 */
export const FORUM_PAGE_STATE_CACHE_ENTRIES: number = 24;

/** 草稿（`utils/DraftStore`）的用户数据容量上限：最多保留 4 个账号桶，每账号最多 32 条回复草稿。 */
export const DRAFT_MAX_ACCOUNTS: number = 4;
export const REPLY_DRAFT_MAX_ENTRIES: number = 32;

/** 私信本地历史库（`utils/ChatHistoryStore`）预算：最多 4 账号、每账号最多 40 会话 × 200 条消息。 */
export const CHAT_HISTORY_MAX_ACCOUNTS: number = 4;
export const CHAT_HISTORY_MAX_GROUPS: number = 40;
export const CHAT_HISTORY_MAX_MESSAGES_PER_GROUP: number = 200;

/** 多账号名册（`auth/AccountRosterStore`）上限：仅存公开资料，凭据在 Asset Store。 */
export const ACCOUNT_ROSTER_MAX_ENTRIES: number = 8;

/** 浏览历史（`utils/BrowseHistory`）账号桶上限：每账号仍沿用 200 条上限。 */
export const BROWSE_HISTORY_MAX_ACCOUNTS: number = 4;
