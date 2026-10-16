

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { authSession } from '../auth/AuthSession';
import {
  BlockRules, BlockedUser, HiddenThread, blockedUserUids, emptyRules, mergeBlockedUser,
  mergeHiddenThread, mergeRules, normalizeForumName, normalizeForumNames, parseBlockedUsers,
  parseHiddenThreads, removeBlockedUser, removeHiddenThread, serializeBlockedUsers,
  serializeHiddenThreads
} from '../model/ThreadBlock';

const STORE: string = 'tieba_thread_block';
const KEY_HIDDEN: string = 'hidden_threads';
const KEY_FORUMS: string = 'blocked_forums';

const KEY_USERS: string = 'blocked_users';

interface RawStringList {
  values?: string[];
}

function ownerKey(): string {
  return authSession.isLoggedIn() ? String(authSession.snapshot.uid) : 'anonymous';
}

function scoped(base: string, owner: string): string {
  return `${base}_${owner}`;
}

@ObservedV2
export class ThreadBlockStore {

  @Trace hidden: HiddenThread[] = [];

  @Trace blockedForums: string[] = [];

  @Trace blockedUsers: BlockedUser[] = [];

  private owner: string = '';
  private loadingOwner: string = '';
  private loaded: boolean = false;
  private loading: Promise<void> | undefined = undefined;

  async load(context: common.UIAbilityContext): Promise<void> {
    const current: string = ownerKey();
    if (this.loading !== undefined && this.loadingOwner === current) { return this.loading; }
    if (this.loaded && this.owner === current) { return; }
    this.loadingOwner = current;
    const pending: Promise<void> = this.read(context, current, authSession.sessionKey());
    this.loading = pending;
    try { await pending; } finally { if (this.loading === pending) { this.loading = undefined; } }
  }

  private async read(context: common.UIAbilityContext, current: string, session: string): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      const hiddenRaw: string = (await store.get(KEY_HIDDEN, '')) as string;

      const forumsRaw: string = (await store.get(scoped(KEY_FORUMS, current), '')) as string;

      const usersRaw: string = (await store.get(scoped(KEY_USERS, current), '')) as string;
      if (current !== ownerKey() || session !== authSession.sessionKey()) { return; }
      this.hidden = parseHiddenThreads(hiddenRaw);
      this.blockedForums = parseForumList(forumsRaw);
      this.blockedUsers = parseBlockedUsers(usersRaw);
      this.owner = current;
      this.loaded = true;
    } catch (e) {
      if (current !== ownerKey() || session !== authSession.sessionKey()) { return; }
      hilog.warn(0x0, 'TiebaThreadBlock', 'block load failed: %{public}s', String(e));

      this.owner = current;
      this.hidden = [];
      this.blockedForums = [];
      this.blockedUsers = [];
    }
  }

  rules(): BlockRules {
    if (this.owner !== ownerKey()) { return emptyRules(); }
    return mergeRules(this.blockedForums, [], blockedUserUids(this.blockedUsers), this.hidden);
  }

  isHidden(tid: number): boolean {
    for (const item of this.hidden) {
      if (item.tid === tid) { return true; }
    }
    return false;
  }

  async hide(context: common.UIAbilityContext, item: HiddenThread): Promise<void> {
    if (item.tid <= 0) { return; }
    this.hidden = mergeHiddenThread(this.hidden, item);
    await this.persist(context, KEY_HIDDEN, serializeHiddenThreads(this.hidden));
  }

  async unhide(context: common.UIAbilityContext, tid: number): Promise<void> {
    this.hidden = removeHiddenThread(this.hidden, tid);
    await this.persist(context, KEY_HIDDEN, serializeHiddenThreads(this.hidden));
  }

  async rememberBlockedForum(context: common.UIAbilityContext, forumName: string): Promise<void> {
    const session: string = authSession.sessionKey();
    await this.load(context);
    if (session !== authSession.sessionKey()) { return; }
    const name: string = normalizeForumName(forumName);
    if (name.length === 0) { return; }
    this.blockedForums = normalizeForumNames(this.blockedForums.concat([name]));
    await this.persist(context, scoped(KEY_FORUMS, ownerKey()),
      JSON.stringify({ values: this.blockedForums }));
  }

  async forgetBlockedForum(context: common.UIAbilityContext, forumName: string): Promise<void> {
    const session: string = authSession.sessionKey();
    await this.load(context);
    if (session !== authSession.sessionKey()) { return; }
    const name: string = normalizeForumName(forumName);
    const kept: string[] = [];
    for (const item of this.blockedForums) {
      if (item !== name) { kept.push(item); }
    }
    this.blockedForums = kept;
    await this.persist(context, scoped(KEY_FORUMS, ownerKey()),
      JSON.stringify({ values: this.blockedForums }));
  }

  async rememberBlockedUser(context: common.UIAbilityContext, uid: number, name: string): Promise<void> {
    const session: string = authSession.sessionKey();
    await this.load(context);
    if (session !== authSession.sessionKey()) { return; }
    if (!Number.isSafeInteger(uid) || uid <= 0) { return; }
    const user: BlockedUser = new BlockedUser();
    user.uid = uid;
    user.name = name;
    user.timeMs = Date.now();
    this.blockedUsers = mergeBlockedUser(this.blockedUsers, user);
    await this.persist(context, scoped(KEY_USERS, ownerKey()),
      serializeBlockedUsers(this.blockedUsers));
  }

  async forgetBlockedUser(context: common.UIAbilityContext, uid: number): Promise<void> {
    const session: string = authSession.sessionKey();
    await this.load(context);
    if (session !== authSession.sessionKey()) { return; }
    this.blockedUsers = removeBlockedUser(this.blockedUsers, uid);
    await this.persist(context, scoped(KEY_USERS, ownerKey()),
      serializeBlockedUsers(this.blockedUsers));
  }

  async replaceBlockedForums(context: common.UIAbilityContext, forums: string[], complete: boolean = true): Promise<void> {
    const session: string = authSession.sessionKey();
    await this.load(context);
    if (session !== authSession.sessionKey()) { return; }
    this.blockedForums = normalizeForumNames(complete ? forums : this.blockedForums.concat(forums));
    await this.persist(context, scoped(KEY_FORUMS, ownerKey()),
      JSON.stringify({ values: this.blockedForums }));
  }

  resetAccount(): void {
    this.blockedForums = [];
    this.blockedUsers = [];
    this.owner = '';
    this.loaded = false;
  }

  private async persist(context: common.UIAbilityContext, key: string, value: string): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE);
      await store.put(key, value);
      await store.flush();
    } catch (e) {

      hilog.warn(0x0, 'TiebaThreadBlock', 'block persist failed: %{public}s', String(e));
    }
  }
}

function parseForumList(raw: string): string[] {
  if (raw.length === 0) { return []; }
  try {
    const parsed: RawStringList = JSON.parse(raw) as RawStringList;
    if (parsed === null || parsed === undefined || !Array.isArray(parsed.values)) { return []; }
    const values: string[] = [];
    for (const item of parsed.values) {
      if (typeof item === 'string') { values.push(item); }
    }
    return normalizeForumNames(values);
  } catch (err) {
    return [];
  }
}

export const threadBlockStore: ThreadBlockStore = new ThreadBlockStore();
