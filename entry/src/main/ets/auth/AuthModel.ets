

import { TiebaSession } from '../net/TiebaParams';
import { UserProfileInfo } from '../model/UserProfile';

/** 登录态。UI 只认这两个值，不要引入"登录中"这类瞬时态到状态机里 */
export enum AuthState {
  /** 未登录（含从未登录、已退出、凭据判定失效后被清除） */
  LOGGED_OUT = 0,
  /** 已登录且凭据已在手 */
  LOGGED_IN = 1
}

/** 登录结果。与 `api/TiebaApi` 的 `ApiResult` 同风格：不抛异常，用字段表达 */
export class LoginResult {
  ok: boolean = false;
  /** 展示给用户的一句话原因；成功时为空串 */
  message: string = '';
  /** 是否为"凭据本身无效"（与网络失败区分：前者要提示重新输入，后者可以重试） */
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

/**
 * 一次登录会话的凭据集合。
 *
 * `AuthStore` 按字段分别落盘；`AuthSession.session()` 转成接口层认识的 `TiebaSession`。
 * tbs 由程序在登录时获取并随刷新更新（用户不需要手工维护）。
 */
export class CredentialBundle {
  /** 客户端接口鉴权载体 */
  bduss: string = '';
  /** 网页 STOKEN；部分网页接口需要，ArkWeb 登录后可能拿到 */
  stoken: string = '';
  /** 写操作令牌；登录成功与后续刷新时会更新 */
  tbs: string = '';

  isUsable(): boolean {
    return this.bduss.length > 0;
  }

  /** 只输出"有哪些字段"，不输出内容 */
  describeShape(): string {
    return `bduss=${this.bduss.length > 0 ? 'set' : 'empty'}`
      + ` stoken=${this.stoken.length > 0 ? 'set' : 'empty'}`
      + ` tbs=${this.tbs.length > 0 ? 'set' : 'empty'}`;
  }
}

export class AuthSnapshot {
  state: AuthState = AuthState.LOGGED_OUT;
  /** 展示用昵称；未登录或未取到时为空串 */
  nickname: string = '';
  /** 展示用 uid；0 表示未知 */
  uid: number = 0;
  /** 头像地址；空串表示未知 */
  portrait: string = '';
  /** 上次判定失效的原因（仅用于提示，不含凭据） */
  expiredReason: string = '';

  /** 用户名（@名）；未设置时为空串。与昵称不是一回事 */
  userName: string = '';
  /** 关注的用户数 */
  concernNum: number = 0;
  /** 粉丝数 */
  fansNum: number = 0;
  /** 成长等级 */
  levelId: number = 0;
  /** 当前成长值 */
  levelScore: number = 0;
  /** 升级所需成长值 */
  levelTargetScore: number = 0;
  /** 发帖数 */
  postNum: number = 0;
  /** 获赞数 */
  totalAgreeNum: number = 0;
  /** 关注的吧数量。**只有 protobuf 通道给得出**（form/JSON 形态没有这个字段） */
  likeForumNum: number = 0;
  /** 吧龄（服务端给字符串，原样保留） */
  tbAge: string = '';
  /**
   * 关注/粉丝/等级这三项**是否已成功取到**（即 `/c/u/user/profile` 的成败）。
   *
   * 为什么单独要一个标志：这三项等于 0 有两种完全不同的含义 ——
   * "真的 0 关注" 与 "这次没取到"。界面必须区分：前者显示 `0`，后者显示 `—`。
   * 它由**同一次请求的结果**直接决定（请求失败时 `fetchSelfProfile` 返回 undefined），
   * 不存在"标志说有、数据其实没有"这种不一致 —— 这正是加它的前提。
   */
  socialLoaded: boolean = false;

  isLoggedIn(): boolean {
    return this.state === AuthState.LOGGED_IN;
  }

  /**
   * 是否已拿到账号资料（用于区分"资料区显示数字"与"显示占位"）。
   *
   * 判据只取"一定有值"的几项：拉取失败时它们保持 0/空串。
   * 换句话说，**没资料时界面显示占位而不是一排 0**，这是本方法存在的唯一目的。
   */
  hasProfile(): boolean {
    return this.uid > 0 || this.nickname.length > 0 || this.portrait.length > 0;
  }

  /** 未登录快照。登出与"判定失效"共用同一个起点 */
  static loggedOut(): AuthSnapshot {
    return new AuthSnapshot();
  }
}

/**
 * BDUSS 的形态校验。
 *
 * 贴吧 BDUSS 的实测形态是**一长串不含空白与 `;` 的可见字符**，长度在几十到两百之间。
 * 这里只做"明显不像 BDUSS"的拦截（防止用户把整条 Cookie 或含空格的文本粘进来），
 * **不校验长度上限**——服务端并没有公开的长度契约，凭印象写上限会把合法值挡在外面。
 * 注意最后要 `trim()`：从浏览器复制常带首尾空白。
 */
export function normalizeBduss(input: string): string {
  return input.trim();
}

/** 返回值：空串表示通过，非空是给用户看的拒绝原因 */
export function validateBduss(input: string): string {
  const value: string = normalizeBduss(input);
  if (value.length === 0) {
    return '请输入 BDUSS';
  }
  // 先判"粘错东西"再判空白：整条 Cookie 里也含空格，
  // 顺序反过来会让最常见的误操作得到"不能包含空格"这种答非所问的提示。
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

/** 从整条 Cookie 文本里抽出 BDUSS。抽不到返回空串（不猜） */
export function extractBdussFromCookie(cookieText: string): string {
  return extractCookieValue(cookieText, 'BDUSS');
}

export function extractStokenFromCookie(cookieText: string): string {
  return extractCookieValue(cookieText, 'STOKEN');
}

/** 按 key 从 cookie 文本取值；键名不区分大小写。抽不到返回空串 */
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

/**
 * 判断用户粘进来的东西是"裸 BDUSS"还是"整条 Cookie"。
 *
 * 判据只用客观形态，不猜语义：**含 `=` 或 `;` 就按 Cookie 文本处理**。
 * 裸 BDUSS 实测是一长串不含这两个字符的可见字符（见 `validateBduss` 的注释）。
 */
export function looksLikeCookieText(input: string): boolean {
  const value: string = input.trim();
  return value.indexOf(';') >= 0 || value.indexOf('=') >= 0;
}

/**
 * 把用户粘贴的内容归一成一组凭据。
 *
 * - 裸 BDUSS → `{ bduss, stoken: '' }`（与原行为一致）
 * - 整条 Cookie → 同时抽出 BDUSS 与 STOKEN（抽不到哪个就哪个为空）
 *
 * **不做有效性判断**（那是 `AuthSession` 拿服务端校验的事），只做"从文本里取到什么"。
 */
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

/**
 * 对"用户粘进来的原始输入"做形态校验。
 *
 * 与 `validateBduss` 的关系：那个函数校验的是**裸 BDUSS 的值**，本项目已有用例锁住它，
 * 因此不改它的行为；本函数是**入口层**的校验——先判断输入形态，
 * 是 Cookie 就按 Cookie 抽，再对抽出来的 BDUSS 复用同一套值校验。
 * 返回值：空串表示通过，非空是给用户看的拒绝原因。
 */
export function validateCredentialInput(input: string): string {
  const raw: string = input.trim();
  if (raw.length === 0) {
    return '请输入 BDUSS，或整条 Cookie';
  }
  if (!looksLikeCookieText(raw)) {
    // 裸 BDUSS：沿用原有校验（提示文案已经打磨过）
    return validateBduss(raw);
  }
  const bundle: CredentialBundle = credentialsFromUserInput(raw);
  if (bundle.bduss.length === 0) {
    return '这段 Cookie 里没有找到 BDUSS，请确认复制完整';
  }
  // 抽出 BDUSS 之后仍要走同一套值校验，避免"绕过了长度/空白检查"
  return validateBduss(bundle.bduss);
}

/** 凭据失效判定仅处理已确认情形；HTTP 200 空响应不足以判断凭据失效。 */
export function classifyWriteFailure(hasBduss: boolean, hasTbs: boolean): string {
  if (!hasBduss) {
    return '需要登录后才能操作';
  }
  if (!hasTbs) {
    return '登录态缺少 tbs，请重新登录';
  }
  return '';
}

/**
 * 落盘用的别名（Asset Store Kit 的 `Tag.ALIAS`）。
 * 用固定常量而不是拼字符串，避免各处写错别名导致"存了读不到"。
 */
export class AuthAlias {
  static readonly BDUSS: string = 'tieba_bduss';
  static readonly STOKEN: string = 'tieba_stoken';
  static readonly TBS: string = 'tieba_tbs';
}

export const ASSET_NOT_FOUND: number = 24000002;

/** 删除凭据时的判据：条目本来不存在**不算错误**（幂等） */
export function isAssetMissing(code: number): boolean {
  return code === ASSET_NOT_FOUND;
}

/* ==========================================================================
 * 状态迁移的纯函数
 *
 * 放在这里而不是 `AuthSession` 内部，是为了让"登录/恢复/失效之后状态应该是什么"
 * 能被 Node 侧直接断言（`AuthSession` 依赖 @kit，Node 侧跑不了）。
 * `AuthSession` 只负责调用它们并触发 @Trace。
 * ========================================================================== */

/**
 * 把凭据装进接口层认识的 `TiebaSession`。
 *
 * **未登录必须返回空会话**：这是"未登录时点赞直接判失败而不是假装成功"的依赖前提，
 * 也是"登录功能不存在时行为完全一致"的保证。
 */
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

/**
 * 登录成功后（或从存储恢复出可用凭据后）的快照。
 *
 * 昵称/uid/头像需要额外接口，本阶段不取——保持"未知"而不是编造：
 * 界面宁可显示"已登录"，也不要显示一个假昵称。
 */
export function loggedInSnapshot(): AuthSnapshot {
  const snapshot: AuthSnapshot = new AuthSnapshot();
  snapshot.state = AuthState.LOGGED_IN;
  snapshot.nickname = '';
  snapshot.uid = 0;
  snapshot.portrait = '';
  return snapshot;
}

/**
 * 服务端判定凭据不可用时的快照。
 *
 * 与"主动退出"区别在于带上了 `expiredReason`：界面要能说清"是失效了"而不是"你刚退出了"。
 */
export function expiredSnapshot(reason: string): AuthSnapshot {
  const snapshot: AuthSnapshot = AuthSnapshot.loggedOut();
  snapshot.expiredReason = reason;
  return snapshot;
}

/**
 * 由凭据推导登录态快照。恢复（从存储读）与登录成功共用这一条判据：
 * **凭据可用 ⇔ 已登录**，不允许两处各写一套判断。
 */
export function snapshotForCredentials(credentials: CredentialBundle): AuthSnapshot {
  return credentials.isUsable() ? loggedInSnapshot() : AuthSnapshot.loggedOut();
}

/**
 * 用一份资料更新快照，**保持原有的 state 与 expiredReason**。
 *
 * 合并规则：**新值非空才覆盖旧值**（与 `mergeProfile` 同一约定）。
 * 为什么不是"直接覆盖"：一次失败/降级的拉取会把界面上已经显示出来的资料清空，
 * 用户看到的是"刷了一下，昵称变没了"。宁可留着旧值，也不要这种回退。
 *
 * `socialLoaded` 单独传入而不是从 `profile` 推断：它是"请求成没成"的事实，
 * 不是"字段有没有值"。推断（比如"三个数都是 0 就当没取到"）会在真的 0 关注时判断错。
 */
export function snapshotWithProfile(previous: AuthSnapshot, profile: UserProfileInfo,
  socialLoaded: boolean): AuthSnapshot {
  const next: AuthSnapshot = new AuthSnapshot();
  next.state = previous.state;
  next.expiredReason = previous.expiredReason;
  // 取到过就一直是 true：后续某次刷新失败不该把已显示的数字退回 `—`
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
