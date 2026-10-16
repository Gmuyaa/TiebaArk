

import { TiebaSession } from '../net/TiebaParams';
import { UserProfileInfo } from '../model/UserProfile';

export enum AuthState {

  LOGGED_OUT = 0,

  LOGGED_IN = 1
}

export class LoginResult {
  ok: boolean = false;

  message: string = '';

  credentialRejected: boolean = false;

  static success(): LoginResult {
    const r: LoginResult = new LoginResult();
    r.ok = true;
    return r;
  }

  static failure(message: string, credentialRejected: boolean = false): LoginResult {
    const r: LoginResult = new LoginResult();
    r.ok = false;
    r.message = message;
    r.credentialRejected = credentialRejected;
    return r;
  }
}

export class CredentialBundle {

  bduss: string = '';

  stoken: string = '';

  tbs: string = '';

  isUsable(): boolean {
    return this.bduss.length > 0;
  }

  describeShape(): string {
    return `bduss=${this.bduss.length > 0 ? 'set' : 'empty'}`
      + ` stoken=${this.stoken.length > 0 ? 'set' : 'empty'}`
      + ` tbs=${this.tbs.length > 0 ? 'set' : 'empty'}`;
  }
}

export class AuthSnapshot {
  state: AuthState = AuthState.LOGGED_OUT;

  nickname: string = '';

  uid: number = 0;

  portrait: string = '';

  expiredReason: string = '';

  userName: string = '';

  concernNum: number = 0;

  fansNum: number = 0;

  levelId: number = 0;

  levelScore: number = 0;

  levelTargetScore: number = 0;

  postNum: number = 0;

  totalAgreeNum: number = 0;

  likeForumNum: number = 0;

  tbAge: string = '';

  socialLoaded: boolean = false;

  isLoggedIn(): boolean {
    return this.state === AuthState.LOGGED_IN;
  }

  hasProfile(): boolean {
    return this.uid > 0 || this.nickname.length > 0 || this.portrait.length > 0;
  }

  static loggedOut(): AuthSnapshot {
    return new AuthSnapshot();
  }
}

export function normalizeBduss(input: string): string {
  return input.trim();
}

export function validateBduss(input: string): string {
  const value: string = normalizeBduss(input);
  if (value.length === 0) {
    return '请输入 BDUSS';
  }

  if (value.indexOf(';') >= 0) {
    return '请只填 BDUSS 的值，不要粘贴整条 Cookie';
  }
  if (value.indexOf('BDUSS=') >= 0 || value.indexOf('bduss=') >= 0) {
    return '请去掉开头的 "BDUSS="，只填等号后面的值';
  }
  if (value.indexOf(' ') >= 0 || value.indexOf('\t') >= 0 || value.indexOf('\n') >= 0
    || value.indexOf('\r') >= 0) {
    return 'BDUSS 不能包含空格或换行，请只粘贴 BDUSS 的值';
  }
  if (value.length < 20) {
    return 'BDUSS 长度不对，请确认是否复制完整';
  }
  return '';
}

export function extractBdussFromCookie(cookieText: string): string {
  return extractCookieValue(cookieText, 'BDUSS');
}

export function extractStokenFromCookie(cookieText: string): string {
  return extractCookieValue(cookieText, 'STOKEN');
}

function extractCookieValue(cookieText: string, key: string): string {
  const parts: string[] = cookieText.split(';');
  for (let i = 0; i < parts.length; i++) {
    const piece: string = parts[i].trim();
    const eq: number = piece.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    if (piece.slice(0, eq).trim().toUpperCase() === key.toUpperCase()) {
      return piece.slice(eq + 1).trim();
    }
  }
  return '';
}

export function looksLikeCookieText(input: string): boolean {
  const value: string = input.trim();
  return value.indexOf(';') >= 0 || value.indexOf('=') >= 0;
}

export function credentialsFromUserInput(input: string): CredentialBundle {
  const bundle: CredentialBundle = new CredentialBundle();
  const raw: string = input.trim();
  if (raw.length === 0) {
    return bundle;
  }
  if (looksLikeCookieText(raw)) {
    bundle.bduss = extractBdussFromCookie(raw);
    bundle.stoken = extractStokenFromCookie(raw);
  } else {
    bundle.bduss = normalizeBduss(raw);
  }
  return bundle;
}

export function validateCredentialInput(input: string): string {
  const raw: string = input.trim();
  if (raw.length === 0) {
    return '请输入 BDUSS，或整条 Cookie';
  }
  if (!looksLikeCookieText(raw)) {

    return validateBduss(raw);
  }
  const bundle: CredentialBundle = credentialsFromUserInput(raw);
  if (bundle.bduss.length === 0) {
    return '这段 Cookie 里没有找到 BDUSS，请确认复制完整';
  }

  return validateBduss(bundle.bduss);
}

export function classifyWriteFailure(hasBduss: boolean, hasTbs: boolean): string {
  if (!hasBduss) {
    return '需要登录后才能操作';
  }
  if (!hasTbs) {
    return '登录态缺少 tbs，请重新登录';
  }
  return '';
}

export class AuthAlias {
  static readonly BDUSS: string = 'tieba_bduss';
  static readonly STOKEN: string = 'tieba_stoken';
  static readonly TBS: string = 'tieba_tbs';
}

export const ASSET_NOT_FOUND: number = 24000002;

export function isAssetMissing(code: number): boolean {
  return code === ASSET_NOT_FOUND;
}

export function sessionFromCredentials(credentials: CredentialBundle): TiebaSession {
  const session: TiebaSession = new TiebaSession();
  if (!credentials.isUsable()) {
    return session;
  }
  session.bduss = credentials.bduss;
  session.stoken = credentials.stoken;
  session.tbs = credentials.tbs;
  return session;
}

export function loggedInSnapshot(): AuthSnapshot {
  const snapshot: AuthSnapshot = new AuthSnapshot();
  snapshot.state = AuthState.LOGGED_IN;
  snapshot.nickname = '';
  snapshot.uid = 0;
  snapshot.portrait = '';
  return snapshot;
}

export function expiredSnapshot(reason: string): AuthSnapshot {
  const snapshot: AuthSnapshot = AuthSnapshot.loggedOut();
  snapshot.expiredReason = reason;
  return snapshot;
}

export function snapshotForCredentials(credentials: CredentialBundle): AuthSnapshot {
  return credentials.isUsable() ? loggedInSnapshot() : AuthSnapshot.loggedOut();
}

export function snapshotWithProfile(previous: AuthSnapshot, profile: UserProfileInfo,
  socialLoaded: boolean): AuthSnapshot {
  const next: AuthSnapshot = new AuthSnapshot();
  next.state = previous.state;
  next.expiredReason = previous.expiredReason;

  next.socialLoaded = socialLoaded || previous.socialLoaded;
  next.nickname = profile.nickName.length > 0 ? profile.nickName : previous.nickname;
  next.uid = profile.uid > 0 ? profile.uid : previous.uid;
  next.portrait = profile.portrait.length > 0 ? profile.portrait : previous.portrait;
  next.userName = profile.userName.length > 0 ? profile.userName : previous.userName;
  next.concernNum = profile.concernNum > 0 ? profile.concernNum : previous.concernNum;
  next.fansNum = profile.fansNum > 0 ? profile.fansNum : previous.fansNum;
  next.levelId = profile.levelId > 0 ? profile.levelId : previous.levelId;
  next.levelScore = profile.levelScore > 0 ? profile.levelScore : previous.levelScore;
  next.levelTargetScore = profile.levelTargetScore > 0
    ? profile.levelTargetScore : previous.levelTargetScore;
  next.postNum = profile.postNum > 0 ? profile.postNum : previous.postNum;
  next.totalAgreeNum = profile.totalAgreeNum > 0 ? profile.totalAgreeNum : previous.totalAgreeNum;
  next.likeForumNum = profile.likeForumNum > 0 ? profile.likeForumNum : previous.likeForumNum;
  next.tbAge = profile.tbAge.length > 0 ? profile.tbAge : previous.tbAge;
  return next;
}

export function loggedInSnapshotCarrying(previous: AuthSnapshot): AuthSnapshot {
  const next: AuthSnapshot = loggedInSnapshot();
  next.nickname = previous.nickname;
  next.uid = previous.uid;
  next.portrait = previous.portrait;
  next.userName = previous.userName;
  next.concernNum = previous.concernNum;
  next.fansNum = previous.fansNum;
  next.levelId = previous.levelId;
  next.levelScore = previous.levelScore;
  next.levelTargetScore = previous.levelTargetScore;
  next.postNum = previous.postNum;
  next.totalAgreeNum = previous.totalAgreeNum;
  next.likeForumNum = previous.likeForumNum;
  next.tbAge = previous.tbAge;
  next.socialLoaded = previous.socialLoaded;
  return next;
}

