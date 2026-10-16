/**
 * HTTP 传输层。只负责"把字节发出去、把字节拿回来"，不含任何贴吧业务语义。
 *
 * 使用 @kit.NetworkKit 的 http 模块。统一在此收敛：
 * - 超时策略
 * - 请求头
 * - 错误归一化（网络异常不向上抛原始错误，转成可判断的结果对象）
 *
 * 上层（接口层与页面 VM）只关心"拿到了什么字节"和"要不要重试"。
 */

import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ReqOptsSnapshot, describeBody, describeHeader, logRequestOptions, shouldLog, summarizeHeaderNames
} from './RequestOptionsTrace';
import { TransferStats } from './TransferStats';

const DOMAIN: number = 0x0000;
const TAG: string = 'HttpClient';

/** 传输结果。用显式字段而非抛异常，便于上层区分"网络失败"与"业务失败"。 */
export class HttpResult {
  /** HTTP 状态码，失败时为 0 */
  code: number = 0;
  /** 响应体原始字节 */
  bytes: Uint8Array = new Uint8Array(0);
  /** 是否成功收到 2xx 响应 */
  ok: boolean = false;
  /** 失败原因，成功时为空串 */
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

/** 把 http 模块给的响应头对象归一成"键小写"的字符串表；非法输入返回空表而不是抛异常 */
function normalizeHeaders(raw: Object | undefined): Record<string, string> {
  const out: Record<string, string> = {};
  if (raw === undefined || raw === null) {
    return out;
  }
  try {
    const src: Record<string, string> = raw as Record<string, string>;
    const keys: string[] = Object.keys(src);
    for (let i = 0; i < keys.length; i++) {
      out[keys[i].toLowerCase()] = String(src[keys[i]]);
    }
  } catch (err) {
    // 拿不到响应头不阻断请求本身；上层按"没有头"处理
    return {};
  }
  return out;
}

export class HttpClient {
  private connectTimeout: number = 10000;
  private readTimeout: number = 15000;

  /**
   * User-Agent。空 UA 会被百度的风控直接 403（实测：网页接口返回 403 + 挑战页），
   * 因此不能依赖系统默认值，必须显式设置。
   * 客户端接口用 "bdtb for Android <版本>"；网页接口需要浏览器 UA。
   */
  userAgent: string = 'bdtb for Android 12.64.1.1';

  /** 以 form 形式 POST。
   * 贴吧的 form 接口要求 body 为 application/x-www-form-urlencoded，
   * 且参数顺序需与签名时一致（本实现在签名后不再重排）。
   *
   * `extraHeaders` 会**覆盖**默认头（写请求需要精确指定
   * UA / Cookie / Connection / client_user_token 等）。
   * **不要在任何日志里输出 Cookie 值**：它可能含 BDUSS/STOKEN。
   */
  async postForm(url: string, body: string,
    extraHeaders?: Record<string, string>): Promise<HttpResult> {
    const header: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': this.userAgent
    };
    if (extraHeaders !== undefined) {
      const keys: string[] = Object.keys(extraHeaders);
      for (let i = 0; i < keys.length; i++) {
        header[keys[i]] = extraHeaders[keys[i]];
      }
    }
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: header,
      extraData: body,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: this.connectTimeout,
      readTimeout: this.readTimeout,
      usingCache: false
    };
    return this.send(url, options);
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
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: header,
      extraData: body.buffer as ArrayBuffer,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: this.connectTimeout,
      readTimeout: this.readTimeout,
      usingCache: false
    };
    return this.send(url, options);
  }

  /** 以 GET 拉取，用于网页端接口与静态资源 */
  async get(url: string): Promise<HttpResult> {
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: {
        'User-Agent': this.userAgent
      },
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: this.connectTimeout,
      readTimeout: this.readTimeout,
      usingCache: false
    };
    return this.send(url, options);
  }

  /** 携带 Cookie 的网页 GET，Cookie 由调用方管理，不得写入日志；extraHeaders 可追加或覆盖默认请求头。 */
  async getWithCookie(url: string, cookie: string,
    extraHeaders?: Record<string, string>): Promise<HttpResult> {
    const header: Record<string, string> = {
      'User-Agent': this.userAgent,
      'Cookie': cookie
    };
    if (extraHeaders !== undefined) {
      const names: string[] = Object.keys(extraHeaders);
      for (let i = 0; i < names.length; i++) {
        header[names[i]] = extraHeaders[names[i]];
      }
    }
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: header,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: this.connectTimeout,
      readTimeout: this.readTimeout,
      usingCache: false
    };
    return this.send(url, options);
  }

  /**
   * 把**实际入参**（真正交给 `@ohos.net.http` 的那个对象）打成一行脱敏日志。
   *
   * 只在点赞端点打印（`shouldLog`），其余请求一行都不打——取证范围之外不留噪音。
   * 头部取值一律经 `describeHeader` 脱敏；body 只给长度与 hash。
   */
  private traceOptions(url: string, options: http.HttpRequestOptions): void {
    if (!shouldLog(url)) {
      return;
    }
    const snapshot: ReqOptsSnapshot = new ReqOptsSnapshot();
    snapshot.url = url;
    snapshot.method = String(options.method);

    const header: Record<string, Object> | undefined =
      options.header as Record<string, Object> | undefined;
    if (header !== undefined) {
      const names: string[] = Object.keys(header);
      const described: string[] = [];
      for (let i = 0; i < names.length; i++) {
        described.push(describeHeader(names[i], String(header[names[i]])));
      }
      // 两侧同名头会被网络栈合并，应用层看到的名字集合才是可比对象；统一排序后再输出
      described.sort((a: string, b: string): number => {
        if (a < b) {
          return -1;
        }
        if (a > b) {
          return 1;
        }
        return 0;
      });
      snapshot.headers = described;
      const summarized: string[] = summarizeHeaderNames(names);
      const duplicates: string[] = [];
      for (let i = 0; i < summarized.length; i++) {
        if (summarized[i].includes(' x')) {
          duplicates.push(summarized[i]);
        }
      }
      snapshot.headerDuplicates = duplicates;
    }

    const body: string = typeof options.extraData === 'string' ? options.extraData : '';
    snapshot.bodyLen = body.length;
    snapshot.bodyHash = body.length === 0 ? '' : describeBody(body);

    snapshot.connectTimeout = options.connectTimeout === undefined
      ? '(default)' : String(options.connectTimeout);
    snapshot.readTimeout = options.readTimeout === undefined
      ? '(default)' : String(options.readTimeout);
    snapshot.expectDataType = options.expectDataType === undefined
      ? '(default)' : String(options.expectDataType);
    snapshot.usingCache = options.usingCache === undefined
      ? '(not set)' : String(options.usingCache);
    // usingProtocol / usingProxy 在本 SDK 的 HttpRequestOptions 里不存在，保持 "(not set)"

    logRequestOptions(snapshot);
  }

  private async send(url: string, options: http.HttpRequestOptions): Promise<HttpResult> {
    const header: Record<string, string> = (options.header ?? {}) as Record<string, string>;
    const carriesCookie: boolean = Object.keys(header).some((name: string): boolean =>
      name.toLowerCase() === 'cookie' && header[name].length > 0);
    if (!url.toLowerCase().startsWith('https://') &&
      (carriesCookie || options.method === http.RequestMethod.POST)) {
      return HttpResult.failure('安全连接不可用，未发送凭据或业务请求');
    }
    this.traceOptions(url, options);
    const request: http.HttpRequest = http.createHttp();
    const startedAt: number = Date.now();
    try {
      const response: http.HttpResponse = await request.request(url, options);
      const result: HttpResult = new HttpResult();
      result.code = response.responseCode;
      result.ok = response.responseCode >= 200 && response.responseCode < 300;
      result.headers = normalizeHeaders(response.header);

      const raw: Object | string | ArrayBuffer = response.result;
      if (raw instanceof ArrayBuffer) {
        result.bytes = new Uint8Array(raw);
      } else if (typeof raw === 'string') {
        // 少数接口返回文本，统一转成字节交由上层处理
        result.bytes = new Uint8Array(0);
        result.ok = false;
        result.error = 'unexpected text response';
        hilog.warn(DOMAIN, TAG, 'text response of length %{public}d', raw.length);
      }

      if (!result.ok && result.error.length === 0) {
        result.error = `http ${response.responseCode}`;
      }
      // 传输统计：官方也是拿到（成功）响应后才入队一条（见 TransferStats 头注释）
      if (result.ok) {
        TransferStats.recordSuccess(Date.now() - startedAt, result.bytes.length);
      } else {
        TransferStats.recordFailure();
      }
      return result;
    } catch (e) {
      // 网络层异常不向上冒泡：上层用 result.ok 判断，避免页面被异常打断
      const err: Error = e as Error;
      hilog.error(DOMAIN, TAG, 'request failed: %{public}s', err.message);
      TransferStats.recordFailure();
      return HttpResult.failure(err.message);
    } finally {
      request.destroy();
    }
  }
}
