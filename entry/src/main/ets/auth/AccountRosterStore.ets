/**
 * 多账号切换公开名册：只保存 UID、昵称、用户名、头像与最近使用时间，严禁写入 BDUSS/STOKEN/TBS。
 */
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ACCOUNT_ROSTER_MAX_ENTRIES } from '../model/CachePolicy';

const STORE_NAME: string = 'tieba_account_roster';
const KEY_ACCOUNTS: string = 'accounts_v1';

export class SavedAccount {
  uid: number = 0;
  nickname: string = '';
  userName: string = '';
  portrait: string = '';
  savedAt: number = 0;

  displayName(): string {
    if (this.nickname.length > 0) { return this.nickname; }
    if (this.userName.length > 0) { return this.userName; }
    return this.uid > 0 ? `UID ${this.uid}` : '贴吧账号';
  }
}

interface RawSavedAccount {
  uid?: number;
  nickname?: string;
  userName?: string;
  portrait?: string;
  savedAt?: number;
}

class StoredAccountRecord implements RawSavedAccount {
  uid: number = 0;
  nickname: string = '';
  userName: string = '';
  portrait: string = '';
  savedAt: number = 0;
}

function getPrefs(context: common.Context): preferences.Preferences | undefined {
  try {
    return preferences.getPreferencesSync(context, { name: STORE_NAME });
  } catch (_) {
    return undefined;
  }
}

function writeAccounts(prefs: preferences.Preferences, list: SavedAccount[]): void {
  const records: StoredAccountRecord[] = [];
  for (let i: number = 0; i < list.length && records.length < ACCOUNT_ROSTER_MAX_ENTRIES; i++) {
    const item: SavedAccount = list[i];
    if (!Number.isSafeInteger(item.uid) || item.uid <= 0) { continue; }
    const rec: StoredAccountRecord = new StoredAccountRecord();
    rec.uid = item.uid;
    rec.nickname = item.nickname;
    rec.userName = item.userName;
    rec.portrait = item.portrait;
    rec.savedAt = item.savedAt;
    records.push(rec);
  }
  try {
    prefs.putSync(KEY_ACCOUNTS, JSON.stringify(records));
    prefs.flush().catch((): void => {});
  } catch (_) {}
}

export function loadAccountRoster(context: common.Context): SavedAccount[] {
  const prefs: preferences.Preferences | undefined = getPrefs(context);
  if (prefs === undefined) { return []; }
  try {
    const rawText: string = String(prefs.getSync(KEY_ACCOUNTS, ''));
    if (rawText.length === 0) { return []; }
    const parsed: RawSavedAccount[] = JSON.parse(rawText) as RawSavedAccount[];
    if (!Array.isArray(parsed)) { return []; }
    const out: SavedAccount[] = [];
    const seen: Set<number> = new Set<number>();
    for (let i: number = 0; i < parsed.length && out.length < ACCOUNT_ROSTER_MAX_ENTRIES; i++) {
      const r: RawSavedAccount = parsed[i];
      if (typeof r.uid !== 'number' || !Number.isSafeInteger(r.uid) || r.uid <= 0 || seen.has(r.uid)) {
        continue;
      }
      seen.add(r.uid);
      const item: SavedAccount = new SavedAccount();
      item.uid = r.uid;
      item.nickname = typeof r.nickname === 'string' ? r.nickname : '';
      item.userName = typeof r.userName === 'string' ? r.userName : '';
      item.portrait = typeof r.portrait === 'string' ? r.portrait : '';
      item.savedAt = typeof r.savedAt === 'number' && Number.isFinite(r.savedAt) ? r.savedAt : 0;
      out.push(item);
    }
    out.sort((a: SavedAccount, b: SavedAccount): number => b.savedAt - a.savedAt);
    return out;
  } catch (_) {
    return [];
  }
}

export function upsertAccountRoster(context: common.Context, entry: SavedAccount): SavedAccount[] {
  if (!Number.isSafeInteger(entry.uid) || entry.uid <= 0) {
    return loadAccountRoster(context);
  }
  const list: SavedAccount[] = loadAccountRoster(context).filter((a: SavedAccount): boolean => a.uid !== entry.uid);
  const next: SavedAccount = new SavedAccount();
  next.uid = entry.uid;
  next.nickname = entry.nickname;
  next.userName = entry.userName;
  next.portrait = entry.portrait;
  next.savedAt = entry.savedAt > 0 ? entry.savedAt : Date.now();
  list.unshift(next);
  const trimmed: SavedAccount[] = list.length > ACCOUNT_ROSTER_MAX_ENTRIES
    ? list.slice(0, ACCOUNT_ROSTER_MAX_ENTRIES) : list;
  const prefs: preferences.Preferences | undefined = getPrefs(context);
  if (prefs !== undefined) { writeAccounts(prefs, trimmed); }
  return trimmed;
}

export function removeAccountRoster(context: common.Context, uid: number): SavedAccount[] {
  const list: SavedAccount[] = loadAccountRoster(context).filter((a: SavedAccount): boolean => a.uid !== uid);
  const prefs: preferences.Preferences | undefined = getPrefs(context);
  if (prefs !== undefined) { writeAccounts(prefs, list); }
  return list;
}
