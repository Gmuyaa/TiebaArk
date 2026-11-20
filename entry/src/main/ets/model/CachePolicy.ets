
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
