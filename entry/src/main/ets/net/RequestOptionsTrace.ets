
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'TiebaApi';
const PREFIX: string = 'opAgreeReqOpts';

const TARGET_PATH: string = '/c/c/agree/opAgree';

const SENSITIVE_NAMES: string[] = [

  'bduss', 'stoken', 'tbs', 'sign', 'authorization', 'password', 'token',
  'client_user_token', 'baiduid',

  'cuid', 'cuid_galaxy2', 'cuid_gid', 'c3_aid', 'oaid', '_phone_imei',
  'android_id', 'imei', 'mac', '_os_version', '_client_id',

  'uid', 'client_logid'
];

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

function utf8Bytes(s: string): number[] {
  const out: number[] = [];
  for (let i = 0; i < s.length; i++) {
    let c: number = s.charCodeAt(i);
    if (c < 0x80) {
      out.push(c);
    } else if (c < 0x800) {
      out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
    } else if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) {

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

export function sha256Hex(text: string): string {
  const bytes: number[] = utf8Bytes(text);
  const bitLen: number = bytes.length * 8;
  bytes.push(0x80);
  while (bytes.length % 64 !== 56) {
    bytes.push(0);
  }

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

export function isSensitiveName(name: string, value: string): boolean {
  const lower: string = name.toLowerCase();
  for (let i = 0; i < SENSITIVE_NAMES.length; i++) {
    if (lower === SENSITIVE_NAMES[i]) {
      return true;
    }
  }

  if (isPlainNegotiationHeader(lower)) {
    return false;
  }

  if (looksLikeCookie(lower, value)) {
    return true;
  }

  if (value.length >= 24 && looksLikeFingerprint(lower, value)) {
    return true;
  }
  return false;
}

function describeValue(name: string, value: string): string {
  if (value.length === 0) {
    return '(empty)';
  }
  if (isSensitiveName(name, value)) {
    return `SENSITIVE(len=${value.length},sha256=${sha256Hex(value).substring(0, 16)})`;
  }
  return `"${value}"`;
}

function guardAgainstLeak(text: string): string {
  if (/\bBDUSS\s*=/i.test(text) || /\bSTOKEN\s*=/i.test(text)) {
    return `REDACTED(len=${text.length},sha256=${sha256Hex(text).substring(0, 16)})`;
  }
  return text;
}

export class ReqOptsSnapshot {
  url: string = '';
  method: string = '';

  headers: string[] = [];

  headerDuplicates: string[] = [];
  bodyLen: number = 0;
  bodyHash: string = '';
  connectTimeout: string = '(default)';
  readTimeout: string = '(default)';
  expectDataType: string = '(default)';
  usingProtocol: string = '(not set)';
  usingCache: string = '(not set)';
  usingProxy: string = '(not set)';

  redirect: string = 'not-a-setting-in-ohos.net.http';

  optionKeys: string[] = [];
}

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

export function shouldLog(url: string): boolean {
  return url.includes(TARGET_PATH);
}

export function logRequestOptions(s: ReqOptsSnapshot): string {
  const line: string = `${PREFIX} ${formatSnapshot(s)}`;
  hilog.info(DOMAIN, TAG, '%{public}s', line);
  return line;
}

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

export function describeHeader(name: string, value: string): string {
  return `${name}:${describeValue(name, value)}`;
}

export function describeBody(body: string): string {
  return sha256Hex(body).substring(0, 16);
}
