/**
 * 账号代次（owner）的单一出处。
 *
 * 各 VM 用它判断「这次异步结果还属于当前账号吗」。历史上这段表达式在 14 个 VM 里各抄一份，
 * 实测有 **4 种口径**。这里每种各留一个具名函数，**行为与原来逐字等价**：
 * 换口径是产品决定（会改变缓存失效时机），不在提取这一步顺手统一。
 *
 * 口径对照：
 * - `accountWithPortrait`：换号或换头像都让在途结果失效（列表行要按新头像重绘）；
 * - `loggedInSessionKey`：只有换号才失效，换头像不影响（未登录返回空串）；
 * - `rawSessionKey`：未登录也取键（目录类缓存需要在未登录时也区分"当前无账号"）；
 * - `sessionWithPortrait`：通知流用，换号或换头像都重来（与分页游标绑定）。
 */
import { authSession } from '../auth/AuthSession';
import { ThreadBlockScope } from '../model/ThreadBlock';

/** `uid:portrait`；未登录为空串。 */
export function accountWithPortrait(): string {
  return authSession.isLoggedIn() ? `${authSession.snapshot.uid}:${authSession.snapshot.portrait}` : '';
}

/** 会话键；未登录为空串。 */
export function loggedInSessionKey(): string {
  return authSession.isLoggedIn() ? authSession.sessionKey() : '';
}

/** 裸会话键：未登录也返回当前会话号。 */
export function rawSessionKey(): string {
  return authSession.sessionKey();
}

/** `sessionKey:uid:portrait`；未登录为空串。 */
export function sessionWithPortrait(): string {
  return authSession.isLoggedIn()
    ? `${authSession.sessionKey()}:${authSession.snapshot.uid}:${authSession.snapshot.portrait}` : '';
}

/**
 * 屏蔽名单落盘的账号作用域（`utils/ThreadBlockStore` 的注入源）。
 *
 * `owner` 口径与改动前逐字一致：登录取 uid、未登录 `'anonymous'`；`session` 取会话键。
 * 注入点在 `EntryAbility.onCreate`——落盘层因此不必 import 认证层。
 */
export function threadBlockScope(): ThreadBlockScope {
  return {
    owner: authSession.isLoggedIn() ? String(authSession.snapshot.uid) : 'anonymous',
    session: authSession.sessionKey()
  };
}
