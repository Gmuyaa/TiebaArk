import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { encodeUtf8 } from '../utils/TextCodec';

// Only display fields are serialized. In particular, no session, response body or thread data enters this file.
export interface StoredForumItem {
  fid: number; fname: string; avatar: string; level: number; levelName: string;
  currentScore: number; nextScore: number; isSigned: boolean; signKnown: boolean;
}
export interface StoredForumHeader {
  fid: number; fname: string; avatar: string; followed: boolean | undefined;
  level: number; levelName: string; currentScore: number; nextScore: number;
  signed: boolean | undefined; missedDays: number;
  continuousCount?: number; totalCount?: number;
  day: string; accessedAt: number; fetchedAt: number;
}
export interface StoredForumSnapshot {
  version: number; uid: number; fetchedAt: number; day: string;
  guideFetchedAt: number; guideDay: string; hasGuide: boolean; hasMore: boolean;
  items: StoredForumItem[]; headers: StoredForumHeader[];
}

const VERSION: number = 1;
const MAX_AGE_MS: number = 7 * 24 * 60 * 60 * 1000;
const MAX_BYTES: number = 512 * 1024;
const MAX_ACCOUNT_FILES: number = 4;
let writeQueue: Promise<void> = Promise.resolve();
let pending: StoredForumSnapshot | undefined = undefined;
let pendingContext: common.UIAbilityContext | undefined = undefined;
let timer: number = -1;

function path(context: common.UIAbilityContext, uid: number): string {
  return `${context.filesDir}/forum-read-v${VERSION}-${uid}.json`;
}

function validItem(item: StoredForumItem): boolean {
  return Number.isSafeInteger(item.fid) && item.fid > 0 && typeof item.fname === 'string' &&
    typeof item.avatar === 'string' && typeof item.level === 'number' &&
    typeof item.levelName === 'string' && typeof item.currentScore === 'number' &&
    typeof item.nextScore === 'number' && typeof item.isSigned === 'boolean' &&
    typeof item.signKnown === 'boolean';
}

class SnapshotFile {
  path: string = '';
  modified: number = 0;
}

/** 离线吧信息属于 filesDir 的显示快照：不扫用户数据，只治理本模块确定的文件名。 */
export function trimForumSnapshotFiles(context: common.UIAbilityContext, keepUid: number): void {
  try {
    const files: SnapshotFile[] = [];
    const now: number = Date.now();
    for (const name of fileIo.listFileSync(context.filesDir)) {
      if (!/^forum-read-v1-[1-9][0-9]*\.json(?:\.tmp)?$/.test(name)) { continue; }
      const filename: string = `${context.filesDir}/${name}`;
      const stat: fileIo.Stat = fileIo.lstatSync(filename);
      if (stat.isSymbolicLink() || !stat.isFile()) { continue; }
      const age: number = now - stat.mtime * 1000;
      const temporary: boolean = name.endsWith('.tmp');
      if ((temporary && age > 10 * 60 * 1000) || age > MAX_AGE_MS || stat.size > MAX_BYTES) {
        fileIo.unlinkSync(filename);
      } else if (!temporary) {
        const item: SnapshotFile = new SnapshotFile();
        item.path = filename; item.modified = stat.mtime;
        files.push(item);
      }
    }
    files.sort((a: SnapshotFile, b: SnapshotFile): number => a.modified - b.modified);
    let count: number = files.length;
    const keep: string = path(context, keepUid);
    for (const item of files) {
      if (count <= MAX_ACCOUNT_FILES) { break; }
      if (item.path !== keep) { fileIo.unlinkSync(item.path); count -= 1; }
    }
  } catch (_) { /* 维护失败不影响读取；既有加载仍校验大小、内容和7天有效期。 */ }
}

export function loadForumSnapshot(context: common.UIAbilityContext, uid: number): StoredForumSnapshot | undefined {
  if (!Number.isSafeInteger(uid) || uid <= 0) { return undefined; }
  trimForumSnapshotFiles(context, uid);
  try {
    const filename: string = path(context, uid);
    if (!fileIo.accessSync(filename) || fileIo.statSync(filename).size > MAX_BYTES) { return undefined; }
    const value: StoredForumSnapshot = JSON.parse(fileIo.readTextSync(filename)) as StoredForumSnapshot;
    const age: number = Date.now() - value.fetchedAt;
    if (value.version !== VERSION || value.uid !== uid || !Number.isFinite(age) || age < 0 ||
      age > MAX_AGE_MS || !Array.isArray(value.items) || !Array.isArray(value.headers) ||
      typeof value.hasGuide !== 'boolean' || typeof value.hasMore !== 'boolean' ||
      typeof value.day !== 'string' || typeof value.guideDay !== 'string' ||
      typeof value.guideFetchedAt !== 'number' || value.headers.length > 256 ||
      !value.items.every(validItem)) { return undefined; }
    for (const header of value.headers) {
      if (!Number.isSafeInteger(header.fid) || header.fid <= 0 || typeof header.fname !== 'string' ||
        typeof header.avatar !== 'string' || typeof header.level !== 'number' ||
        typeof header.levelName !== 'string' || typeof header.currentScore !== 'number' ||
        typeof header.nextScore !== 'number' || typeof header.day !== 'string' ||
        typeof header.accessedAt !== 'number' || typeof header.fetchedAt !== 'number' ||
        typeof header.missedDays !== 'number' ||
        (header.continuousCount !== undefined && !Number.isSafeInteger(header.continuousCount)) ||
        (header.totalCount !== undefined && !Number.isSafeInteger(header.totalCount))) { return undefined; }
    }
    return value;
  } catch (_) { return undefined; }
}

function fit(snapshot: StoredForumSnapshot): string {
  // Header LRU is the only bounded collection. The guide retains the actual fetched range.
  snapshot.headers.sort((a: StoredForumHeader, b: StoredForumHeader): number => a.accessedAt - b.accessedAt);
  while (snapshot.headers.length > 256) { snapshot.headers.shift(); }
  while (snapshot.headers.length > 0) {
    const body: string = JSON.stringify(snapshot);
    if (encodeUtf8(body).byteLength <= MAX_BYTES) { return body; }
    snapshot.headers.shift();
  }
  return JSON.stringify(snapshot);
}

function write(context: common.UIAbilityContext, snapshot: StoredForumSnapshot): void {
  const body: string = fit(snapshot);
  if (encodeUtf8(body).byteLength > MAX_BYTES) { return; }
  const filename: string = path(context, snapshot.uid);
  const temp: string = `${filename}.tmp`;
  const file: fileIo.File = fileIo.openSync(temp,
    fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  try {
    fileIo.writeSync(file.fd, body);
    fileIo.fsyncSync(file.fd);
  } finally { fileIo.closeSync(file); }
  fileIo.renameSync(temp, filename);
  trimForumSnapshotFiles(context, snapshot.uid);
}

function flush(): void {
  if (timer >= 0) { clearTimeout(timer); timer = -1; }
  const snapshot: StoredForumSnapshot | undefined = pending;
  const context: common.UIAbilityContext | undefined = pendingContext;
  pending = undefined; pendingContext = undefined;
  if (snapshot === undefined || context === undefined) { return; }
  writeQueue = writeQueue.then((): void => { write(context, snapshot); }).catch((): void => {});
}

export function saveForumSnapshot(context: common.UIAbilityContext, snapshot: StoredForumSnapshot,
  urgent: boolean = false): void {
  pending = snapshot; pendingContext = context;
  if (urgent) { flush(); return; }
  if (timer < 0) { timer = setTimeout(flush, 500) as number; }
}

export function deleteForumSnapshot(context: common.UIAbilityContext, uid: number): Promise<void> {
  if (uid <= 0) { return Promise.resolve(); }
  if (pending?.uid === uid) {
    if (timer >= 0) { clearTimeout(timer); timer = -1; }
    pending = undefined; pendingContext = undefined;
  }
  writeQueue = writeQueue.then((): void => {
    const filename: string = path(context, uid);
    if (fileIo.accessSync(filename)) { fileIo.unlinkSync(filename); }
  }).catch((): void => {});
  return writeQueue;
}
