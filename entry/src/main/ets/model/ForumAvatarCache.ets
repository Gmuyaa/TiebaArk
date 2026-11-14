/**
 * 吧头像落盘索引（纯逻辑）：吧名 → fid + 头像 URL + 写入时刻。
 *
 * 为什么值得落盘：
 * - **fid 永久稳定**且是公开标识，记住它之后反查就能走轻量端点 `getforumdetail`
 *   （真机 A/B：中位 364ms）而不是按吧名拉整页 `frs/page`（中位 1066ms）；
 *   收藏列表的 `store_thread[]` 里**没有** fid（2026-11-13 真机 dump 实证），
 *   所以这张表是收藏页唯一能变快的手段。
 * - 头像 URL 带签名时效（`?tbpicau=<年-月-日-时>_<hex>`），不能无限复用；
 *   这里记下写入时刻，读取方按固定 TTL 判定"还能用"还是"该重新取一次"。
 *
 * 本文件不引任何 `@kit.*`：Node 与真机跑同一份逻辑（见 tools/verify 镜像）。
 */

/** 条数上限：与内存表一致；吧数量远小于帖子量，512 足够 */
export const FORUM_AVATAR_CACHE_MAX: number = 512;

/** 落盘快照版本：格式改动时递增，旧版本整体丢弃而不是硬解析 */
export const FORUM_AVATAR_SNAPSHOT_VERSION: number = 1;

/** 一条落盘记录 */
export class ForumAvatarCacheEntry {
  name: string = '';
  fid: number = 0;
  url: string = '';
  savedAtMs: number = 0;
}

/** 快照里的一行：[吧名, fid, 头像URL, 写入时刻]（数组形态，便于 JSON 紧凑存储） */
type ForumAvatarRow = Object[];

export class ForumAvatarCache {
  private entries: Map<string, ForumAvatarCacheEntry> = new Map<string, ForumAvatarCacheEntry>();
  /** 有改动但还没落盘 */
  private dirty: boolean = false;

  size(): number {
    return this.entries.size;
  }

  isDirty(): boolean {
    return this.dirty;
  }

  /** 落盘完成后由平台层调用 */
  markSaved(): void {
    this.dirty = false;
  }

  markDirty(): void {
    this.dirty = true;
  }

  /**
   * 记一条（同名覆盖为新值）。fid / url 为 0 或空串表示"这次没有该字段"，不覆盖已有的有效值。
   *
   * `refreshTime` 决定是否把"写入时刻"（TTL 判据）更新为 `nowMs`：
   * - **false**（默认）：只有 URL 真的换了才更新时刻。把落盘地址读出来重新写回索引时
   *   必须走这条，否则每读一次就续命一次，TTL 永远不会到期；
   * - **true**：确实刚从网络拿到当前地址（即使签名没变也算"这次确认过"），刷新时刻。
   *
   * @returns 内容真的变化了才返回 true（调用方据此决定要不要重新落盘）
   */
  remember(forumName: string, forumId: number, avatarUrl: string, nowMs: number,
    refreshTime: boolean = false): boolean {
    const name: string = forumName.trim();
    if (name.length === 0) {
      return false;
    }
    const url: string = avatarUrl.trim();
    const existing: ForumAvatarCacheEntry | undefined = this.entries.get(name);
    if (existing !== undefined) {
      const nextId: number = Number.isSafeInteger(forumId) && forumId > 0 ? forumId : existing.fid;
      const nextUrl: string = url.length > 0 ? url : existing.url;
      const urlChanged: boolean = nextUrl !== existing.url;
      const changed: boolean = nextId !== existing.fid || urlChanged;
      if (!changed && !refreshTime) {
        return false;
      }
      const out: ForumAvatarCacheEntry = new ForumAvatarCacheEntry();
      out.name = name;
      out.fid = nextId;
      out.url = nextUrl;
      out.savedAtMs = urlChanged || refreshTime ? nowMs : existing.savedAtMs;
      this.entries.set(name, out);
      this.dirty = true;
      return true;
    }
    const out: ForumAvatarCacheEntry = new ForumAvatarCacheEntry();
    out.name = name;
    out.fid = Number.isSafeInteger(forumId) && forumId > 0 ? forumId : 0;
    out.url = url;
    out.savedAtMs = nowMs;
    this.evictIfFull(name);
    this.entries.set(name, out);
    this.dirty = true;
    return true;
  }

  /** 记住 fid（不动 URL / 时间戳时按调用方给的 nowMs 更新写入时刻） */
  fidOf(forumName: string): number {
    const name: string = forumName.trim();
    if (name.length === 0) {
      return 0;
    }
    return this.entries.get(name)?.fid ?? 0;
  }

  /**
   * 取可复用的头像 URL。
   *
   * @param ttlMs >0 时按写入时刻判新鲜：超过 TTL 返回空串（调用方重新请求一次并覆盖写入）。
   *   0 = 不判新鲜度（当前未使用）。
   */
  urlOf(forumName: string, nowMs: number = 0, ttlMs: number = 0): string {
    const name: string = forumName.trim();
    if (name.length === 0) {
      return '';
    }
    const entry: ForumAvatarCacheEntry | undefined = this.entries.get(name);
    if (entry === undefined || entry.url.length === 0) {
      return '';
    }
    if (ttlMs > 0) {
      const age: number = nowMs - entry.savedAtMs;
      // 时间戳异常（未来时间）按过期处理：宁可多查一次，也不拿不可判定的地址去加载
      if (entry.savedAtMs <= 0 || age < 0 || age >= ttlMs) {
        return '';
      }
    }
    return entry.url;
  }

  /** 丢弃一条（URL 加载失败时用：下次按名/按 ID 重新取） */
  forget(forumName: string): void {
    const name: string = forumName.trim();
    if (name.length > 0 && this.entries.delete(name)) {
      this.dirty = true;
    }
  }

  clear(): void {
    if (this.entries.size > 0) {
      this.dirty = true;
    }
    this.entries.clear();
  }

  /** 序列化为落盘 JSON；条目按写入时刻升序，读回时顺序即淘汰顺序 */
  serialize(): string {
    const rows: ForumAvatarRow[] = [];
    this.entries.forEach((entry: ForumAvatarCacheEntry): void => {
      const row: ForumAvatarRow = [entry.name, entry.fid, entry.url, entry.savedAtMs];
      rows.push(row);
    });
    rows.sort((a: ForumAvatarRow, b: ForumAvatarRow): number => Number(a[3]) - Number(b[3]));
    const head: string = `{"version":${FORUM_AVATAR_SNAPSHOT_VERSION},"entries":[`;
    const body: string[] = [];
    for (let i: number = 0; i < rows.length; i++) {
      body.push(JSON.stringify(rows[i]));
    }
    return `${head}${body.join(',')}]}`;
  }

  /**
   * 从落盘 JSON 还原。坏数据（非法 JSON / 未知版本 / 单行格式不对）整条忽略，
   * 绝不让一份损坏的缓存把页面卡住。
   * @returns 还原成功的条数
   */
  hydrate(text: string, enforceMax: boolean = true): number {
    this.entries.clear();
    if (text.length === 0) {
      return 0;
    }
    let raw: Object | undefined = undefined;
    try {
      raw = JSON.parse(text) as Object;
    } catch (err) {
      return 0;
    }
    if (raw === null || raw === undefined) {
      return 0;
    }
    const wrapper: Record<string, Object> = raw as Record<string, Object>;
    if (Number(wrapper.version) !== FORUM_AVATAR_SNAPSHOT_VERSION) {
      return 0;
    }
    const list: Object = wrapper.entries as Object;
    if (!Array.isArray(list)) {
      return 0;
    }
    const rows: Object[] = list as Object[];
    let loaded: number = 0;
    for (let i: number = 0; i < rows.length; i++) {
      const row: Object = rows[i];
      if (!Array.isArray(row)) {
        continue;
      }
      const fields: Object[] = row as Object[];
      if (fields.length < 4) {
        continue;
      }
      const name: string = typeof fields[0] === 'string' ? (fields[0] as string).trim() : '';
      if (name.length === 0) {
        continue;
      }
      const fid: number = Number(fields[1]);
      const url: string = typeof fields[2] === 'string' ? fields[2] as string : '';
      const savedAt: number = Number(fields[3]);
      const entry: ForumAvatarCacheEntry = new ForumAvatarCacheEntry();
      entry.name = name;
      entry.fid = Number.isSafeInteger(fid) && fid > 0 ? fid : 0;
      entry.url = url;
      entry.savedAtMs = Number.isFinite(savedAt) && savedAt > 0 ? savedAt : 0;
      this.evictIfFull(name);
      this.entries.set(name, entry);
      loaded++;
    }
    if (enforceMax && this.entries.size > FORUM_AVATAR_CACHE_MAX) {
      this.trimToMax();
    }
    this.dirty = false;
    return loaded;
  }

  /** 插入新键前按插入序淘汰最早的一条（同名覆盖不更新插入序，可接受） */
  private evictIfFull(key: string): void {
    if (!this.entries.has(key) && this.entries.size >= FORUM_AVATAR_CACHE_MAX) {
      const oldest: IteratorResult<string> = this.entries.keys().next();
      if (!oldest.done) {
        this.entries.delete(oldest.value);
      }
    }
  }

  /** 超出上限时按写入时刻淘汰最旧的一批（hydrate 后兜底） */
  private trimToMax(): void {
    const rows: ForumAvatarCacheEntry[] = [];
    this.entries.forEach((entry: ForumAvatarCacheEntry): void => {
      rows.push(entry);
    });
    rows.sort((a: ForumAvatarCacheEntry, b: ForumAvatarCacheEntry): number => a.savedAtMs - b.savedAtMs);
    const overflow: number = rows.length - FORUM_AVATAR_CACHE_MAX;
    for (let i: number = 0; i < overflow; i++) {
      this.entries.delete(rows[i].name);
    }
  }
}

/** 进程级单例：会话内所有页面共用一份（落盘由 utils/ForumAvatarPrefs 负责） */
export const forumAvatarCache: ForumAvatarCache = new ForumAvatarCache();
