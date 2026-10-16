/** 点赞请求的脱敏诊断日志。凭据、Cookie、签名和设备标识只记录存在性、长度或摘要，禁止输出原值。使用同步 SHA-256 避免改变请求的异步时序；日志字段与顺序需保持解析兼容。 */
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'TiebaApi';
const PREFIX: string = 'opAgreeReqOpts';
/** 只取证这一个端点；其余请求一行都不打 */
const TARGET_PATH: string = '/c/c/agree/opAgree';

/** 显式敏感字段名（小写比较）。含 cookie 的键由名字规则覆盖，不必逐个列 */
const SENSITIVE_NAMES: string[] = [
  // 凭据
  'bduss', 'stoken', 'tbs', 'sign', 'authorization', 'password', 'token',
  'client_user_token', 'baiduid',
  // 设备指纹：值很短（如 `26`），靠"长值/形态"启发式永远拦不住，必须显式列名
  'cuid', 'cuid_galaxy2', 'cuid_gid', 'c3_aid', 'oaid', '_phone_imei',
  'android_id', 'imei', 'mac', '_os_version', '_client_id',
  /** model 仅参与请求体；诊断日志只记录请求体长度与哈希。 */
  // 账号标识：本次 Diff 不需要看到它的值
  'uid', 'client_logid'
];

/* ────────────────────────── 纯 sha256（无平台依赖） ────────────────────────── */

const K: number[] = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
];

function rotr(x: number, n: number): number {
  return ((x >>> n) | (x << (32 - n))) >>> 0;
}

/** UTF-8 编码（不用 util.TextEncoder，避免平台差异影响日志本身） */
function utf8Bytes(s: string): number[] {
  const out: number[] = [];
  for (let i = 0; i < s.length; i++) {
    let c: number = s.charCodeAt(i);
    if (c < 0x80) {
      out.push(c);
    } else if (c < 0x800) {
      out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
    } else if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) {
      // 代理对（表情等）：合并成一个码点再编码
      const next: number = s.charCodeAt(i + 1);
      c = 0x10000 + (((c & 0x3ff) << 10) | (next & 0x3ff));
      i++;
      out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 0x3f), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    } else {
      out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    }
  }
  return out;
}

function hex8(x: number): string {
  const s: string = (x >>> 0).toString(16);
  let out: string = s;
  while (out.length < 8) {
    out = `0${out}`;
  }
  return out;
}

/** sha256 → 小写 hex */
export function sha256Hex(text: string): string {
  const bytes: number[] = utf8Bytes(text);
  const bitLen: number = bytes.length * 8;
  bytes.push(0x80);
  while (bytes.length % 64 !== 56) {
    bytes.push(0);
  }
  // 长度按 64 位大端追加（高 32 位对短输入恒为 0）
  bytes.push(0, 0, 0, 0);
  bytes.push((bitLen >>> 24) & 0xff, (bitLen >>> 16) & 0xff, (bitLen >>> 8) & 0xff, bitLen & 0xff);

  let h0: number = 0x6a09e667;
  let h1: number = 0xbb67ae85;
  let h2: number = 0x3c6ef372;
  let h3: number = 0xa54ff53a;
  let h4: number = 0x510e527f;
  let h5: number = 0x9b05688c;
  let h6: number = 0x1f83d9ab;
  let h7: number = 0x5be0cd19;

  const w: number[] = new Array<number>(64).fill(0);
  for (let off = 0; off < bytes.length; off += 64) {
    for (let i = 0; i < 16; i++) {
      const j: number = off + i * 4;
      w[i] = ((bytes[j] << 24) | (bytes[j + 1] << 16) | (bytes[j + 2] << 8) | bytes[j + 3]) >>> 0;
    }
    for (let i = 16; i < 64; i++) {
      const s0: number = (rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3)) >>> 0;
      const s1: number = (rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10)) >>> 0;
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
    }
    let a: number = h0;
    let b: number = h1;
    let c: number = h2;
    let d: number = h3;
    let e: number = h4;
    let f: number = h5;
    let g: number = h6;
    let h: number = h7;
    for (let i = 0; i < 64; i++) {
      const S1: number = (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) >>> 0;
      const ch: number = ((e & f) ^ ((~e) & g)) >>> 0;
      const t1: number = (h + S1 + ch + K[i] + w[i]) >>> 0;
      const S0: number = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) >>> 0;
      const maj: number = ((a & b) ^ (a & c) ^ (b & c)) >>> 0;
      const t2: number = (S0 + maj) >>> 0;
      h = g;
      g = f;
      f = e;
      e = (d + t1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) >>> 0;
    }
    h0 = (h0 + a) >>> 0;
    h1 = (h1 + b) >>> 0;
    h2 = (h2 + c) >>> 0;
    h3 = (h3 + d) >>> 0;
    h4 = (h4 + e) >>> 0;
    h5 = (h5 + f) >>> 0;
    h6 = (h6 + g) >>> 0;
    h7 = (h7 + h) >>> 0;
  }
  return hex8(h0) + hex8(h1) + hex8(h2) + hex8(h3)
    + hex8(h4) + hex8(h5) + hex8(h6) + hex8(h7);
}

/* ────────────────────────── 取值判定与脱敏 ────────────────────────── */

/**
 * 值是否像一条 Cookie（形如 `a=1; b=2`）。
 *
 * ⚠️ 判据不能只看"含 `;` 且含 `=`"：`Accept-Language: zh-CN,en-US;q=0.9` 就是这样，
 * 早期版本因此把一个**普通的协商头**误判为凭据（日志里看不到它的值，两侧就没得比）。
 * 真正的 Cookie 串至少要有**两段** `名字=值`，否则不认。
 * 名字列表里的普通头（Accept-Language / Content-Type / Connection / User-Agent）另有
 * 显式白名单兜底，见 `isPlainNegotiationHeader`。
 */
function looksLikeCookie(name: string, value: string): boolean {
  if (name.includes('cookie')) {
    return true;
  }
  if (/\bBDUSS\s*=/i.test(value) || /\bSTOKEN\s*=/i.test(value)) {
    return true;
  }
  const pairs: number = (value.match(/[^=;\s]+=[^;]*/g) ?? []).length;
  return value.includes(';') && pairs >= 2;
}

/** 这些头按协议就是普通协商头，值不含隐私：显式排除，避免被启发式误伤 */
const PLAIN_NEGOTIATION_HEADERS: string[] = [
  'accept', 'accept-language', 'accept-encoding', 'content-type', 'content-length',
  'connection', 'host', 'referer', 'origin', 'pragma', 'cache-control', 'transfer-encoding'
];

function isPlainNegotiationHeader(lower: string): boolean {
  for (let i = 0; i < PLAIN_NEGOTIATION_HEADERS.length; i++) {
    if (lower === PLAIN_NEGOTIATION_HEADERS[i]) {
      return true;
    }
  }
  return false;
}

function looksLikeFingerprint(name: string, value: string): boolean {
  if (/^[0-9a-fA-F]{16,}$/.test(value)) {
    return true;
  }
  if (value.includes('|')) {
    return true;
  }
  if (name.length > 1 && name.charAt(0) === '_') {
    return true;
  }
  return name.startsWith('wappc_');
}

/** 这个键的值是否必须脱敏 */
export function isSensitiveName(name: string, value: string): boolean {
  const lower: string = name.toLowerCase();
  for (let i = 0; i < SENSITIVE_NAMES.length; i++) {
    if (lower === SENSITIVE_NAMES[i]) {
      return true;
    }
  }
  // 普通协商头先放行：它们的值本身就是要比对的对象，不能被启发式误伤
  if (isPlainNegotiationHeader(lower)) {
    return false;
  }
  // ⚠️ 必须传 lower：函数的 `includes('cookie')` 是大小写敏感的，
  // 传原始 name 会让 `Cookie` 这种标准写法漏网（用例已经把它钉住）。
  if (looksLikeCookie(lower, value)) {
    return true;
  }
  // 长值 + 指纹形态（hex / 带 | / 下划线开头的客户端字段）
  if (value.length >= 24 && looksLikeFingerprint(lower, value)) {
    return true;
  }
  return false;
}

/** 单个值：非敏感原样，敏感只给 len+hash */
function describeValue(name: string, value: string): string {
  if (value.length === 0) {
    return '(empty)';
  }
  if (isSensitiveName(name, value)) {
    return `SENSITIVE(len=${value.length},sha256=${sha256Hex(value).substring(0, 16)})`;
  }
  return `"${value}"`;
}

/** 值里带凭据子串时的兜底：整条降级为敏感 */
function guardAgainstLeak(text: string): string {
  if (/\bBDUSS\s*=/i.test(text) || /\bSTOKEN\s*=/i.test(text)) {
    return `REDACTED(len=${text.length},sha256=${sha256Hex(text).substring(0, 16)})`;
  }
  return text;
}

/* ────────────────────────── 对外接口 ────────────────────────── */

/** 与 `@ohos.net.http` 的 HttpRequestOptions 对应的最小取值面（两侧各写一份） */
export class ReqOptsSnapshot {
  url: string = '';
  method: string = '';
  /** 键按字典序排好，便于直接比对 */
  headers: string[] = [];
  /** 同一键出现多次时的次数（`name xN`；正常应为空） */
  headerDuplicates: string[] = [];
  bodyLen: number = 0;
  bodyHash: string = '';
  connectTimeout: string = '(default)';
  readTimeout: string = '(default)';
  expectDataType: string = '(default)';
  usingProtocol: string = '(not set)';
  usingCache: string = '(not set)';
  usingProxy: string = '(not set)';
  /** 自动重定向：ArkTS 的 HttpRequestOptions 没有这个字段，如实记录"不可设置" */
  redirect: string = 'not-a-setting-in-ohos.net.http';
  /** RequestOptions 顶层出现过的键（两侧差集就是"一边有另一边没有"的项） */
  optionKeys: string[] = [];
}

/** 把快照排成一行（两侧格式**必须**逐字符一致） */
export function formatSnapshot(s: ReqOptsSnapshot): string {
  const parts: string[] = [];
  parts.push(`url=${s.url}`);
  parts.push(`method=${s.method}`);
  parts.push(`headerCount=${s.headers.length}`);
  parts.push(`headers=[${s.headers.join(',')}]`);
  parts.push(`headerDuplicates=[${s.headerDuplicates.length === 0 ? 'none' : s.headerDuplicates.join(',')}]`);
  parts.push(`bodyLen=${s.bodyLen}`);
  parts.push(`bodySha256_16=${s.bodyLen === 0 ? '-' : s.bodyHash}`);
  parts.push(`connectTimeout=${s.connectTimeout}`);
  parts.push(`readTimeout=${s.readTimeout}`);
  parts.push(`expectDataType=${s.expectDataType}`);
  parts.push(`usingProtocol=${s.usingProtocol}`);
  parts.push(`usingCache=${s.usingCache}`);
  parts.push(`usingProxy=${s.usingProxy}`);
  parts.push(`autoRedirect=${s.redirect}`);
  parts.push(`optionKeys=[${s.optionKeys.join(',')}]`);
  return guardAgainstLeak(parts.join(' '));
}

/** 只在点赞端点打印 */
export function shouldLog(url: string): boolean {
  return url.includes(TARGET_PATH);
}

/**
 * 打印一行脱敏 RequestOptions。返回该行文本（便于用例断言/Node 侧复用）。
 *
 * `headerValues` 与 `options` 是**真正交给 `@ohos.net.http` 的对象**，
 * 不是调用方的意图——取证必须取自实际入参。
 */
export function logRequestOptions(s: ReqOptsSnapshot): string {
  const line: string = `${PREFIX} ${formatSnapshot(s)}`;
  hilog.info(DOMAIN, TAG, '%{public}s', line);
  return line;
}

/** 头名排序 + 重复计数。`names` 允许重复（同名头出现多次时必须能看出来） */
export function summarizeHeaderNames(names: string[]): string[] {
  const sorted: string[] = names.slice();
  sorted.sort((a: string, b: string): number => {
    if (a < b) {
      return -1;
    }
    if (a > b) {
      return 1;
    }
    return 0;
  });
  const out: string[] = [];
  for (let i = 0; i < sorted.length; i++) {
    const name: string = sorted[i];
    let count: number = 1;
    while (i + 1 < sorted.length && sorted[i + 1] === name) {
      count++;
      i++;
    }
    out.push(count > 1 ? `${name} x${count}` : name);
  }
  return out;
}

/** 一个 header 条目的文本形式：`Name:value`（值走脱敏），供 headers=[...] 使用 */
export function describeHeader(name: string, value: string): string {
  return `${name}:${describeValue(name, value)}`;
}

/** body：只给长度与 hash（body 里含 BDUSS/STOKEN，绝不打原文） */
export function describeBody(body: string): string {
  return sha256Hex(body).substring(0, 16);
}
