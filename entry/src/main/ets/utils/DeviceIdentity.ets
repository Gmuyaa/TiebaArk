/** 应用设备身份参数的生成与本地持久化。 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CryptoUtil } from './CryptoUtil';
import { TiebaDevice, TiebaVersion } from '../net/TiebaParams';

const DOMAIN: number = 0x0000;
const TAG: string = 'DeviceIdentity';

/** net_type 当前固定为 1，尚无官方取值证据；空串不发送。 */
const IDENTITY_NET_TYPE: string = '1';

export const IDENTITY_STORE_NAME: string = 'tieba_device_identity';
export const IDENTITY_KEY_ANDROID_ID: string = 'android_id';
export const IDENTITY_KEY_UUID: string = 'uuid';
export const IDENTITY_KEY_CLIENT_ID: string = 'client_id';

const STORE_NAME: string = IDENTITY_STORE_NAME;
const KEY_ANDROID_ID: string = IDENTITY_KEY_ANDROID_ID;
const KEY_UUID: string = IDENTITY_KEY_UUID;
const KEY_CLIENT_ID: string = IDENTITY_KEY_CLIENT_ID;

/** 已加载的身份。整个应用生命周期内只初始化一次。 */
let cached: TiebaDevice | undefined = undefined;
/** 初始化中的 promise。并发调用时复用同一个，避免重复生成出两套身份。 */
let pending: Promise<TiebaDevice> | undefined = undefined;

function toHex(bytes: Uint8Array): string {
  let out: string = '';
  for (let i = 0; i < bytes.length; i++) {
    const b: number = bytes[i];
    out += b < 16 ? `0${b.toString(16)}` : b.toString(16);
  }
  return out;
}

async function randomBytes(length: number): Promise<Uint8Array> {
  const random: cryptoFramework.Random = cryptoFramework.createRandom();
  const blob: cryptoFramework.DataBlob = await random.generateRandom(length);
  return blob.data;
}

/** 16 位小写 hex，对应 8 字节，符合 androidId 的字段约束 */
async function newAndroidId(): Promise<string> {
  return toHex(await randomBytes(8));
}

/** 标准 uuid v4 形态（协议只要求"含 16 字节信息"） */
async function newUuid(): Promise<string> {
  const b: Uint8Array = await randomBytes(16);
  const hex: string = toHex(b);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

/**
 * `_client_id` 当前生成形态为 `wappc_<毫秒时间戳>_<0..999 随机整数>`。
 * 待定：官方只有字段名可证，取值生成代码不在本机反编译子集里；本格式尚无官方取证。
 */
function newClientId(): string {
  return `wappc_${Date.now()}_${Math.floor(Math.random() * 1000)}`;
}

async function deriveCuid(androidId: string): Promise<string> {
  const hex: string = await CryptoUtil.md5(`com.baidu${androidId}`);
  return `${hex.toUpperCase()}|000000000000000`;
}

async function build(androidId: string, uuid: string, clientId: string): Promise<TiebaDevice> {
  const device: TiebaDevice = new TiebaDevice();
  device.androidId = androidId;
  device.uuid = uuid;
  /** cuid 由持久化 android_id 确定性派生。 */
  const cuid: string = await deriveCuid(androidId);
  device.cuid = cuid;
  device.cuidGalaxy2 = cuid;
  device.clientId = clientId;
  device.osVersion = String(deviceInfo.sdkApiVersion);
  device.netType = IDENTITY_NET_TYPE;
  /** model 发送空字符串，避免把不可用的设备型号当成真实型号。 */
  device.model = '';
  device.clientVersion = TiebaVersion.LATEST;
  hilog.info(DOMAIN, TAG,
    'identity(实验 E2): cuid=%{public}s clientId=%{public}s osVersion=%{public}s netType=%{public}s',
    brief(cuid), brief(clientId), device.osVersion, device.netType);
  return device;
}

export class DeviceIdentity {

  static async ensure(context: common.Context): Promise<TiebaDevice> {
    if (cached !== undefined) {
      return cached;
    }
    if (pending !== undefined) {
      return pending;
    }
    pending = DeviceIdentity.loadOrCreate(context);
    try {
      const device: TiebaDevice = await pending;
      cached = device;
      return device;
    } finally {
      pending = undefined;
    }
  }

  private static async loadOrCreate(context: common.Context): Promise<TiebaDevice> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);

      let androidId: string = await store.get(KEY_ANDROID_ID, '') as string;
      let uuid: string = await store.get(KEY_UUID, '') as string;
      let clientId: string = await store.get(KEY_CLIENT_ID, '') as string;

      hilog.info(DOMAIN, TAG, 'preferences read: androidId=%{public}s uuid=%{public}s clientId=%{public}s',
        brief(androidId), brief(uuid), brief(clientId));

      let changed: boolean = false;
      if (androidId.length === 0) {
        androidId = await newAndroidId();
        await store.put(KEY_ANDROID_ID, androidId);
        changed = true;
      }
      if (uuid.length === 0) {
        uuid = await newUuid();
        await store.put(KEY_UUID, uuid);
        changed = true;
      }
      /** _client_id 首次生成后持久化并复用。 */
      if (clientId.length === 0) {
        clientId = newClientId();
        await store.put(KEY_CLIENT_ID, clientId);
        changed = true;
      }
      if (changed) {
        await store.flush();
        hilog.info(DOMAIN, TAG, 'preferences flushed: generated a new identity androidId=%{public}s',
          brief(androidId));
      } else {
        hilog.info(DOMAIN, TAG, 'preferences hit: reusing persisted identity');
      }
      return await build(androidId, uuid, clientId);
    } catch (err) {
      /*
       * 存储不可用：不阻断浏览，退回临时身份。
       *
       * ⚠️ 这条分支**必须留日志**：它会让 CUID 在每次进程启动时都变一次，
       * 而"点赞是否落库"高度依赖服务端是否把请求认成同一台设备。
       * 曾经的写法是静默 catch，结果"CUID 到底固定不固定"根本无从判断。
       */
      const e: Error = err as Error;
      hilog.error(DOMAIN, TAG,
        'device identity store unavailable, falling back to a PER-RUN identity: %{public}s', e.message);
      return await build(await newAndroidId(), await newUuid(), newClientId());
    }
  }
}

/**
 * 日志用的简短摘要：空串显式标注，非空只留前缀与长度。
 *
 * 放在**模块级**而不是类里，因为模块级的 `build()` 也要用它
 * （类里的 private 方法对模块级函数不可见）。
 */
function brief(value: string): string {
  if (value.length === 0) {
    return '(empty)';
  }
  const head: string = value.length > 8 ? value.slice(0, 8) : value;
  return `${head}…(len=${value.length})`;
}
