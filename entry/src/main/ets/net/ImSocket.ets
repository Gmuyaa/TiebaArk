/**
 * 私信 IM 的 WebSocket 传输层。帧格式（官方实现复刻，见 `docs/协议/协议证据-私信.md`）：
 * `[flag 1B][cmd 4B 大端][reqId 4B 大端][payload]`，flag 0x08 固定位、0x40 gzip、0x80 AES-256-ECB/PKCS7。
 *
 * 握手（cmd 1001）不加密，其余请求默认加密。本层只做连接、打包、按 reqId 配对与重连，不含会话模型；
 * 业务调用方在 `viewmodel/ChatStore.ets`。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { TiebaDevice, TiebaSession } from './TiebaParams';
import { IM_CLIENT_VERSION, ImCmd, ImRequest, ImUpdateClientParams, fullDeviceJson } from './ImParams';
import { ImInitInfo, parseImInit } from '../model/Chat';
import { ImCrypto, WS_SEC_KEY_LEN } from '../utils/ImCrypto';
import { Gzip } from '../utils/Gzip';
import { ImWsTcp } from './ImWsTcp';

const DOMAIN: number = 0x0000;
const TAG: string = 'ImSocket';

/** 官方 IM 地址：明文 TCP + 8000，服务端不做 TLS；系统 `webSocket` 在该地址一律 `code=200`（upgrade 失败），因此改用自建 `ImWsTcp`。 */
const IM_HOST: string = 'im.tieba.baidu.com';
const IM_PORT: number = 8000;
/** 扩展协商值来自官方服务端行为（`Sec-WebSocket-Extensions: im_version=2.3`）。 */
const WS_EXTENSION: string = 'im_version=2.3';
const REQUEST_TIMEOUT_MS: number = 15000;
const CONNECT_TIMEOUT_MS: number = 12000;
const MAX_RECONNECT: number = 5;

/** 帧头固定的 0x08 位。 */
const FLAG_BASE: number = 0x08;
const FLAG_COMPRESS: number = 0x40;
const FLAG_ENCRYPT: number = 0x80;

class ImPending {
  resolve: (body: Uint8Array) => void = (): void => {};
  reject: (err: Error) => void = (): void => {};
  timer: number = -1;
}

class ImFrame {
  cmd: number = 0;
  reqId: number = 0;
  body: Uint8Array = new Uint8Array(0);
}

export type ImPushHandler = (body: Uint8Array) => void;
export type ImReconnectHandler = () => void;

function bigEndian32(out: Uint8Array, offset: number, value: number): void {
  out[offset] = (value >>> 24) & 0xff;
  out[offset + 1] = (value >>> 16) & 0xff;
  out[offset + 2] = (value >>> 8) & 0xff;
  out[offset + 3] = value & 0xff;
}

function readBigEndian32(input: Uint8Array, offset: number): number {
  return ((input[offset] << 24) | (input[offset + 1] << 16) | (input[offset + 2] << 8)
    | input[offset + 3]) >>> 0;
}

class ImSessionKeys {
  secKey: Uint8Array = new Uint8Array(0);
  aesKey: Uint8Array = new Uint8Array(0);
}

export class ImSocket {
  private ws: ImWsTcp | undefined = undefined;
  private keys: ImSessionKeys = new ImSessionKeys();
  private initInfo: ImInitInfo | undefined = undefined;
  private connecting: Promise<ImInitInfo> | undefined = undefined;
  private pending: Map<number, ImPending> = new Map<number, ImPending>();
  private pushHandlers: Map<number, ImPushHandler> = new Map<number, ImPushHandler>();
  private reconnectHandler: ImReconnectHandler | undefined = undefined;
  private reqSeq: number = 0;
  private owner: string = '';
  private keepAlive: boolean = false;
  private closedByUser: boolean = false;
  private reconnectAttempt: number = 0;
  private reconnectTimer: number = -1;
  private opened: boolean = false;

  isReady(): boolean {
    return this.opened && this.initInfo !== undefined;
  }

  selfUid(): bigint {
    return this.initInfo === undefined ? BigInt(0) : this.initInfo.userId;
  }

  /** 注册推送处理；同一 cmd 覆盖。 */
  onPush(cmd: number, handler: ImPushHandler): void {
    this.pushHandlers.set(cmd, handler);
  }

  /** 注册非主动断线后的指数退避重连回调。 */
  onReconnectNeeded(handler: ImReconnectHandler): void {
    this.reconnectHandler = handler;
  }

  /** 保证连上并完成握手：同账号并发调用共用同一个 Promise，换账号（owner 变化）先断开重来。 */
  async login(session: TiebaSession, owner: string, device?: TiebaDevice): Promise<ImInitInfo> {
    this.keepAlive = true;
    if (session.bduss.length === 0) {
      throw new Error('未登录，无法连接私信通道');
    }
    if (this.owner !== owner) {
      await this.reset();
      this.owner = owner;
    }
    if (this.isReady() && this.initInfo !== undefined) {
      return this.initInfo;
    }
    if (this.connecting !== undefined) {
      return this.connecting;
    }
    const task: Promise<ImInitInfo> = this.doConnect(session, device);
    this.connecting = task;
    try {
      return await task;
    } finally {
      if (this.connecting === task) { this.connecting = undefined; }
    }
  }

  /** 发送请求并等待同 reqId 的回包；超时抛错。 */
  async request(req: ImRequest, encrypt: boolean = true): Promise<Uint8Array> {
    const ws: ImWsTcp | undefined = this.ws;
    if (!this.opened || ws === undefined) {
      throw new Error('私信通道未连接');
    }
    const reqId: number = this.nextReqId();
    const packed: Uint8Array = await this.packFrame(req.cmd, reqId, req.body, encrypt);
    const wait: Promise<Uint8Array> = new Promise<Uint8Array>((resolve: (body: Uint8Array) => void,
      reject: (err: Error) => void): void => {
      const item: ImPending = new ImPending();
      item.resolve = resolve;
      item.reject = reject;
      item.timer = setTimeout((): void => {
        this.pending.delete(reqId);
        reject(new Error('私信请求超时'));
      }, REQUEST_TIMEOUT_MS);
      this.pending.set(reqId, item);
    });
    try {
      await ws.send(packed);
    } catch (err) {
      this.failPending(reqId, '私信请求发送失败');
      throw new Error('私信请求发送失败');
    }
    return wait;
  }

  async close(): Promise<void> {
    this.closedByUser = true;
    this.keepAlive = false;
    this.clearReconnect();
    await this.reset();
  }

  private async reset(): Promise<void> {
    this.opened = false;
    this.initInfo = undefined;
    this.keys = new ImSessionKeys();
    this.failAll('私信通道已断开');
    const ws: ImWsTcp | undefined = this.ws;
    this.ws = undefined;
    if (ws !== undefined) {
      try { await ws.close(); } catch (err) { /* 已断开 */ }
    }
  }

  private nextReqId(): number {
    this.reqSeq = (this.reqSeq + 1) % 1000000;
    // 必须落在 32 位内：帧头只写 4 字节，服务端原样回传，超出范围会导致回包配不上请求。
    return (Date.now() % 1000000) * 1000 + this.reqSeq;
  }

  private failPending(reqId: number, message: string): void {
    const item: ImPending | undefined = this.pending.get(reqId);
    if (item === undefined) { return; }
    this.pending.delete(reqId);
    if (item.timer >= 0) { clearTimeout(item.timer); }
    item.reject(new Error(message));
  }

  private failAll(message: string): void {
    const ids: number[] = Array.from(this.pending.keys());
    for (let i = 0; i < ids.length; i++) { this.failPending(ids[i], message); }
  }

  private clearReconnect(): void {
    if (this.reconnectTimer >= 0) { clearTimeout(this.reconnectTimer); this.reconnectTimer = -1; }
  }

  /** 建连 + 握手。失败时清理半开连接，把具体原因抛给调用方。 */
  private async doConnect(session: TiebaSession, device?: TiebaDevice): Promise<ImInitInfo> {
    this.closedByUser = false;
    const ws: ImWsTcp = await this.open(session);
    this.ws = ws;
    // 传输层已连上：握手请求必须现在就能发；`initInfo` 才代表"业务就绪"。
    this.opened = true;
    try {
      const info: ImInitInfo = await this.handshake(session, device);
      this.initInfo = info;
      this.reconnectAttempt = 0;
      hilog.info(DOMAIN, TAG, 'im ready uid=%{public}s groups=%{public}d',
        info.userIdText, info.groups.length);
      return info;
    } catch (err) {
      await this.reset();
      throw err instanceof Error ? (err as Error) : new Error('私信握手失败');
    }
  }

  private async open(session: TiebaSession): Promise<ImWsTcp> {
    const ws: ImWsTcp = new ImWsTcp();
    const header: Record<string, string> = {};
    header['Sec-WebSocket-Extensions'] = WS_EXTENSION;
    header['Accept-Encoding'] = 'gzip';
    header['User-Agent'] = `bdtb for Android ${IM_CLIENT_VERSION}`;
    hilog.info(DOMAIN, TAG, 'ws connecting host=%{public}s:%{public}d', IM_HOST, IM_PORT);
    try {
      await ws.connect(IM_HOST, IM_PORT, header);
      hilog.info(DOMAIN, TAG, 'ws opened');
      this.bindHandlers(ws, session);
      return ws;
    } catch (err) {
      const failure: Error = err instanceof Error ? (err as Error) : new Error('私信通道连接失败');
      hilog.warn(DOMAIN, TAG, 'ws open failed msg=%{public}s', failure.message);
      try { await ws.close(); } catch (closeErr) { /* 忽略 */ }
      throw failure;
    }
  }


  private bindHandlers(ws: ImWsTcp, session: TiebaSession): void {
    ws.onMessage = (data: Uint8Array): void => {
      void this.onFrame(data, session);
    };
    ws.onClose = (code: number, reason: string): void => {
      this.onDisconnected(reason.length > 0 ? `连接已关闭（${code} ${reason}）` : `连接已关闭（${code}）`);
    };
    ws.onError = (error: Error): void => {
      this.onDisconnected(`连接出错：${error.message}`);
    };
  }

  private onDisconnected(message: string): void {
    if (!this.opened && this.initInfo === undefined) {
      this.failAll(message);
      return;
    }
    this.opened = false;
    this.failAll(message);
    hilog.warn(DOMAIN, TAG, 'im disconnected: %{public}s', message);
    if (this.keepAlive && !this.closedByUser) {
      this.scheduleReconnect();
    }
  }

  private scheduleReconnect(): void {
    this.clearReconnect();
    if (this.reconnectAttempt >= MAX_RECONNECT) { return; }
    const delay: number = Math.min(30000, 1000 * Math.pow(2, this.reconnectAttempt));
    this.reconnectAttempt++;
    this.reconnectTimer = setTimeout((): void => {
      this.reconnectTimer = -1;
      const ws: ImWsTcp | undefined = this.ws;
      if (ws !== undefined || !this.keepAlive || this.closedByUser || this.owner.length === 0) { return; }
      if (this.reconnectHandler !== undefined) {
        this.reconnectHandler();
      }
    }, delay);
  }

  private async onFrame(data: Uint8Array, session: TiebaSession): Promise<void> {
    if (data.length < 9) {
      hilog.warn(DOMAIN, TAG, 'short frame length=%{public}d', data.length);
      return;
    }
    const flag: number = data[0];
    const cmd: number = readBigEndian32(data, 1);
    const reqId: number = readBigEndian32(data, 5);
    let body: Uint8Array = data.slice(9);
    if ((flag & FLAG_ENCRYPT) !== 0) {
      if (this.keys.aesKey.length === 0) {
        this.failPending(reqId, '收到加密响应，但本地没有会话密钥');
        return;
      }
      try {
        body = await ImCrypto.aesDecrypt(this.keys.aesKey, body);
      } catch (err) {
        this.failPending(reqId, '私信响应解密失败');
        return;
      }
    }
    if ((flag & FLAG_COMPRESS) !== 0) {
      // 服务端即使客户端没声明 Accept-Encoding，回包也带 gzip 位。
      try {
        body = Gzip.inflate(body);
      } catch (err) {
        this.failPending(reqId, `私信响应解压失败：${err instanceof Error ? (err as Error).message : '未知'}`);
        return;
      }
    }
    const item: ImPending | undefined = this.pending.get(reqId);
    if (item !== undefined) {
      this.pending.delete(reqId);
      if (item.timer >= 0) { clearTimeout(item.timer); }
      item.resolve(body);
      return;
    }
    const push: ImPushHandler | undefined = this.pushHandlers.get(cmd);
    if (push !== undefined) {
      push(body);
      return;
    }
    hilog.info(DOMAIN, TAG, 'unhandled cmd=%{public}d len=%{public}d', cmd, body.length);
  }

  /** 握手：1001 明文，回包带账号信息与会话列表。 */
  private async handshake(session: TiebaSession, device?: TiebaDevice): Promise<ImInitInfo> {
    this.keys.secKey = ImCrypto.randomBytes(WS_SEC_KEY_LEN);
    const encrypted: Uint8Array = await ImCrypto.rsaEncrypt(this.keys.secKey);
    // full 模式：真实设备串 + 真实 cuid + STOKEN。缺设备身份时退回最小握手。
    let deviceJson: string = '';
    let cuid: string = '';
    if (device !== undefined) {
      deviceJson = fullDeviceJson(device.cuidGalaxy2, device.androidId, device.clientId,
        device.osVersion, device.netType, device.model, IM_CLIENT_VERSION);
      cuid = device.cuid;
    }
    const req: ImRequest = ImUpdateClientParams.build(session.bduss, encrypted, IM_CLIENT_VERSION,
      deviceJson, cuid, session.stoken);
    const body: Uint8Array = await this.request(req, false);
    const info: ImInitInfo = parseImInit(body);
    if (info.code !== 0) {
      throw new Error(info.message.length > 0 ? info.message : '私信握手被拒绝');
    }
    this.keys.aesKey = await ImCrypto.deriveAesKey(this.keys.secKey);
    return info;
  }

  /** 组帧：flag 固定 0x08 位，按参数决定是否加密（本端不压缩）。 */
  private async packFrame(cmd: number, reqId: number, body: Uint8Array,
    encrypt: boolean): Promise<Uint8Array> {
    let payload: Uint8Array = body;
    let flag: number = FLAG_BASE;
    if (encrypt) {
      if (this.keys.aesKey.length === 0) {
        throw new Error('私信会话密钥尚未就绪');
      }
      payload = await ImCrypto.aesEncrypt(this.keys.aesKey, payload);
      flag |= FLAG_ENCRYPT;
    }
    const out: Uint8Array = new Uint8Array(9 + payload.length);
    out[0] = flag;
    bigEndian32(out, 1, cmd);
    bigEndian32(out, 5, reqId);
    out.set(payload, 9);
    return out;
  }
}

export const imSocket: ImSocket = new ImSocket();


