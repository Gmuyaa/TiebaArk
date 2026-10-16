import { connection } from '@kit.NetworkKit';

/** 只监听默认网络；不读取网络标识资料，不因网络恢复自动播放。 */
export class VideoNetworkWatch {
  private net: connection.NetConnection | undefined = undefined;
  private registering: Promise<boolean> | undefined = undefined;
  private registered: boolean = false;
  private closed: boolean = false;
  private lastId: number = -1;
  async start(notify: (lost: boolean) => void): Promise<boolean> {
    if (this.closed || this.net !== undefined) { return false; }
    try {
      const net: connection.NetConnection = connection.createNetConnection(); this.net = net;
      net.on('netAvailable', (handle: connection.NetHandle): void => {
        if (this.closed) { return; }
        const changed: boolean = this.lastId >= 0 && this.lastId !== handle.netId;
        this.lastId = handle.netId; if (changed) { notify(false); }
      });
      net.on('netLost', (handle: connection.NetHandle): void => {
        if (this.closed || (this.lastId >= 0 && this.lastId !== handle.netId)) { return; }
        this.lastId = 0; notify(true);
      });
      this.registering = new Promise<boolean>((resolve: (value: boolean) => void): void => {
        try { net.register((err): void => { this.registered = !err; resolve(this.registered); }); }
        catch (err) { resolve(false); }
      });
      return await this.registering;
    } catch (err) { return false; }
  }
  async close(): Promise<boolean> {
    this.closed = true;
    if (this.registering !== undefined) { await this.registering; this.registering = undefined; }
    const net: connection.NetConnection | undefined = this.net;
    if (net === undefined || !this.registered) { this.net = undefined; return true; }
    try {
      const ok: boolean = await new Promise<boolean>((resolve: (value: boolean) => void): void => {
        net.unregister((err): void => { resolve(!err); });
      });
      if (ok) { this.net = undefined; this.registered = false; } return ok;
    } catch (err) { return false; }
  }
}
