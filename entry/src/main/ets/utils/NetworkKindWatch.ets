/** 监听默认网络的 Wi-Fi / 移动数据类别；不读取 SSID、IP 或账号资料，读取失败一律归入移动数据。 */
import { connection } from '@kit.NetworkKit';
import { NetworkKind } from '../model/ImageLoadPolicy';

function isWifiBearers(bearerTypes: connection.NetBearType[] | undefined): boolean {
  if (bearerTypes === undefined) { return false; }
  return bearerTypes.indexOf(connection.NetBearType.BEARER_WIFI) >= 0 ||
    bearerTypes.indexOf(connection.NetBearType.BEARER_ETHERNET) >= 0;
}

function isVpnOnly(capabilities: connection.NetCapabilities | undefined): boolean {
  if (capabilities === undefined || capabilities.bearerTypes === undefined) { return false; }
  const types: connection.NetBearType[] = capabilities.bearerTypes;
  return types.indexOf(connection.NetBearType.BEARER_VPN) >= 0 &&
    !isWifiBearers(types) &&
    types.indexOf(connection.NetBearType.BEARER_CELLULAR) < 0;
}

function kindFromCapabilities(capabilities: connection.NetCapabilities | undefined): NetworkKind {
  if (capabilities === undefined || capabilities.bearerTypes === undefined) {
    return NetworkKind.MOBILE;
  }
  return isWifiBearers(capabilities.bearerTypes) ? NetworkKind.WIFI : NetworkKind.MOBILE;
}

@ObservedV2
export class NetworkKindWatch {
  @Trace kind: NetworkKind = NetworkKind.MOBILE;
  private net: connection.NetConnection | undefined = undefined;
  private registered: boolean = false;
  private started: boolean = false;
  private refreshSeq: number = 0;

  /** 首帧前同步探测一次，随后注册系统回调持续跟踪切换。 */
  start(): void {
    if (this.started) { return; }
    this.started = true;
    this.readSync();
    void this.refresh();
    try {
      const net: connection.NetConnection = connection.createNetConnection();
      this.net = net;
      net.on('netCapabilitiesChange', (info: connection.NetCapabilityInfo): void => {
        if (!this.started) { return; }
        if (isVpnOnly(info.netCap)) {
          void this.refresh();
          return;
        }
        this.kind = kindFromCapabilities(info.netCap);
      });
      net.on('netAvailable', (_handle: connection.NetHandle): void => {
        if (!this.started) { return; }
        void this.refresh();
      });
      net.on('netLost', (_handle: connection.NetHandle): void => {
        if (!this.started) { return; }
        void this.refresh();
      });
      net.register((err): void => {
        this.registered = !err;
      });
    } catch (_) {
      this.kind = NetworkKind.MOBILE;
    }
  }

  stop(): void {
    this.started = false;
    ++this.refreshSeq;
    const net: connection.NetConnection | undefined = this.net;
    this.net = undefined;
    if (net !== undefined && this.registered) {
      this.registered = false;
      try { net.unregister((): void => {}); } catch (_) {}
    }
  }

  private readSync(): void {
    try {
      const handle: connection.NetHandle = connection.getDefaultNetSync();
      if (handle.netId === 0) {
        this.kind = NetworkKind.MOBILE;
        return;
      }
      const cap: connection.NetCapabilities = connection.getNetCapabilitiesSync(handle);
      if (isVpnOnly(cap)) {
        this.kind = this.kindFromUnderlyingSync();
        return;
      }
      this.kind = kindFromCapabilities(cap);
    } catch (_) {
      this.kind = NetworkKind.MOBILE;
    }
  }

  private kindFromUnderlyingSync(): NetworkKind {
    try {
      const nets: connection.NetHandle[] = connection.getAllNetsSync();
      for (let i: number = 0; i < nets.length; i++) {
        const cap: connection.NetCapabilities = connection.getNetCapabilitiesSync(nets[i]);
        if (isWifiBearers(cap.bearerTypes)) {
          return NetworkKind.WIFI;
        }
      }
    } catch (_) {}
    return NetworkKind.MOBILE;
  }

  private async refresh(): Promise<void> {
    const seq: number = ++this.refreshSeq;
    try {
      const handle: connection.NetHandle = await connection.getDefaultNet();
      if (!this.started || seq !== this.refreshSeq) { return; }
      if (handle.netId === 0) {
        this.kind = NetworkKind.MOBILE;
        return;
      }
      const cap: connection.NetCapabilities = await connection.getNetCapabilities(handle);
      if (!this.started || seq !== this.refreshSeq) { return; }
      if (isVpnOnly(cap)) {
        const nets: connection.NetHandle[] = await connection.getAllNets();
        if (!this.started || seq !== this.refreshSeq) { return; }
        for (let i: number = 0; i < nets.length; i++) {
          const itemCap: connection.NetCapabilities = await connection.getNetCapabilities(nets[i]);
          if (!this.started || seq !== this.refreshSeq) { return; }
          if (isWifiBearers(itemCap.bearerTypes)) {
            this.kind = NetworkKind.WIFI;
            return;
          }
        }
        this.kind = NetworkKind.MOBILE;
        return;
      }
      this.kind = kindFromCapabilities(cap);
    } catch (_) {
      if (this.started && seq === this.refreshSeq) {
        this.kind = NetworkKind.MOBILE;
      }
    }
  }
}

export const networkKindWatch: NetworkKindWatch = new NetworkKindWatch();
