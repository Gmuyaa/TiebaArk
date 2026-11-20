/**
 * 自建 WebSocket 客户端（TCP + HTTP Upgrade + 手写帧），用于私信通道。
 *
 * 不用 `@ohos.net.webSocket`：系统实现在 `ws://im.tieba.baidu.com:8000/` 上一律 `open=N code=200`
 * （TCP 已连、upgrade 失败），而同一网络下手写 upgrade 能拿到 101 并跑通 1001/202003。
 * 只支持明文 ws（服务端 8000 不做 TLS）；帧层实现 RFC 6455 最小子集：
 * 客户端掩码、两档长度、分片拼接、ping/pong、close。
 */

import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { encodeUtf8, decodeUtf8 } from '../utils/TextCodec';

const DOMAIN: number = 0x0000;
const TAG: string = 'ImWsTcp';
const CONNECT_TIMEOUT_MS: number = 12000;
const HANDSHAKE_TIMEOUT_MS: number = 12000;

/** 收到一帧（已重组分片）。 */
export type ImWsMessage = (data: Uint8Array) => void;
export type ImWsClosed = (code: number, reason: string) => void;
export type ImWsFailed = (error: Error) => void;

export class ImWsTcp {
  private tcp: socket.TCPSocket | undefined = undefined;
  private buffer: Uint8Array = new Uint8Array(0);
  private fragments: Uint8Array[] = [];
  private opened: boolean = false;
  private closed: boolean = false;

  onMessage: ImWsMessage = (): void => {};
  onClose: ImWsClosed = (): void => {};
  onError: ImWsFailed = (): void => {};

  /** 建立 TCP 并完成 HTTP Upgrade；失败抛错（含 HTTP 状态码）。 */
  async connect(host: string, port: number, extraHeaders: Record<string, string>): Promise<void> {
    const tcp: socket.TCPSocket = socket.constructTCPSocketInstance();
    this.tcp = tcp;
    tcp.on('message', (info: socket.SocketMessageInfo): void => {
      this.ingest(new Uint8Array(info.message));
    });
    tcp.on('close', (): void => {
      if (!this.opened) { return; }
      this.opened = false;
      this.onClose(1006, 'socket closed');
    });
    tcp.on('error', (err: BusinessError): void => {
      this.onError(new Error(`tcp error ${err.code}`));
    });

    const key: string = this.makeKey();
    await new Promise<void>((resolve: () => void, reject: (err: Error) => void): void => {
      let settled: boolean = false;
      const timer: number = setTimeout((): void => {
        if (settled) { return; }
        settled = true;
        reject(new Error('tcp connect timeout'));
      }, CONNECT_TIMEOUT_MS);
      tcp.connect({
        address: { address: host, port: port, family: 1 },
        timeout: CONNECT_TIMEOUT_MS
      }).then((): void => {
        if (settled) { return; }
        settled = true;
        clearTimeout(timer);
        resolve();
      }).catch((err: BusinessError): void => {
        if (settled) { return; }
        settled = true;
        clearTimeout(timer);
        reject(new Error(`tcp connect failed ${err.code}`));
      });
    });

    const lines: string[] = [
      'GET / HTTP/1.1',
      `Host: ${host}:${port}`,
      'Upgrade: websocket',
      'Connection: Upgrade',
      `Sec-WebSocket-Key: ${key}`,
      'Sec-WebSocket-Version: 13'
    ];
    const names: string[] = Object.keys(extraHeaders);
    for (let i = 0; i < names.length; i++) {
      lines.push(`${names[i]}: ${extraHeaders[names[i]]}`);
    }
    const request: string = `${lines.join('\r\n')}\r\n\r\n`;
    await this.sendRaw(encodeUtf8(request));

    await new Promise<void>((resolve: () => void, reject: (err: Error) => void): void => {
      let settled: boolean = false;
      const timer: number = setTimeout((): void => {
        if (settled) { return; }
        settled = true;
        reject(new Error('ws handshake timeout'));
      }, HANDSHAKE_TIMEOUT_MS);
      this.handshakeWaiter = (status: number, rest: Uint8Array): void => {
        if (settled) { return; }
        settled = true;
        clearTimeout(timer);
        if (status === 101) {
          this.opened = true;
          if (rest.length > 0) { this.ingest(rest); }
          resolve();
        } else {
          reject(new Error(`ws handshake rejected HTTP ${status}`));
        }
      };
    });
  }

  async send(data: Uint8Array): Promise<void> {
    if (!this.opened) { throw new Error('ws not open'); }
    await this.sendRaw(this.encodeFrame(0x2, data));
  }

  /** 关闭 TCP；不发 close 帧。 */
  async close(): Promise<void> {
    const tcp: socket.TCPSocket | undefined = this.tcp;
    this.tcp = undefined;
    this.opened = false;
    this.closed = true;
    if (tcp === undefined) { return; }
    try { await tcp.close(); } catch (err) { /* 已断开 */ }
  }

  private handshakeWaiter: ((status: number, rest: Uint8Array) => void) | undefined = undefined;

  private async sendRaw(bytes: Uint8Array): Promise<void> {
    const tcp: socket.TCPSocket | undefined = this.tcp;
    if (tcp === undefined) { throw new Error('tcp not connected'); }
    await tcp.send({ data: bytes.buffer as ArrayBuffer });
  }

  private makeKey(): string {
    const bytes: Uint8Array = new Uint8Array(16);
    for (let i = 0; i < 16; i++) { bytes[i] = Math.floor(Math.random() * 256); }
    return new util.Base64Helper().encodeToStringSync(bytes);
  }

  /** 累积字节：握手阶段先切 HTTP 头，之后按 WS 帧解析。 */
  private ingest(chunk: Uint8Array): void {
    this.buffer = concat(this.buffer, chunk);
    if (!this.opened && this.handshakeWaiter !== undefined) {
      const end: number = indexOfHeaderEnd(this.buffer);
      if (end < 0) { return; }
      const head: string = decodeUtf8(this.buffer.subarray(0, end));
      const rest: Uint8Array = this.buffer.slice(end + 4);
      this.buffer = new Uint8Array(0);
      const statusLine: string = head.split('\r\n')[0];
      const status: number = Number(statusLine.split(' ')[1]);
      const waiter = this.handshakeWaiter;
      this.handshakeWaiter = undefined;
      waiter(status, rest);
      return;
    }
    this.drainFrames();
  }

  private drainFrames(): void {
    while (this.buffer.length >= 2) {
      const first: number = this.buffer[0];
      const second: number = this.buffer[1];
      const fin: boolean = (first & 0x80) !== 0;
      const opcode: number = first & 0x0f;
      const masked: boolean = (second & 0x80) !== 0;
      let length: number = second & 0x7f;
      let offset: number = 2;
      if (length === 126) {
        if (this.buffer.length < 4) { return; }
        length = (this.buffer[2] << 8) | this.buffer[3];
        offset = 4;
      } else if (length === 127) {
        if (this.buffer.length < 10) { return; }
        let big: number = 0;
        for (let i = 0; i < 8; i++) { big = big * 256 + this.buffer[2 + i]; }
        length = big;
        offset = 10;
      }
      let mask: Uint8Array | undefined = undefined;
      if (masked) {
        if (this.buffer.length < offset + 4) { return; }
        mask = this.buffer.slice(offset, offset + 4);
        offset += 4;
      }
      if (this.buffer.length < offset + length) { return; }
      let payload: Uint8Array = this.buffer.slice(offset, offset + length);
      this.buffer = this.buffer.slice(offset + length);
      if (mask !== undefined) { payload = xor(payload, mask); }
      if (opcode === 0x8) {
        const code: number = payload.length >= 2 ? (payload[0] << 8) | payload[1] : 1005;
        const reason: string = payload.length > 2 ? decodeUtf8(payload.subarray(2)) : '';
        this.opened = false;
        this.onClose(code, reason);
        continue;
      }
      if (opcode === 0x9) {
        void this.sendRaw(this.encodeFrame(0xA, payload));
        continue;
      }
      if (opcode === 0xA) { continue; }
      if (opcode === 0x1 || opcode === 0x2 || opcode === 0x0) {
        this.fragments.push(payload);
        if (fin) {
          let total: number = 0;
          for (let i = 0; i < this.fragments.length; i++) { total += this.fragments[i].length; }
          const full: Uint8Array = new Uint8Array(total);
          let at: number = 0;
          for (let i = 0; i < this.fragments.length; i++) {
            full.set(this.fragments[i], at);
            at += this.fragments[i].length;
          }
          this.fragments = [];
          this.onMessage(full);
        }
      }
    }
  }

  /** 客户端帧必须掩码；长度三档。 */
  private encodeFrame(opcode: number, payload: Uint8Array): Uint8Array {
    const length: number = payload.length;
    let header: Uint8Array;
    if (length < 126) {
      header = new Uint8Array([0x80 | opcode, 0x80 | length]);
    } else if (length < 65536) {
      header = new Uint8Array(4);
      header[0] = 0x80 | opcode;
      header[1] = 0x80 | 126;
      header[2] = (length >>> 8) & 0xff;
      header[3] = length & 0xff;
    } else {
      header = new Uint8Array(10);
      header[0] = 0x80 | opcode;
      header[1] = 0x80 | 127;
      let remaining: number = length;
      for (let i = 9; i >= 2; i--) {
        header[i] = remaining & 0xff;
        remaining = Math.floor(remaining / 256);
      }
    }
    const mask: Uint8Array = new Uint8Array(4);
    for (let i = 0; i < 4; i++) { mask[i] = Math.floor(Math.random() * 256); }
    const masked: Uint8Array = xor(payload, mask);
    const out: Uint8Array = new Uint8Array(header.length + 4 + masked.length);
    out.set(header, 0);
    out.set(mask, header.length);
    out.set(masked, header.length + 4);
    return out;
  }
}

function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  if (a.length === 0) { return b.slice(); }
  const out: Uint8Array = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
}

function xor(data: Uint8Array, mask: Uint8Array): Uint8Array {
  const out: Uint8Array = new Uint8Array(data.length);
  for (let i = 0; i < data.length; i++) { out[i] = data[i] ^ mask[i % 4]; }
  return out;
}

function indexOfHeaderEnd(data: Uint8Array): number {
  for (let i = 0; i + 3 < data.length; i++) {
    if (data[i] === 13 && data[i + 1] === 10 && data[i + 2] === 13 && data[i + 3] === 10) { return i; }
  }
  return -1;
}
