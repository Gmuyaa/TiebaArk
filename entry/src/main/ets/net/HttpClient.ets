/**
 * HTTP 传输层：基于共享 `rcp.Session` 复用 TCP/TLS 长连接与压缩协商，不含贴吧业务语义。
 *
 * 超时、默认请求头与错误归一化都在这里收口；网络异常转成结果对象，不向上抛原始异常。
 */

import { rcp } from '@kit.RemoteCommunicationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Gzip } from '../utils/Gzip';
import {
  ReqOptsSnapshot, describeBody, describeHeader, logRequestOptions, shouldLog, summarizeHeaderNames
} from './RequestOptionsTrace';
import { TransferStats } from './TransferStats';

const DOMAIN: number = 0x0000;
const TAG: string = 'HttpClient';
const DEFAULT_CONNECT_TIMEOUT_MS: number = 10000;
const DEFAULT_READ_TIMEOUT_MS: number = 15000;

let sharedSession: rcp.Session | undefined = undefined;

function getSharedSession(): rcp.Session {
  if (sharedSession === undefined) {
    sharedSession = rcp.createSession({
      connectionConfiguration: {
        maxConnectionsPerHost: 8,
        maxTotalConnections: 64
      },
      requestConfiguration: {
        transfer: {
          autoRedirect: true,
          timeout: {
            connectMs: DEFAULT_CONNECT_TIMEOUT_MS,
            transferMs: DEFAULT_READ_TIMEOUT_MS
          }
        }
      }
    });
  }
  return sharedSession;
}

/** 释放进程级共享 HTTP 会话；由 Ability.onDestroy 调用。 */
export function closeSharedHttpSession(): void {
  if (sharedSession !== undefined) {
    const session: rcp.Session = sharedSession;
    sharedSession = undefined;
    try { session.close(); } catch (_) {}
  }
}

/** 传输结果。用显式字段而非抛异常，便于上层区分"网络失败"与"业务失败"。 */
export class HttpResult {
  code: number = 0;
  bytes: Uint8Array = new Uint8Array(0);
  ok: boolean = false;
  error: string = '';
  /** 响应头键名统一为小写。set-cookie 可能包含认证凭据，日志只记录存在性或长度。 */
  headers: Record<string, string> = {};

  static failure(reason: string): HttpResult {
    const r: HttpResult = new HttpResult();
    r.ok = false;
    r.error = reason;
    return r;
  }
}

function normalizeRcpHeaders(raw: rcp.ResponseHeaders | undefined): Record<string, string> {
  const out: Record<string, string> = {};
  if (raw === undefined || raw === null) {
    return out;
  }
  try {
    const src: Record<string, string | string[] | undefined> =
      raw as Record<string, string | string[] | undefined>;
    const keys: string[] = Object.keys(src);
    for (let i = 0; i < keys.length; i++) {
      const value: string | string[] | undefined = src[keys[i]];
      if (value === undefined) { continue; }
      out[keys[i].toLowerCase()] = Array.isArray(value) ? value.join(', ') : String(value);
    }
  } catch (err) {
    // 拿不到响应头不阻断请求本身；上层按"没有头"处理
    return {};
  }
  return out;
}

function toRcpHeaders(src: Record<string, string>): rcp.RequestHeaders {
  const out: rcp.RequestHeaders = {};
  const keys: string[] = Object.keys(src);
  for (let i = 0; i < keys.length; i++) {
    const key: string = keys[i];
    out[key.toLowerCase()] = src[key];
  }
  return out;
}

function hasHeaderIgnoreCase(header: Record<string, string>, targetLower: string): boolean {
  const keys: string[] = Object.keys(header);
  for (let i = 0; i < keys.length; i++) {
    if (keys[i].toLowerCase() === targetLower) {
      return true;
    }
  }
  return false;
}

function isGzipMagic(bytes: Uint8Array): boolean {
  return bytes.length >= 2 && bytes[0] === 0x1f && bytes[1] === 0x8b;
}

export class HttpClient {
  private connectTimeout: number = DEFAULT_CONNECT_TIMEOUT_MS;
  private readTimeout: number = DEFAULT_READ_TIMEOUT_MS;

  /** User-Agent。空 UA 会被风控直接 403，不能依赖系统默认值；客户端接口用 "bdtb for Android <版本>"，网页接口需浏览器 UA。 */
  userAgent: string = 'bdtb for Android 12.64.1.1';

  /** 以 form 形式 POST。
   * 参数顺序必须与签名时一致，签名后不能再重排；`extraHeaders` 覆盖默认头。
   * Cookie 可能含 BDUSS/STOKEN，任何日志都不能输出其值。
   */
  async postForm(url: string, body: string,
    extraHeaders?: Record<string, string>): Promise<HttpResult> {
    const header: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': this.userAgent,
      'Accept-Encoding': 'gzip'
    };
    if (extraHeaders !== undefined) {
      const keys: string[] = Object.keys(extraHeaders);
      for (let i = 0; i < keys.length; i++) {
        header[keys[i]] = extraHeaders[keys[i]];
      }
    }
    return this.send(url, 'POST', header, body);
  }

  /** 二进制 POST；extraHeaders 可追加或覆盖默认请求头，用于 protobuf 通道。 */
  async postBinary(url: string, body: Uint8Array,
    extraHeaders?: Record<string, string>): Promise<HttpResult> {
    const header: Record<string, string> = {
      'Content-Type': 'application/octet-stream',
      'User-Agent': this.userAgent
    };
    if (extraHeaders !== undefined) {
      const names: string[] = Object.keys(extraHeaders);
      for (let i = 0; i < names.length; i++) {
        header[names[i]] = extraHeaders[names[i]];
      }
    }
    const payload: ArrayBuffer = body.byteOffset === 0 && body.byteLength === body.buffer.byteLength
      ? (body.buffer as ArrayBuffer)
      : (body.slice().buffer as ArrayBuffer);
    return this.send(url, 'POST', header, payload);
  }

  async get(url: string): Promise<HttpResult> {
    const header: Record<string, string> = {
      'User-Agent': this.userAgent,
      'Accept-Encoding': 'gzip'
    };
    return this.send(url, 'GET', header, undefined);
  }

  /** 携带 Cookie 的网页 GET，Cookie 由调用方管理，不得写入日志；extraHeaders 可追加或覆盖默认请求头。 */
  async getWithCookie(url: string, cookie: string,
    extraHeaders?: Record<string, string>): Promise<HttpResult> {
    const header: Record<string, string> = {
      'User-Agent': this.userAgent,
      'Cookie': cookie,
      'Accept-Encoding': 'gzip'
    };
    if (extraHeaders !== undefined) {
      const names: string[] = Object.keys(extraHeaders);
      for (let i = 0; i < names.length; i++) {
        header[names[i]] = extraHeaders[names[i]];
      }
    }
    return this.send(url, 'GET', header, undefined);
  }

  /**
   * 把真正交给传输层的实际入参打成一行脱敏日志，只在点赞端点打印，其余请求一行都不打。
   * 头取值一律经 `describeHeader` 脱敏；body 只给长度与 hash。
   */
  private traceOptions(url: string, method: string, header: Record<string, string>,
    content: string | ArrayBuffer | undefined): void {
    if (!shouldLog(url)) {
      return;
    }
    const snapshot: ReqOptsSnapshot = new ReqOptsSnapshot();
    snapshot.url = url;
    snapshot.method = method;

    const names: string[] = Object.keys(header);
    const described: string[] = [];
    for (let i = 0; i < names.length; i++) {
      described.push(describeHeader(names[i], String(header[names[i]])));
    }
    described.sort((a: string, b: string): number => (a < b ? -1 : (a > b ? 1 : 0)));
    snapshot.headers = described;
    const summarized: string[] = summarizeHeaderNames(names);
    const duplicates: string[] = [];
    for (let i = 0; i < summarized.length; i++) {
      if (summarized[i].includes(' x')) {
        duplicates.push(summarized[i]);
      }
    }
    snapshot.headerDuplicates = duplicates;

    const body: string = typeof content === 'string' ? content : '';
    snapshot.bodyLen = body.length;
    snapshot.bodyHash = body.length === 0 ? '' : describeBody(body);

    snapshot.connectTimeout = String(this.connectTimeout);
    snapshot.readTimeout = String(this.readTimeout);
    snapshot.expectDataType = 'ARRAY_BUFFER';
    snapshot.usingCache = 'false';

    logRequestOptions(snapshot);
  }

  private async send(url: string, method: rcp.HttpMethod, header: Record<string, string>,
    content: string | ArrayBuffer | undefined): Promise<HttpResult> {
    const carriesCookie: boolean = hasHeaderIgnoreCase(header, 'cookie') &&
      Object.keys(header).some((name: string): boolean =>
        name.toLowerCase() === 'cookie' && header[name].length > 0);
    if (!url.toLowerCase().startsWith('https://') && (carriesCookie || method === 'POST')) {
      return HttpResult.failure('安全连接不可用，未发送凭据或业务请求');
    }
    this.traceOptions(url, method, header, content);
    const startedAt: number = Date.now();
    const request: rcp.Request = new rcp.Request(
      url,
      method,
      toRcpHeaders(header),
      content,
      undefined,
      undefined,
      {
        transfer: {
          autoRedirect: true,
          timeout: {
            connectMs: this.connectTimeout,
            transferMs: this.readTimeout
          }
        }
      }
    );
    try {
      const response: rcp.Response = await getSharedSession().fetch(request);
      const result: HttpResult = new HttpResult();
      result.code = response.statusCode;
      result.ok = response.statusCode >= 200 && response.statusCode < 300;
      result.headers = normalizeRcpHeaders(response.headers);

      if (response.body !== undefined) {
        let bytes: Uint8Array = new Uint8Array(response.body);
        const encoding: string = (result.headers['content-encoding'] ?? '').toLowerCase();
        // 若底层未自动解压且响应体仍是 gzip 流，透明解压兜底。
        if (encoding.includes('gzip') && isGzipMagic(bytes)) {
          bytes = Gzip.inflate(bytes);
        }
        result.bytes = bytes;
      }

      if (!result.ok && result.error.length === 0) {
        result.error = `http ${response.statusCode}`;
      }
      const elapsedMs: number = Date.now() - startedAt;
      if (url.endsWith('/c/f/frs/page')) {
        hilog.info(DOMAIN, TAG,
          'frs transport ok=%{public}s code=%{public}d bytes=%{public}d enc=%{public}s ver=%{public}s ms=%{public}d',
          String(result.ok), result.code, result.bytes.length,
          result.headers['content-encoding'] ?? 'none',
          String(response.httpVersion ?? 'unknown'), elapsedMs);
      }
      if (result.ok) {
        TransferStats.recordSuccess(elapsedMs, result.bytes.length);
      } else {
        TransferStats.recordFailure();
      }
      return result;
    } catch (e) {
      const err: Error = e as Error;
      hilog.error(DOMAIN, TAG, 'request failed: %{public}s', err.message ?? String(e));
      TransferStats.recordFailure();
      return HttpResult.failure(err.message ?? String(e));
    }
  }
}
